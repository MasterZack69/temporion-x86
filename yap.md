> Rewrite note: the packaged daemon is now x86-64 assembly. The original Rust
> implementation is retained for comparison. See README.md and bench/RESULTS.md
> for current build instructions, tests and measured performance.

# temporion

Temperature fetcher extension for GNOME — because freon still lags.

Shows **CPU**, **GPU**, **disk0** and **disk1** temperatures in the GNOME top
bar (left side, right after the workspace indicator), in that order.

Built specifically for one machine — no cross-hardware bloat:

- **x86_64 NixOS**, GNOME 50
- **CPU:** Ryzen 7 7435HS → `k10temp` **Tctl**
- **GPU:** RTX 4050 → **NVML**
- **Disks:** two NVMe SSDs (Micron + WD) → `nvme` **Composite** sensor

## Why it doesn't stutter like freon

freon reads sensor files and shells out to `nvidia-smi` **synchronously inside
the `gnome-shell` process**, blocking the compositor's main loop on every poll —
that's the jank.

Temporion splits the work:

- **`temporiond`** — a small x86-64 assembly daemon that reads every sensor on its own
  timer, in its own process, and streams one line of temperatures to stdout.
- **the extension** — ~200 lines of GJS (unavoidable: extensions must have a
  JavaScript entry point, there is no Rust runtime inside gnome-shell) that
  reads those lines **asynchronously** and just updates labels. gnome-shell
  never does blocking sensor I/O, so the compositor never stalls.

### How each temperature is read (no root, no subprocess spawning)

| Sensor | Source | Notes |
| --- | --- | --- |
| CPU | `/sys/class/hwmon/*/` where `name == k10temp`, `Tctl` label | plain sysfs read |
| GPU | `libnvidia-ml.so.1` via `dlopen` (NVML) | no `nvidia-smi` spawn |
| Disks | `/sys/class/hwmon/*/` where `name == nvme`, `Composite` label | no `smartctl`, no root |

The production daemon is assembly linked to libc; NVML is loaded dynamically.
The original Rust baseline has zero external crates and is retained unchanged.

**Battery note:** on this Optimus laptop the RTX 4050 is often
runtime-suspended. Querying NVML would force it back on, so by default the
daemon checks the GPU's PCI `power/runtime_status` first and reports `–` while
it is suspended instead of waking it. Set `TEMPORION_GPU_ALWAYS=1` to always
query it.

## Install (NixOS, flake)

Add the extension package to your system (it pulls the daemon in automatically):

```nix
# flake.nix inputs
temporion.url = "github:MasterZack69/temporion-x86";

# configuration.nix (with inputs in specialArgs)
environment.systemPackages = [ inputs.temporion.packages.${pkgs.system}.default ];
```

Rebuild, then enable **Temporion** in the Extensions app (or
`gnome-extensions enable temporion@masterzack69`). Log out/in if GNOME doesn't
pick it up immediately.

### Try the daemon without installing

```sh
nix run github:MasterZack69/temporion-x86
# prints: <cpu> <gpu> <disk0> <disk1>  e.g.  61 52 44 39
# (a field is "-" when that sensor is unavailable)
```

## Configuration

Environment variables read by `temporiond`:

| Variable | Default | Meaning |
| --- | --- | --- |
| `TEMPORION_INTERVAL_MS` | `2000` | sample interval in milliseconds (min 100) |
| `TEMPORION_GPU_ALWAYS` | unset | set to `1` to query the dGPU even while suspended |

Panel colour thresholds and position are constants at the top of
`extension/extension.js`.

## Development

```sh
nix develop          # cargo, rustc, clippy, rustfmt, gjs, node
make && ./build/temporiond  # assembly daemon
make test differential     # assembly/Rust correctness checks
cargo clippy               # retained Rust baseline lints
```

Build just the daemon or the packaged extension:

```sh
nix build .#temporiond
nix build .#temporion
```

## Layout

```
asm/
  temporiond.S         production x86-64 daemon
Makefile               assembly build, tests and benchmarks
src/                   unchanged Rust reference
  main.rs              loop + stdout streaming
  sensors/
    mod.rs             discovery + sampling
    hwmon.rs           shared sysfs helpers
    cpu.rs             k10temp / Tctl
    gpu.rs             NVML via dlopen (+ suspend gate)
    disk.rs            nvme Composite
extension/
  extension.js         thin async GJS frontend
  metadata.json
  stylesheet.css
flake.nix              builds temporiond + the extension
```

## License

AGPL-3.0-only.
