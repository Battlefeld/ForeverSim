"""Package the tested simulator (ForeverSim + ForeverCore bridge, engine, core) for installation."""
import argparse,hashlib,json,shutil,zipfile
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--core-exe',required=True,type=Path);p.add_argument('--engine-exe',required=True,type=Path);p.add_argument('--lua',required=True,type=Path);p.add_argument('--engine-source',required=True,type=Path);p.add_argument('--lua-license',required=True,type=Path);p.add_argument('--output',required=True,type=Path);p.add_argument('--routes-addon',type=Path,help='ForeverRoutes-addon.zip of the ForeverRoutes release: installed with the others');a=p.parse_args()
core=Path(__file__).resolve().parent
manifest=json.loads((core/'engine-data.json').read_text())
from engine_source import read_lock
lock=read_lock()
if manifest.get('engineRevision')!=lock['buildIdentity'] or manifest.get('levelOverlay')!=lock['overlay']:
 raise SystemExit('Engine manifest does not match the current source/level overlay; build_engine.py first')
if manifest.get('engineSHA256')!=hashlib.sha256(a.engine_exe.read_bytes()).hexdigest():
 raise SystemExit('Engine executable does not match the built manifest; build_engine.py first')
repo=core.parent;stage=a.output.parent/'ForeverCore_0.6.0_Integration_Test'
if stage.exists():shutil.rmtree(stage)
stage.mkdir(parents=True)
for src,name in [(a.core_exe,'ForeverCore.exe'),(a.engine_exe,'MythicSim.exe'),(a.lua,'Lua.exe')]:shutil.copy2(src,stage/name)
for name in ['Install.ps1','Restore.ps1','Installieren.cmd','Starten.cmd','config.example.json','engine.lock.json']:shutil.copy2(core/name,stage/name)
shutil.copy2(core/'README-DE.md',stage/'START-HIER.md')
shutil.copytree(repo/'ForeverCoreBridge',stage/'AddOns/ForeverCoreBridge')
# ForeverRoutes is installed from its own release. Never overwrite it with the
# obsolete HUD copy in this simulator repository.
# Full matching addon set; the installer backs up existing addon folders.
for addon in ['ForeverSimBridge']:
 shutil.copytree(repo/addon,stage/'AddOns'/addon,ignore=shutil.ignore_patterns('Development','tools','__pycache__','*.md','CHANGES_*'))
if a.routes_addon:
 # the standalone ForeverRoutes HUD from its own release, installed by ForeverCore.exe with the other addons
 with zipfile.ZipFile(a.routes_addon)as z:
  for info in z.infolist():
   name=info.filename.replace('\\','/')
   if info.is_dir()or not name.startswith('ForeverRoutes/')or '..'in name.split('/'):continue
   dest=stage/'AddOns'/name;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(z.read(info))
 if not (stage/'AddOns/ForeverRoutes/ForeverRoutes.toc').exists():raise SystemExit('ForeverRoutes-addon.zip has no ForeverRoutes/ForeverRoutes.toc')
runtime=stage/'Runtime';runtime.mkdir()
for addon in ['ForeverSimBridge']:
 for src in (repo/addon).rglob('*'):
  if not src.is_file()or src.suffix not in {'.lua','.toc'}or 'Development'in src.parts or 'tools'in src.parts:continue
  dest=runtime/src.relative_to(repo);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dest)
for name in ['routelib.lua','wowmock.lua','gameapi.lua','timemodel.lua']:
 src=repo/'_dev/harness'/name;dest=runtime/'_dev/harness'/name;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dest)
(runtime/'ForeverCore').mkdir()
for name in ['headless.lua','engine-data.json','engine.lock.json']:shutil.copy2(core/name,runtime/'ForeverCore'/name)
if (core/'creature-families.json').exists():shutil.copy2(core/'creature-families.json',runtime/'ForeverCore'/'creature-families.json')
shutil.copytree(core,stage/'Source/ForeverCore',ignore=shutil.ignore_patterns('*.exe','forevercore','__pycache__'))
shutil.copytree(repo/'ForeverCoreBridge',stage/'Source/ForeverCoreBridge')
license_dir=stage/'Lizenzen';license_dir.mkdir();shutil.copy2(a.engine_source/'LICENSE',license_dir/'MythicSim-MIT.txt');shutil.copy2(a.lua_license,license_dir/'Lua.txt')
notice='MythicSim / WoWSims: https://github.com/sage3648/mythicsim-forever-engine-go\nhttps://github.com/wowsims/forever\nEngine: '+json.loads((core/'engine.lock.json').read_text())['commit']+'\nRestedXP: https://github.com/RestedXP/RXPGuides (CC BY-NC-SA 4.0; routes of ForeverRoutes adapted from its guides are shared under the same licence)\nForeverRoutes: https://github.com/Battlefeld/ForeverRoutes (routes and dataset, GPL-3.0)\nQuestieDB: https://github.com/Questie/QuestieDB\nLua: https://www.lua.org (MIT)\n'
(license_dir/'QUELLEN.txt').write_text(notice)
files={str(f.relative_to(stage)).replace('\\','/'):hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted(stage.rglob('*'))if f.is_file()}
(stage/'SHA256.json').write_text(json.dumps(files,indent=2))
with zipfile.ZipFile(a.output,'w',zipfile.ZIP_DEFLATED,compresslevel=6)as z:
 for f in sorted(stage.rglob('*')):
  if f.is_file():z.write(f,stage.name+'/'+str(f.relative_to(stage)))
with zipfile.ZipFile(a.output)as z:
 assert z.testzip()is None
print(json.dumps({'file':str(a.output),'bytes':a.output.stat().st_size,'files':len(files),'sha256':hashlib.sha256(a.output.read_bytes()).hexdigest()}))
