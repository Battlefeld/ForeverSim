"""Average single-target DPS per spec suite from wowsimcli test goldens (*.results / *.results.tmp).

Used by the level smoke: the upstream spec suites run with FOREVERCORE_LEVEL set, their golden
comparison fails by design, and the written .results.tmp files hold the DPS at that level.
"""
import re
import sys
from pathlib import Path

ENTRY = re.compile(r'key: "([^"]+)"\s*\n\s*value: \{\s*\n\s*dps: ([-0-9.e+]+)', re.M)


def suite_dps(path):
    """Mean DPS over the suite's long single-target settings runs."""
    text = Path(path).read_text()
    values = [float(v) for k, v in ENTRY.findall(text) if '-Settings-' in k and k.endswith('LongSingleTarget')]
    return sum(values) / len(values) if values else None


if __name__ == '__main__':
    for p in sys.argv[1:]:
        print(Path(p).name.split('.')[0], suite_dps(p))
