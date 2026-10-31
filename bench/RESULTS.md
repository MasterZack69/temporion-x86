# Benchmark results — x86-64 rewrite

## Outcome

Assembly wins the paired median comparison against both Rust profiles in all four steady-state fixture workloads. This is a software-overhead result, not a real-hardware or battery-life claim.

## Steady-state wall time

All times are median microseconds per complete sample across 11 trials per build/workload. Each trial performs 12,000 samples. The timer excludes discovery and 100 warm-up samples; the normal 100–2000 ms sleep is deliberately excluded.

| GPU fixture | Mode | Assembly (µs) | Rust -Os (µs) | Rust -O3 (µs) | Paired speedup vs -O3 |
| --- | --- | ---: | ---: | ---: | ---: |
| suspended | sample | 6.426 | 7.078 | 7.073 | 1.102× |
| suspended | write | 6.635 | 7.334 | 7.407 | 1.099× |
| active | sample | 6.956 | 7.819 | 7.770 | 1.093× |
| active | write | 6.610 | 7.519 | 7.296 | 1.104× |

“Sample” builds the full line; “write” additionally sends it to `/dev/null`, including Rust stdout flushes as in its daemon. Active GPU uses a stub returning 52°C, not the proprietary driver. All modes read the CPU, two disks and PCI runtime status through the same fixture-only `/sys` mapping shim.

The speedup column is the median of paired per-trial Rust/assembly wall-time ratios, not the ratio of separately computed medians. Do not interpret differences between sampling and write rows as an I/O speed benefit: those are separate trial batches subject to host noise.

## Paired uncertainty

95% percentile bootstrap intervals for the median paired speedup, using 10,000 resamples (seed 19). These describe run-to-run variation on this host, not uncertainty across machines.

| GPU | Mode | Baseline | Speedup | Bootstrap 95% interval | Assembly wins |
| --- | --- | --- | ---: | ---: | ---: |
| active | sample | rust-size | 1.109× | 1.063–1.127× | 9/11 |
| active | sample | rust-speed | 1.093× | 1.037–1.110× | 10/11 |
| active | startup | rust-size | 1.243× | 1.235–1.255× | 53/55 |
| active | startup | rust-speed | 1.244× | 1.240–1.249× | 53/55 |
| active | write | rust-size | 1.111× | 1.102–1.145× | 11/11 |
| active | write | rust-speed | 1.104× | 1.092–1.114× | 10/11 |
| suspended | sample | rust-size | 1.103× | 1.098–1.108× | 11/11 |
| suspended | sample | rust-speed | 1.102× | 1.098–1.107× | 11/11 |
| suspended | write | rust-size | 1.096× | 1.080–1.120× | 10/11 |
| suspended | write | rust-speed | 1.099× | 1.084–1.130× | 10/11 |

## Startup

Median startup + discovery + first sample + error exit: assembly **536.300 µs**, Rust -Os **667.745 µs**, Rust -O3 **667.084 µs** (55 trials/build). Stdout is `/dev/full`, so neither daemon reaches its sleep. This includes process creation and the dynamic loader; it is not pure sensor-discovery latency.

## Method and reproduction

- x86-64 Intel Xeon virtual CPU; Linux sandbox with two exposed logical CPUs. Each benchmark process inherits affinity to one CPU. No frequency locking or bare-metal isolation.
- rustc 1.99.1 (58cf8f9c3 2026-10-13); cc (GCC) 11.5.0 20240719 (Red Hat 11.5.0-5).
- Rust -Os mirrors the repository profile; -O3 changes optimization level only. Both use LTO, one codegen unit, panic=abort, and stripped symbols. No target-cpu=native advantage for either side.
- Original Rust sensor sources remain unchanged. Both drivers discover once, reuse their output buffers, append a newline, and consume output. Matching sample checksums are asserted during analysis.
- Randomized build order within each paired repeat, deterministic seed 42; warm page cache, regular files rather than actual sysfs hardware.
- Raw observations: `results.json`; aggregate/evidence: `summary.json`. CPU-time and checksum fields are intentionally absent for startup measurements, not zero.
- Source and measured executable SHA-256 values are recorded in `results.json`. Its HEAD is the shared Rust baseline; uncommitted rewrite sources are identified by these hashes.

```sh
make bench-build
python3 bench/run.py --samples 12000 --repeats 11
python3 bench/summarize.py
```

## Validation and limits

- 100,000 integer-format cases, bounded read and parser unit tests; 12,095 deterministic UTF-8/trim/parser cases match Rust.
- 18 integration scenarios pass for assembly, original release Rust, and -O3 Rust, including NVMe numeric order, disappearing attributes, malformed data, exact-fit/oversized reads, short reads/EINTR, quiet broken-pipe exit, suspended/resumed GPU gating, absent library/symbols, and initialization/handle/temperature failures.
- `cargo test` (five original tests) and `cargo clippy --all-targets -- -D warnings` pass.
- Nix packaging was updated but cannot be built in this sandbox (no Nix). CI configuration is provided; a successful remote CI run is not assumed.
- **Not measured:** Ryzen hwmon latency, actual NVIDIA driver/device behavior, GNOME compositor responsiveness, energy, battery life, or long-running hotplug behavior on the LOQ.
- At a two-second polling interval, microseconds saved per sample do not establish a noticeable UI improvement. Hardware I/O may dominate and reduce or erase this overhead advantage.

Before deployment: build the flake on the laptop, compare both line streams and suspended-GPU behavior there, then repeat sampling/startup measurements under equivalent load. Keep the Rust baseline available for rollback.
