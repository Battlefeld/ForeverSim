"""Level smoke test for an overlay engine build.

For every request and every level it runs wowsimcli with FOREVERCORE_LEVEL and checks:
  * the run succeeds and deals damage,
  * no cast or damaging action uses a class spell rank taught above that level,
  * DPS does not fall when the level rises (same gear, same seed),
and at level 60 the overlay build must equal the upstream build after normalisation.

    python level_smoke.py --overlay wowsimcli-overlay --upstream wowsimcli-upstream \
        --spell-levels spell-levels.json req1.json req2.json
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from compare_results import canon, differences

LEVELS = [10, 15, 20, 30, 40, 50, 59]


def run(binary, request, out, level=None):
    env = dict(os.environ)
    env.pop('FOREVERCORE_LEVEL', None)
    if level is not None:
        env['FOREVERCORE_LEVEL'] = str(level)
    p = subprocess.run([binary, 'sim', '--infile', str(request), '--outfile', str(out)],
                       env=env, capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError(f'{request.name} level {level}: wowsimcli failed\n{p.stderr[-2000:]}')
    data = json.loads(Path(out).read_text())
    if data.get('error'):
        raise RuntimeError(f'{request.name} level {level}: {data["error"]}')
    return data


def used_spells(result):
    for party in result['raidMetrics']['parties']:
        for player in party['players']:
            units = [player] + player.get('pets', [])
            for unit in units:
                for action in unit.get('actions', []):
                    sid = action['id'].get('spellId')
                    casts = sum(t.get('casts', 0) for t in action.get('targets', []))
                    damage = sum(t.get('damage', 0) for t in action.get('targets', []))
                    if sid and (casts or damage):
                        yield unit.get('name', ''), sid


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--overlay', required=True)
    p.add_argument('--upstream', required=True)
    p.add_argument('--spell-levels', required=True, help='JSON {spellId: taughtLevel} for class spells')
    p.add_argument('--report', type=Path)
    p.add_argument('requests', nargs='+', type=Path)
    a = p.parse_args()
    taught = {int(k): v for k, v in json.loads(Path(a.spell_levels).read_text()).items()}
    problems, rows = [], []
    with tempfile.TemporaryDirectory() as temp:
        temp = Path(temp)
        for req in a.requests:
            up = run(a.upstream, req, temp / 'up.json')
            ov = run(a.overlay, req, temp / 'ov.json')
            diff = differences(canon(up), canon(ov))
            if diff:
                problems.append(f'{req.name}: level 60 differs from upstream: ' + '; '.join(diff[:5]))
            last = None
            for level in LEVELS:
                res = run(a.overlay, req, temp / f'l{level}.json', level)
                dps = res['raidMetrics']['dps']['avg']
                rows.append({'request': req.name, 'level': level, 'dps': round(dps, 2)})
                if dps <= 0:
                    problems.append(f'{req.name} level {level}: no damage')
                if last is not None and dps + 1e-6 < last * 0.97:
                    problems.append(f'{req.name}: DPS falls from {last:.1f} to {dps:.1f} at level {level}')
                last = dps
                for unit, sid in used_spells(res):
                    if taught.get(sid, 0) > level:
                        problems.append(f'{req.name} level {level}: {unit} uses spell {sid} taught at {taught[sid]}')
            rows.append({'request': req.name, 'level': 60, 'dps': round(ov['raidMetrics']['dps']['avg'], 2)})
    report = {'ok': not problems, 'problems': problems, 'dps': rows}
    if a.report:
        a.report.write_text(json.dumps(report, indent=1) + '\n')
    for r in rows:
        print(f"{r['request']:40s} L{r['level']:<3d} {r['dps']:9.1f}")
    if problems:
        print('\n'.join(problems), file=sys.stderr)
        sys.exit(1)
    print('level smoke ok')


if __name__ == '__main__':
    main()
