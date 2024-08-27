// Send message to Python script to initiate IPC
send('status');

var payload_args;
// Wait for Python to send args
var op = recv('args', function (value) {
    payload_args = value.payload;
})
op.wait();

var path;
var data_dir;
// Check if we are remote mode
if ('path' in payload_args)
{
    var path = payload_args['path'];
}
else
{
    // Use Android API to find our apps data dir
    Java.perform(function() {
            const context = Java.use('android.app.ActivityThread').currentApplication().getApplicationContext();
            data_dir = context.getDataDir();
        });
    var local_file = data_dir + "/tmpFile";
    // Copy our ELF to this directory
    console.log('Writing payload:' + local_file);
    var file = new File(local_file,"w");
    file.write(payload_args['data']);
    Java.perform(function() {
            const File = Java.use('java.io.File');
            var localFile = File.$new.overload('java.lang.String').call(File, local_file);
            localFile.setExecutable(true, false);
        });
    file.close();
    // Set the path to be exec'd to our new local file
    path = local_file;
}

// Get required library symbols for CModule
var fork_ptr = Module.findExportByName('libc.so', 'fork');
var alog_ptr = Module.findExportByName('liblog.so', '__android_log_print');
var execv_ptr = Module.findExportByName('libc.so', 'execv');
var waitpid_ptr = Module.findExportByName('libc.so', 'waitpid');
var _exit_ptr = Module.findExportByName('libc.so', '_exit');
var errno_ptr = Module.findExportByName('libc.so', '__errno');
var strerror_ptr = Module.findExportByName('libc.so', 'strerror');

// Allocate argv array
// Calculate size based on size of payload args
var argc = payload_args['args'].length;

// Argv always needs to be at least 2 elements,
// {path, NULL}
var argv_size = Process.pointerSize * (argc + 2);
var args_ptr = Memory.alloc(argv_size);
// Temp array to store pointers so they are not GC'd
var tmp_args_arr = new Array(argc + 2);
// Allocate path temp array
tmp_args_arr[0] = Memory.allocUtf8String(path);
console.log(args_ptr + " arg[0]: " + path);
// Write path to argv[0]
args_ptr.writePointer(tmp_args_arr[0]);
// If we passed in any args, write them to the array
for (var i = 1; i < payload_args['args'].length + 1; i++)
{
    tmp_args_arr[i] = Memory.allocUtf8String(payload_args['args'][i-1]);
    console.log(args_ptr.add(Process.pointerSize * i) + " arg[" + i + "]: " + payload_args['args'][i-1]);
    args_ptr.add(Process.pointerSize * i).writePointer(tmp_args_arr[i]);
}

// symbol list to be passed into CModule
const symbols = {
    fork: fork_ptr,
    _exit: _exit_ptr,
    execv: execv_ptr,
    log: alog_ptr,
    waitpid: waitpid_ptr,
    __errno: errno_ptr,
    strerror: strerror_ptr,
    args: args_ptr,
};

const ccode=`
#include <stdio.h>

// Prototypes of functions we're passing in
extern int fork(void);
extern int waitpid(int pid, int *wstatus, int opts);
extern void _exit(int status);
extern int execv(const char *pathname, char *const argv[]);
extern int log(int prio, const char *tag, const char *fmt, ...);
extern char *args[${argc}];
extern int *__errno();
extern char *strerror(int errnum);

#define errno (*__errno())

#define        WEXITSTATUS(status)     (((status) & 0xff00) >> 8)
#define        WTERMSIG(status)        ((status) & 0x7f)
#define        WIFEXITED(status)       (WTERMSIG(status) == 0)
#define DBG 3
#define ERR 6

int main(char *path) {
    const char *TAG = "Bungeegum_elf";
    int pid = -1;
    int status = 1;
    int argc = ${argc};

    pid = fork();
    if (pid == 0)
    {
        for (int i = 0; i <= argc + 1; i++)
        {
            log(DBG, TAG, "%p arg[%d]: %s", &args[i], i, args[i]);
        }

        log(DBG, TAG, "execve(%s, %p)", path, args);
        int exec_ret = execv(path, args);
        log(ERR, TAG, "execv() returned: %d. errno: %i, %s", exec_ret, errno, strerror(errno));
        _exit(exec_ret);

    }
    if (pid > 0)
    {
        log(DBG, TAG, "Elf payload pid is %d", pid);
        if (!waitpid(pid, &status, 0))
        {
            log(ERR, TAG, "waitpid() failed. errno: %d, %s", errno, strerror(errno));
            return -1;
        }
        if (WIFEXITED(status))
        {
            status = WEXITSTATUS(status);
            log(DBG, TAG, "Elf payload process exited with status = %d", status);
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
const nativeFunc= new NativeFunction(cm.main, 'int', ['pointer']);
var path_ptr = Memory.allocUtf8String(path);
var result = nativeFunc(ptr(path_ptr));
send(result);
