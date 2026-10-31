# Temporion x86

An independent **x86-64 assembly** rewrite of the daemon from
[Temporion](https://github.com/MasterZack69/temporion), with its own GNOME
extension identity. This repository is `MasterZack69/temporion-x86`, not an
in-place upgrade of the original project.

## Separate identities

Both projects can be installed together without sharing an executable name,
extension UUID, GObject type, panel status-area ID, CSS classes, or runtime
configuration keys.

| Component | This repository |
| --- | --- |
| Display name | Temporion x86 |
| Daemon executable | `temporion-x86d` |
| Nix daemon package | `.#temporion-x86d` |
| Nix extension package | `.#temporion-x86` (also the default) |
| Extension package name | `temporion-x86-gnome-extension` |
| GNOME extension UUID | `temporion-x86@masterzack69` |
| GObject type | `TemporionX86Indicator` |
| Panel status-area ID | `temporion-x86` |
| CSS class prefix | `temporion-x86-` |
| Environment prefix | `TEMPORION_X86_` |
| Cargo package (reference only) | `temporion-x86-rust-reference` |
| Cargo executable (reference only) | `temporion-x86d-rust-reference` |

There are **no legacy-name aliases or old-environment fallbacks** in the
production assembly daemon. The retained Rust reference still uses upstream
`TEMPORION_*` keys internally so its sensor source remains unchanged; the test
harness translates keys only when explicitly launching that reference.

## Build and run

Production daemon logic is in [`asm/temporion-x86d.S`](asm/temporion-x86d.S): GNU
assembler Intel syntax, System V AMD64 ABI. It links libc for filesystem,
allocation, timer and dynamic-loader services; NVML is loaded dynamically.
No Rust or C implementation code is linked into the production daemon.
This is not a libc-free or 32-bit build.

```sh
make
./build/temporion-x86d
make install PREFIX="$HOME/.local"
# x86_64-linux / NixOS:
nix build .#temporion-x86d
nix build .#temporion-x86
nix run .
gnome-extensions enable temporion-x86@masterzack69
```

The default Nix package installs the extension in its own UUID directory and
bakes the absolute `temporion-x86d` store path into its frontend. Manual installs
look up **only** `temporion-x86d` on PATH, never the original `temporiond`.
Both extensions may be enabled simultaneously; they produce separate readouts
and launch independent daemons. Each retains its own GPU-suspend policy.

For a NixOS flake input:

```nix
# inputs
temporion-x86.url = "github:MasterZack69/temporion-x86";
# configuration.nix, with inputs in specialArgs
environment.systemPackages = [ inputs.temporion-x86.packages.${pkgs.system}.default ];
```

## Protocol and configuration

The stdout protocol intentionally remains compatible:

```text
<cpu> <gpu> <disk0> <disk1> ...
61 52 39 44
```

A missing value is `-`. CPU discovery selects `k10temp` / `Tctl`; NVMe discovery
selects `nvme` / `Composite`, ordered by numeric controller index. Discovery is
once at startup; attributes are reopened each sample. Duplicate matching
CPU/label devices have no defined cross-implementation selection order; the
intended laptop has one Tctl and one Composite per controller.

| Variable | Default | Behavior |
| --- | --- | --- |
| `TEMPORION_X86_INTERVAL_MS` | `2000` | Trimmed unsigned decimal milliseconds, minimum 100; invalid/overflow uses default |
| `TEMPORION_X86_GPU_ALWAYS` | unset | Exactly `1` overrides the GPU suspend gate |

NVML initialization/device queries are deferred while the GPU is `suspended`,
unless explicitly overridden. Failed initialization is retried on later samples;
broken stdout pipes exit quietly. Sampling has no explicit daemon-owned heap
allocation (libc/NVML internals may allocate).

The parser validates UTF-8, uses Rust's Unicode whitespace set, bounds sysfs
attributes to 256 bytes (exact fit accepted), handles short/EINTR reads, and
checks numeric overflow. Temperature rounding preserves upstream release-Rust
`(milli + 500) / 1000`, including wrapping i32 addition and truncation toward zero.

## Tests and benchmarks

```sh
make test                      # unit, namespace/install and integration checks
cargo test                     # original five Rust helper tests
cargo build --release          # distinct Rust reference executable
make test differential         # both daemons + Rust parser oracle
make bench-build
TEMPORION_X86_RUST_BIN="$PWD/build/temporion-x86d-rust-speed" python3 tests/integration.py
python3 bench/run.py --samples 12000 --repeats 11
python3 bench/summarize.py
```

`make test` uses Python 3 and C test fixtures. `make differential` and benchmarks
also need Rust. C fixtures/shims are never linked into the shipped daemon.
The original Rust sensor sources are retained unchanged; only the Cargo package
and executable identities differ from upstream.

[`bench/RESULTS.md`](bench/RESULTS.md) documents the measured pre-rename snapshot,
raw trials and limitations. Historical artifact paths/hashes are intentionally
preserved as evidence rather than silently relabeled. Run the commands above
to benchmark the current namespaced build.

The Nix flake and actual GNOME coexistence have **not** been run in this sandbox
(no Nix/GNOME environment). Build the flake and verify the distinct extension
UUIDs, output and GPU suspend behavior on the actual NixOS laptop before deploying.

## License

AGPL-3.0-only.
