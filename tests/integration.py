#!/usr/bin/env python3
"""Same unmodified /sys contract for Rust and assembly via fixture-only shim."""
import os
import pathlib
import select
import subprocess
import tempfile

REPO = pathlib.Path(__file__).resolve().parents[1]
ASM = REPO / 'build/temporiond'
RUST = pathlib.Path(os.environ.get('TEMPORION_RUST_BIN', REPO / 'target/release/temporiond'))

def put(root, name, value):
    p = root / name
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_bytes(value if isinstance(value, bytes) else value.encode())
    return p

def fixture(root):
    put(root, 'class/hwmon/hwmon9/name', ' k10temp\n')
    put(root, 'class/hwmon/hwmon9/temp2_label', 'Tctl\n')
    put(root, 'class/hwmon/hwmon9/temp2_input', '60500\n')
    # hwmon and controller order deliberately disagree (numeric 2 < 10).
    for hw, idx, temp in [(0, 10, '44000\n'), (7, 2, '39000\n')]:
        d = f'class/hwmon/hwmon{hw}'
        put(root, d + '/name', 'nvme\n')
        put(root, d + '/temp1_label', 'Composite\n')
        put(root, d + '/temp1_input', temp)
        target = root / f'devices/nvme{idx}'
        target.mkdir(parents=True)
        (root / d / 'device').symlink_to(target)
        put(root, f'class/nvme/nvme{idx}/model', f' Disk {idx} \n')
    put(root, 'bus/pci/devices/0000:01:00.0/vendor', '0x10de\n')
    put(root, 'bus/pci/devices/0000:01:00.0/class', '0x030200\n')
    put(root, 'bus/pci/devices/0000:01:00.0/power/runtime_status', 'suspended\n')

def start(binary, root, **extra):
    env = dict(os.environ, TEMPORION_TEST_ROOT=str(root),
               LD_PRELOAD=str(REPO / 'build/redirect.so'),
               LD_LIBRARY_PATH=str(REPO / 'build'), TEMPORION_INTERVAL_MS='100',
               TEMPORION_TEST_NVML_LOG=str(root / 'nvml.log'))
    env.pop('TEMPORION_GPU_ALWAYS', None)
    env.update(extra)
    return subprocess.Popen([str(binary)], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

def line(p):
    ready, _, _ = select.select([p.stdout], [], [], 5)
    assert ready, 'daemon did not produce a sample'
    out = p.stdout.readline()
    assert out, f'daemon exited: {p.stderr.read()!r}'
    return out.decode().rstrip('\n')

def finish(p):
    p.stdout.close()
    try:
        p.wait(timeout=4)
    except subprocess.TimeoutExpired:
        p.kill(); p.wait(); raise
    assert p.returncode == 0, f'unclean pipe exit {p.returncode}'
    return p.stderr.read().decode()

def run(binary):
    count = 0
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        fixture(root)
        cpu = root / 'class/hwmon/hwmon9/temp2_input'
        status = root / 'bus/pci/devices/0000:01:00.0/power/runtime_status'
        log = root / 'nvml.log'
        p = start(binary, root, TEMPORION_TEST_SHORT_READS='1')
        try:
            assert line(p) == '61 - 39 44'; count += 1
            assert not log.exists(), 'suspended GPU was queried'
            # Lazy initialize when awake; every subsequent sample queries only temp.
            status.write_text('active\n')
            assert line(p) == '61 52 39 44'; count += 1
            assert line(p) == '61 52 39 44'
            calls = log.read_text().splitlines()
            assert calls.count('init') == 1 and calls.count('handle') == 1
            status.write_text('suspended\n')
            assert line(p) == '61 - 39 44'; count += 1
            calls = log.read_text()
            assert line(p) == '61 - 39 44'
            assert log.read_text() == calls, 'resuspended GPU queried'
            # Reopens every sample: content changes, removal, reappearance.
            cpu.write_bytes(b'\xc2\xa0-12500\xe3\x80\x80\n')
            assert line(p) == '-12 - 39 44'; count += 1
            cpu.write_bytes(b'2147483648\n')
            assert line(p) == '- - 39 44'; count += 1
            cpu.write_bytes(b'61000\0junk\n')
            assert line(p) == '- - 39 44'; count += 1
            cpu.write_bytes(b'\xff61000\n')
            assert line(p) == '- - 39 44'; count += 1
            cpu.write_bytes(b' ' * 251 + b'61000')  # exactly 256 accepted
            assert line(p) == '61 - 39 44'; count += 1
            cpu.write_bytes(b' ' * 252 + b'61000')
            assert line(p) == '- - 39 44'; count += 1
            cpu.unlink()
            assert line(p) == '- - 39 44'; count += 1
            cpu.write_text('71500\n')
            assert line(p) == '72 - 39 44'; count += 1
        finally:
            summary = finish(p)
        assert 'disks=2' in summary and 'disk0 = nvme2 (Disk 2)' in summary
        assert 'disk1 = nvme10 (Disk 10)' in summary
        log.unlink()
        p = start(binary, root, TEMPORION_GPU_ALWAYS='1')
        try: assert line(p) == '72 52 39 44'; count += 1
        finally: finish(p)
        log.unlink()
        status.write_text('active\n')
        p = start(binary, root, TEMPORION_TEST_NVML_FAIL='1')
        try:
            assert line(p) == '72 - 39 44'
            assert line(p) == '72 - 39 44'
            assert log.read_text().splitlines() == ['init', 'init']; count += 1
        finally: finish(p)
        log.unlink()
        for failure, expected in [('handle', ['init', 'handle', 'init', 'handle']),
                                  ('temperature', ['init', 'handle', 'temperature', 'temperature'])]:
            log.unlink(missing_ok=True)
            p = start(binary, root, TEMPORION_TEST_NVML_FAIL=failure)
            try:
                assert line(p) == '72 - 39 44'
                assert line(p) == '72 - 39 44'
                assert log.read_text().splitlines() == expected; count += 1
            finally: finish(p)
        log.unlink(missing_ok=True)
        p = start(binary, root, LD_LIBRARY_PATH=str(REPO / 'build/missing'))
        try:
            assert line(p) == '72 - 39 44'; count += 1
            assert not log.exists(), 'missing symbol must prevent initialization'
        finally: finish(p)
        p = start(binary, root, TEMPORION_TEST_NO_NVML='1')
        try:
            assert line(p) == '72 - 39 44'; count += 1
            assert not log.exists()
        finally: assert 'gpu=unavailable' in finish(p)
    # Entirely missing sysfs tree (no CPU, disks or PCI devices).
    with tempfile.TemporaryDirectory() as tmp:
        p = start(binary, pathlib.Path(tmp), TEMPORION_TEST_NO_NVML='1')
        try: assert line(p) == '- -'; count += 1
        finally: finish(p)
    return count

if __name__ == '__main__':
    binaries = [ASM] + ([RUST] if RUST.exists() else [])
    for binary in binaries:
        print(f'integration: {binary.name} ({binary.parent}): {run(binary)} scenarios PASS')
    if not RUST.exists():
        print('NOTE: Rust differential checks skipped; cargo build --release enables them.')
