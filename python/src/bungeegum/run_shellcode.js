// Send message to Python script to initiate IPC
send('status');

var payload_args;
// Wait for Python to send args
var op = recv('args', function (value) {
    payload_args = value.payload;
})
op.wait();

// Get required library symbols for CModule
var fork_ptr = Module.findExportByName('libc.so', 'fork');
var alog_ptr = Module.findExportByName('liblog.so', '__android_log_print');
var waitpid_ptr = Module.findExportByName('libc.so', 'waitpid');
var errno_ptr = Module.findExportByName('libc.so', '__errno');
var strerror_ptr = Module.findExportByName('libc.so', 'strerror');
var _exit_ptr = Module.findExportByName('libc.so', '_exit');
var pipe_ptr = Module.findExportByName('libc.so', 'pipe');
var dup2_ptr = Module.findExportByName('libc.so', 'dup2');
var close_ptr = Module.findExportByName('libc.so', 'close');
var read_ptr = Module.findExportByName('libc.so', 'read');
var ppoll_ptr = Module.findExportByName('libc.so', 'ppoll');

var shellcode_ptr;
var shellcode_main_ptr;
var shellcode_bytes;

shellcode_bytes = Uint8Array.from(payload_args['data']);
var page_size = Process.pageSize;
shellcode_ptr = Memory.alloc(shellcode_bytes.length);
shellcode_ptr.writeByteArray(shellcode_bytes);
Memory.protect(shellcode_ptr, shellcode_bytes.length, 'rwx')
shellcode_main_ptr = new NativeFunction(shellcode_ptr, 'int', []);

const stdoutCallback = new NativeCallback(function (buf, size) {
    if (!size || size <= 0) {
        return;
    }
    var chunk = Memory.readByteArray(buf, size);
    send({type: 'stdout'}, chunk);
}, 'void', ['pointer', 'int']);

// symbol list to be passed into CModule
const symbols = {
    fork: fork_ptr,
    log: alog_ptr,
    waitpid: waitpid_ptr,
    __errno: errno_ptr,
    strerror: strerror_ptr,
    pipe: pipe_ptr,
    dup2: dup2_ptr,
    close: close_ptr,
    read: read_ptr,
    ppoll: ppoll_ptr,
    report_stdout: stdoutCallback,
    _exit: _exit_ptr,
    shellcode_main: shellcode_main_ptr
};

const ccode=`
#include <stdio.h>
#include <stddef.h>

// Prototypes of functions we're passing in
extern int fork(void);
extern int waitpid(int pid, int *wstatus, int opts);
extern void _exit(int status);
extern int shellcode_main();
extern int log(int prio, const char *tag, const char *fmt, ...);
extern int *__errno();
extern char *strerror(int errnum);
extern int pipe(int pipefd[2]);
extern int dup2(int oldfd, int newfd);
extern int close(int fd);
extern ssize_t read(int fd, void *buf, size_t count);
extern void report_stdout(char *buf, int len);
extern int ppoll(
    struct pollfd *fds, unsigned long nfds, const struct timespec *timeout_ts, const void *sigmask
);

#define errno (*__errno())

#define        WEXITSTATUS(status)     (((status) & 0xff00) >> 8)
#define        WTERMSIG(status)        ((status) & 0x7f)
#define        WIFEXITED(status)       (WTERMSIG(status) == 0)
#ifndef EINTR
#define EINTR 4
#endif
#define DBG 3
#define ERR 6
#define STDOUT_BUF_SIZE 1024
#ifndef POLLIN
#define POLLIN 0x0001
#define POLLHUP 0x0010
#define POLLERR 0x0008
#endif
#ifndef WNOHANG
#define WNOHANG 1
#endif

// Structure definitions
struct timespec
{
    long tv_sec;
    long tv_nsec;
};

struct pollfd
{
    int fd;
    short events;
    short revents;
};

int main(char *path) {
    const char *TAG = "Bungeegum_sc";
    int pid = -1;
    int status = -1;
    int pipefd[2] = {-1, -1};

    if (pipe(pipefd) != 0)
    {
        log(ERR, TAG, "pipe() failed. errno: %d, %s", errno, strerror(errno));
        return status;
    }

    pid = fork();
    if (pid == 0)
    {
        // Spawned process: redirect stdout/stderr to the pipe.
        close(pipefd[0]);
        if (dup2(pipefd[1], 1) == -1 || dup2(pipefd[1], 2) == -1)
        {
            log(ERR, TAG, "dup2() failed. errno: %d, %s", errno, strerror(errno));
            close(pipefd[1]);
            _exit(1);
        }
        close(pipefd[1]);

        status = shellcode_main();
        log(DBG, TAG, "shellcode returned: %d", status);
        fflush(NULL); // Flush stdio buffers to ensure output is written before _exit
        _exit(status);
    }
    if (pid > 0)
    {
        log(DBG, TAG, "Shellcode payload pid is %d", pid);

        // Parent process: send child's stdout/stderr back to the CLI.
        close(pipefd[1]);

        // Use ppoll to wait for data to be available.
        struct pollfd pfd;
        pfd.fd = pipefd[0];
        pfd.events = POLLIN;

        // Set a one second timeout on the ppoll call.
        struct timespec timeout;
        timeout.tv_sec = 1;
        timeout.tv_nsec = 0;

        int wait_ret = 0;

        char buffer[STDOUT_BUF_SIZE];
        while (1)
        {
            // Check if the child has exited. If the child is dead, we stop
            // waiting for pipe closure, because some other process
            // (grandchild) might have it open indefinitely.
            int wait_status;
            wait_ret = waitpid(pid, &wait_status, WNOHANG);
            if (wait_ret > 0)
            {
                // Child exited - drain any remaining data in pipe
                status = wait_status;

                // Do a final non-blocking read to get any buffered data
                struct timespec drain_timeout = {0, 0};
                while (ppoll(&pfd, 1, &drain_timeout, NULL) > 0 && (pfd.revents & POLLIN))
                {
                    ssize_t count = read(pipefd[0], buffer, sizeof(buffer));
                    if (count > 0) {
                        report_stdout(buffer, (int)count);
                    }
                    else
                    {
                        break;
                    }
                }
                break;
            }
            else if (wait_ret < 0)
            {
                log(ERR, TAG, "waitpid() WNOHANG failed. errno: %d, %s", errno, strerror(errno));
                break;
            }

            // wait_ret == 0 means child is still running, so continue polling for data in the pipe.
            int poll_ret = ppoll(&pfd, 1, &timeout, NULL);
            if (poll_ret > 0)
            {
                if (pfd.revents & POLLERR)
                {
                    log(ERR, TAG, "poll error on pipe");
                    break;
                }
                if (pfd.revents & POLLIN)
                {
                    // There's data in the pipe, so read it.
                    ssize_t count = read(pipefd[0], buffer, sizeof(buffer));
                    if (count > 0)
                    {
                        report_stdout(buffer, (int)count);
                    }
                    else if (count == 0)
                    {
                        // EOF
                        break;
                    }
                    else if (errno == EINTR)
                    {
                        continue;
                    }
                    else
                    {
                        log(ERR, TAG, "read() failed. errno: %d, %s", errno, strerror(errno));
                        break;
                    }
                }
                // Check POLLHUP after reading available data
                else if (pfd.revents & POLLHUP)
                {
                    // All write ends closed and no data to read
                    break;
                }
            }
            else if (poll_ret < 0 && errno != EINTR)
            {
                log(ERR, TAG, "ppoll() failed. errno: %d, %s", errno, strerror(errno));
                break;
            }
            // poll_ret == 0 means timeout, just loop again
        }
        close(pipefd[0]);

        if (wait_ret == 0)
        {
            // We only want to reap the child process if it hasn't already been reaped.
            if (!waitpid(pid, &status, 0))
            {
                log(ERR, TAG, "waitpid() failed. errno: %d, %s", errno, strerror(errno));
                return -1;
            }
        }
        if (WIFEXITED(status))
        {
            status = WEXITSTATUS(status);
            log(DBG, TAG, "Shellcode payload process exited with status = %d", status);
        }
        return status;

    }
    if (pid < 0)
    {
        log(ERR, TAG, "fork() returned: %d. errno: %d, %s", pid, errno, strerror(errno));
        close(pipefd[0]);
        close(pipefd[1]);
        return status;
    }
}
`;

const cm = new CModule(ccode, symbols, {toolchain: 'any'});
const nativeFunc= new NativeFunction(cm.main, 'int', []);
var result = nativeFunc();
send(result);
