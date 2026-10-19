"""Rebuilding data must preserve live talent geometry/rules and be idempotent."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root=Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory() as temp:
    target=Path(temp)/'ForeverSimBridge'
    shutil.copytree(root/'Classes',target/'Classes')
    shutil.copytree(root/'Development',target/'Development',ignore=shutil.ignore_patterns('__pycache__','renders'))
    before={p.name:p.read_text() for p in (target/'Classes').glob('*.lua')}
    for index in range(2):
        subprocess.run([sys.executable,str(target/'Development/extend_reference_rules.py')],check=True,capture_output=True,text=True)
        current={p.name:p.read_text() for p in (target/'Classes').glob('*.lua')}
        if index:assert current==previous,'Generator ist nicht idempotent'
        previous=current
    for name,source in before.items():
        markers=[m for m in ['-- BEGIN FUS-UNIFIED-TALENT-TREES','-- Talent rules added']if m in source]
        if markers:
            marker=min(markers,key=source.index)
            assert source[source.index(marker):]==current[name][current[name].index(marker):],name+': Talentdaten verloren'
print('PASS: model generator preserves canonical trees/sheet rules and rebuilds identically twice.')
