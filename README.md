# Temporion

- Freon was a very very good extension for fetching temps, but the sad reality is that it only "was" and not "is"
- So I ~~decided to reinvent the wheel and~~ made temporion (llm did all the job while i was staring at the screen)
- Temporion's pronounciation is like Temp-o-ryan
- I had no wish to spend tokens on providing cross compatibility across systems that might never even use it, So it's designed to run solely on my LOQ 15ARP9
- I use bullet points wherever I want
- Sometimes I accidentally pronounce it as temporeon like vaporeon
# Attaching a fastfetch because why not

![fuckin fastfetch](./fastfetch.png)

---

## x86-64 daemon rewrite

The shipped daemon is now **hand-written x86-64 assembly** in
[`asm/temporiond.S`](asm/temporiond.S), using GNU assembler Intel syntax and
the System V AMD64 ABI. Production daemon logic contains no Rust or C.
It links libc for filesystem, allocation, timer, and dynamic-loader services;
NVML is still loaded dynamically. This is **not** a libc-free or 32-bit build.
The original Rust sources remain unchanged as an executable reference.

### Build and run

```sh
make                         # GCC/binutils, no Rust toolchain required
./build/temporiond
make install PREFIX="$HOME/.local"
# NixOS / x86_64-linux (extension automatically uses the assembly executable):
nix build .#temporiond
nix build .#temporion
nix run .
```

The Nix flake now intentionally exports packages only for `x86_64-linux`.
The GNOME extension and its line protocol have not changed:

```text
<cpu> <gpu> <disk0> <disk1> ...
61 52 39 44
```

A missing or unreadable value is `-`. CPU discovery selects `k10temp` / `Tctl`;
NVMe discovery selects `nvme` / `Composite`, ordered by numeric controller index.
Discovery occurs once; attributes are reopened each sample so disappearing or
replaced nodes are not held through stale descriptors. As in Rust, duplicate
matching CPU/label devices have no defined cross-implementation selection order.
The intended laptop has one Tctl and one Composite per controller.

| Variable | Default | Behavior |
| --- | --- | --- |
| `TEMPORION_INTERVAL_MS` | `2000` | Trimmed unsigned decimal milliseconds, minimum 100; invalid/overflow falls back to default |
| `TEMPORION_GPU_ALWAYS` | unset | Exactly `1` overrides the GPU suspend gate |

NVML initialization and device queries are deferred until the GPU is not
`suspended`, unless explicitly overridden. Failed initialization is retried on
later samples, and broken stdout pipes exit quietly. Sampling performs no
explicit daemon-owned heap allocation; libc/NVML internals may allocate.

The parser validates UTF-8, uses Rust's Unicode whitespace set, bounds sysfs
attributes to 256 bytes (exact fit accepted), handles short/EINTR reads, and
checks numeric overflow. Negative-temperature rounding deliberately preserves
the original release-Rust expression `(milli + 500) / 1000`, including its
wrapping i32 addition. That expression is not symmetric rounding for negatives.

### Correctness and performance

```sh
make test                    # assembly unit + synthetic sysfs/NVML scenarios
cargo test                   # original Rust helper tests
cargo build --release
make test differential       # both daemons + deterministic Rust parser oracle
make bench-build
TEMPORION_RUST_BIN="$PWD/build/temporiond-rust-speed" python3 tests/integration.py
python3 bench/run.py --samples 12000 --repeats 11
python3 bench/summarize.py
```

`make test` needs Python 3 and a C compiler **only for test fixtures**. If the
Rust release executable exists, the integration scenarios run against it too.
`make differential` and `make bench-build` additionally require Rust. See
[`bench/RESULTS.md`](bench/RESULTS.md) for measured comparisons, limitations, and
reproduction details. Raw trials are checked in; no performance win is inferred
merely from the use of assembly.

Nix packaging has been updated but was **not executed in the development
sandbox**, which has no Nix installation. Test the flake on the actual NixOS
laptop before switching the installed extension.
