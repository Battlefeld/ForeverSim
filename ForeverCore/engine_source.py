"""Direct MythicSim dependency with a locked, reviewable patch overlay."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
from engine_identity import build_identity, leveling_digest
import sys

CORE = Path(__file__).resolve().parent


def git(source, *args, **kwargs):
    return subprocess.check_output(['git', '-C', str(source), *args], text=True, **kwargs).strip()


def lock_file():
    # engine_update.py stages a candidate lock here before it replaces the real one.
    return Path(os.environ.get('FOREVERCORE_LOCK') or CORE / 'engine.lock.json')


def read_lock():
    lock = json.loads(lock_file().read_text())
    for patch in lock['patches']:
        path = (CORE / patch['file']).resolve()
        if not path.is_relative_to(CORE) or hashlib.sha256(path.read_bytes()).hexdigest() != patch['sha256']:
            raise ValueError('Engine patch checksum mismatch: ' + patch['file'])
    sys.path.insert(0, str(CORE / 'engine-overlay'))
    from apply_overlay import overlay_digest
    if lock.get('overlay') != overlay_digest():
        raise ValueError('Level overlay differs from engine.lock.json; refresh the engine lock')
    data = Path(os.environ.get('FOREVERCORE_LEVEL_DATA') or CORE / 'leveling-data.json')
    if lock.get('levelDataSHA256') != leveling_digest(data):
        raise ValueError('Level data differs from engine.lock.json')
    expected = build_identity(lock['commit'], lock['patches'], lock['overlay'], lock['levelDataSHA256'])
    if lock['buildIdentity'] != expected:
        raise ValueError('Engine buildIdentity does not match source, patches, overlay and level data')
    return lock


def verify_source(source, patched=True):
    source = Path(source).resolve()
    lock = read_lock()
    if git(source, 'rev-parse', 'HEAD') != lock['commit']:
        raise ValueError('Engine checkout differs from engine.lock.json')
    # Build an expected index without changing the checkout's own index.
    with tempfile.TemporaryDirectory(prefix='forevercore-index-') as temp:
        env = dict(os.environ, GIT_INDEX_FILE=str(Path(temp) / 'index'))
        git(source, 'read-tree', 'HEAD', env=env)
        if patched:
            for patch in lock['patches']:
                git(source, 'apply', '--cached', '--whitespace=nowarn', str(CORE / patch['file']), env=env)
        git(source, 'diff', '--exit-code', env=env)
    build = (source / 'assets/db_inputs/forever_client_build.txt').read_text().strip()
    if build != lock['clientBuild']:
        raise ValueError('Unexpected client data: ' + build)
    return lock


def overlay(source):
    lock = verify_source(source, patched=False)
    for patch in lock['patches']:
        git(source, 'apply', '--whitespace=nowarn', str(CORE / patch['file']))
    verify_source(source)


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--overlay', action='store_true')
    args = parser.parse_args()
    if args.overlay:
        overlay(args.source)
    else:
        verify_source(args.source)
    print(read_lock()['buildIdentity'])
