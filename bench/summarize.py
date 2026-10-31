#!/usr/bin/env python3
"""Standard-library-only reproduction summary; raw input remains unchanged."""
import json
import pathlib
import statistics
p=pathlib.Path(__file__).with_name('results.json')
rows=json.loads(p.read_text())['observations']
print('GPU state | Mode | Build | Median us/sample (startup: us/process) | Trials')
for key in sorted({(r['gpu'],r['mode'],r['version']) for r in rows}):
    selected=[r for r in rows if (r['gpu'],r['mode'],r['version'])==key]
    value=statistics.median(r['wall_ns']/r['samples']/1000 for r in selected)
    print(' | '.join(key),f'| {value:.3f} | {len(selected)}')
print('\nPaired median speedup (Rust wall time / assembly wall time):')
for gpu,mode in sorted({(r['gpu'],r['mode']) for r in rows}):
    for baseline in ['rust-size','rust-speed']:
        a={r['repeat']:r['wall_ns'] for r in rows if (r['gpu'],r['mode'],r['version'])==(gpu,mode,'assembly')}
        b={r['repeat']:r['wall_ns'] for r in rows if (r['gpu'],r['mode'],r['version'])==(gpu,mode,baseline)}
        assert a.keys()==b.keys()
        print(f'{gpu} {mode} vs {baseline}: {statistics.median(b[i]/a[i] for i in a):.3f}x')
