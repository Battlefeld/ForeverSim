"""Refresh the spell numbers of the addon's class tables (ForeverSimBridge/Classes/*.lua) from the engine.

The engine's spell store is the source: for every ability rank the tables list by spell id, the taught level,
the cast time, the cooldown, the base cost and the direct damage or healing (with the spell power coefficient
and the per-level scaling) are read from it. What the engine does not state as one plain fact - rotation
rules, procs, talent modifiers, forms - is left as it is, and so is a row whose spell has no single direct
effect to read the amount from. Rows with a spell id the engine does not know are reported, not removed.

    python3 ui_spells.py ENGINE_CHECKOUT [--check]
"""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

CORE = Path(__file__).resolve().parent
CLASSES = CORE.parent / 'ForeverSimBridge' / 'Classes'
HELPER = CORE / 'ui-spells-tool' / 'ui_spells.go.tmpl'
DIRECT_DAMAGE, HEAL = 2, 10  # SpellEffectType
POWER = {0: 'mana', 1: 'rage', 3: 'energy'}


def dump_spells(engine):
    with tempfile.TemporaryDirectory() as t:
        main = Path(t) / 'main.go'
        shutil.copyfile(HELPER, main)
        out = subprocess.run(['go', 'run', str(main)], cwd=engine, check=True, capture_output=True, text=True).stdout
    spells = json.loads(out)
    for s in spells.values():
        s['effects'] = s['effects'] or []
        s['powers'] = s['powers'] or []
    return spells


def match_brace(text, start):
    depth = 0
    i = start
    while i < len(text):
        c = text[i]
        if c == '"':
            i = text.index('"', i + 1)
        elif c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise ValueError('unbalanced table')


def top_fields(entry):
    """{key: (valueStart, valueEnd)} of the entry's own fields, nested tables as one value."""
    fields = {}
    i, depth = 1, 0
    while i < len(entry) - 1:
        m = re.compile(r'\["(\w+)"\]=').match(entry, i)
        if m and depth == 0:
            start = m.end()
            end = match_brace(entry, start) + 1 if entry[start] == '{' else start
            if entry[start] != '{':
                while entry[end] not in ',}':
                    end += 1
            fields[m.group(1)] = (start, end)
            i = end
            continue
        i += 1
    return fields


def num(v):
    return repr(round(float(v), 10)).removesuffix('.0') if float(v) != int(v) else str(int(v))


def direct_effect(spell):
    candidates = [e for e in spell['effects'] if e['type'] in (DIRECT_DAMAGE, HEAL) and (e['min'] or e['max'])]
    return candidates[0] if len(candidates) == 1 else None


def refresh_entry(entry, spell, changes):
    fields = top_fields(entry)
    edits = {}

    def want(key, value, tolerance=1e-4):
        if key not in fields:
            return
        s, e = fields[key]
        old = entry[s:e]
        try:
            same = abs(float(old) - float(value)) <= tolerance
        except ValueError:
            return
        if not same:
            edits[key] = (s, e, num(value))
            changes.append((key, old, num(value)))

    if spell['level'] not in (0, 1, 60):
        want('level', spell['level'])
    if spell['castMs'] >= 0:
        want('cast', spell['castMs'] / 1000)
    if spell['cooldownMs'] > 0:
        want('cooldown', spell['cooldownMs'] / 1000)
    resource = entry[slice(*fields['resource'])].strip('"') if 'resource' in fields else 'mana'
    for p in spell['powers']:
        if POWER.get(p['type']) == resource and p['cost'] > 0:
            want('cost', p['cost'] / 10 if resource == 'rage' else p['cost'])
    effect = direct_effect(spell)
    # the effect is the one the row already describes: its spell power coefficient is the same
    if effect and effect['spCoef'] > 0 and 'coef' in fields and 'base' in fields \
            and abs(float(entry[slice(*fields['coef'])]) - effect['spCoef']) < 0.01:
        # the tables hold the unrounded spread; a difference inside a point is that rounding, not new data
        moved = abs(float(entry[slice(*fields['base'])]) - effect['min']) > 1 or \
            ('max' in fields and abs(float(entry[slice(*fields['max'])]) - effect['max']) > 1)
        if moved:
            want('base', effect['min'])
            want('max', effect['max'])
            want('coef', effect['spCoef'])
        if moved and 'levelScaling' in fields:
            low, high = effect['min'], effect['max']
            mid = (low + high) / 2
            scaling = {'base': mid, 'variance': (high - low) / (2 * mid) if mid else 0, 'perLevel': effect['perLevel'],
                       'start': spell['baseLevel'], 'cap': spell['maxLevel'] or 60, 'low': low, 'high': high}
            s, e = fields['levelScaling']
            sub = entry[s:e]
            for k, v in scaling.items():
                m = re.search(r'\["' + k + r'"\]=([^,}]+)', sub)
                if m and abs(float(m.group(1)) - v) > 1e-4:
                    sub = sub[:m.start(1)] + num(v) + sub[m.end(1):]
                    changes.append(('levelScaling.' + k, m.group(1), num(v)))
            if sub != entry[s:e]:
                edits['levelScaling'] = (s, e, sub)
    new = entry
    for s, e, v in sorted(edits.values(), reverse=True):
        new = new[:s] + v + new[e:]
    return new


def refresh_file(path, spells, report):
    text = path.read_text()
    if '["abilities"]=' not in text:
        return
    a = text.index('["abilities"]=') + len('["abilities"]=')
    b = match_brace(text, a) + 1
    block = text[a:b]
    out, pos = [], 0
    for m in re.finditer(r'\["id"\]=(\d+)', block):
        if m.start() < pos:
            continue
        # the rank entry is the innermost table holding this id and a level
        start = block.rfind('{', 0, m.start())
        depth = 0
        while True:
            seg = block[start:m.start()]
            if seg.count('{') - seg.count('}') == 1:
                break
            start = block.rfind('{', 0, start)
            if start < 0:
                break
        if start < 0:
            continue
        end = match_brace(block, start) + 1
        entry = block[start:end]
        fields = top_fields(entry)
        if 'level' not in fields or 'key' not in fields:
            continue
        spell = spells.get(m.group(1))
        key = entry[slice(*fields['key'])].strip('"')
        if spell is None:
            report['unknown'].append((path.stem, key, int(m.group(1))))
            pos = end
            continue
        changes = []
        new = refresh_entry(entry, spell, changes)
        if changes:
            report['changed'].append((path.stem, key, int(m.group(1)), changes))
        out.append((start, end, new))
        pos = end
    for s, e, v in sorted(out, reverse=True):
        block = block[:s] + v + block[e:]
    path.write_text(text[:a] + block + text[b:])


def refresh_classes(engine, check=False, spells=None):
    spells = spells if spells is not None else dump_spells(engine)
    for s in spells.values():
        s['effects'] = s['effects'] or []
        s['powers'] = s['powers'] or []
    report = {'changed': [], 'unknown': []}
    for path in sorted(CLASSES.glob('*.lua')):
        before = path.read_text()
        refresh_file(path, spells, report)
        if check:
            path.write_text(before)
    return report


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('engine', type=Path)
    p.add_argument('--check', action='store_true', help='report only, change nothing')
    p.add_argument('--spells', type=Path, help='read the spell dump from this file instead of running the engine')
    args = p.parse_args()
    spells = json.loads(args.spells.read_text()) if args.spells else None
    report = refresh_classes(args.engine, args.check, spells)
    print(json.dumps({'changedRows': len(report['changed']), 'unknownIds': report['unknown']}, indent=1))
    return report


if __name__ == '__main__':
    main()
