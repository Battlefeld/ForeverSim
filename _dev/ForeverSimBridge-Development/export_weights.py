"""Writes measured level-60 stat weights into StatWeights60.lua (ZIELE.md, Ziel 3).

    python3 export_weights.py <ForeverSimBridge.lua aus WTF/Account/<Konto>/SavedVariables>

In the game: Level-60 character in the target spec, /fsim weights messen. Repeat for every spec you want.
Only weights the SIM measured are written; nothing is filled in by hand.
"""
import re
import sys
from pathlib import Path

from lupa.lua51 import LuaRuntime

TARGET = Path(__file__).resolve().parent.parent / 'StatWeights60.lua'


def lua_table(value, indent=1):
    pad = '    ' * indent
    if hasattr(value, 'items'):
        items = sorted(value.items(), key=lambda kv: str(kv[0]))
        inner = ''.join('%s[%r] = %s,\n' % (pad, str(k), lua_table(v, indent + 1)) for k, v in items)
        return '{\n%s%s}' % (inner, '    ' * (indent - 1))
    if isinstance(value, float):
        return repr(round(value, 6))
    return repr(value)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(Path(sys.argv[1]).read_text(encoding='utf-8-sig'))
    db = lua.globals().ForeverSimBridgeDB
    measured = db['measuredWeights'] if db is not None else None
    if measured is None:
        sys.exit('Keine gemessenen Gewichte gefunden (im Spiel: /fsim weights messen).')
    out = {}
    for cls, specs in measured.items():
        for spec, entry in specs.items():
            if entry['level'] != 60:
                continue
            out.setdefault(str(cls), {})[str(spec)] = {str(k): float(v) for k, v in entry['weights'].items()}
    if not out:
        sys.exit('Nur Stufe-60-Messungen werden übernommen; keine gefunden.')
    text = TARGET.read_text(encoding='utf-8')
    new = '-- BEGIN DATA (written by Development/export_weights.py)\nM.data = %s\n-- END DATA' % lua_table(out)
    text, n = re.subn(r'-- BEGIN DATA.*?-- END DATA', lambda m: new, text, flags=re.S)
    if n != 1:
        sys.exit('DATA-Markierungen in StatWeights60.lua nicht gefunden.')
    TARGET.write_text(text, encoding='utf-8')
    print('geschrieben:', ', '.join('%s/%s' % (c, s) for c, d in out.items() for s in d))


if __name__ == '__main__':
    main()
