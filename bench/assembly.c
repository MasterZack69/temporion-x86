#define _POSIX_C_SOURCE 200809L
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <signal.h>
typedef struct { const unsigned char *p; size_t n; } Sample;
extern void discover(void);
extern Sample sample(void);
extern int write_sample(void);
static uint64_t ns(struct timespec t){return (uint64_t)t.tv_sec*1000000000+(uint64_t)t.tv_nsec;}
int main(int argc,char**argv) {
    if(argc!=3)return 2;
    unsigned long n=strtoul(argv[1],NULL,10);
    int io=!strcmp(argv[2],"write");
    signal(SIGPIPE,SIG_IGN);
    discover();
    for(unsigned i=0;i<100;++i)sample();
    struct timespec begin,end,cpu_begin,cpu_end;
    clock_gettime(CLOCK_MONOTONIC,&begin);
    clock_gettime(CLOCK_PROCESS_CPUTIME_ID,&cpu_begin);
    uint64_t checksum=0;
    for(unsigned long i=0;i<n;++i) {
        if(io){if(write_sample())return 3;}
        else{Sample s=sample();checksum+=s.n+s.p[0];}
    }
    clock_gettime(CLOCK_PROCESS_CPUTIME_ID,&cpu_end);
    clock_gettime(CLOCK_MONOTONIC,&end);
    fprintf(stderr,"{\"wall_ns\":%"PRIu64",\"cpu_ns\":%"PRIu64",\"checksum\":%"PRIu64"}\n",ns(end)-ns(begin),ns(cpu_end)-ns(cpu_begin),checksum);
}
