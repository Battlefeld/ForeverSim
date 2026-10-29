"""Download and validate build-specific Raidbots verified HTFX v9 caches."""
import hashlib
from pathlib import Path
import struct
from urllib.error import HTTPError

from watch import fetch


def validate(raw, build):
    if len(raw) < 44 or raw[:4] != b'XFTH':
        raise ValueError('Invalid hotfix header')
    version, embedded = struct.unpack_from('<ii', raw, 4)
    if version != 9 or embedded != int(build):
        raise ValueError(f'Unsupported cache version/build: {version}/{embedded}')
    offset, count = 44, 0
    while offset < len(raw):
        if len(raw) - offset < 32:
            raise ValueError('Truncated hotfix record header')
        magic, region, push, unique, table, record, size, op, _, _, _ = struct.unpack_from('<4siiiIii4B', raw, offset)
        if magic != b'XFTH' or size < 0 or offset + 32 + size > len(raw):
            raise ValueError('Invalid hotfix record boundary')
        offset += 32 + size
        count += 1
    if not count:
        raise ValueError('Empty hotfix cache')
    return {'format': version, 'build': embedded, 'records': count,
            'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()}


def download(build, folder):
    url = f'https://storage.googleapis.com/raidbots-static/wow/{int(build)}/enUS/DBCache.bin'
    try:
        raw = fetch(url)
    except HTTPError as exc:
        if exc.code == 404:
            return {'status': 'not_available', 'source': url}
        raise
    facts = validate(raw, build)
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    destination = folder / 'DBCache.bin'
    destination.with_suffix('.tmp').write_bytes(raw)
    destination.with_suffix('.tmp').replace(destination)
    return dict(facts, status='available', source=url, region='NA', locale='enUS',
                verification='raidbots_verified_not_completeness_guarantee')
