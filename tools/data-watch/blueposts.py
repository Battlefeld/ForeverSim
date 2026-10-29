"""Daily Forever blue-post feed comparison. Posts trigger checks, never supply simulation values."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

from watch import fetch

FEED = 'https://theforeverera.com/en/blue.xml'
RELEVANT = re.compile(r'hotfix|patch|development notes|tuning|bug|fix|update', re.I)


def parse(raw):
    root = ET.fromstring(raw)
    items = root.findall('./channel/item')
    if not items:
        raise ValueError('Blue tracker feed has no RSS items')
    posts = {}
    for item in items:
        title = item.findtext('title', '').strip()
        link = item.findtext('link', '').strip()
        ident = item.findtext('guid') or link
        if not title or not ident:
            raise ValueError('Blue tracker item has no title or identity')
        body = item.findtext('description', '') + item.findtext('{http://purl.org/rss/1.0/modules/content/}encoded', '')
        digest = hashlib.sha256(json.dumps([title, link, body], ensure_ascii=False).encode()).hexdigest()
        posts[ident] = {'title': title, 'url': link, 'sha256': digest,
                        'published': item.findtext('pubDate', ''),
                        'relevant': bool(RELEVANT.search(title + ' ' + body))}
    return posts


def compare(previous, current):
    old = previous.get('posts', {})
    changes = [dict(post, id=ident, kind='edited' if ident in old else 'new')
               for ident, post in current.items() if old.get(ident, {}).get('sha256') != post['sha256']]
    # First observation establishes a baseline; feed expiry never means deletion.
    return [] if not old else changes


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--previous', type=Path)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--report', type=Path, required=True)
    a = p.parse_args()
    old = json.loads(a.previous.read_text()) if a.previous and a.previous.exists() else {}
    state = old
    try:
        posts = parse(fetch(FEED, timeout=25))
        changes = compare(old, posts)
        state = {'schema': 1, 'feed': FEED, 'posts': posts}
        result = {'status': 'available', 'source': FEED, 'baseline': not bool(old.get('posts')),
                  'changes': changes, 'relevantChanges': sum(c['relevant'] for c in changes)}
    except Exception as exc:
        result = {'status': 'unavailable', 'source': FEED, 'error': str(exc), 'relevantChanges': 0}
        print('::warning::Blue tracker unavailable; daily Blizzard/cache check continues. ' + str(exc))
    state['lastCheck'] = result
    a.output.parent.mkdir(parents=True, exist_ok=True)
    a.output.write_text(json.dumps(state, indent=2) + '\n')
    report = json.loads(a.report.read_text())
    report['blueposts'] = result
    a.report.write_text(json.dumps(report, indent=2) + '\n')

if __name__ == '__main__': main()
