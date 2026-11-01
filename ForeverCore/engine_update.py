"""Follow wowsims/forever automatically: newest master, level overlay, full checks.

Steps (each one stops the run on failure, so engine.lock.json keeps the last good engine):
  1. Fetch master and take its tip (the engine is upstream as it is, plus the level overlay; there are no engine patches).
  2. Refresh leveling-data.json from the client's PlayerExpectedStat (wago.tools CSV for the client build the
     engine's spell data names). Without that build on wago.tools the old table stays and the overlay test proves it
     still matches upstream's level-60 values.
  3. Build upstream and upstream+overlay; run every upstream Go test with the overlay (level 60 must not move),
     compare both CLIs on reference requests, and run the level smoke (all spec suites at several levels: no panic,
     no unlearnt rank cast, DPS rising with level).
  4. Write engine.lock.json, leveling-data.json, creature-families.json and engine-update-report.json.

    python engine_update.py --work /tmp/fc-engine [--branch master] [--dry-run]
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
from engine_source import client_build as read_client_build
from talent_layout import write as write_talent_layout
import ui_spells
from compare_results import canon, differences  # noqa: E402

SMOKE_LEVELS = [10, 20, 30, 45, 59]
DPS_DROP_TOLERANCE = 0.80
# Below 60 only these cases of every spec suite run: they carry the DPS and hit every start-up path. The item and enchant
# cases of a suite are hundreds of runs that say nothing more about a level; level 60 runs in full in the package tests.
SMOKE_CASES = '^(?:CharacterStats|Settings)'
REFERENCE_REQUESTS = [
    'sim/warlock/testdata/imp-brand/kerani.request.json',
    'sim/paladin/retribution/testdata/lights_vigil_request.json',
]


class UpdateError(Exception):
    pass


def failure_summary(output):
    """What failed in a go test run: the failed packages and top-level tests, then the end of the output."""
    lines = output.splitlines()
    heads = [l for l in lines if re.match(r'^(FAIL\t|--- FAIL: |panic: )', l)]
    return '\n'.join(heads[:40]) + '\n...\n' + output[-1500:] if heads else output[-3000:]


def sh(*cmd, cwd=None, env=None, capture=False, check=True):
    p = subprocess.run([str(c) for c in cmd], cwd=cwd, env=env, text=True,
                       capture_output=capture)
    if check and p.returncode != 0:
        tail = failure_summary(p.stderr or p.stdout or '') if capture else ''
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
       '+refs/heads/master:refs/remotes/origin/master')


# Files that are numbers, generated from the client's tables, tests, interface or documents: not the calculation.
DATA_SUFFIXES = ('.json', '.bin', '.results', '.md', '.txt', '.png', '.jpg', '.svg', '.webp', '.css', '.scss', '.html',
                 '.ts', '.tsx', '.mts', '.mjs', '.yml', '.yaml', '.lock', '.sum', '.sh', '.toml')
DATA_DIRS = ('assets/', 'ui/', 'docs/', 'schemas/', 'locales/', '.github/')


def is_calculation_file(path):
    """True for a file that carries the rules of the calculation (Go code, the protobuf schema, the build files)."""
    if path.startswith(DATA_DIRS) or path.endswith(DATA_SUFFIXES):
        return False
    if path.endswith('_test.go') or '_auto_gen' in path or path.endswith('_gen.go') or '/testdata/' in path:
        return False
    return True


def calculation_changes(repo, locked, base):
    """The calculation files that differ between the locked commit and base: a list (empty when none), or None when the
    two cannot be compared (the locked commit is not in the fetched history)."""
    if subprocess.run(['git', '-C', str(repo), 'cat-file', '-e', locked + '^{commit}'], capture_output=True).returncode != 0:
        return None
    names = git(repo, 'diff', '--name-only', locked, base).splitlines()
    changed = [n for n in names if is_calculation_file(n)]
    return changed if changed else False


def pick_base(repo, locked, forced=None):
    """(branch, tip, descends): the tip of master, or of the forced branch, and whether it contains the locked commit."""
    branch = forced or 'master'
    sha = git(repo, 'rev-parse', f'origin/{branch}')
    have_locked = subprocess.run(['git', '-C', str(repo), 'cat-file', '-e', locked + '^{commit}'],
                                 capture_output=True).returncode == 0
    descends = have_locked and subprocess.run(['git', '-C', str(repo), 'merge-base', '--is-ancestor', locked, sha],
                                              capture_output=True).returncode == 0
    return branch, sha, descends


# 2. checkout ------------------------------------------------------------------------------------

def checkout(repo, base, dest):
    # A worktree of the blobless clone fetches the blobs it needs from the promisor remote.
    if dest.exists():
        shutil.rmtree(dest)
    sh('git', '-C', repo, 'worktree', 'prune')
    sh('git', '-C', repo, 'worktree', 'add', '-q', '--detach', dest, base)


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
    sh('protoc', '-I=proto', '--go_out=paths=source_relative:sim/core/proto', *protos, cwd=src)


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
    # the smoke runs only the character-stats and settings cases of each suite (see SMOKE_CASES)
    wanted = re.compile(r'-(?:CharacterStats|Settings)-')
    expected_keys = sorted(k for k in re.findall(r'(?m)^ ?key:\s*"([^"\n]+)"', original.decode()) if wanted.search(k))
    actual_keys = sorted(k for k in re.findall(r'(?m)^ ?key:\s*"([^"\n]+)"', actual) if wanted.search(k))
    if not expected_keys or expected_keys != actual_keys:
        raise UpdateError(f'incomplete level test results: {path.name}')
    if re.search(r'(?i)\b(?:nan|inf|infinity)\b', actual):
        raise UpdateError(f'non-finite level test result: {path.name}')


def checks(upstream_src, overlay_src, work, report, classes=None):
    """upstream = wowsims/forever as it is; overlay = the same plus the level overlay (must equal upstream at 60)."""
    pk = packages(overlay_src)
    if classes:
        # partial run: only the packages of these classes (sim/<class> and its spec folders)
        pk = [p for p in pk if any(re.search(rf'/sim/{c}(/|$)', p) for c in classes)]
    else:
        print('upstream Go tests with the overlay (level 60 must not move)...')
        sh('go', 'test', '-tags=with_db', '-count=1', *pk, cwd=overlay_src, env=go_env())
    suites = golden_suites(overlay_src) if not classes else sorted({p.name.split('.')[0] for c in classes for p in overlay_src.glob(f'sim/{c}/**/*.results')} - {'TestProtoVersioning'})
    up_cli, ov_cli = work / 'wowsimcli-upstream', work / 'wowsimcli-overlay'
    if not classes:
        build_cli(upstream_src, up_cli)
        build_cli(overlay_src, ov_cli)
    taught = spell_levels(overlay_src, work / 'spell-levels.json') if not classes else {}
    problems, cli_rows = [], []
    for rel in ([] if classes else REFERENCE_REQUESTS):
        req = overlay_src / rel
        if not req.exists():
            report.setdefault('notes', []).append(f'reference request {rel} missing upstream')
            continue
        data = json.loads(req.read_text())
        data.setdefault('simOptions', {}).update(iterations=300, randomSeed='7', debugFirstIteration=False)
        req = work / Path(rel).name
        req.write_text(json.dumps(data))
        up = run_cli(up_cli, req, work / 'up.json')
        ov = run_cli(ov_cli, req, work / 'ov.json')
        diff = differences(canon(up), canon(ov))
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
    skipped_suites = set()
    goldens = list(overlay_src.rglob('*.results'))
    originals = {p: p.read_bytes() for p in goldens}
    try:
        for level in SMOKE_LEVELS:
            print(f'level {level}: collect and verify every spec suite...', flush=True)
            for path, contents in originals.items():
                path.write_bytes(contents)
            for tmp in overlay_src.rglob('*.results.tmp'):
                tmp.unlink()
            env = go_env()
            env['FOREVERCORE_LEVEL'] = str(level)
            # First pass produces level-specific goldens. Differences from level 60 are expected.
            first = subprocess.run(['go', 'test', '-tags=with_db', '-count=1', '-timeout', '6m', '-v', '-run', pattern + '/' + SMOKE_CASES, *pk],
                                   cwd=overlay_src, env=env, capture_output=True, text=True)
            if first.returncode not in (0, 1) or re.search(r'(?m)^panic: ', first.stdout + first.stderr):
                raise UpdateError(f'spec suites failed at level {level}: ' + failure_summary(first.stdout + first.stderr))
            # upstream skips a suite on purpose (t.Skip): it writes no results and has nothing to compare
            skipped = set(re.findall(r'--- SKIP: (\w+)', first.stdout))
            skipped_suites |= skipped
            for path, original in originals.items():
                if path.name.split('.')[0] not in table or path.name.split('.')[0] in skipped:
                    continue
                tmp = Path(str(path) + '.tmp')
                # a suite with no character-stats or settings case (coverage suites) has nothing to compare
                if not re.search(rb'-(?:CharacterStats|Settings)-', original):
                    continue
                validate_level_golden(path, tmp, original)
                name = path.name.split('.')[0]
                table[name][level] = suite_dps(tmp)
    finally:
        for path, contents in originals.items():
            path.write_bytes(contents)
    for name in skipped_suites:
        table.pop(name, None)  # not run, so no DPS to follow across the levels
    for name, row in table.items():
        last = None
        for level in SMOKE_LEVELS + [60]:
            dps = row.get(level)
            if row.get(60) is not None and row[60] > 0 and (dps is None or not math.isfinite(dps) or dps <= 0):
                problems.append(f'{name}: missing or nonpositive DPS at level {level}')
            if dps is None:
                continue
            # A higher rank can lower the damage on fixed endgame gear (a longer cast, a bigger cost), as downranking shows in
            # the game; only a real drop means a broken rank choice.
            if last is not None and last > 1 and dps < last * DPS_DROP_TOLERANCE:
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
    ap.add_argument('--branch', help='take this branch of the engine repository instead of master')
    ap.add_argument('--dry-run', action='store_true', help='check only, leave lock and level data alone')
    ap.add_argument('--windows-exe', type=Path, help='also build the overlay engine for Windows here')
    ap.add_argument('--report', type=Path, default=CORE / 'engine-update-report.json')
    ap.add_argument('--classes', help='iterate on some classes only (comma list, e.g. warlock,mage): skips the full Go tests and the CLI comparison, '
                    'runs the level smoke for these classes, writes nothing; a full run is still needed before a push')
    ap.add_argument('--check-only', action='store_true',
                    help='only say whether upstream has a newer base than the lock (changed=true|false, for $GITHUB_OUTPUT)')
    a = ap.parse_args()
    classes = [c for c in (a.classes or '').split(',') if c]
    if classes:
        a.dry_run = True

    lock = json.loads(lock_path().read_text())
    if a.check_only:
        # cheap: a blob-less fetch of the branch tips, no build; the weekly run stops here when nothing is new
        repo = a.work.resolve() / 'upstream.git-work'
        fetch_upstream(repo, lock['repository'])
        branch, base, _ = pick_base(repo, lock['commit'], a.branch)
        code = calculation_changes(repo, lock['commit'], base)
        # a new upstream base only matters when the calculation changed; numbers, generated tables, tests, the UI and
        # documents are ours to keep (we maintain the values ourselves)
        print(f'changed={"true" if base != lock["commit"] and code is not False else "false"}')
        print(f'base={branch} {base}', file=sys.stderr)
        if base != lock['commit']:
            if code is None:
                print('calculation: cannot compare with the locked commit, treating as changed', file=sys.stderr)
            elif code is False:
                print('calculation: unchanged (only data, generated tables, tests, UI or documents differ)', file=sys.stderr)
            else:
                print('calculation: changed in ' + ', '.join(code[:12]) + (' ...' if len(code) > 12 else ''), file=sys.stderr)
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
        upstream_src, overlay_src = work / 'upstream', work / 'overlay'
        for src in (upstream_src, overlay_src):
            checkout(repo, base, src)
        # Generate Go imports before prepare_leveling.py executes 'go run'.
        for src in (upstream_src, overlay_src):
            prepare_checkout(src)
        client_build = read_client_build(overlay_src)
        report['clientBuild'] = client_build

        new_lock = dict(lock, commit=base, branch=branch, clientBuild=client_build,
                        reference=f"{lock['repository']}/tree/{branch}",
                        overlay=overlay_digest(), levelDataSHA256=leveling_digest(CORE / 'leveling-data.json'))
        new_lock['buildIdentity'] = build_identity(base, new_lock['overlay'], new_lock['levelDataSHA256'])
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
        new_lock['buildIdentity'] = build_identity(base, new_lock['overlay'], new_lock['levelDataSHA256'])
        staged_lock.write_text(json.dumps(new_lock, indent=2) + '\n')
        env['FOREVERCORE_LEVEL_DATA'] = str(leveling)
        sh(sys.executable, CORE / 'prepare_engine.py', overlay_src, engine_data, env=env)
        level_contents['engineRevision'] = new_lock['buildIdentity']
        staged_leveling = work / 'leveling-final.json'
        staged_leveling.write_text(json.dumps(level_contents, separators=(',', ':')) + '\n')
        leveling = staged_leveling
        report['overlay'] = apply_overlay(overlay_src, leveling)
        manifest = json.loads(engine_data.read_text())
        manifest.update(levelRange=[10, 60], levelOverlay=report['overlay']['overlay'],
                        liveHunter='hunter-live-ammo' in report['overlay']['applied'],
                        liveWarlock='warlock-live-demon-stats' in report['overlay']['applied'])
        engine_data.write_text(json.dumps(manifest, separators=(',', ':')))
        ov_cli = checks(upstream_src, overlay_src, work, report, classes)
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
            ui_spells.refresh_classes(overlay_src)
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
