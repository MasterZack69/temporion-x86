#define _GNU_SOURCE
#include <assert.h>
#include <fcntl.h>
#include <inttypes.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
/* Assembly view returns two registers, equivalent to a two-word C struct. */
typedef struct { const char *p; size_t n; } View;
typedef struct { uint64_t value, ok; } Parsed;
extern View trim_utf8(const char *, size_t);
extern View read_attr(const char *);
extern Parsed parse_u64(const char *, size_t);
extern Parsed parse_i32(const char *, size_t);
extern Parsed read_degree(const char *);
/* append_field uses eax/edx custom ABI, invoked through inline assembly. */
static char *format(char *out, int32_t n, unsigned valid) {
    register char *d __asm__("rdi") = out;
    register uint64_t a __asm__("rax") = (uint32_t)n;
    register uint64_t v __asm__("rdx") = valid;
    __asm__ volatile("call append_field" : "+a"(a), "+D"(d), "+d"(v) : : "rcx", "r8", "r9", "r10", "r11", "memory", "cc");
    return (char *)a;
}
static void trim(const char *raw, size_t len, const char *expected) {
    View v = trim_utf8(raw, len);
    if (!expected) { assert(!v.p); return; }
    assert(v.p && v.n == strlen(expected) && !memcmp(v.p, expected, v.n));
}
static void attr_test(const void *raw, size_t n, const char *expected) {
    char path[] = "/tmp/temporion-unit-XXXXXX";
    int fd = mkstemp(path); assert(fd >= 0);
    assert(write(fd, raw, n) == (ssize_t)n); close(fd);
    View v = read_attr(path); unlink(path);
    if (!expected) { assert(!v.p); return; }
    assert(v.p && v.n == strlen(expected) && !memcmp(v.p, expected, v.n));
}
int main(void) {
    trim("", 0, ""); trim(" \t\r\n", 4, "");
    trim(" \t-12500 \n", 10, "-12500");
    trim("\xc2\xa0\xe3\x80\x80" "61000\xe2\x80\xaf", 13, "61000");
    const char *bad[] = {"\xff", "\xc0\xaf", "\xed\xa0\x80", "\xf4\x90\x80\x80", "\xe0\x80\x80", "\xe2\x82"};
    for (size_t i=0; i<sizeof(bad)/sizeof(*bad); ++i) trim(bad[i], strlen(bad[i]), NULL);
    trim("\xef\xbb\xbf", 3, "\xef\xbb\xbf"); /* BOM isn't whitespace. */
    const char *invalid[] = {"", "+", "-", "--1", "-+1", "1\n", " 1", "1x", "2147483648", "-2147483649", "18446744073709551616"};
    for (size_t i=0;i<sizeof(invalid)/sizeof(*invalid);++i) assert(!parse_i32(invalid[i],strlen(invalid[i])).ok);
    assert(parse_u64("18446744073709551615",20).ok);
    assert(!parse_u64("18446744073709551616",20).ok);
    assert(!parse_i32("12\0x",4).ok);
    int32_t edges[] = {INT_MIN, INT_MIN+1, -12500, -1001,-500,-1,0,1,499,500,61000,INT_MAX-500,INT_MAX};
    uint64_t state=42;
    for (unsigned i=0;i<100000;++i) {
        state=state*6364136223846793005ULL+1;
        int32_t n=i<sizeof(edges)/sizeof(*edges)?edges[i]:(int32_t)(state>>32);
        char s[32], out[32]; int k=snprintf(s,sizeof(s),"%" PRId32,n);
        Parsed p=parse_i32(s,k); assert(p.ok && (int32_t)p.value==n);
        char *end=format(out,n,1); assert(end-out==k && !memcmp(s,out,k));
    }
    char out[4]; assert(format(out,0,0)==out+1 && out[0]=='-');
    char buf[257]; memset(buf,'x',sizeof(buf));
    buf[256]=0; attr_test(buf,256,buf); attr_test(buf,257,NULL);
    attr_test(" 61000\n",7,"61000"); attr_test("\xff",1,NULL);
    char path[]="/tmp/temporion-degree-XXXXXX"; int fd=mkstemp(path); assert(fd>=0);
    assert(write(fd,"-12500\n",7)==7); close(fd);
    Parsed p=read_degree(path); assert(p.ok && (int32_t)p.value==-12); unlink(path);
    assert(!read_attr("/no/such/temporion/file").p);
    puts("unit: UTF-8/trim, checked parsers, 100000 format cases, bounded reads: PASS");
}
