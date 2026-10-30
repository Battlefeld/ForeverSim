"""Follow MythicSim automatically: newest upstream, ForeverCore patches, level overlay, full checks.

Steps (each one stops the run on failure, so engine.lock.json keeps the last good engine):
  1. Fetch every mythicsim/* branch and pick the newest tip that contains the locked commit. When
     no branch descends from it (upstream rewrote history) the newest tip is taken and reported.
  2. Drop every ForeverCore patch whose upstreamCommit the new base already contains; check that
     the rest still apply.
  3. Refresh leveling-data.json from the client's PlayerExpectedStat (wago.tools CSV for the
     client build the base names). Without that build on wago.tools the old table stays and the
     overlay test proves it still matches upstream's level-60 values.
  4. Build upstream and upstream+patches+overlay; run every upstream Go test with the overlay
     (level 60 must not move), compare both CLIs on reference requests, and run the level smoke
     (all spec suites at several levels: no panic, no unlearnt rank cast, DPS rising with level).
  5. Write engine.lock.json, leveling-data.json, creature-families.json and engine-update-report.json.

    python engine_update.py --work /tmp/fc-engine [--branch mythicsim/client70425] [--dry-run]
"""
import argparse
import csv
import hashlib
import io
import json
import os
import re
import math
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import urllib.request

CORE = Path(__file__).resolve().parent
OVERLAY = CORE / 'engine-overlay'
sys.path.insert(0, str(OVERLAY))
from apply_overlay import apply as apply_overlay, overlay_digest, OverlayError  # noqa: E402
from golden_dps import suite_dps  # noqa: E402
from engine_identity import build_identity, leveling_digest
from talent_layout import write as write_talent_layout
from compare_results import canon, differences  # noqa: E402

SMOKE_LEVELS = [10, 20, 30, 45, 59]
REFERENCE_REQUESTS = [
    'sim/warlock/testdata/imp-brand/kerani.request.json',
    'sim/paladin/retribution/testdata/lights_vigil_request.json',
]


class UpdateError(Exception):
    pass


def sh(*cmd, cwd=None, env=None, capture=False, check=True):
    p = subprocess.run([str(c) for c in cmd], cwd=cwd, env=env, text=True,
                       capture_output=capture)
    if check and p.returncode != 0:
        tail = (p.stderr or p.stdout or '')[-3000:] if capture else ''
        raise UpdateError(f'{" ".join(map(str, cmd[:4]))} failed ({p.returncode})\n{tail}')
    return p.stdout.strip() if capture else p.returncode


def git(repo, *args, **kw):
    return sh('git', '-C', repo, *args, capture=True, **kw)


def lock_path():
    return CORE / 'engine.lock.json'


# 1. upstream -------------------------------------------------------------------------------------

def fetch_upstream(repo, url):
    if not (repo / '.git').exists():
        repo.mkdir(parents=True, exist_ok=True)
        sh('git', 'init', '-q', repo)
        sh('git', '-C', repo, 'remote', 'add', 'origin', url)
    sh('git', '-C', repo, 'fetch', '-q', '--filter=blob:none', 'origin',
       '+refs/heads/mythicsim/*:refs/remotes/origin/mythicsim/*')


def pick_base(repo, locked, forced=None):
    if forced:
        ref = f'origin/{forced}'
        return forced, git(repo, 'rev-parse', ref), True
    rows = git(repo, 'for-each-ref', '--sort=-committerdate', '--format=%(refname:short) %(objectname)',
               'refs/remotes/origin/mythicsim').splitlines()
    branches = [r.split() for r in rows if r.strip()]
    if not branches:
        raise UpdateError('no mythicsim/* branches upstream')
    have_locked = subprocess.run(['git', '-C', str(repo), 'cat-file', '-e', locked + '^{commit}'],
                                 capture_output=True).returncode == 0
    for ref, sha in branches:
        if have_locked and subprocess.run(['git', '-C', str(repo), 'merge-base', '--is-ancestor', locked, sha],
                                          capture_output=True).returncode == 0:
            return ref.removeprefix('origin/'), sha, True
    ref, sha = branches[0]
    return ref.removeprefix('origin/'), sha, False


# 2. patches --------------------------------------------------------------------------------------

def settle_patches(repo, base, patches):
    kept, dropped = [], []
    for p in patches:
        up = p.get('upstreamCommit')
        if up and subprocess.run(['git', '-C', str(repo), 'merge-base', '--is-ancestor', up, base],
                                 capture_output=True).returncode == 0:
            dropped.append(p['file'])
            continue
        kept.append(p)
    return kept, dropped


def checkout(repo, base, dest):
    # A worktree of the blobless clone fetches the blobs it needs from the promisor remote.
    if dest.exists():
        shutil.rmtree(dest)
    sh('git', '-C', repo, 'worktree', 'prune')
    sh('git', '-C', repo, 'worktree', 'add', '-q', '--detach', dest, base)


def apply_patches(src, patches):
    for p in patches:
        path = CORE / p['file']
        if hashlib.sha256(path.read_bytes()).hexdigest() != p['sha256']:
            raise UpdateError(f'patch checksum mismatch: {p["file"]}')
        if sh('git', '-C', src, 'apply', '--check', '--whitespace=nowarn', path, check=False, capture=False) != 0:
            raise UpdateError(f'{p["file"]} no longer applies to the new base and is not upstream yet')
        sh('git', '-C', src, 'apply', '--whitespace=nowarn', path)


# 3. level data -----------------------------------------------------------------------------------

def client_table(build, cache):
    """PlayerExpectedStat for the client build as an sqlite file, or None when wago.tools lacks it."""
    url = f'https://wago.tools/db2/PlayerExpectedStat/csv?build={build}'
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'ForeverCore engine_update'})
        text = urllib.request.urlopen(req, timeout=60).read().decode()
    except Exception as e:  # network or missing build
        print(f'wago.tools PlayerExpectedStat {build}: {e}; keeping the existing level table')
        return None
    rows = list(csv.DictReader(io.StringIO(text)))
    need = {'ClassID', 'Level', 'BaseMana', 'CritPerAgility', 'SpellCritPerIntellect', 'ContentSetID'}
    if not rows or not need <= set(rows[0]):
        print(f'wago.tools PlayerExpectedStat {build}: unexpected columns; keeping the existing level table')
        return None
    db = cache / f'PlayerExpectedStat-{build}.sqlite'
    db.unlink(missing_ok=True)
    with sqlite3.connect(db) as conn:
        conn.execute('CREATE TABLE PlayerExpectedStat (ClassID, Level, BaseMana, CritPerAgility, SpellCritPerIntellect, ContentSetID)')
        conn.executemany('INSERT INTO PlayerExpectedStat VALUES (?,?,?,?,?,?)',
                         [(int(r['ClassID']), int(r['Level']), float(r['BaseMana']), float(r['CritPerAgility']),
                           float(r['SpellCritPerIntellect']), int(r['ContentSetID'])) for r in rows])
    return db


# 4. checks ---------------------------------------------------------------------------------------

def go_env():
    env = dict(os.environ)
    env.pop('FOREVERCORE_LEVEL', None)
    env.pop('FOREVERCORE_SPELLBOOK', None)
    env.pop('FOREVERCORE_HUNTER', None)
    env.pop('FOREVERCORE_WARLOCK', None)
    return env


def protoc(src):
    protos = sorted(str(p.relative_to(src)) for p in (src / 'proto').glob('*.proto'))
    sh('protoc', '-I=proto', '--go_opt=Mgoogle/protobuf/descriptor.proto=google.golang.org/protobuf/types/descriptorpb',
       '--go_out=sim/core', *protos, cwd=src)


def prepare_checkout(src):
    """Generate upstream Go protobuf dependencies before any Go-based data extractor.

    prepare_leveling.py imports sim/core/spelldata, which imports sim/core/proto.
    The fresh upstream checkout does not contain generated proto Go sources.
    """
    prepare = os.environ.get('FOREVERCORE_PREPARE')
    if prepare:
        sh('bash', '-c', prepare, cwd=src)
    else:
        protoc(src)


def packages(src):
    # sim/web needs the UI build (binary_dist); it is not part of the engine.
    return [p for p in sh('go', 'list', '-e', './sim/...', cwd=src, capture=True).splitlines() if not p.endswith('/sim/web')]


def build_cli(src, out, goos=None):
    env = go_env()
    if goos:
        env.update(GOOS=goos, GOARCH='amd64', CGO_ENABLED='0')
    sh('go', 'build', '-tags=with_db', '-trimpath', '-o', out, './cmd/wowsimcli', cwd=src, env=env)


def run_cli(cli, request, out, level=None):
    env = go_env()
    if level:
        env['FOREVERCORE_LEVEL'] = str(level)
    sh(cli, 'sim', '--infile', request, '--outfile', out, env=env, capture=True)
    data = json.loads(Path(out).read_text())
    if data.get('error'):
        raise UpdateError(f'{Path(request).name} level {level}: {data["error"]}')
    return data


def spell_levels(src, out):
    with tempfile.TemporaryDirectory() as t:
        main = Path(t) / 'main.go'
        shutil.copyfile(OVERLAY / 'tools' / 'spell_levels.go.tmpl', main)
        Path(out).write_text(sh('go', 'run', main, cwd=src, capture=True, env=go_env()))
    return {int(k): v for k, v in json.loads(Path(out).read_text()).items()}


def used_spells(result):
    for party in result['raidMetrics']['parties']:
        for player in party['players']:
            for unit in [player] + player.get('pets', []):
                for a in unit.get('actions', []):
                    sid = a['id'].get('spellId')
                    if sid and any(t.get('casts') or t.get('damage') for t in a.get('targets', [])):
                        yield unit.get('name', ''), sid


def golden_suites(src):
    return sorted({p.name.split('.')[0] for p in src.rglob('*.results')} - {'TestProtoVersioning'})


def validate_level_golden(path, tmp, original):
    if not tmp.is_file():
        raise UpdateError(f'missing level test results: {path.name}')
    actual = tmp.read_text()
    expected_keys = sorted(re.findall(r'(?m)^ ?key:\s*"([^"\n]+)"', original.decode()))
    actual_keys = sorted(re.findall(r'(?m)^ ?key:\s*"([^"\n]+)"', actual))
    if not expected_keys or expected_keys != actual_keys:
        raise UpdateError(f'incomplete level test results: {path.name}')
    if re.search(r'(?i)\b(?:nan|inf|infinity)\b', actual):
        raise UpdateError(f'non-finite level test result: {path.name}')


def touched_packages(src, patches):
    """Go packages a ForeverCore patch edits; their golden suites move by design."""
    dirs = set()
    for p in patches:
        for line in (CORE / p['file']).read_text().splitlines():
            if line.startswith('+++ b/') and line.endswith('.go'):
                dirs.add(str(Path(line[6:]).parent))
    module = sh('go', 'list', '-m', cwd=src, capture=True)
    return {f'{module}/{d}' for d in dirs}


def checks(upstream_src, parity_src, shipped_src, patches, work, report):
    """parity = upstream + overlay (must equal upstream at 60); shipped = upstream + patches + overlay."""
    print('upstream Go tests with the overlay, no ForeverCore patches (level 60 must not move)...')
    sh('go', 'test', '-tags=with_db', '-count=1', *packages(parity_src), cwd=parity_src, env=go_env())
    suites = golden_suites(shipped_src)
    touched = touched_packages(shipped_src, patches)
    pk = packages(shipped_src)
    print('shipped engine tests (patched packages without their goldens)...')
    plain = [p for p in pk if p not in touched]
    if plain:
        sh('go', 'test', '-tags=with_db', '-count=1', *plain, cwd=shipped_src, env=go_env())
    if touched & set(pk):
        sh('go', 'test', '-tags=with_db', '-count=1', '-skip', '^(' + '|'.join(suites) + ')$',
           *sorted(touched & set(pk)), cwd=shipped_src, env=go_env())
    up_cli, par_cli, ov_cli = work / 'wowsimcli-upstream', work / 'wowsimcli-parity', work / 'wowsimcli-overlay'
    build_cli(upstream_src, up_cli)
    build_cli(parity_src, par_cli)
    build_cli(shipped_src, ov_cli)
    overlay_src = shipped_src
    taught = spell_levels(overlay_src, work / 'spell-levels.json')
    problems, cli_rows = [], []
    for rel in REFERENCE_REQUESTS:
        req = overlay_src / rel
        if not req.exists():
            report.setdefault('notes', []).append(f'reference request {rel} missing upstream')
            continue
        data = json.loads(req.read_text())
        data.setdefault('simOptions', {}).update(iterations=300, randomSeed='7', debugFirstIteration=False)
        req = work / Path(rel).name
        req.write_text(json.dumps(data))
        up = run_cli(up_cli, req, work / 'up.json')
        par = run_cli(par_cli, req, work / 'par.json')
        ov = run_cli(ov_cli, req, work / 'ov.json')
        diff = differences(canon(up), canon(par))
        if diff:
            problems.append(f'{req.name}: level 60 differs from upstream: ' + '; '.join(diff[:5]))
        for level in SMOKE_LEVELS:
            res = run_cli(ov_cli, req, work / f'l{level}.json', level)
            current_dps = res['raidMetrics']['dps']['avg']
            if not math.isfinite(current_dps) or current_dps <= 0:
                problems.append(f'{req.name} level {level}: no finite positive damage')
            cli_rows.append({'request': req.name, 'level': level, 'dps': round(current_dps, 1)})
            for unit, sid in used_spells(res):
                if taught.get(sid, 0) > level:
                    problems.append(f'{req.name} level {level}: {unit} uses {sid} taught at {taught[sid]}')
        cli_rows.append({'request': req.name, 'level': 60, 'dps': round(ov['raidMetrics']['dps']['avg'], 1)})

    print('spec suites per level...')
    pattern = '^(' + '|'.join(suites) + ')$'
    table = {s: {} for s in suites}
    for p in overlay_src.rglob('*.results'):
        name = p.name.split('.')[0]
        if name in table:
            table[name][60] = suite_dps(p)
    goldens = list(overlay_src.rglob('*.results'))
    originals = {p: p.read_bytes() for p in goldens}
    try:
        for level in [60] + SMOKE_LEVELS:
            print(f'level {level}: collect and verify every spec suite...', flush=True)
            for path, contents in originals.items():
                path.write_bytes(contents)
            for tmp in overlay_src.rglob('*.results.tmp'):
                tmp.unlink()
            env = go_env()
            env['FOREVERCORE_LEVEL'] = str(level)
            # First pass produces level-specific goldens. Differences from level 60 are expected.
            first = subprocess.run(['go', 'test', '-tags=with_db', '-count=1', '-run', pattern, *pk],
                                   cwd=overlay_src, env=env, capture_output=True, text=True)
            if first.returncode not in (0, 1) or 'panic:' in first.stdout + first.stderr:
                raise UpdateError(f'spec suites failed at level {level}: ' + (first.stdout + first.stderr)[-3000:])
            for path, original in originals.items():
                if path.name.split('.')[0] not in table:
                    continue
                tmp = Path(str(path) + '.tmp')
                validate_level_golden(path, tmp, original)
                name = path.name.split('.')[0]
                table[name][level] = suite_dps(tmp)
                path.write_bytes(tmp.read_bytes())
            # No failures are ignored here: deterministic golden differences have been accounted
            # for, while compiler errors, assertions, missing tests and concurrency errors still fail.
            sh('go', 'test', '-tags=with_db', '-count=1', '-run', pattern, *pk,
               cwd=overlay_src, env=env, capture=True)
    finally:
        for path, contents in originals.items():
            path.write_bytes(contents)
    for name, row in table.items():
        last = None
        for level in SMOKE_LEVELS + [60]:
            dps = row.get(level)
            if row.get(60) is not None and row[60] > 0 and (dps is None or not math.isfinite(dps) or dps <= 0):
                problems.append(f'{name}: missing or nonpositive DPS at level {level}')
            if dps is None:
                continue
            if last is not None and last > 1 and dps < last * 0.97:
                problems.append(f'{name}: DPS falls from {last:.1f} to {dps:.1f} at level {level}')
            last = dps
    report['cli'] = cli_rows
    report['specDps'] = {k: {str(l): (round(v, 1) if v is not None else None) for l, v in r.items()} for k, r in table.items()}
    report['problems'] = problems
    if problems:
        raise UpdateError('checks failed:\n' + '\n'.join(problems[:40]))
    return ov_cli


# main --------------------------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--work', type=Path, default=Path(tempfile.gettempdir()) / 'forevercore-engine')
    ap.add_argument('--branch', help='take this mythicsim/* branch instead of the newest descendant')
    ap.add_argument('--dry-run', action='store_true', help='check only, leave lock and level data alone')
    ap.add_argument('--windows-exe', type=Path, help='also build the overlay engine for Windows here')
    ap.add_argument('--report', type=Path, default=CORE / 'engine-update-report.json')
    ap.add_argument('--check-only', action='store_true',
                    help='only say whether upstream has a newer base than the lock (changed=true|false, for $GITHUB_OUTPUT)')
    a = ap.parse_args()

    lock = json.loads(lock_path().read_text())
    if a.check_only:
        # cheap: a blob-less fetch of the branch tips, no build; the weekly run stops here when nothing is new
        repo = a.work.resolve() / 'upstream.git-work'
        fetch_upstream(repo, lock['repository'])
        branch, base, _ = pick_base(repo, lock['commit'], a.branch)
        print(f'changed={"true" if base != lock["commit"] else "false"}')
        print(f'base={branch} {base}', file=sys.stderr)
        return 0
    work = a.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    repo = work / 'upstream.git-work'
    report = {'previous': lock['buildIdentity'], 'ok': False}
    try:
        fetch_upstream(repo, lock['repository'])
        branch, base, descends = pick_base(repo, lock['commit'], a.branch)
        report.update(branch=branch, base=base, descendsFromLock=descends)
        print(f'base {branch} {base[:10]}' + ('' if descends else ' (does NOT descend from the locked commit)'))
        patches, dropped = settle_patches(repo, base, lock['patches'])
        report.update(patchesKept=[p['file'] for p in patches], patchesDropped=dropped)

        upstream_src, parity_src, overlay_src = work / 'upstream', work / 'parity', work / 'overlay'
        for src in (upstream_src, parity_src, overlay_src):
            checkout(repo, base, src)
        apply_patches(overlay_src, patches)
        # Generate Go imports before prepare_leveling.py executes 'go run'.
        for src in (upstream_src, parity_src, overlay_src):
            prepare_checkout(src)
        client_build = (overlay_src / 'assets/db_inputs/forever_client_build.txt').read_text().strip()
        report['clientBuild'] = client_build

        new_lock = dict(lock, commit=base, branch=branch, clientBuild=client_build, patches=patches,
                        reference=f"{lock['repository']}/tree/{branch}",
                        overlay=overlay_digest(), levelDataSHA256=leveling_digest(CORE / 'leveling-data.json'))
        new_lock['buildIdentity'] = build_identity(base, patches, new_lock['overlay'], new_lock['levelDataSHA256'])
        leveling = CORE / 'leveling-data.json'
        staged_lock = work / 'engine.lock.json'
        staged_lock.write_text(json.dumps(new_lock, indent=2) + '\n')
        env = dict(os.environ, FOREVERCORE_LOCK=str(staged_lock))
        engine_data = work / 'engine-data.json'
        db = client_table(client_build, work)
        if db:
            out = work / 'leveling-data.json'
            sh(sys.executable, CORE / 'prepare_leveling.py', overlay_src, db, out, env=env)
            leveling = out
            report['levelData'] = f'refreshed from PlayerExpectedStat {client_build}'
        else:
            report['levelData'] = 'kept (client table not on wago.tools)'
        families = work / 'creature-families.json'
        if sh(sys.executable, CORE / 'prepare_families.py', client_build, families, check=False, capture=False) == 0:
            report['creatureFamilies'] = f'refreshed from CreatureFamily {client_build}'
        else:
            families = None
            report['creatureFamilies'] = 'kept (CreatureFamily not on wago.tools)'

        level_contents = json.loads(leveling.read_text())
        if level_contents['clientBuild'] != client_build:
            raise UpdateError('Client build changed but matching level data is unavailable')
        new_lock['levelDataSHA256'] = leveling_digest(leveling)
        new_lock['buildIdentity'] = build_identity(base, patches, new_lock['overlay'], new_lock['levelDataSHA256'])
        staged_lock.write_text(json.dumps(new_lock, indent=2) + '\n')
        env['FOREVERCORE_LEVEL_DATA'] = str(leveling)
        sh(sys.executable, CORE / 'prepare_engine.py', overlay_src, engine_data, env=env)
        level_contents['engineRevision'] = new_lock['buildIdentity']
        staged_leveling = work / 'leveling-final.json'
        staged_leveling.write_text(json.dumps(level_contents, separators=(',', ':')) + '\n')
        leveling = staged_leveling
        apply_overlay(parity_src, leveling)
        report['overlay'] = apply_overlay(overlay_src, leveling)
        manifest = json.loads(engine_data.read_text())
        manifest.update(levelRange=[10, 60], levelOverlay=report['overlay']['overlay'],
                        liveHunter='hunter-live-ammo' in report['overlay']['applied'],
                        liveWarlock='warlock-live-demon-stats' in report['overlay']['applied'])
        engine_data.write_text(json.dumps(manifest, separators=(',', ':')))
        ov_cli = checks(upstream_src, parity_src, overlay_src, patches, work, report)
        if a.windows_exe:
            a.windows_exe.parent.mkdir(parents=True, exist_ok=True)
            build_cli(overlay_src, a.windows_exe, goos='windows')
            manifest['engineSHA256'] = hashlib.sha256(a.windows_exe.read_bytes()).hexdigest()
            engine_data.write_text(json.dumps(manifest, separators=(',', ':')))
        report['ok'] = True
        report['buildIdentity'] = new_lock['buildIdentity']
        if not a.dry_run:
            lock_path().write_text(json.dumps(new_lock, indent=2) + '\n')
            if leveling != CORE / 'leveling-data.json':
                shutil.copyfile(leveling, CORE / 'leveling-data.json')
            shutil.copyfile(engine_data, CORE / 'engine-data.json')
            write_talent_layout(manifest, CORE.parent / 'ForeverSimBridge/TalentLayoutData.lua')
            if families:
                shutil.copyfile(families, CORE / 'creature-families.json')
        print(f"engine {new_lock['buildIdentity']} + overlay {new_lock['overlay']}: all checks passed")
    except (UpdateError, OverlayError, OSError, ValueError, subprocess.SubprocessError) as e:
        report['error'] = str(e)
        print(f'ENGINE UPDATE FAILED, keeping {lock["buildIdentity"]}:\n{e}', file=sys.stderr)
        a.report.write_text(json.dumps(report, indent=1) + '\n')
        sys.exit(1)
    a.report.write_text(json.dumps(report, indent=1) + '\n')


if __name__ == '__main__':
    main()
