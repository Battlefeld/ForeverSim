"""Build the pinned wowsims/forever engine with the level 10-60 overlay."""
import argparse
from pathlib import Path
import subprocess
import sys
import tempfile
from engine_source import CORE, read_lock, verify_source
import json
import hashlib
from talent_layout import write as write_talent_layout
sys.path.insert(0, str(CORE / 'engine-overlay'))
from apply_overlay import apply as apply_level_overlay  # noqa: E402

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--engine-source', type=Path, default=CORE.parent / 'deps/engine')
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--manifest', type=Path, default=CORE / 'engine-data.json')
parser.add_argument('--check', action='store_true', help='Run upstream regression tests before building')
args = parser.parse_args()
source = args.engine_source.resolve()
if not source.exists():
    subprocess.run([sys.executable, str(CORE / 'checkout_engine.py'), '--destination', str(source)], check=True)
verify_source(source)
with tempfile.TemporaryDirectory(prefix='forevercore-engine-') as temp:
    stage = Path(temp) / 'source'
    subprocess.run(['git', 'clone', '--shared', '--no-checkout', str(source), str(stage)], check=True)
    subprocess.run(['git', '-C', str(stage), 'checkout', '--detach', read_lock()['commit']], check=True)
    # The adapter manifest reads the upstream tree, before the level overlay touches it.
    subprocess.run([sys.executable, str(CORE / 'prepare_engine.py'), str(stage), str(args.manifest.resolve())], check=True)
    level = apply_level_overlay(stage, CORE / 'leveling-data.json')
    manifest = json.loads(args.manifest.read_text())
    manifest.update(levelRange=[10, 60], levelOverlay=level['overlay'], liveHunter='hunter-live-ammo' in level['applied'],
                    liveWarlock='warlock-live-demon-stats' in level['applied'])
    args.manifest.write_text(json.dumps(manifest, separators=(',', ':')))
    protos = sorted(str(p.relative_to(stage)) for p in (stage / 'proto').glob('*.proto'))
    subprocess.run(['protoc', '-I=proto', '--go_out=paths=source_relative:sim/core/proto', *protos], cwd=stage, check=True)
    if args.check:
        # Every upstream package runs with the overlay: level 60 must not move. sim/web needs the UI build.
        packages = [p for p in subprocess.check_output(['go', 'list', '-e', './sim/...'], cwd=stage, text=True).split()
                    if not p.endswith('/sim/web')]
        subprocess.run(['go', 'test', '-tags=with_db', *packages], cwd=stage, check=True)
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['go', 'build', '-tags=with_db', '-trimpath', '-o', str(output), './cmd/wowsimcli'], cwd=stage, check=True)
    manifest['engineSHA256'] = hashlib.sha256(output.read_bytes()).hexdigest()
    args.manifest.write_text(json.dumps(manifest, separators=(',', ':')))
write_talent_layout(manifest, CORE.parent / 'ForeverSimBridge/TalentLayoutData.lua')
print(read_lock()['buildIdentity'])
