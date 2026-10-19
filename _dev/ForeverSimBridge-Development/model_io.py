"""Keep canonical talent geometry and sheet rules when rebuilding generated data."""
from pathlib import Path

MARKER = '-- BEGIN FUS-UNIFIED-TALENT-TREES'


def write_model(path, source):
    path = Path(path)
    previous = path.read_text() if path.exists() else ''
    markers=[m for m in (MARKER,'-- Talent rules added') if m in previous]
    if markers and not any(m in source for m in markers):
        start=min(previous.index(m) for m in markers)
        source = source.rstrip() + '\n\n' + previous[start:]
    path.write_text(source)
