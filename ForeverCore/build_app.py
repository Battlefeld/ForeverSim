"""Build the one ForeverCore.exe users download: the installation package (package.py's ZIP) built in, a window
instead of a console. Usage: python build_app.py --package <ForeverCore_..._Windows_Test.zip> --output <ForeverCore.exe>"""
import argparse,hashlib,json,os,shutil,subprocess,zipfile
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--package',required=True,type=Path);p.add_argument('--output',required=True,type=Path);p.add_argument('--build',default=__import__('datetime').datetime.now(__import__('datetime').timezone.utc).strftime('%Y%m%d%H%M%S'),help='build number (UTC yyyymmddhhmmss): a later one updates installed programs');a=p.parse_args()
core=Path(__file__).resolve().parent
with zipfile.ZipFile(a.package)as z:
 names=set(n.split('/',1)[1]for n in z.namelist()if '/'in n)
 for need in ['MythicSim.exe','Lua.exe','engine.lock.json','AddOns/ForeverCoreBridge/ForeverCoreBridge.toc','AddOns/ForeverSimBridge/ForeverSimBridge.toc']:
  if need not in names:raise SystemExit('package lacks '+need)
 if 'AddOns/ForeverRoutes/ForeverRoutes.toc'not in names:print('warning: package has no ForeverRoutes addon (--routes-addon of package.py)')
payload=core/'payload.zip'
shutil.copy2(a.package,payload)
try:
 env=dict(os.environ,GOOS='windows',GOARCH='amd64',CGO_ENABLED='0')
 subprocess.run(['go','build','-trimpath','-tags','payload','-ldflags=-H windowsgui -s -w -X main.Build='+a.build,'-o',str(a.output.resolve()),'.'],cwd=core,env=env,check=True)
finally:payload.unlink(missing_ok=True)
print(json.dumps({'build':a.build,'file':str(a.output),'bytes':a.output.stat().st_size,'sha256':hashlib.sha256(a.output.read_bytes()).hexdigest()}))
