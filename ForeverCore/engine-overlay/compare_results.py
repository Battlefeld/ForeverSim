"""Compare two wowsimcli results for equality after removing upstream's unordered lists.

wowsimcli lists actions, auras and resources in map iteration order, so two runs of the same binary
differ byte-wise. Lists whose entries carry an `id` are sorted by it; everything else, every number
included, must be exactly equal. Exit 0 on equality, 1 with the first differences otherwise.

    python compare_results.py upstream.json overlay.json
"""
import json
import sys


def canon(v):
    if isinstance(v, dict):
        return {k: canon(x) for k, x in sorted(v.items()) if k not in ('timing', 'elapsedMs')}
    if isinstance(v, list):
        items = [canon(x) for x in v]
        if items and all(isinstance(x, dict) and 'id' in x for x in items):
            items.sort(key=lambda x: json.dumps(x, sort_keys=True))
        return items
    return v


def differences(a, b, path='', out=None, limit=20):
    out = [] if out is None else out
    if len(out) >= limit:
        return out
    if type(a) is not type(b):
        out.append(f'{path}: {a!r} != {b!r}')
    elif isinstance(a, dict):
        for k in sorted(set(a) | set(b)):
            if k not in a or k not in b:
                out.append(f'{path}/{k}: only in one result')
            else:
                differences(a[k], b[k], f'{path}/{k}', out, limit)
    elif isinstance(a, list):
        if len(a) != len(b):
            out.append(f'{path}: {len(a)} entries != {len(b)}')
        for i, (x, y) in enumerate(zip(a, b)):
            differences(x, y, f'{path}[{i}]', out, limit)
    elif a != b:
        out.append(f'{path}: {a!r} != {b!r}')
    return out


def main():
    a, b = (canon(json.load(open(p))) for p in sys.argv[1:3])
    diff = differences(a, b)
    if diff:
        print('\n'.join(diff))
        sys.exit(1)
    print('identical')


if __name__ == '__main__':
    main()
