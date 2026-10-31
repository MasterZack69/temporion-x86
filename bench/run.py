#!/usr/bin/env python3
"""Randomized paired fixture benchmark; raw observations saved, never gated in CI."""
import argparse
import hashlib
import json
import os
import pathlib
import platform
import random
import subprocess
import sys
import tempfile
import time
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / 'tests'))
from integration import REPO, fixture

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--samples',type=int,default=20000)
    parser.add_argument('--repeats',type=int,default=11)
    parser.add_argument('--out',default='bench/results.json')
    args=parser.parse_args()
    cpu=min(os.sched_getaffinity(0));os.sched_setaffinity(0,{cpu})
    observations=[];rng=random.Random(42)
    with tempfile.TemporaryDirectory() as tmp:
        root=pathlib.Path(tmp);fixture(root)
        env=dict(os.environ,TEMPORION_TEST_ROOT=str(root),
                 LD_PRELOAD=str(REPO/'build/redirect.so'),
                 LD_LIBRARY_PATH=str(REPO/'build'))
        for name in ['TEMPORION_TEST_NVML_LOG','TEMPORION_TEST_SHORT_READS','TEMPORION_TEST_NVML_FAIL','TEMPORION_TEST_NO_NVML','TEMPORION_GPU_ALWAYS']:
            env.pop(name,None)
        for gpu in ['suspended','active']:
            (root/'bus/pci/devices/0000:01:00.0/power/runtime_status').write_text(gpu+'\n')
            for mode in ['sample','write']:
                for repeat in range(args.repeats):
                    versions=['assembly','rust-size','rust-speed'];rng.shuffle(versions)
                    for version in versions:
                        with open(os.devnull,'wb') as null:
                            r=subprocess.run([str(REPO/f'build/bench-{version}'),str(args.samples),mode],env=env,stdout=null,stderr=subprocess.PIPE,check=True)
                        row=json.loads(r.stderr)
                        row.update(version=version,gpu=gpu,mode=mode,repeat=repeat,samples=args.samples)
                        observations.append(row)
        # Startup + discovery + first sample + failing stdout => no timer sleep.
        for repeat in range(args.repeats*5):
            versions=['assembly','rust-size','rust-speed'];rng.shuffle(versions)
            paths={'assembly':REPO/'build/temporiond','rust-size':REPO/'target/release/temporiond','rust-speed':REPO/'build/temporiond-rust-speed'}
            for version in versions:
                with open('/dev/full','wb') as full, open(os.devnull,'wb') as null:
                    begin=time.perf_counter_ns()
                    subprocess.run([str(paths[version])],env=env,stdout=full,stderr=null,check=True)
                    elapsed=time.perf_counter_ns()-begin
                observations.append(dict(version=version,gpu='active',mode='startup',repeat=repeat,samples=1,wall_ns=elapsed))
    metadata=dict(cpu=cpu,machine=platform.machine(),platform=platform.platform(),
                  rust=subprocess.check_output(['rustc','--version'],text=True).strip(),
                  gcc=subprocess.check_output(['cc','--version'],text=True).splitlines()[0],
                  head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=REPO,text=True).strip(),
                  seed=42,fixture='AMD Tctl + two NVMe regular files + runtime_status; fake NVML; warm page cache; LD_PRELOAD maps /sys; one pinned virtual CPU',
                  limitations='No real hwmon/NVML hardware, power, or compositor measurements. Startup includes process/loader overhead. Shared virtual host, not bare metal.')
    sources=['asm/temporiond.S','bench/assembly.c','bench/rust.rs','tests/redirect.c','tests/nvml.c',
             'src/main.rs', *[str(p.relative_to(REPO)) for p in sorted((REPO/'src/sensors').glob('*.rs'))]]
    binaries=['build/temporiond','build/bench-assembly','build/bench-rust-size','build/bench-rust-speed',
              'build/temporiond-rust-speed','target/release/temporiond','build/redirect.so','build/libnvidia-ml.so.1']
    metadata['source_sha256']={p:hashlib.sha256((REPO/p).read_bytes()).hexdigest() for p in sources}
    metadata['binary_sha256']={p:hashlib.sha256((REPO/p).read_bytes()).hexdigest() for p in binaries}
    output=dict(metadata=metadata,observations=observations)
    pathlib.Path(args.out).write_text(json.dumps(output,indent=2)+'\n')
    print(f'wrote {len(observations)} observations to {args.out}')
if __name__=='__main__':main()
