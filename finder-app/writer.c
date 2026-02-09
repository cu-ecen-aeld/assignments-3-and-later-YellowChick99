#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <syslog.h>

int main(int argc, char *argv[])
{
    openlog("writer", LOG_PID, LOG_USER);

    if (argc != 3) {
        syslog(LOG_ERR, "invalid arguments: expected 2, got %d", argc - 1);
        closelog();
        return 1;
    }

    const char *writefile = argv[1];
    const char *writestr = argv[2];

    FILE *fp = fopen(writefile, "w");
    if (!fp) {
        syslog(LOG_ERR, "failed to open file %s: %s", writefile, strerror(errno));
        closelog();
        return 1;
    }

    syslog(LOG_DEBUG, "Writing %s to %s", writestr, writefile);

    if (fputs(writestr, fp) == EOF) {
        syslog(LOG_ERR, "failed to write to file %s: %s", writefile, strerror(errno));
        fclose(fp);
        closelog();
        return 1;
    }

    if (fclose(fp) != 0) {
        syslog(LOG_ERR, "failed to close file %s: %s", writefile, strerror(errno));
        closelog();
        return 1;
    }

    closelog();
    return 0;
}

