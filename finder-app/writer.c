#include <syslog.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[])
{
    openlog(NULL, 0, LOG_USER);

    if (argc != 3) {
        syslog(LOG_ERR, "Usage: %s <writefile> <writestr>", argv[0]);
        closelog();
        return 1;
    }

    const char *writefile = argv[1];
    const char *writestr = argv[2];

    FILE *fp = fopen(writefile, "w");
    if (!fp) {
        syslog(LOG_ERR, "Error opening file: %s", writefile);
        closelog();
        return 1;
    }

    syslog(LOG_DEBUG, "Writing \"%s\" to \"%s\"", writestr, writefile);

    if (fprintf(fp, "%s", writestr) < 0) {
        syslog(LOG_ERR, "Error writing to file: %s", writefile);
        fclose(fp);
        closelog();
        return 1;
    }

    fclose(fp);
    closelog();
    return 0;
}
