"""Content identity shared by source verification, builds and automatic updates."""
import hashlib
import json
from pathlib import Path


def leveling_digest(path):
    data = json.loads(Path(path).read_text())
    # This label is derived from this digest; excluding it avoids a circular hash.
    data.pop('engineRevision', None)
    return hashlib.sha256(json.dumps(data, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def build_identity(commit, patches, overlay, level_data):
    inputs = dict(commit=commit, patches=[p['sha256'] for p in patches],
                  overlay=overlay, levelDataSHA256=level_data)
    digest = hashlib.sha256(json.dumps(inputs, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    return commit + '+' + digest[:24]
