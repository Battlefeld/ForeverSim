#!/usr/bin/env python3
"""Compare the engine's spell table with the ForeverDB API: what changed that we have not taken over yet?

    python tools/spell-check/check.py --dump spells.json --out report [--max-level 30]

The engine side (spells.json) comes from tools/spell-check/spelldump.go.tmpl. The API side is /classes/{name} (every
ability with its ranks, spell ids and the level each is taught at) and /spells/{id} (the tooltip text). For every rank:

  missing   the API knows the spell, the engine's table does not
  name      the engine's name or rank text differs
  level     the level the rank is taught at differs
  value     a number the engine's values predict is not in the tooltip

The values are checked where the tooltip is simple and the rule is known: direct damage or healing (a range of
average * (1 -/+ variance/2), or one number), and periodic damage or healing (per tick times the ticks). Nothing else is
guessed. The report only lists; it never changes anything.

Data from ForeverDB.net (https://foreverdb.net): credit it wherever the data is shown. The key is read from the
environment (FOREVERDB_API_KEY), is never printed and never written.
"""
import argparse
import json
import math
import os
import re
import struct
import sys
import time
import urllib.error
import urllib.request

BASE = 'https://foreverdb.net/api/v1'
CLASSES = ['druid', 'hunter', 'mage', 'paladin', 'priest', 'rogue', 'shaman', 'warlock', 'warrior']
# the client's numbers (dbcenums): effect types and aura types
E_SCHOOL_DAMAGE, E_APPLY_AURA, E_HEAL = 2, 6, 10
A_PERIODIC_DAMAGE, A_PERIODIC_HEAL = 3, 8


class Api:
    """The API politely: at most `budget` calls, `interval` seconds apart, a pause when it says so."""

    def __init__(self, key, budget, interval):
        self.key, self.budget, self.interval, self.calls, self.last = key, budget, interval, 0, 0.0

    def get(self, path):
        if self.calls >= self.budget:
            raise RuntimeError('call budget reached')
        for attempt in range(4):
            wait = self.interval - (time.time() - self.last)
            if wait > 0:
                time.sleep(wait)
            self.last = time.time()
            self.calls += 1
            req = urllib.request.Request(BASE + path, headers={'X-API-Key': self.key, 'User-Agent': 'ForeverSim-spell-check'})
            try:
                with urllib.request.urlopen(req, timeout=60) as r:
                    return json.load(r)['data']
            except urllib.error.HTTPError as e:
                if e.code == 429:
                    time.sleep(min(int(e.headers.get('Retry-After', '30')), 120))
                    continue
                if e.code == 404:
                    return None
                raise
            except (urllib.error.URLError, TimeoutError):
                time.sleep(5)
        raise RuntimeError('API did not answer: ' + path)


def numbers(text):
    """Every number in a tooltip that is not a time ("over 9 sec", "5 min"), thousands separators and decimals read."""
    text = re.sub(r'\d[\d,]*\.?\d*\s*(?:sec|seconds|min|minutes)\b', ' ', text or '')
    return {float(n.replace(',', '')) for n in re.findall(r'\d[\d,]*\.?\d*', text)}


def f32(x):
    return struct.unpack('f', struct.pack('f', x))[0]


def average(e, level):
    """The engine's Effect.Average(level): the base plus the gain per level between the spell's level and the caster's
    (capped at the effect's MaxLevel), as float32, floored."""
    lvl = level
    if e.get('maxLevel', 0) > 0 and e['maxLevel'] < lvl:
        lvl = e['maxLevel']
    delta = max(0, lvl - e.get('spellLevel', 0))
    return math.floor(f32(f32(e['base']) + f32(f32(delta) * f32(e.get('ppl', 0)))))


def expected_values(spell, level=30):
    """The tooltip numbers the engine's values predict at the tooltip's level, per effect, as alternatives of which one
    must be fully present: [(label, [set, ...])]. The client states a base one lower than the tooltip shows, so the
    average and average+1 are both accepted; a periodic effect may be shown per tick or as the total."""
    out = []
    for e in spell.get('effects') or []:
        # the engine's own amount where the dump has it (it knows the spells that scale with the level)
        if level == 30 and 'avg30' in e:
            base = e['avg30']
        elif level == 0 and 'avg0' in e:
            base = e['avg0']
        else:
            base = average(e, level)
        var = e['variance']
        is_direct = e['type'] in (E_SCHOOL_DAMAGE, E_HEAL)
        is_periodic = e['type'] == E_APPLY_AURA and e['aura'] in (A_PERIODIC_DAMAGE, A_PERIODIC_HEAL) and e['periodMs'] > 0
        if is_direct and base > 0:
            alts = []
            for b in (base, base + 1):
                if var:
                    alts.append({round(b * (1 - var / 2)), round(b * (1 + var / 2))})
                else:
                    alts.append({round(b)})
            out.append(('direct', alts))
        elif is_periodic and base > 0 and spell['durationMs'] > 0:
            ticks = spell['durationMs'] // e['periodMs']
            alts = [{round(b * ticks)} for b in (base, base + 1)] + [{round(b)} for b in (base, base + 1)]
            out.append(('periodic', alts))
    return out


def check_values(spell, text, level=30):
    nums = numbers(text)
    if not nums:
        return []  # a tooltip without a number ("Judge the target, dealing Holy damage") says nothing to compare
    # only a tooltip that says "(Numbers at level 30; they grow with your level.)" is written for a level; every other
    # one shows the rank's own numbers, without the gain per level
    stated = re.search(r'Numbers at level (\d+)', text or '')
    level = int(stated.group(1)) if stated else 0
    problems = []
    for label, alts in expected_values(spell, level):
        if not any(all(float(v) in nums for v in alt) for alt in alts):
            shown = ' or '.join('/'.join(str(v) for v in sorted(alt)) for alt in alts)
            problems.append(f'{label}: the values predict {shown}, the tooltip has {sorted(int(n) if n == int(n) else n for n in nums)[:12]}')
    return problems


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--dump', required=True, help='spells.json from spelldump')
    ap.add_argument('--out', required=True, help='path without extension: writes .json and .md')
    ap.add_argument('--max-level', type=int, default=30, help='only ranks taught at this level or lower')
    ap.add_argument('--tooltip-level', type=int, default=30, help='the level the API tooltips are written for ("Numbers at level 30")')
    ap.add_argument('--budget', type=int, default=900, help='most API calls')
    ap.add_argument('--interval', type=float, default=1.2, help='seconds between calls (the API allows 60 a minute)')
    ap.add_argument('--classes', default=','.join(CLASSES))
    a = ap.parse_args()

    key = os.environ.get('FOREVERDB_API_KEY', '')
    if not key:
        print('FOREVERDB_API_KEY is not set', file=sys.stderr)
        return 2
    engine = {s['id']: s for s in json.load(open(a.dump))}
    api = Api(key, a.budget, a.interval)
    findings, checked, build = [], 0, ''
    for cls in a.classes.split(','):
        data = api.get(f'/classes/{cls}')
        if not data:
            findings.append({'class': cls, 'kind': 'class', 'what': 'the API does not know this class'})
            continue
        for ability in data.get('abilities', []):
            for rank in ability.get('ranks', []):
                if rank.get('level', 0) > a.max_level:
                    continue
                sid = rank['spellId']
                spell = engine.get(sid)
                where = {'class': cls, 'ability': ability['name'], 'rank': rank.get('rank', ''), 'spellId': sid, 'level': rank.get('level')}
                checked += 1
                if spell is None:
                    findings.append({**where, 'kind': 'missing', 'what': 'the engine table has no such spell'})
                    continue
                if spell['name'] != ability['name'] or (spell['rank'] or '') != (rank.get('rank') or ''):
                    findings.append({**where, 'kind': 'name', 'what': f'engine: {spell["name"]!r} {spell["rank"]!r}'})
                # level 0 is a passive without one, 60 the engine's "no level": neither says anything
                if rank.get('level') and spell['spellLevel'] not in (0, 60) and spell['spellLevel'] != rank.get('level'):
                    findings.append({**where, 'kind': 'level', 'what': f'engine teaches it at {spell["spellLevel"]}, the API at {rank.get("level")}'})
                if not expected_values(spell, a.tooltip_level):
                    continue
                full = api.get(f'/spells/{sid}')
                if full is None:
                    findings.append({**where, 'kind': 'missing', 'what': 'the API has no tooltip for this spell'})
                    continue
                for p in check_values(spell, full.get('description', ''), a.tooltip_level):
                    findings.append({**where, 'kind': 'value', 'what': p, 'tooltip': (full.get('description') or '')[:300]})
        print(f'{cls}: {api.calls} calls, {len(findings)} findings so far', flush=True)

    counts = {}
    for f in findings:
        counts[f['kind']] = counts.get(f['kind'], 0) + 1
    summary = {'ranksChecked': checked, 'apiCalls': api.calls, 'findings': counts, 'maxLevel': a.max_level}
    with open(a.out + '.json', 'w') as fh:
        json.dump({'summary': summary, 'findings': findings}, fh, ensure_ascii=False, indent=1)
    lines = ['# Spell check: engine table against the ForeverDB API', '',
             'Data from [ForeverDB.net](https://foreverdb.net). Only lists; nothing is changed.', '',
             f'Ranks checked (taught at level {a.max_level} or lower): **{checked}**, API calls: {api.calls}. '
             'Findings: ' + (', '.join(f'{k} {v}' for k, v in sorted(counts.items())) or 'none') + '.', '']
    for kind, title in (('missing', 'Missing'), ('name', 'Name or rank differs'), ('level', 'Taught at another level'), ('value', 'Values differ from the tooltip')):
        rows = [f for f in findings if f['kind'] == kind]
        if not rows:
            continue
        lines += [f'## {title} ({len(rows)})', '']
        for f in rows[:150]:
            lines.append(f"- **{f['class']}** {f.get('ability', '')} {f.get('rank', '')} (spell {f.get('spellId', '')}, level {f.get('level', '')}): {f['what']}")
        if len(rows) > 150:
            lines.append(f'- ... {len(rows) - 150} more in the JSON')
        lines.append('')
    with open(a.out + '.md', 'w') as fh:
        fh.write('\n'.join(lines) + '\n')
    print(json.dumps(summary))
    return 0


if __name__ == '__main__':
    sys.exit(main())
