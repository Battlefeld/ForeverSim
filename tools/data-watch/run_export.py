"""Run a pinned local CASC/DB2 exporter, then compare plain and hotfixed records."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import subprocess
import sys
import time
from urllib.request import urlopen
import zipfile

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from watch import fetch, discover
VERSION = '0.9.9'
SHA256 = '47dea46331a09ee9460118bc80366165e4f72aa45a739302e5402b5a038d157e'
URL = f'https://github.com/Marlamin/wow.tools.local/releases/download/{VERSION}/Release-linux-x64.zip'


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--work', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--previous', type=Path)
    p.add_argument('--wow-folder', type=Path, help='Optional local WoW installation, including client hotfix cache')
    p.add_argument('--product', choices=['wowf', 'wow_classic_beta'], default='wowf')
    p.add_argument('--port', type=int, default=5089)
    a = p.parse_args()
    work = a.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    executable = work / 'wow.tools.local'
    if not executable.exists():
        raw = fetch(URL, timeout=120)
        if hashlib.sha256(raw).hexdigest() != SHA256:
            raise ValueError('Exporter archive checksum mismatch')
        with zipfile.ZipFile(io.BytesIO(raw)) as archive:
            for info in archive.infolist():
                if not (work / info.filename).resolve().is_relative_to(work):
                    raise ValueError('Unsafe exporter archive path')
            archive.extractall(work)
        executable.chmod(0o700)
    # Supply config explicitly: empty additionalCDNs arguments may revert to mirrors in WTL.
    config = {'config': {'wowProduct': a.product, 'wowFolder': str(a.wow_folder.resolve()) if a.wow_folder else '',
                         'useWago': 'false', 'useTACTChannels': 'false', 'region': 'eu', 'locale': 'enUS',
                         'additionalCDNs': 'level3.blizzard.com', 'readOnly': 'true'}}
    (work / 'config.json').write_text(json.dumps(config))
    base = f'http://127.0.0.1:{a.port}'
    with (work / 'exporter.log').open('wb') as log:
        process = subprocess.Popen([str(executable), '--urls', base], cwd=work, stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 900
            while True:
                if process.poll() is not None:
                    raise RuntimeError('CASC exporter exited; see exporter.log. No baseline was replaced.')
                try:
                    with urlopen(base + '/build/list', timeout=3) as response:
                        builds = json.load(response)
                    if builds:
                        break
                except Exception:
                    pass
                if time.monotonic() >= deadline:
                    raise TimeoutError('CASC exporter did not become ready')
                time.sleep(2)
            args = [sys.executable, str(HERE / 'watch.py'), '--output', str(a.output.resolve()), '--exporter', base, '--build', discover('eu')[a.product]['row']['VersionsName']]
            if a.previous: args += ['--previous', str(a.previous.resolve())]
            if a.wow_folder: args += ['--cache-dir', str(a.wow_folder.resolve() / 'Cache')]
            subprocess.run(args, check=True)
        finally:
            process.terminate()
            try: process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()

if __name__ == '__main__': main()
