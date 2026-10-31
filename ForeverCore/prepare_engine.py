"""Generate the adapter manifest from the locked wowsims/forever schema, never an unrelated fork."""
import argparse,json,os,re,shutil,subprocess,tempfile
from pathlib import Path
from engine_source import verify_source
p=argparse.ArgumentParser();p.add_argument('engine',type=Path);p.add_argument('output',type=Path);a=p.parse_args()
def engine_facts(engine,spell_ids=()):
 """The engine's own readings, from its loaders: {rotations: {ui/specs folder: {name: rotation}} (apls and builds, .siml
 and .json), spells: {id: [{type, aura, base}]} for the given ids}. Needs the generated protobuf Go files."""
 if not list((engine/'sim/core/proto').glob('*.pb.go')):
  protos=sorted(str(p.relative_to(engine)) for p in (engine/'proto').glob('*.proto'))
  subprocess.run(['protoc','-I=proto','--go_out=paths=source_relative:sim/core/proto',*protos],cwd=engine,check=True)
 env=dict(os.environ);[env.pop(k,None) for k in ('FOREVERCORE_LEVEL','FOREVERCORE_SPELLBOOK','FOREVERCORE_HUNTER','FOREVERCORE_WARLOCK','GOOS','GOARCH','CGO_ENABLED')]  # the helper runs here, whatever the engine is built for
 with tempfile.TemporaryDirectory() as t:
  main=Path(t)/'main.go';shutil.copyfile(Path(__file__).resolve().parent/'engine-overlay/tools/rotations.go.tmpl',main)
  out=subprocess.run(['go','run','-tags=with_db',str(main),*map(str,spell_ids)],cwd=engine,env=env,check=True,capture_output=True,text=True).stdout
 return json.loads(out)
PET_SPEED_IDS={n:int(i) for n,i in re.findall(r'^\s*((?:Faster|Slower)Attack\w+):\s*spelldata\.Ranked\((\d+)\)',(a.engine/'sim/hunter/spell_data_auto_gen.go').read_text(),re.M)}
FACTS=engine_facts(a.engine,PET_SPEED_IDS.values())
ROTATIONS=FACTS['rotations']
common=(a.engine/'proto/common.proto').read_text()
stats={k:int(v) for k,v in re.findall(r'(Stat\w+)\s*=\s*(\d+);',re.search(r'enum Stat\s*\{(.*?)\}',common,re.S).group(1))}
lock=verify_source(a.engine)
api=int(re.search(r'option\s*\(current_version_number\)\s*=\s*(\d+)',common).group(1))
out={'engineRevision':lock['buildIdentity'],'upstreamRevision':lock['commit'],'clientBuild':lock['clientBuild'],'apiVersion':api,'rulesetField':False,'liveSpellbook':True,'levelDataSHA256':lock['levelDataSHA256'],'statCount':max(stats.values())+1,'armorStat':stats['StatArmor'],'stats':stats,'classes':{},'races':{},'specs':{}}
for n,v in re.findall(r'^\s*(Race\w+)\s*=\s*(\d+);',common,re.M):out['races'][n]=int(v)
profiles={'warlock':('warlock/dps','warlock'),'mage':('mage/dps','mage'),'warrior':('warrior/dps','dpsWarrior'),'paladin':('paladin/retribution','retributionPaladin'),'hunter':('hunter/dps','hunter'),'priest':('priest/dps','dpsPriest'),'rogue':('rogue/dps','rogue'),'shaman':('shaman/elemental','elementalShaman'),'druid':('druid/balance','balanceDruid')}
extra={'feralCatDruid':('druid','druid/feralcat'),'feralBearDruid':('druid','druid/feralbear'),'enhancementShaman':('shaman','shaman/enhancement'),'protectionWarrior':('warrior','warrior/protection'),'protectionPaladin':('paladin','paladin/protection')}
MELEE_DISTANCE={'warrior/dps':0.0,'warrior/protection':0.0,'druid/feralcat':0.0,'druid/feralbear':0.0,'paladin/retribution':5.0,'paladin/protection':5.0,'rogue/dps':5.0,'shaman/enhancement':5.0}
def distance(folder):
 # A melee character of the app stands at the target (upstream's own start of 25 yd is for a class that charges in); the
 # others take upstream's default for the spec: ui/specs/<spec>/presets.ts OtherDefaults, or the spec's defaults.siml.
 if folder in MELEE_DISTANCE:return MELEE_DISTANCE[folder]
 siml=a.engine/'ui/specs'/folder/'defaults.siml'
 if siml.exists():
  m=re.search(r'^\s*distance_from_target\s+([\d.]+)',siml.read_text(),re.M)
  if m:return float(m.group(1))
 m=re.search(r'OtherDefaults\s*=\s*\{[^}]*?distanceFromTarget:\s*([\d.]+)',(a.engine/'ui/specs'/folder/'presets.ts').read_text(),re.S)
 return float(m.group(1)) if m else 0.0
for cl,(folder,spec)in profiles.items():extra[spec]=(cl,folder)
for spec,(cl,folder)in extra.items():
 rotations=ROTATIONS.get(folder)
 if not rotations:raise SystemExit('No nonempty rotations: '+folder)
 out['specs'][spec]={'class':cl,'spec':spec,'rotations':rotations,'referenceSpec':folder,'distanceFromTarget':distance(folder)}
for cl,(folder,spec)in profiles.items():
 rotations=ROTATIONS.get(folder)
 if not rotations:raise SystemExit('No rotations: '+folder)
 out['classes'][cl]={'spec':spec,'trees':json.loads((a.engine/'ui/sim/talents/trees'/f'{cl}.json').read_text()),'rotations':rotations,'referenceSpec':folder}
def hunter_options(engine):
 """Hunter option enums and their engine values, read from the engine source (never typed by hand)."""
 proto=(engine/'proto/hunter.proto').read_text()
 block=re.search(r'message HunterOptions\s*\{(.*?)\n\}',proto,re.S).group(1)
 def enum(name):
  body=re.search(r'enum '+name+r'\s*\{(.*?)\}',block,re.S).group(1)
  return {n:int(v) for n,v in re.findall(r'^\s*(\w+)\s*=\s*(\d+);',body,re.M)}
 pets=enum('PetType');ammo=enum('Ammo');quiver=enum('QuiverBonus');speeds=enum('PetAttackSpeed')
 gen=(engine/'sim/hunter/pet_families_auto_gen.go').read_text()
 names=dict(re.findall(r'^\t"(\w+)":\s*\{Name:\s*"([^"]+)"',gen,re.M))
 quivers={k:float(h) for k,h in re.findall(r'^\t"(\w+)":\s*\{Name:[^}]*Haste:\s*([\d.]+)\}',(engine/'sim/hunter/ammo_auto_gen.go').read_text(),re.M)}
 # a pet swings every 2 s; a Faster or Slower Attack passive scales the speed by its percent (Faster Attack III, +33%, 1.5 s)
 seconds={}
 for n,sid in PET_SPEED_IDS.items():
  eff=[e for e in FACTS['spells'][str(sid)] if e['aura']==9]
  if len(eff)!=1:raise SystemExit('Pet attack speed passive without one speed effect: '+n)
  seconds[n]=round(2.0/(1+eff[0]['base']/100),2)
 if set(seconds)!=set(speeds)-{'PetAttackSpeedNone'} or not set(names)>=set(pets)-{'PetNone'} or set(quivers)!=set(quiver)-{'QuiverNone'}:
  raise SystemExit('Hunter option tables in the engine source do not line up')
 return {'petTypes':{names[n]:v for n,v in pets.items() if n!='PetNone'},
  'petAttackSpeeds':[{'value':speeds['PetAttackSpeedNone'],'seconds':2.0}]+[{'value':speeds[n],'seconds':s} for n,s in sorted(seconds.items(),key=lambda x:x[1])],
  'quiver':[{'value':quiver[n],'spellId':0,'hastePct':quivers[n]} for n in sorted(quivers,key=lambda x:quiver[x])],
  'petLevel60Damage':{'min':petswing(engine)[0],'max':petswing(engine)[1]},
  'ammoNone':ammo.get('AmmoNone',0),'petNone':pets['PetNone'],'quiverNone':quiver['QuiverNone']}
def petswing(engine):
 """The pet's swing before attack power, per second of a 2 s swing: the creature dps over 2 s, 20% either side."""
 src=(engine/'sim/hunter/pets.go').read_text()
 m=re.search(r'const petSwingAverage = core\.CreatureAutoAttackDpsMaxLevel \* ([\d.]+)',src)
 var=re.search(r'BaseDamageMin:\s*petSwingAverage \* \(1 - ([\d.]+)\),\s*BaseDamageMax:\s*petSwingAverage \* \(1 \+ ([\d.]+)\)',src)
 dps=re.search(r'CreatureAutoAttackDpsMaxLevel\s*=\s*([\d.]+)',(engine/'sim/core/creature_values.go').read_text()) if (engine/'sim/core/creature_values.go').exists() else None
 if not m or not var:raise SystemExit('Pet swing not found in the engine source')
 if not dps:
  hits=[p for p in (engine/'sim/core').glob('*.go') if re.search(r'CreatureAutoAttackDpsMaxLevel\s*=\s*[\d.]+',p.read_text())]
  if not hits:raise SystemExit('CreatureAutoAttackDpsMaxLevel not found')
  dps=re.search(r'CreatureAutoAttackDpsMaxLevel\s*=\s*([\d.]+)',hits[0].read_text())
 avg=float(dps.group(1))*float(m.group(1))
 return round(avg*(1-float(var.group(1))),4)/2,round(avg*(1+float(var.group(2))),4)/2
out['hunter']=hunter_options(a.engine)
# Map every APL's high-rank spell IDs to the actual learned ranks. The engine
# already generates these families from client spell data. Do not infer them
# from translated names or hand-maintain a list of class spells.
def rotation_spell_rank_families(engine):
 result={}
 for cls in profiles:
  source=(engine/'sim'/cls/'spell_data_auto_gen.go').read_text()
  families={};ambiguous=set()
  for raw in re.findall(r'spelldata\.Ranked\(([\d,\s]+)\)',source):
   ranks=[int(n) for n in re.findall(r'\d+',raw)]
   if len(ranks)<2:continue
   for spell_id in ranks:
    key=str(spell_id)
    if key in ambiguous:continue
    if key in families and families[key]!=ranks:
     # Some proc ladders share an ID with a regular spell. Never guess its family.
     ambiguous.add(key);families.pop(key);continue
    families[key]=ranks
  result[cls]=families
 return result
out['spellRankFamilies']=rotation_spell_rank_families(a.engine)

def armor_mitigation(engine):
 # The engine's physical mitigation K/(armor+K), K = base + perLevel * attacker level, floored.
 src=(engine/'sim/core/spell_resistances.go').read_text()
 k=re.search(r'armorConstant\s*:=\s*([\d.]+)\s*\+\s*([\d.]+)\s*\*\s*float64\(at\.Attacker\.Level\)',src)
 f=re.search(r'return max\(1-defenderArmor/\(defenderArmor\+armorConstant\),\s*([\d.]+)\)',src)
 if not k or not f:raise SystemExit('Armor mitigation formula not found in the engine source')
 return {'base':float(k.group(1)),'perLevel':float(k.group(2)),'minMultiplier':float(f.group(1))}
out['armorMitigation']=armor_mitigation(a.engine)
def class_live_options(engine):
 """What a live snapshot can set in each class's options, with every spell or enchant ID read from
 the engine: its generated rank ladders and the client spell store it was built from. Only options
 the engine models are listed; anything else stays visible to the player as 'not taken over'."""
 import gzip
 store=json.loads(gzip.open(engine/'assets/db_inputs/spell_store_inputs.json').read())
 effects=store['Effects']
 def ladders(cls):
  src=(engine/'sim'/cls/'spell_data_auto_gen.go').read_text()
  return {n:[int(x) for x in ids.split(',')] for n,ids in re.findall(r'^\s*(\w+):\s*spelldata\.Ranked\(([\d,\s]+)\)',src,re.M)}
 def enum(proto,name):
  body=re.search(r'enum '+name+r'\s*\{(.*?)\}',(engine/'proto'/proto).read_text(),re.S).group(1)
  return {n:int(v) for n,v in re.findall(r'^\s*(\w+)\s*=\s*(\d+);',body,re.M)}
 def enchants(ids):
  # Temporary weapon enchantments a spell applies (classic type 54, Forever's imbue effect 360).
  out=set()
  for i in ids:
   for e in effects.get(str(i),[]):
    if e['Type'] in (54,360) and e['Misc']>0:out.add(e['Misc'])
  return sorted(out)
 def need(cond,what):
  if not cond:raise SystemExit('Live option source missing in the engine: '+what)
 rules={}
 def rule(cls,scope,field,value,source,ids,spec=None):
  need(ids,f'{cls}.{field}={value}')
  r={'scope':scope,'field':field,'value':value,'source':source,'ids':ids}
  if spec:r['spec']=spec
  rules.setdefault(cls,[]).append(r)
 # Mage: the armor each MageArmor case of armors.go applies.
 L=ladders('mage');e=enum('mage.proto','MageArmor')
 armors=(engine/'sim/mage/armors.go').read_text()
 # the default armor is picked through a map from the proto enum to the registered aura; each aura comes from registerArmor
 # of a rank variable, which is the highest rank of a ladder
 chosen=dict(re.findall(r'proto\.MageArmor_(\w+):\s*(\w+),',armors))
 rank_of=dict(re.findall(r'(\w+) := mage\.registerArmor\((\w+),',armors))
 ladder_of=dict(re.findall(r'(\w+) := spellData\.(\w+)\.Highest\(\)',armors))
 need(chosen,'mage default armors')
 for name,var in chosen.items():
  ladder=ladder_of.get(rank_of.get(var,''),'')
  need(ladder in L,ladder or var);rule('mage','classOptions','defaultMageArmor',e[name],'aura',L[ladder])
 # Warlock: Demon Armor (armors.go), the demon each sacrifice buff belongs to (talents_demonology.go).
 L=ladders('warlock');e=enum('warlock.proto','Armor');src=(engine/'sim/warlock/armors.go').read_text()
 armor=re.search(r'Options\.Armor == proto\.WarlockOptions_(\w+)',src).group(1);ladder=re.search(r'spellData\.(\w+)\.ByID',src).group(1)
 need(ladder in L,ladder);rule('warlock','classOptions','armor',e[armor],'aura',L[ladder])
 demo=(engine/'sim/warlock/talents_demonology.go').read_text();summon=enum('warlock.proto','Summon')
 sacrifice={n:[int(i)] for n,i in re.findall(r'\{proto\.WarlockOptions_(\w+),\s*(\d+)\},',demo)}
 need(sacrifice,'demonic sacrifice rows')
 for demon,ids in sacrifice.items():
  need(set(ids)<=set(L['DemonicSacrificeTriggered']),'sacrifice '+demon);rule('warlock','classOptions','sacrificeDemon',summon[demon],'aura',ids)
 registered=re.findall(r'warlock\.registerPet\(proto\.WarlockOptions_(\w+),',(engine/'sim/warlock/pets.go').read_text())
 # Priest: Inner Fire (priest.go) and Shadowform before the pull.
 L=ladders('priest');e=enum('priest.proto','Armor')
 need('InnerFire' in L and 'Shadowform' in L,'priest ladders')
 rule('priest','classOptions','armor',e['InnerFire'],'aura',L['InnerFire'])
 rule('priest','classOptions','preShadowform',True,'form',L['Shadowform'])
 # Warrior: the stance spell of each WarriorStance case in stances.go.
 L=ladders('warrior');e=enum('warrior.proto','WarriorStance');src=(engine/'sim/warrior/stances.go').read_text()
 for name,var in re.findall(r'case proto\.WarriorStance_(\w+):\s*\n\s*core\.MakePermanent\(warrior\.(\w+)\.RelatedSelfBuff\)',src):
  need(var in L,var);rule('warrior','classOptions','defaultStance',e[name],'form',L[var])
 # Shaman: each ShamanImbue's weapon spell and the enchantments it puts on the weapon.
 L=ladders('shaman');e=enum('shaman.proto','ShamanImbue')
 for name,v in e.items():
  if v==0:continue
  need(name in L,name);ids=enchants(L[name])
  rule('shaman','classOptions','imbueMh',v,'mainhand',ids)
  rule('shaman','options','imbueOh',v,'offhand',ids,spec='enhancementShaman')
 # Demon spells the engine models (register<Name>Spell in pets.go), with every client spell ID of that name.
 pets=(engine/'sim/warlock/pets.go').read_text();petSpells={}
 for fn in [f for f in re.findall(r'func \(pet \*WarlockPet\) register(\w+)\(\)',pets) if f in ('Firebolt','LashOfPain')]:
  words=re.sub(r'(?<!^)([A-Z])',r' \1',fn).lower()
  ids=sorted(int(i) for i,n in store['Names'].items() if n.lower()==words)
  need(ids,'demon spell '+fn);petSpells[fn[0].lower()+fn[1:]]=ids
 return {'rules':rules,'warlockPets':registered,'warlockSummon':{n:v for n,v in summon.items() if v},'warlockPetSpells':petSpells}
out['liveOptions']=class_live_options(a.engine)
db=json.loads((a.engine/'assets/database/db.json').read_text())
out['items']={str(item['id']):True for item in db['items']}
# Talent builds and gear sets the engine ships for each spec ("Engine Top" in the addon). Never fails the build.
try:
 from engine_presets import collect_presets
 out['presets'],_report=collect_presets(a.engine,extra,out['items'],FACTS)
 for _line in _report:print('Vorlagen:',_line)
except Exception as _issue:
 out['presets']={};print('Vorlagen: nicht gelesen:',_issue)
a.output.write_text(json.dumps(out,separators=(',',':')))
