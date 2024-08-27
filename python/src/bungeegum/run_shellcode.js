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

var shellcode_ptr;
var shellcode_main_ptr;
var shellcode_bytes;

shellcode_bytes = Uint8Array.from(payload_args['data']);
var page_size = Process.pageSize;
shellcode_ptr = Memory.alloc(shellcode_bytes.length);
shellcode_ptr.writeByteArray(shellcode_bytes);
Memory.protect(shellcode_ptr, shellcode_bytes.length, 'rwx')
shellcode_main_ptr = new NativeFunction(shellcode_ptr, 'int', []);

// symbol list to be passed into CModule
const symbols = {
    fork: fork_ptr,
    log: alog_ptr,
    waitpid: waitpid_ptr,
    __errno: errno_ptr,
    strerror: strerror_ptr,
    _exit: _exit_ptr,
    shellcode_main: shellcode_main_ptr
};

const ccode=`
#include <stdio.h>

// Prototypes of functions we're passing in
extern int fork(void);
extern int waitpid(int pid, int *wstatus, int opts);
extern void _exit(int status);
extern int shellcode_main();
extern int log(int prio, const char *tag, const char *fmt, ...);
extern int *__errno();
extern char *strerror(int errnum);

#define errno (*__errno())

#define        WEXITSTATUS(status)     (((status) & 0xff00) >> 8)
#define        WTERMSIG(status)        ((status) & 0x7f)
#define        WIFEXITED(status)       (WTERMSIG(status) == 0)
#define DBG 3
#define ERR 6

int main(char *path) {
    const char *TAG = "Bungeegum_sc";
    int pid = -1;
    int status = -1;

    pid = fork();
    if (pid == 0)
    {
        status = shellcode_main();
        log(DBG, TAG, "shellcode returned: %d", status);
        _exit(status);
    }
    if (pid > 0)
    {
        log(DBG, TAG, "Shellcode payload pid is %d", pid);
        if (!waitpid(pid, &status, 0))
        {
            log(ERR, TAG, "waitpid() failed. errno: %d, %s", errno, strerror(errno));
            return -1;
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
        return status;
    }
}
`;

const cm = new CModule(ccode, symbols, {toolchain: 'any'});
const nativeFunc= new NativeFunction(cm.main, 'int', []);
var result = nativeFunc();
send(result);
