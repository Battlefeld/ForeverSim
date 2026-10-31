#!/usr/bin/env python3
"""Read the level scaling of Forever's newer spells from their tooltips and write the engine's table of it.

    python tools/spell-check/scaling.py --dump spells.json --tooltips wowhead.json --out forever_scaling.go \
        [--fdb spell-check.json] [--report scaling-report.json]

Forever writes the newer spells (runes, the spells of the new class kits) with a coefficient and a level polynomial.
The Wowhead Forever tooltip of such a spell reads, for example (Starsurge):

    causes [248 / 100 * (9.183105 + 0.616405 * level + 0.028608 * level * level)] to [304 / 100 * (...)] Arcane damage

The engine stores N (the base points: the average of 248 and 304, with the variance) and used it as a flat amount at
every level. Per spell this takes the polynomial (A, B, C) from the tooltip, but only when

  1. the tooltip has exactly one polynomial,
  2. every damage or healing effect of the spell in the engine's table is explained by numbers of the formulas (the
     range, or the tick, as N / 100: the engine's coefficients and the tooltip's agree), and
  3. where the ForeverDB report (the second source) has the spell, its tooltip at level 30 is what the polynomial
     gives at level 30.

Everything else is listed in the report with the reason, and changed nothing.
"""
import argparse
import html
import json
import re

POLY = re.compile(r'(-?\d+\.\d+)\s*([+-])\s*(\d+\.\d+)\s*\*\s*(\d+)\s*([+-])\s*(\d+\.\d+)\s*\*\s*(\d+)(?:\s*\*\s*\d+)?')


def damage_like(e):
    return e['base'] > 0 and (e['type'] in (2, 10) or (e['type'] == 6 and e['aura'] in (3, 8)))


def tooltip_text(raw):
    return re.sub(r'\s+', ' ', html.unescape(re.sub(r'<[^>]+>', ' ', raw or '')))


def parse(raw):
    """(polys, numbers) of the formulas of a tooltip: the distinct (A, B, C) and the loose integers around them."""
    polys, numbers = set(), set()
    for expr in re.findall(r'\[([^\]]*)\]', tooltip_text(raw)):
        found = POLY.findall(expr)
        if not found:
            continue
        for a, s1, b, _, s2, c, _ in found:
            polys.add((float(a), float(b) * (1 if s1 == '+' else -1), float(c) * (1 if s2 == '+' else -1)))
        rest = POLY.sub(' ', expr)
        rest = re.sub(r'Attack Power|Spell Power', ' ', rest)
        numbers |= {int(n) for n in re.findall(r'(?<![\d.])\d+(?![\d.])', rest)}
    return polys, numbers


def near(values, n):
    return any(abs(n - v) <= 1 for v in values)


def explained(spell, numbers):
    """Is every damage or healing effect of the spell a coefficient the formulas state?"""
    effects = [e for e in spell['effects'] if damage_like(e)]
    if not effects:
        return False, 'no damage or healing effect'
    for e in effects:
        var, base = e['variance'], e['base']
        if var:
            ok = near(numbers, round(base * (1 - var / 2))) and near(numbers, round(base * (1 + var / 2)))
        else:
            ok = near(numbers, round(base))
        if not ok:
            return False, f"effect {e['index']} (base {base:g}, variance {var:g}) is not in the formulas {sorted(numbers)}"
    return True, ''


def at(poly, level):
    return poly[0] + poly[1] * level + poly[2] * level * level


def amount(e, poly, level):
    """One hit or one tick at a level, not rounded: the tooltips add up the formula (a tick of 45.96 four times is
    184, not 4 * 45)."""
    return e['base'] / 100 * at(poly, level)


def fdb_agrees(spell, poly, text):
    """The ForeverDB tooltip names level 30: every damage or healing effect the polynomial gives there must be in it."""
    nums = {float(n.replace(',', '')) for n in re.findall(r'\d[\d,]*\.?\d*', re.sub(r'\d[\d,]*\.?\d*\s*(?:sec|min)\b', ' ', text))}
    for e in spell['effects']:
        if not damage_like(e):
            continue
        avg = amount(e, poly, 30)
        if e['variance']:
            want = [{round(avg * (1 - e['variance'] / 2)), round(avg * (1 + e['variance'] / 2))}]
        elif e['type'] == 6:
            ticks = spell['durationMs'] // e['periodMs'] if e['periodMs'] else 1
            want = [{round(avg)}, {round(avg * ticks)}]  # shown per tick or as the total
        else:
            want = [{round(avg)}]
        # a tolerance of one: the client floors, the tooltip rounds
        if not any(all(any(abs(n - w) <= 1 for n in nums) for w in alt) for alt in want):
            return False
    return True


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--dump', required=True)
    ap.add_argument('--tooltips', required=True, help='{"spellId": "<html tooltip>"} from nether.wowhead.com')
    ap.add_argument('--out', required=True)
    ap.add_argument('--fdb', help='the JSON of check.py (its value findings carry the ForeverDB tooltips)')
    ap.add_argument('--report')
    a = ap.parse_args()

    engine = {s['id']: s for s in json.load(open(a.dump))}
    tooltips = json.load(open(a.tooltips))
    fdb = {}
    if a.fdb:
        for f in json.load(open(a.fdb))['findings']:
            if f['kind'] == 'value' and 'Numbers at level' in f.get('tooltip', ''):
                fdb[f['spellId']] = f['tooltip']
    accepted, unresolved = {}, {}
    for sid_s, raw in sorted(tooltips.items(), key=lambda kv: int(kv[0])):
        sid = int(sid_s)
        spell = engine.get(sid)
        if spell is None or raw.startswith('ERR'):
            unresolved[sid] = 'no engine row or no tooltip'
            continue
        polys, numbers = parse(raw)
        if not polys:
            continue  # a fixed-rank spell: nothing to scale
        if len(polys) != 1:
            unresolved[sid] = f'{len(polys)} different polynomials in the tooltip'
            continue
        poly = next(iter(polys))
        ok, why = explained(spell, numbers)
        if not ok:
            unresolved[sid] = why
            continue
        if sid in fdb and not fdb_agrees(spell, poly, fdb[sid]):
            unresolved[sid] = 'the polynomial at level 30 is not the ForeverDB tooltip: ' + fdb[sid][:100]
            continue
        accepted[sid] = {'name': spell['name'], 'poly': poly, 'checkedWithForeverDB': sid in fdb}

    lines = ['// Code generated by tools/spell-check/scaling.py from the Wowhead Forever tooltips. DO NOT EDIT.', '',
             'package spelldata', '', '// The spells whose coefficient Forever scales with the level (see LevelScale).',
             'func init() {']
    for sid, v in accepted.items():
        A, B, C = v['poly']
        lines.append(f"\tforeverScales[{sid}] = LevelScale{{{A:.6f}, {B:.6f}, {C:.6f}}} // {v['name']}")
    lines += ['}', '']
    open(a.out, 'w').write('\n'.join(lines))
    if a.report:
        json.dump({'accepted': {str(k): v for k, v in accepted.items()}, 'unresolved': {str(k): v for k, v in unresolved.items()}},
                  open(a.report, 'w'), indent=1, ensure_ascii=False)
    print(f'{len(accepted)} spells scale with the level ({sum(1 for v in accepted.values() if v["checkedWithForeverDB"])} checked with ForeverDB), '
          f'{len(unresolved)} left alone')


if __name__ == '__main__':
    main()
