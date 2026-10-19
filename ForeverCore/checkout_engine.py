"""Fetch the official MythicSim source at the reviewed revision. Never follows a moving branch."""
import argparse
from pathlib import Path
import subprocess
from engine_source import CORE, git, read_lock, verify_source

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--destination', type=Path, default=CORE.parent / 'deps/mythicsim')
args = parser.parse_args()
dest = args.destination.resolve()
lock = read_lock()
if not dest.exists():
    dest.mkdir(parents=True)
    subprocess.run(['git', 'init', str(dest)], check=True)
    subprocess.run(['git', '-C', str(dest), 'remote', 'add', 'origin', lock['repository']], check=True)
else:
    if git(dest, 'remote', 'get-url', 'origin').removesuffix('.git') != lock['repository'].removesuffix('.git'):
        raise SystemExit('Destination is not the locked MythicSim repository')
    if git(dest, 'status', '--porcelain', '--untracked-files=all'):
        raise SystemExit('Engine checkout has local changes; preserve them before updating')
subprocess.run(['git', '-C', str(dest), 'fetch', '--depth=1', 'origin', lock['commit']], check=True)
subprocess.run(['git', '-C', str(dest), 'checkout', '--detach', lock['commit']], check=True)
verify_source(dest, patched=False)
print(dest)
