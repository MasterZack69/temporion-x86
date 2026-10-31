/* Deliberately tiny controllable NVML substitute. Logs every device query. */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
static unsigned call(const char *s) {
    const char *p=getenv("TEMPORION_X86_TEST_NVML_LOG");
    if(p){FILE*f=fopen(p,"a");if(f){fprintf(f,"%s\n",s);fclose(f);}}
    const char *fail=getenv("TEMPORION_X86_TEST_NVML_FAIL");
    return fail && (*fail=='1' || !strcmp(fail,s));
}
unsigned nvmlInit_v2(void){return call("init");}
unsigned nvmlDeviceGetHandleByIndex_v2(unsigned i,void **p){(void)i;*p=(void*)(uintptr_t)1;return call("handle");}
#ifndef TEMPORION_X86_TEST_OMIT_TEMP
unsigned nvmlDeviceGetTemperature(void *p,unsigned t,unsigned *out){(void)p;(void)t;*out=52;return call("temperature");}

#endif
