#!/usr/bin/env python3
"""Guard the fork's independent installation and GNOME runtime namespace."""
import json
import pathlib
import re
import subprocess
import tempfile

R = pathlib.Path(__file__).resolve().parents[1]
metadata = json.loads((R / 'extension/metadata.json').read_text())
js = (R / 'extension/extension.js').read_text()
css = (R / 'extension/stylesheet.css').read_text()
flake = (R / 'flake.nix').read_text()
assembly = (R / 'asm/temporion-x86d.S').read_text()
cargo = (R / 'Cargo.toml').read_text()
assert metadata['uuid'] == 'temporion-x86@masterzack69'
assert metadata['name'] == 'Temporion x86'
assert metadata['url'] == 'https://github.com/MasterZack69/temporion-x86'
assert 'uuid = "temporion-x86@masterzack69";' in flake
assert "GTypeName: 'TemporionX86Indicator'" in js
assert "addToStatusArea('temporion-x86'," in js
assert "find_program_in_path('temporion-x86d')" in js
assert "[found ?? 'temporion-x86d']" in js
assert "const DAEMON_PATH = '@TEMPORION_X86D@';" in js
assert "--replace-fail '@TEMPORION_X86D@' '${temporion-x86d}/bin/temporion-x86d'" in flake
for name in re.findall(r"style_class: '([^']+)'", js):
    assert name.startswith('temporion-x86-') and f'.{name} ' in css
assert 'mainProgram = "temporion-x86d";' in flake
assert 'inherit temporion-x86d temporion-x86;' in flake
assert 'inherit (self.packages.${system}) temporion-x86d temporion-x86;' in flake
assert '.asciz "TEMPORION_X86_INTERVAL_MS"' in assembly
assert '.asciz "TEMPORION_X86_GPU_ALWAYS"' in assembly
assert '"TEMPORION_INTERVAL_MS"' not in assembly
assert '"TEMPORION_GPU_ALWAYS"' not in assembly
assert 'name = "temporion-x86-rust-reference"' in cargo
assert 'name = "temporion-x86d-rust-reference"' in cargo
assert 'temporion@masterzack69' not in flake + js + css
assert 'GTypeName: \'TemporionIndicator\'' not in js
with tempfile.TemporaryDirectory() as tmp:
    subprocess.run(['make', 'install', 'PREFIX=/usr', f'DESTDIR={tmp}'], cwd=R, check=True, stdout=subprocess.DEVNULL)
    installed = list((pathlib.Path(tmp) / 'usr/bin').iterdir())
    assert [p.name for p in installed] == ['temporion-x86d']
print('identity: package/daemon/UUID/GType/panel/CSS/env and staged install: PASS')
# Prove inherited original-project keys neither wake this daemon's GPU nor
# replace its independently configured sampling interval.
import select
from integration import ASM, fixture, start, line, finish
with tempfile.TemporaryDirectory() as tmp:
    root = pathlib.Path(tmp)
    fixture(root)
    p = start(ASM, root, TEMPORION_INTERVAL_MS='9999', TEMPORION_GPU_ALWAYS='1')
    try:
        assert line(p) == '61 - 39 44'
        ready, _, _ = select.select([p.stdout], [], [], 2)
        assert ready, 'original TEMPORION_INTERVAL_MS overrode the fork interval'
        assert line(p) == '61 - 39 44'
        assert not (root / 'nvml.log').exists(), 'original GPU override leaked into fork'
    finally:
        summary = finish(p)
    assert summary.startswith('temporion-x86d:')
print('identity: original-project environment keys do not affect assembly daemon: PASS')
