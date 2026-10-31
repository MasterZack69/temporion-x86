#define _GNU_SOURCE
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
typedef struct {const char*p;size_t n;} View;
typedef struct {uint64_t value,ok;} Parsed;
extern View trim_utf8(const char*,size_t);
extern Parsed parse_u64(const char*,size_t);
extern Parsed parse_i32(const char*,size_t);
int main(void){
 char *line=NULL;size_t cap=0;ssize_t len;
 while((len=getline(&line,&cap,stdin))>=0){
  if(len && line[len-1]=='\n')--len;
  size_t n=(size_t)len/2;char *raw=malloc(n?n:1);if(!raw)return 1;
  for(size_t i=0;i<n;++i){char byte[3]={line[i*2],line[i*2+1],0};raw[i]=(char)strtoul(byte,NULL,16);}
  View v=trim_utf8(raw,n);
  if(!v.p){puts("invalid");free(raw);continue;}
  for(size_t i=0;i<v.n;++i)printf("%02x",(unsigned char)v.p[i]);
  Parsed u=parse_u64(v.p,v.n),s=parse_i32(v.p,v.n);
  if(u.ok)printf("|%"PRIu64,u.value);else printf("|invalid");
  if(s.ok)printf("|%"PRId32"\n",(int32_t)s.value);else puts("|invalid");
  free(raw);
 }
 free(line);
}
