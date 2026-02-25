#include "systemcalls.h"

#include <stdbool.h>
#include <stdarg.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <errno.h>

bool do_system(const char *cmd)
{
    if (cmd == NULL) return false;

    int ret = system(cmd);
    if (ret == -1) return false;

    if (WIFEXITED(ret) && (WEXITSTATUS(ret) == 0)) return true;
    return false;
}

bool do_exec(int count, ...)
{
    if (count < 1) return false;

    va_list args;
    va_start(args, count);

    char *argv[count + 1];
    for (int i = 0; i < count; i++) argv[i] = va_arg(args, char *);
    argv[count] = NULL;

    va_end(args);

    pid_t pid = fork();
    if (pid < 0) return false;

    if (pid == 0) {
        execv(argv[0], argv);
        _exit(127);
    }

    int status = 0;
    if (waitpid(pid, &status, 0) < 0) return false;

    if (WIFEXITED(status) && (WEXITSTATUS(status) == 0)) return true;
    return false;
}

bool do_exec_redirect(const char *outputfile, int count, ...)
{
    if (outputfile == NULL || count < 1) return false;

    va_list args;
    va_start(args, count);

    char *argv[count + 1];
    for (int i = 0; i < count; i++) argv[i] = va_arg(args, char *);
    argv[count] = NULL;

    va_end(args);

    pid_t pid = fork();
    if (pid < 0) return false;

    if (pid == 0) {
        int fd = open(outputfile, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd < 0) _exit(127);

        if (dup2(fd, STDOUT_FILENO) < 0) _exit(127);
        close(fd);

        execv(argv[0], argv);
        _exit(127);
    }

    int status = 0;
    if (waitpid(pid, &status, 0) < 0) return false;

    if (WIFEXITED(status) && (WEXITSTATUS(status) == 0)) return true;
    return false;
}
