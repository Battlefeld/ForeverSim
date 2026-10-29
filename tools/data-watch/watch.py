"""Blizzard build discovery and record-level client/hotfix diffs. Standard library only.

The optional exporter is a locally operated wow.tools.local instance. Start it with
-useWago false -additionalCDNs '' to read Blizzard/local CASC, not data websites.
"""
import argparse
import csv
import gzip
import hashlib
import io
import json
from pathlib import Path
import re
import sys
import time
from urllib.parse import urlencode, urlparse
from urllib.request import Request, urlopen

PRODUCTS = ('wowf', 'wow_classic_beta')
TABLES = ('TraitNode', 'TraitDefinition', 'TraitEdge', 'SpellName', 'SpellEffect',
          'SpellLevels', 'SpellPower', 'SpellMisc', 'SpellItemEnchantment',
          'QuestV2', 'QuestXP', 'QuestMoneyReward',
          'SkillLineAbility', 'ItemSparse', 'ItemEffect', 'PlayerExpectedStat')

def fetch(url, timeout=90):
    error = None
    for attempt in range(3):
        try:
            with urlopen(Request(url, headers={'User-Agent': 'ForeverDataWatch/1.0'}), timeout=timeout) as response:
                return response.read()
        except Exception as exc:
            error = exc
            if attempt < 2:
                time.sleep(2 ** attempt)
    raise error


def ngdp(text):
    lines = [line for line in text.splitlines() if line.strip() and not line.startswith('#')]
    if not lines:
        raise ValueError('Empty Blizzard version response')
    names = [column.split('!')[0] for column in lines[0].split('|')]
    rows = []
    for line in lines[1:]:
        values = line.split('|')
        if len(values) != len(names):
            raise ValueError('Malformed Blizzard version row')
        rows.append(dict(zip(names, values)))
    return rows


def discover(region):
    products = {}
    for product in PRODUCTS:
        url = f'https://us.version.battle.net/{product}/versions'
        raw = fetch(url)
        rows = ngdp(raw.decode('utf-8-sig'))
        row = next((r for r in rows if r['Region'] == region), None)
        if not row or not re.fullmatch(r'1\.60\.\d+\.\d+', row.get('VersionsName', '')):
            raise ValueError(f'{product}: no Forever build for {region}')
        if not all(re.fullmatch('[0-9a-f]{32}', row.get(key, '')) for key in ('BuildConfig', 'CDNConfig')):
            raise ValueError('Malformed Blizzard build/config identity')
        products[product] = {'source': url, 'row': row, 'responseSHA256': hashlib.sha256(raw).hexdigest()}
    return products


def parse_csv(raw):
    text = raw.decode('utf-8-sig')
    reader = csv.DictReader(io.StringIO(text))
    if not reader.fieldnames or len(set(reader.fieldnames)) != len(reader.fieldnames):
        raise ValueError('Missing or duplicate CSV columns')
    id_key = next((key for key in reader.fieldnames if key.casefold() == 'id'), None)
    if not id_key:
        raise ValueError('Export has no record ID; refusing an unkeyed comparison')
    records = {}
    for row in reader:
        if None in row or any(value is None for value in row.values()):
            raise ValueError('Truncated CSV record')
        key = row[id_key]
        if not re.fullmatch(r'\d+', key) or key in records:
            raise ValueError('Invalid or duplicate record ID')
        records[key] = {k: v for k, v in row.items() if k != id_key}
    if not records:
        raise ValueError('Empty table export')
    return records


def diff(before, after):
    changes = []
    for record in sorted(set(before) | set(after), key=int):
        old, new = before.get(record), after.get(record)
        if old == new:
            continue
        if old is None or new is None:
            changes.append({'id': record, 'kind': 'added' if old is None else 'removed', 'before': old, 'after': new})
        else:
            fields = {key: {'before': old.get(key), 'after': new.get(key)}
                      for key in sorted(set(old) | set(new)) if old.get(key) != new.get(key)}
            changes.append({'id': record, 'kind': 'modified', 'fields': fields})
    return changes


def cache_facts(folder):
    if folder is None:
        return []
    folder = Path(folder)
    if not folder.is_dir():
        raise ValueError('Hotfix cache folder does not exist')
    files = sorted(folder.rglob('DBCache.bin'))
    # Explicit DBCache root only: no account/SavedVariables files are collected.
    return [{'file': str(path.relative_to(folder)), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
             'bytes': path.stat().st_size} for path in files]


def export_table(base, table, build, hotfixes):
    query = urlencode({'name': table, 'build': build, 'useHotfixes': str(hotfixes).lower(), 'locale': 'enUS'})
    raw = fetch(base.rstrip('/') + '/dbc/export/csv?' + query, timeout=300)
    return parse_csv(raw), hashlib.sha256(raw).hexdigest()


def read_state(path):
    if not path or not Path(path).exists():
        return {}
    with gzip.open(path, 'rt', encoding='utf-8') as stream:
        state = json.load(stream)
    if state.get('schema') != 1:
        raise ValueError('Unknown baseline schema')
    return state


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--raidbots', action='store_true', help='Fetch build-specific verified caches even when build is unchanged')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--previous', type=Path)
    parser.add_argument('--product', choices=PRODUCTS, default='wowf')
    parser.add_argument('--region', choices=('eu', 'us', 'kr', 'tw', 'cn'), default='eu')
    parser.add_argument('--exporter', help='Local wow.tools.local base URL; must use direct CASC mode')
    parser.add_argument('--build', help='Explicit four-part build loaded by exporter')
    parser.add_argument('--tables', nargs='+', default=TABLES)
    parser.add_argument('--cache-dir', type=Path, help='Cache folder loaded by this exporter instance')
    args = parser.parse_args()
    previous = read_state(args.previous)
    products = discover(args.region)
    state = {'schema': 1, 'products': products, 'locale': 'enUS', 'tables': {}}
    report = {'schema': 1, 'products': products, 'buildChanges': {}, 'tables': {},
              'documentationStatus': 'not_assessed', 'hotfixCoverage': 'missing_client_cache',
              'limitations': ['Server-only changes invisible to client data require in-game measurements.',
                              'A data delta without matching release notes is a candidate undocumented change, not proof.']}
    for product, value in products.items():
        old = previous.get('products', {}).get(product, {}).get('row')
        if old != value['row']:
            report['buildChanges'][product] = {'before': old, 'after': value['row']}
    if args.raidbots:
        from hotfix_cache import download
        state['raidbots'] = {}
        for product, value in products.items():
            build_number = value['row']['VersionsName'].split('.')[-1]
            facts = download(build_number, args.output / 'caches' / product)
            state['raidbots'][product] = facts
        report['raidbots'] = state['raidbots']
    elif previous.get('raidbots'):
        state['raidbots'] = previous['raidbots']
    if args.exporter:
        url = urlparse(args.exporter)
        if url.scheme != 'http' or url.hostname not in ('localhost', '127.0.0.1', '::1'):
            raise ValueError('Exporter must be a local HTTP service')
        build = args.build or max((p['row']['VersionsName'] for p in products.values()), key=lambda v: tuple(map(int, v.split('.'))))
        if not re.fullmatch(r'1\.60\.\d+\.\d+', build):
            raise ValueError('Not a Forever build')
        if previous.get('tables') and previous.get('product', 'wowf') != args.product:
            raise ValueError('Cannot mix product baselines')
        state['product'] = args.product
        state['build'] = build
        caches = cache_facts(args.cache_dir)
        state['hotfixCaches'] = caches
        report['hotfixCoverage'] = 'local_cache_available_not_global' if caches else 'missing_client_cache'
        if previous.get('tables') and previous.get('locale') != state['locale']:
            raise ValueError('Baseline locale mismatch')
        for table in args.tables:
            if not re.fullmatch(r'[A-Za-z][A-Za-z0-9]+', table):
                raise ValueError('Invalid table name')
            plain, plain_hash = export_table(args.exporter, table, build, False)
            effective, effective_hash = export_table(args.exporter, table, build, True)
            old = previous.get('tables', {}).get(table)
            state['tables'][table] = {'plain': plain, 'effective': effective}
            report['tables'][table] = {'records': len(effective), 'plainSHA256': plain_hash,
                                      'effectiveSHA256': effective_hash,
                                      'baseline': old is None,
                                      'clientChanges': diff(old['plain'], plain) if old else [],
                                      'effectiveChanges': diff(old['effective'], effective) if old else [],
                                      'hotfixOverlay': diff(plain, effective)}
        missing = set(previous.get('tables', {})) - set(state['tables'])
        if missing:
            raise ValueError('Refusing to erase baseline tables: ' + ', '.join(sorted(missing)))
    elif previous.get('tables'):
        # Metadata checks must never erase a full extraction baseline.
        state.update({key: previous[key] for key in ('tables', 'build', 'hotfixCaches', 'product') if key in previous})
    if args.exporter:
        state['exportedCacheSHA256'] = state.get('raidbots', {}).get(args.product, {}).get('sha256')
    elif 'exportedCacheSHA256' in previous:
        state['exportedCacheSHA256'] = previous['exportedCacheSHA256']
    cache = state.get('raidbots', {}).get(args.product, {})
    report['extractionRequired'] = (state.get('build') != products[args.product]['row']['VersionsName']
        or state.get('exportedCacheSHA256') != cache.get('sha256'))
    report['effectiveBuild'] = state.get('build')
    report['exportedCacheSHA256'] = state.get('exportedCacheSHA256')
    if not args.exporter and cache.get('status') == 'available':
        report['hotfixCoverage'] = 'downloaded_not_applied' if report['extractionRequired'] else 'previous_validated_export'
    # All fetches and validation finish before replacing either baseline/output.
    args.output.mkdir(parents=True, exist_ok=True)
    state_path = args.output / 'state.json.gz'
    raw_state = json.dumps(state, sort_keys=True, separators=(',', ':')).encode('utf-8')
    state_path.with_suffix('.tmp').write_bytes(gzip.compress(raw_state, mtime=0))
    state_path.with_suffix('.tmp').replace(state_path)
    (args.output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'buildChanges': len(report['buildChanges']), 'tables': len(report['tables']),
                      'hotfixCoverage': report['hotfixCoverage']}))


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print('DATA WATCH FAILED; previous baseline retained: ' + str(exc), file=sys.stderr)
        sys.exit(1)
