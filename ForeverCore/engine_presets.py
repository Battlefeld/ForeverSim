"""Talent builds and gear sets that the engine ships for each spec (ui/specs/<spec>/presets.ts, the builds and gear_sets folders).

The ForeverSim addon offers them as "Engine Top". They stay current with the engine: the daily engine update reads
them again. Nothing here may fail the engine build: a spec whose presets cannot be read just has none, and the
addon works with the player's own builds.
"""
import json
import re
from pathlib import Path

# A quoted string; its text is in one of three consecutive groups (see pick).
QUOTED = r"""(?:'([^']*)'|"([^"]*)"|`([^`]*)`)"""


def pick(m, first):
    """Text of the quoted string whose groups start at `first`."""
    for i in range(first, first + 3):
        if m.group(i) is not None:
            return m.group(i)
    return ''


def _strings(pattern, text, flags=re.S):
    return list(re.finditer(pattern, text, flags))


def parse_talent_presets(text):
    """[{'name', 'talentsString', 'var'}] from `{ name: 'Fire', data: SavedTalents.create({ talentsString: '..' }) }`."""
    found = []
    pattern = r"(?:export\s+const\s+(\w+)\s*=\s*)?\{\s*name:\s*" + QUOTED + r"\s*,\s*data:\s*SavedTalents\.create\(\s*\{\s*talentsString:\s*" + QUOTED
    for m in _strings(pattern, text):
        found.append({'var': m.group(1) or '', 'name': pick(m, 2).strip(), 'talentsString': pick(m, 5).strip()})
    # Current Engine uses makePresetTalents(name, SavedTalents.create(...)).
    pattern = r"(?:export\s+const\s+(\w+)\s*=\s*)?(?:PresetUtils\.)?makePresetTalents\(\s*" + QUOTED + r"\s*,\s*SavedTalents\.create\(\s*\{\s*talentsString:\s*" + QUOTED
    for m in _strings(pattern, text):
        found.append({'var': m.group(1) or '', 'name': pick(m, 2).strip(), 'talentsString': pick(m, 5).strip()})
    return found


def parse_gear_imports(text):
    """{variable: file name} for `import Var from './gear_sets/p1.gear.json'`."""
    return {m.group(1): m.group(2) for m in re.finditer(r"import\s+(\w+)\s+from\s+['\"]\./gear_sets/([\w./-]+\.json)['\"]", text)}


def parse_gear_presets(text, folder, imports=None):
    """[{'name', 'items', 'var'}]: gear sets named in presets.ts, read from the JSON files under gear_sets/.
    Files that presets.ts does not name are added under their file name (without `.gear.json`)."""
    imports = imports if imports is not None else parse_gear_imports(text)
    seen, out = set(), []

    def load(file):
        path = Path(folder) / 'gear_sets' / file
        try:
            data = json.loads(path.read_text())
        except (OSError, ValueError):
            return None
        items = data.get('items') if isinstance(data, dict) else None
        return items if isinstance(items, list) else None

    pattern = r"(?:export\s+const\s+(\w+)\s*=\s*)?PresetUtils\.makePresetGear\(\s*" + QUOTED + r"\s*,\s*(\w+)"
    for m in _strings(pattern, text):
        file = imports.get(m.group(5))
        items = load(file) if file else None
        if items is not None:
            out.append({'var': m.group(1) or '', 'name': pick(m, 2).strip(), 'items': items})
            seen.add(file)
    gear_dir = Path(folder) / 'gear_sets'
    if gear_dir.is_dir():
        for path in sorted(gear_dir.glob('*.gear.json')):
            if path.name in seen:
                continue
            items = load(path.name)
            if items is not None:
                out.append({'var': '', 'name': path.name[:-len('.gear.json')], 'items': items})
    return out


def parse_builds(text, talents, gear):
    """Pairs of talents and gear: PresetUtils.makePresetBuild('Name', { gear: X, talents: Y, ... })."""
    by_talent = {t['var']: t['name'] for t in talents if t['var']}
    by_gear = {g['var']: g['name'] for g in gear if g['var']}
    out = []
    for m in _strings(r"makePresetBuild\(\s*" + QUOTED + r"\s*,\s*\{(.*?)\}\s*\)", text):
        body = m.group(4)
        t = re.search(r"talents:\s*(\w+)", body)
        g = re.search(r"gear:\s*(\w+)", body)
        row = {'name': pick(m, 1).strip()}
        if t and t.group(1) in by_talent:
            row['talents'] = by_talent[t.group(1)]
        if g and g.group(1) in by_gear:
            row['gear'] = by_gear[g.group(1)]
        if 'talents' in row:
            out.append(row)
    return out


def merge_engine_files(got, folder, facts):
    """Add what the engine's own loaders read from the spec's builds (talents, gear, the pair) and gear_sets folders
    (.siml and .json): the specs that moved their presets out of presets.ts have no talent lines there."""
    talents = {t['name'] for t in got['talents']}
    gear = {g['name'] for g in got['gear']}
    for name, build in sorted((facts.get('builds') or {}).get(folder, {}).items()):
        if name not in talents:
            got['talents'].append({'var': '', 'name': name, 'talentsString': build['talents']})
            talents.add(name)
        row = {'name': name, 'talents': name}
        items = (build.get('equipment') or {}).get('items')
        if items:
            if name not in gear:
                got['gear'].append({'var': '', 'name': name, 'items': items})
                gear.add(name)
            row['gear'] = name
        got['builds'].append(row)
    for name, equipment in sorted((facts.get('gearSets') or {}).get(folder, {}).items()):
        if name not in gear and equipment.get('items'):
            got['gear'].append({'var': '', 'name': name, 'items': equipment['items']})
            gear.add(name)
    return got


def read_spec_presets(engine, folder, facts=None):
    """Presets of one spec folder; empty lists when the file is missing or in an unknown shape."""
    spec_dir = Path(engine) / 'ui' / 'specs' / folder
    try:
        text = (spec_dir / 'presets.ts').read_text()
    except OSError:
        text = ''
    talents = parse_talent_presets(text)
    gear = parse_gear_presets(text, spec_dir)
    got = {'talents': talents, 'gear': gear, 'builds': parse_builds(text, talents, gear)}
    return merge_engine_files(got, folder, facts) if facts else got


def collect_presets(engine, specs, known_items, facts=None):
    """presets[class] = {talents, gear, builds} for every class, merged over its spec folders.

    specs: {spec: (class, folder)}; facts: the engine's own readings (builds, gearSets) from engine-overlay/tools/rotations.go.tmpl. Gear sets that name an item the engine database does not know are dropped (the
    engine would reject the whole run); the report lists what was left out."""
    result, report = {}, []
    for spec, (cl, folder) in sorted(specs.items()):
        got = read_spec_presets(engine, folder, facts)
        entry = result.setdefault(cl, {'talents': [], 'gear': [], 'builds': []})
        names = {t['name'] for t in entry['talents']}
        talent_names = {}
        for t in got['talents']:
            name = t['name']
            if name in names:
                name = f"{name} [{spec}]"
            names.add(name)
            talent_names[t['name']] = name
            entry['talents'].append({'name': name, 'talentsString': t['talentsString'], 'spec': spec})
        gnames = {g['name'] for g in entry['gear']}
        gear_names = {}
        for g in got['gear']:
            unknown = sorted({str(i['id']) for i in g['items'] if isinstance(i, dict) and i.get('id') and str(i['id']) not in known_items})
            if unknown:
                report.append(f"{folder}: Ausruestung '{g['name']}' enthaelt unbekannte Items {', '.join(unknown[:5])}")
                continue
            name = g['name']
            if name in gnames:
                name = f"{name} [{spec}]"
            gnames.add(name)
            gear_names[g['name']] = name
            entry['gear'].append({'name': name, 'items': g['items'], 'spec': spec})
        for b in got['builds']:
            row = dict(b, spec=spec)
            row['talents'] = talent_names[b['talents']]
            if b.get('gear'):
                if b['gear'] not in gear_names:
                    continue
                row['gear'] = gear_names[b['gear']]
            entry['builds'].append(row)
        if not got['talents']:
            report.append(f"{folder}: keine Talentvorlagen gefunden")
    return result, report
