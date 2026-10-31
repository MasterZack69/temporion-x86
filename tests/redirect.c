/* Fixture-only LD_PRELOAD shim. Never linked into the shipped daemon.
 * Both implementations see the same synthetic /sys tree; no source changes. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdarg.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <dirent.h>
#include <glob.h>
#include <sys/stat.h>
#include <unistd.h>
#include <limits.h>
static const char *map(const char *p,char *b) {
    const char *root=getenv("TEMPORION_X86_TEST_ROOT");
    if(root && p && !strncmp(p,"/sys/",5)) { snprintf(b,PATH_MAX,"%s%s",root,p+4); return b; }
    return p;
}
#define NEXT(name) __typeof__(&name) fn=(__typeof__(&name))dlsym(RTLD_NEXT,#name)
#define OPEN(name) int name(const char*p,int f,...) { mode_t m=0; if(f&O_CREAT){va_list ap;va_start(ap,f);m=va_arg(ap,int);va_end(ap);} NEXT(name); char b[PATH_MAX];return fn(map(p,b),f,m); }
OPEN(open)
OPEN(open64)
DIR *opendir(const char*p){NEXT(opendir);char b[PATH_MAX];return fn(map(p,b));}
char *realpath(const char*p,char*r){NEXT(realpath);char b[PATH_MAX],resolved[PATH_MAX];char *out=fn(map(p,b),r?r:resolved);return out && !r ? strdup(out):out;}
int access(const char*p,int mode){NEXT(access);char b[PATH_MAX];return fn(map(p,b),mode);}
#define STAT(name,typ) int name(const char*p,struct typ*s){NEXT(name);char b[PATH_MAX];return fn(map(p,b),s);}
STAT(stat,stat)
STAT(stat64,stat64)
STAT(lstat,stat)
STAT(lstat64,stat64)
int statx(int fd,const char*p,int flags,unsigned mask,struct statx*s){NEXT(statx);char b[PATH_MAX];return fn(fd,map(p,b),flags,mask,s);}
ssize_t readlink(const char*p,char*r,size_t n){NEXT(readlink);char b[PATH_MAX];return fn(map(p,b),r,n);}
int glob(const char*p,int flags,int(*err)(const char*,int),glob_t*g){NEXT(glob);char b[PATH_MAX];return fn(map(p,b),flags,err,g);}
/* Force one-byte short reads and an initial EINTR for fixture attributes. */
#include <errno.h>
static unsigned char fixture_fd[65536];
ssize_t read(int fd,void *buf,size_t n) {
    NEXT(read);
    if(getenv("TEMPORION_X86_TEST_SHORT_READS") && (unsigned)fd<sizeof(fixture_fd)) {
        if(!fixture_fd[fd]) {
            char proc[64],target[PATH_MAX];
            snprintf(proc,sizeof(proc),"/proc/self/fd/%d",fd);
            ssize_t len=readlink(proc,target,sizeof(target)-1);
            const char *root=getenv("TEMPORION_X86_TEST_ROOT");
            if(len>=0){target[len]=0;if(root && !strncmp(target,root,strlen(root)))fixture_fd[fd]=1;}
        }
        if(fixture_fd[fd]==1){fixture_fd[fd]=2;errno=EINTR;return -1;}
        if(fixture_fd[fd] && n>1)n=1;
    }
    return fn(fd,buf,n);
}
int close(int fd){NEXT(close);if((unsigned)fd<sizeof(fixture_fd))fixture_fd[fd]=0;return fn(fd);}
/* Explicit library absence, independent of the CI runner's NVIDIA setup. */
void *dlopen(const char *p,int flags) {
    NEXT(dlopen);
    if(p && strstr(p,"libnvidia-ml") && getenv("TEMPORION_X86_TEST_NO_NVML"))return NULL;
    return fn(p,flags);
}
