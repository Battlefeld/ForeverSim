"""The engine is wowsims/forever at a locked commit plus the level overlay (no engine patches)."""
import gzip
import json
import os
from pathlib import Path
import subprocess
import sys
from engine_identity import build_identity, leveling_digest

CORE = Path(__file__).resolve().parent


def git(source, *args, **kwargs):
    return subprocess.check_output(['git', '-C', str(source), *args], text=True, **kwargs).strip()


def lock_file():
    # engine_update.py stages a candidate lock here before it replaces the real one.
    return Path(os.environ.get('FOREVERCORE_LOCK') or CORE / 'engine.lock.json')


def client_build(source):
    """The newest game build the engine's spell data was generated from (assets/db_inputs/spell_store_inputs.json is
    gzipped despite its name; its Builds map stamps each part of the store)."""
    inputs = json.loads(gzip.open(Path(source) / 'assets/db_inputs/spell_store_inputs.json').read())
    builds = sorted(inputs['Builds'].values(), key=lambda b: [int(n) for n in b.split('.')])
    return builds[-1]


def read_lock():
    lock = json.loads(lock_file().read_text())
    sys.path.insert(0, str(CORE / 'engine-overlay'))
    from apply_overlay import overlay_digest
    if lock.get('overlay') != overlay_digest():
        raise ValueError('Level overlay differs from engine.lock.json; refresh the engine lock')
    data = Path(os.environ.get('FOREVERCORE_LEVEL_DATA') or CORE / 'leveling-data.json')
    if lock.get('levelDataSHA256') != leveling_digest(data):
        raise ValueError('Level data differs from engine.lock.json')
    expected = build_identity(lock['commit'], lock['overlay'], lock['levelDataSHA256'])
    if lock['buildIdentity'] != expected:
        raise ValueError('Engine buildIdentity does not match source, overlay and level data')
    return lock


def verify_source(source):
    """The checkout is the locked commit, unmodified, on the locked client build."""
    source = Path(source).resolve()
    lock = read_lock()
    if git(source, 'rev-parse', 'HEAD') != lock['commit']:
        raise ValueError('Engine checkout differs from engine.lock.json')
    if git(source, 'status', '--porcelain', '--untracked-files=no'):
        raise ValueError('Engine checkout has local changes')
    build = client_build(source)
    if build != lock['clientBuild']:
        raise ValueError('Unexpected client data: ' + build)
    return lock


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    args = parser.parse_args()
    verify_source(args.source)
    print(read_lock()['buildIdentity'])
