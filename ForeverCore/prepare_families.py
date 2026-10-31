"""Build creature-families.json from the client's CreatureFamily table (wago.tools DB2 export).

The live addon reads the pet family as the client shows it (localized name, and the family ID where
the client exposes it). Engine names its pet types in English. This table connects both from game
data, so no family name is typed into ForeverCore by hand.

Usage: prepare_families.py <client build> <output.json> [--from-dir DIR]
  --from-dir reads CreatureFamily-<locale>.csv files instead of downloading (tests, offline machines).
"""
import argparse
import csv
import hashlib
import io
import json
import sys
import urllib.request
from pathlib import Path

LOCALES = ['enUS', 'deDE', 'frFR', 'esES', 'esMX', 'itIT', 'ptBR', 'ruRU', 'koKR', 'zhCN', 'zhTW']


def download(build, locale):
    """CSV text for one locale, or None. Tries the exact client build first, then the newest
    Classic Era export (family IDs and names are stable; the result records which one was used)."""
    for query in (f'build={build}&locale={locale}', f'locale={locale}'):
        url = f'https://wago.tools/db2/CreatureFamily/csv?{query}'
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'ForeverCore prepare_families'})
            return urllib.request.urlopen(req, timeout=60).read().decode('utf-8-sig'), url
        except Exception as e:  # network or build missing on wago.tools
            print(f'{url}: {e}', file=sys.stderr)
    return None, None


def parse(text):
    rows = list(csv.DictReader(io.StringIO(text)))
    if not rows or not {'ID', 'Name_lang'} <= set(rows[0]):
        raise ValueError('CreatureFamily CSV without ID/Name_lang columns')
    return {int(r['ID']): r['Name_lang'].strip() for r in rows if r['Name_lang'].strip()}


def build(build_id, texts):
    """texts: {locale: (csv text, source url)}. enUS is required: Engine's names are English."""
    if 'enUS' not in texts:
        raise ValueError('CreatureFamily enUS export missing')
    english = parse(texts['enUS'][0])
    families = []
    localized = {loc: parse(t) for loc, (t, _) in texts.items()}
    for fid in sorted(english):
        families.append({'id': fid, 'name': english[fid],
                         'names': {loc: names[fid] for loc, names in sorted(localized.items()) if fid in names}})
    digest = hashlib.sha256(json.dumps({k: v[0] for k, v in sorted(texts.items())}, sort_keys=True).encode()).hexdigest()
    return {'schema': 1, 'clientBuild': build_id, 'table': 'CreatureFamily',
            'sources': {loc: url for loc, (_, url) in sorted(texts.items())}, 'sourceSHA256': digest,
            'families': families}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('build')
    p.add_argument('output', type=Path)
    p.add_argument('--from-dir', type=Path)
    a = p.parse_args()
    texts = {}
    for loc in LOCALES:
        if a.from_dir:
            f = a.from_dir / f'CreatureFamily-{loc}.csv'
            if f.exists():
                texts[loc] = (f.read_text(encoding='utf-8-sig'), f.name)
        else:
            text, url = download(a.build, loc)
            if text:
                texts[loc] = (text, url)
    try:
        out = build(a.build, texts)
    except ValueError as e:
        raise SystemExit(f'creature families: {e}')
    a.output.write_text(json.dumps(out, ensure_ascii=False, separators=(',', ':')) + '\n', encoding='utf-8')
    print(f"{len(out['families'])} creature families, locales: {', '.join(sorted(texts))}")


if __name__ == '__main__':
    main()
