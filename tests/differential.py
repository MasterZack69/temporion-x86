#!/usr/bin/env python3
"""Deterministic UTF-8, trim and decimal-parser differential corpus."""
import pathlib
import random
import subprocess
R=pathlib.Path(__file__).resolve().parents[1]
rng=random.Random(17)
white=[9,10,11,12,13,32,0x85,0xa0,0x1680,*range(0x2000,0x200b),0x2028,0x2029,0x202f,0x205f,0x3000]
cases=[b'',b'+',b'-',b'-+1',b'\0',b'2147483647',b'2147483648',b'-2147483648',b'-2147483649',b'18446744073709551615',b'18446744073709551616']
for cp in white+[0x200b,0xfeff,0x180e]:
 w=chr(cp).encode();cases.extend([w,w+b'61000'+w,w+b'-12500'+w])
for _ in range(12000):
 choice=rng.randrange(3)
 if choice==0:raw=rng.randbytes(rng.randrange(0,270))
 elif choice==1:raw=(''.join(chr(rng.choice(white)) for _ in range(rng.randrange(4)))+str(rng.randrange(-2**65,2**65))+''.join(chr(rng.choice(white)) for _ in range(rng.randrange(4)))).encode()
 else:
  cps=[rng.randrange(0x110000) for _ in range(rng.randrange(1,20))]
  raw=''.join(chr(c) for c in cps if not 0xd800<=c<=0xdfff).encode()
 cases.append(raw)
corpus=''.join(r.hex()+'\n' for r in cases).encode()
a=subprocess.check_output([R/'build/probe'],input=corpus).splitlines()
b=subprocess.check_output([R/'build/oracle'],input=corpus).splitlines()
assert len(a)==len(b)==len(cases)
for i,(x,y) in enumerate(zip(a,b)):
 assert x==y,(i,cases[i],x,y)
print(f'differential: {len(cases)} UTF-8/trim/parser cases match Rust')
