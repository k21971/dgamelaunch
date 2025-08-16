/* zork1-wrapper.c - C wrapper for Zork I in dgamelaunch */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <errno.h>

int main(int argc, char *argv[]) {
    const char *username;
    char user_initial[2];
    char user_base[512];
    char zork_dat[256];
    struct stat st;

    /* Get username from environment */
    username = getenv("DGL_USER");
    if (!username || !*username) {
        username = getenv("USER");
        if (!username || !*username) {
            username = "unknown";
        }
    }

    /* Extract first character of username */
    user_initial[0] = username[0];
    user_initial[1] = '\0';

    /* Build paths */
    snprintf(user_base, sizeof(user_base), "/dgldir/userdata/%s/%s/zork1",
             user_initial, username);
    snprintf(zork_dat, sizeof(zork_dat), "/zork1/zork1.z3");

    /* Create user directory if needed */
    if (stat(user_base, &st) != 0) {
        /* Create parent directories first */
        char parent[512];
        snprintf(parent, sizeof(parent), "/dgldir/userdata/%s", user_initial);
        mkdir(parent, 0755);

        snprintf(parent, sizeof(parent), "/dgldir/userdata/%s/%s",
                 user_initial, username);
        mkdir(parent, 0755);

        /* Create zork directory */
        if (mkdir(user_base, 0755) != 0 && errno != EEXIST) {
            fprintf(stderr, "Failed to create directory %s: %s\n",
                    user_base, strerror(errno));
            return 1;
        }
    }

    /* Change to user directory */
    if (chdir(user_base) != 0) {
        fprintf(stderr, "Failed to change to directory %s: %s\n",
                user_base, strerror(errno));
        return 1;
    }

    /* Execute frotz */
    execl("/bin/frotz", "frotz", "-q", "-f", "white", "-b", "blue",
          "-l", "1", "-r", "1",
          zork_dat, (char *)NULL);

    /* If we get here, exec failed */
    fprintf(stderr, "Failed to execute frotz: %s\n", strerror(errno));
    return 1;
}
