#ifndef __TTYREC_H__
#define __TTYREC_H__

#include <sys/time.h>
#include <sys/types.h>

typedef struct header
{
  struct timeval tv;
  size_t len;
}
Header;

extern void done (void);
extern void fail (void);
extern void fixtty (void);
extern void getslave (void);
extern void doinput (void);
extern void dooutput (int max_idle_time);
extern void doshell (int, char *);
extern void finish (int);
extern void remove_ipfile (void);

extern int ttyrec_main (int, char *username, char *ttyrec_path, char* ttyrec_filename);

extern pid_t child; /* nethack process */
extern int master, slave;
extern struct termios tt;
extern struct winsize win;

/* Upper bound on any window size we install on a game's pty; see
   clamp_winsize() in ttyrec.c for why it exists. */
#define DGL_MAX_WS_ROW 512
#define DGL_MAX_WS_COL 512

extern void clamp_winsize (struct winsize *w);

extern int encoding_by_name(const char *enc);
#endif
