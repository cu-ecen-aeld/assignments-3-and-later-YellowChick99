#include <stdbool.h>
#include <stdarg.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>
#include <fcntl.h>

bool do_system(const char *cmd)
{
    if (!cmd) return false;

    int status = system(cmd);
    if (status == -1) return false;

    if (WIFEXITED(status) && WEXITSTATUS(status) == 0) return true;
    return false;
}

bool do_exec(int count, ...)
{
    if (count < 1) return false;

    char **argv = calloc((size_t)count + 1, sizeof(char *));
    if (!argv) return false;

    va_list args;
    va_start(args, count);
    for (int i = 0; i < count; i++) argv[i] = va_arg(args, char *);
    va_end(args);
    argv[count] = NULL;

    pid_t pid = fork();
    if (pid < 0) {
        free(argv);
        return false;
    }

    if (pid == 0) {
        execv(argv[0], argv);
        _exit(127);
    }

    int status = 0;
    pid_t w = waitpid(pid, &status, 0);
    free(argv);
    if (w < 0) return false;

    if (WIFEXITED(status) && WEXITSTATUS(status) == 0) return true;
    return false;
}

bool do_exec_redirect(const char *outputfile, int count, ...)
{
    if (!outputfile || count < 1) return false;

    char **argv = calloc((size_t)count + 1, sizeof(char *));
    if (!argv) return false;

    va_list args;
    va_start(args, count);
    for (int i = 0; i < count; i++) argv[i] = va_arg(args, char *);
    va_end(args);
    argv[count] = NULL;

    pid_t pid = fork();
    if (pid < 0) {
        free(argv);
        return false;
    }

    if (pid == 0) {
        int fd = open(outputfile, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd < 0) _exit(127);

        if (dup2(fd, STDOUT_FILENO) < 0) _exit(127);
        close(fd);

        execv(argv[0], argv);
        _exit(127);
    }

    int status = 0;
    pid_t w = waitpid(pid, &status, 0);
    free(argv);
    if (w < 0) return false;

    if (WIFEXITED(status) && WEXITSTATUS(status) == 0) return true;
    return false;
}

