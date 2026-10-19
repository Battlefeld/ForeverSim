"""Idempotent source-backed extension of the verified baseline class models."""
from pathlib import Path
from model_io import write_model
import json
DEV=Path(__file__).resolve().parent;ROOT=DEV.parent;BASE=DEV/'baseline-models'
D=json.loads((DEV/'reference-data.json').read_text())
models={c:json.loads((BASE/f'{c}.baseline.json').read_text())for c in ['priest','paladin','hunter','rogue','warrior','druid','enhancement']}
shaman=json.loads((BASE/'shaman.baseline.json').read_text())
for field in ['procs','modifiers','talentDefinitions','talents']:
 models['enhancement'][field]=json.loads(json.dumps(shaman.get(field,[])))
changes=[]
def lua(x):
 if x is None:return 'nil'
 if isinstance(x,bool):return 'true'if x else'false'
 if isinstance(x,str):return json.dumps(x,ensure_ascii=False)
 if isinstance(x,(int,float)):return repr(x)
 if isinstance(x,list):return '{'+','.join(map(lua,x))+'}'
 return '{'+','.join('['+lua(k)+']='+lua(v)for k,v in x.items())+'}'
def append(m,field,r):
 if not isinstance(m.get(field),list):m[field]=[]
 if r not in m[field]:m[field].append(r)
def row(c,n):
 if c=='druid'and n=='Berserk':return D['spells']['417141']
 return D['spells'][str(D['classes']['shaman'if c=='enhancement'else c][n]['ids'][0])]
def vals(c,n,e=0,scale=100):
 r=row(c,n);curve=D['curves'].get(str(r['ID']))
 if curve and len(curve)>e:return [v/scale for v in curve[e]]
 return [r['Effects'][e].get('BasePoints',0)/scale]
def support(c,n,scope=None):
 m=models[c];k=n[0].lower()+n[1:]
 for key in list(m.get('unsupportedTalents',{})):
  if key.lower()==k.lower():del m['unsupportedTalents'][key]
 for t in m.get('talentDefinitions',[]):
  if t['key'].lower()==k.lower():t['supported']=True;t['scope']=scope or 'Source-backed rule in shared CombatEngine.'
 changes.append({'class':c,'talent':n,'scope':scope or 'combat'});return k
def mod(c,n,field,targets=None,e=0,scale=100,op='add'):
 m=models[c];k=support(c,n);r={'talent':k,'field':field,'op':op,'values':vals(c,n,e,scale)}
 if targets:r['targets']=targets
 # Avoid retaining a partial auto-generated modifier on the same field.
 m['modifiers']=[v for v in m.get('modifiers',[])if not(v.get('talent')==k and v.get('field')==field)]
 append(m,'modifiers',r)
def context(c,n,field,e=0,**kw):
 k=support(c,n);append(models[c],'contextModifiers',dict(talent=k,field=field,values=vals(c,n,e),**kw))
def proc(c,n,trigger,sources=None,**kw):
 k=support(c,n);r=dict(talent=k,key=k,trigger=trigger,chanceValues=[1]*max(1,len(vals(c,n))));r.update(kw)
 if sources:r['sources']=sources
 append(models[c],'procs',r)
def buff(c,n,duration=None,forms=None,resource='mana',**effects):
 m=models[c];r=row(c,n);k=support(c,n)
 b=dict(key=k,id=r['ID'],name=r['Name'],rank=1,level=max(1,r.get('SpellLevel',1)),requiredTalent=k,school='physical'if resource!='mana'else 'holy',attackType='spell',resource=resource,cost=0,cast=0,gcd=r.get('GCDMs',0)/1000,cooldown=max(r.get('CooldownMs',0),r.get('CategoryCooldownMs',0))/1000,kind='buff',ignoreHaste=resource!='mana',duration=duration or r.get('DurationMs',0)/1000,grantsBuff=dict(key=k,charges=1,duration=duration or r.get('DurationMs',0)/1000,**effects))
 for p in r['Powers']:
  if p.get('CostPct'):b['baseManaCost']=p['CostPct']/100
  elif p.get('Cost'):b['cost']=p['Cost']/(10 if p.get('Type')==1 else 1)
 if forms:b['forms']=forms
 m['abilities'][k]=[b];m['spellAliases'][k]=[r['Name'].lower()]
 append(m,'cooldownAbilities',k)
 return k,b
def attack(c,n,required=True,**extra):
 m=models[c];family=D['classes'][c][n];k=support(c,n)if required else n[0].lower()+n[1:];rs=[]
 for ordinal,ident in enumerate(family['ids'],1):
  r=D['spells'][str(ident)];res={0:'mana',1:'rage',3:'energy'}.get(next(iter(r['Powers']),{}).get('Type',0),'mana');power=next(iter(r['Powers']),{})
  b=dict(key=k,id=ident,name=r['Name'],rank=ordinal,level=max(1,r.get('SpellLevel',1)),school={1:'physical',2:'holy',4:'fire',8:'nature',16:'frost',32:'shadow',64:'arcane'}.get(r.get('School',1),'physical'),resource=res,cost=power.get('Cost',0)/(10 if res=='rage'else 1),cast=r.get('CastTimeMs',0)/1000,gcd=r.get('GCDMs',1500)/1000,cooldown=max(r.get('CooldownMs',0),r.get('CategoryCooldownMs',0))/1000,attackType={1:'spell',2:'melee',3:'ranged'}.get(r.get('DefenseType',1),'spell'),base=0,max=0,coef=0,ignoreHaste=res!='mana',refundFraction=.8 if r['Attr'].get('1',0)&0x8000000 else 0)
  if power.get('CostPct'):b['baseManaCost']=power['CostPct']/100
  if required:b['requiredTalent']=k
  for e in r['Effects']:
   if e['Type'] in ['E_SCHOOL_DAMAGE','E_WEAPON_DAMAGE','E_NORMALIZED_WEAPON_DMG','E_WEAPON_DAMAGE_NOSCHOOL']:
    bp=e.get('BasePoints',0);b.update(base=bp,max=bp,coef=e.get('SPCoef',0)if e['Type']=='E_SCHOOL_DAMAGE'else 0,apCoef=e.get('APCoef',0),directScaling=dict(base=bp,variance=e.get('Variance',0),perLevel=e.get('PPL',0),start=e.get('SpellLevel',b['level']),cap=e.get('MaxLevel',60)))
    if 'WEAPON'in e['Type']:b['weaponDamage']=dict(hand='ranged'if b['attackType']=='ranged'else'mainhand',normalized=e['Type']=='E_NORMALIZED_WEAPON_DMG',multiplier=1)
   if e['Type']=='E_WEAPON_PERCENT_DAMAGE':b.setdefault('weaponDamage',dict(hand='mainhand',normalized=True))['multiplier']=e.get('BasePoints',100)/100
   if e['Type']=='E_ENERGIZE'and e.get('Misc')==4:b['comboGain']=e.get('BasePoints',1)
   if e.get('Aura')=='A_PERIODIC_DAMAGE':b.update(duration=r.get('DurationMs',0)/1000,tickEvery=e.get('PeriodMs',3000)/1000,tickBase=e.get('BasePoints',0),tickCoef=0,periodicCrit=bool(r['Attr'].get('8',0)&0x200),periodicScaling=dict(base=e.get('BasePoints',0),perLevel=e.get('PPL',0),start=e.get('SpellLevel',b['level']),cap=e.get('MaxLevel',60)))
  b.update(extra);rs.append(b)
 m['abilities'][k]=rs;m['spellAliases'][k]=[r['Name'].lower()];return k,rs

# Priest: source methods, plus execute crit from shadow_word_death.go.
mod('priest','DevouringContagion','cost',['devouringPlague'],op='multiply')
mod('priest','ImprovedMindFlay','periodicBonus',['mindFlay'])
k=support('priest','EarlyDemise');append(models['priest'],'conditionalModifiers',dict(talent=k,values=vals('priest','EarlyDemise'),field='crit',targets=['shadowWordDeath'],targetBelow=20))
k,b=buff('priest','PowerInfusion',damageBonus=.2,schools=['holy','shadow','nature','arcane','fire','frost'])
# Inner Focus lasts until the next class spell; its cooldown starts when consumed.
k,b=buff('priest','InnerFocus',duration=1e9)
append(models['priest'],'buffRules',dict(buff=k,consumeOn=[x for x in models['priest']['abilities']if x not in ['innerFocus','powerInfusion']],costOverride=0,buffCritPerStack=.25,critExcluded=['shadowWordDeath','shadowWordPain','devouringPlague'],consumeCharges=True,autoPriority=False,cooldownOnConsume=180,snapshotCrit=True))
for n in ['Martyrdom','RenewedHope','LitanyOfLight']:
 support('priest',n,'Reference TODO; no effect on stationary damage-only fights. Healing and pushback are not represented.')
k,rs=attack('priest','HolyNova',forms=['caster'])
append(models['priest']['search'],'optionalAbilities',dict(key=k))
mod('priest','SearingLight','mult',e=0,op='multiply');models['priest']['modifiers'][-1]['schools']=['holy']
proc('priest','SearingLight','tick',['holyFire'],buff='searingLight',duration=10,charges=1,chanceValues=vals('priest','SearingLight',1),costOverride=0,consumeOn=['holyNova'],castOverride=0,priorityAtStacks=1)

# Weapon specialization conditions are evaluated for each compared loadout.
for c in ['paladin','warrior']:
 context(c,'TwoHandedWeaponSpecialization','damage',schools=['physical'],twoHanded=True)
context('paladin','OneHandedWeaponSpecialization','damage',schools=['physical'],twoHanded=False)
context('warrior','Bastion','damage',schools=['physical'],shield=True)
mod('warrior','ImprovedSlam','cast',['slam'],scale=1000)
mod('warrior','ImprovedSlam','gcd',['slam'],e=1,scale=1000)
# Cooldown has no rank curve: source ValueAt scales the -3000 ms at both ranks.
append(models['warrior'],'modifiers',dict(talent='improvedSlam',field='cooldown',op='add',values=[-3,-3],targets=['slam']))
mod('warrior','RagingBlows','cost',['whirlwind'],e=1,scale=10)
k=support('warrior','DualWieldSpecialization')
# Replace the baseline rule; adding it twice squares the damage multiplier.
models['warrior']['staticRules']=[r for r in models['warrior'].get('staticRules',[]) if not(r.get('talent')==k and r.get('field')=='offhandMultiplier')]
append(models['warrior'],'staticRules',dict(talent=k,field='offhandMultiplier',values=vals('warrior','DualWieldSpecialization')))
append(models['warrior'],'staticRules',dict(talent=k,field='offhandRageMultiplier',values=vals('warrior','DualWieldSpecialization',1)))

# Hunter sheet AP already contains Careful Aim; only item intellect deltas are added.
context('hunter','CarefulAim','intellectAttackPower')
context('hunter','FocusedFire','damage',petActive=True,includePet=True)
context('hunter','LoneWolf','damage',petActive=False)
context('hunter','RangedWeaponSpecialization','damage',attackTypes=['ranged'],targets=['auto:ranged','aimedShot','multiShot','arcaneShot','sniperShot'])
for n in ['ImprovedAspectOfTheMonkey']:
 support('hunter',n,'Dodge has no effect without incoming attacks.')
k,b=buff('hunter','RapidFire',attackHaste=.4,rangedHaste=.4);b.pop('requiredTalent',None)
mod('hunter','RapidKilling','cooldown',['rapidFire'],scale=1000)
k,b=buff('hunter','BestialWrath',actorDamageBonus=.5);b['requiresPet']=True
k,rs=attack('hunter','SniperShot',weaponDamage=dict(hand='ranged',normalized=True,multiplier=1),apType='ranged',pausesAutoAttack=True)
append(models['hunter']['search'],'optionalAbilities',dict(key=k))
# Melee hunter attacks require a melee encounter; do not insert a kick into a ranged rotation.
k,rs=attack('hunter','StriderKick',weaponDamage=dict(hand='mainhand',normalized=True,multiplier=1),ignoreHaste=True,requiresMeleeRange=True)
append(models['hunter']['search'],'optionalAbilities',dict(key=k))
proc('hunter','RapidRecuperation','applicationHit',['serpentSting'],buff='rapidRecuperation',duration=row('hunter','RapidRecuperationTriggered').get('DurationMs',0)/1000,buffCastingRegenValues=vals('hunter','RapidRecuperation'))
proc('hunter','Resourcefulness','crit',buff='resourcefulness',duration=30,chanceValues=[.5,1],buffCastingRegen=.5)

# Rogue finishers: source checks chance per spent point, energy only after a landed finisher.
k=support('rogue','RelentlessStrikes');append(models['rogue'],'finisherProcs',dict(talent=k,key=k,chanceValues=[.2],perCombo=True,resource='energy',resourceGain=25))
context('rogue','SerratedBlades','armorIgnore')
context('rogue','Murder','damage',mobTypes=['humanoid','giant'])
k,b=buff('rogue','ColdBlood',duration=1e9,resource='energy');b['level']=30
append(models['rogue'],'buffRules',dict(buff=k,consumeOn=['sinisterStrike','backstab','eviscerate','mutilate','venom'],costOn=[],buffCritPerStack=1,consumeCharges=True,autoPriority=False,snapshotCrit=True))
# No crit chance is added to white swings or DoTs by Cold Blood.
k,rs=attack('rogue','Hemorrhage',grantsDebuff=dict(key='hemorrhage',duration=15,charges=1e9,damageBonus=.15,affectedSpells=['rupture']),weaponMultipliersBySubclass={'15':1.45})
models['rogue']['search']['filler']['alternatives'].append(k)
proc('rogue','PuncturingWounds','hit',['backstab'],chanceValues=vals('rogue','PuncturingWounds',1),comboGain=1)
mod('rogue','PuncturingWounds','physicalCritBonus',['mutilate'],e=2)
# Mutilate's parent rolls avoidance once; both strikes subsequently roll block/crit only.
k,rs=attack('rogue','Mutilate',weaponSubclasses=[15],requiredOffhandSubclass=15,parentAttackOnly=True,weaponHands=['mainhand','offhand'],weaponDamage=dict(hand='mainhand',normalized=True,multiplier=.75),damageIfPoison=1.2)
for b,flat in zip(rs,[23,33,48,67]):b['base']=flat;b['max']=flat;b.pop('directScaling',None)
models['rogue']['search']['filler']['alternatives'].append(k)
for r in models['rogue'].get('genericProcs',[]):
 if r.get('talent')=='sealFate':r['sources']+=['mutilate:mainhand','mutilate:offhand','hemorrhage']
for rule in models['rogue']['modifiers']:
 if rule.get('talent')in ['opportunity','lethality']:rule['targets']+=['mutilate']
# Client poison enchant IDs, not the reference UI's consumable IDs.
models['rogue']['weaponEnchantRules']={'625':dict(type='spellProc',chance=.2,spellKey='instantPoison'),'2630':dict(type='spellProc',chance=.3,spellKey='deadlyPoison'),'706':dict(type='spellProc',chance=.3,spellKey='woundPoison')}
support('rogue','ImprovedPoisons')
models['rogue']['poisonChanceValues']=vals('rogue','ImprovedPoisons')
for key,id,base,maxi,duration in [('instantPoison',11337,76,100,0),('deadlyPoison',25349,0,0,12),('woundPoison',13224,0,0,15)]:
 b=dict(key=key,id=id,name=key,rank=1,level=1,alwaysKnown=True,school='nature',attackType='spell',resource='mana',cost=0,cast=0,gcd=0,base=base,max=maxi,coef=0,passive=True,poison=True)
 if duration:b.update(stackingDot=True,duration=duration,maxStacks=5)
 if key=='deadlyPoison':b.update(tickBase=23,tickCoef=0,tickEvery=3,periodicCrit=True)
 models['rogue']['abilities'][key]=[b]
# Lower ranks: enchant IDs verified against Forever's spell pages; damage comes from the pinned
# client proc rows, not from Classic/TBC tooltip damage. The rank-6/5 reference constants stay intact.
for enchant,ident in [(323,8680),(324,8685),(325,8689),(623,11335),(624,11336)]:
 r=D['spells'][str(ident)];e=r['Effects'][0];bp=e.get('BasePoints',0);spread=bp*e.get('Variance',0)/2
 models['rogue']['weaponEnchantRules'][str(enchant)]=dict(type='spellProc',chance=.2,spellKey='instantPoison',abilityOverride=dict(id=ident,base=bp-spread,max=bp+spread))
for enchant,ident in [(7,2818),(8,2819),(626,11353),(627,11354)]:
 r=D['spells'][str(ident)];e=r['Effects'][0]
 models['rogue']['weaponEnchantRules'][str(enchant)]=dict(type='spellProc',chance=.3,spellKey='deadlyPoison',abilityOverride=dict(id=ident,tickBase=e.get('BasePoints',0),periodicCrit=bool(r['Attr'].get('8',0)&0x200)))
for enchant,ident in [(703,13218),(704,13222),(705,13223)]:
 models['rogue']['weaponEnchantRules'][str(enchant)]=dict(type='spellProc',chance=.3,spellKey='woundPoison',abilityOverride=dict(id=ident,cannotCrit=True))
models['rogue']['poisonRankSources']=['https://www.wowhead.com/forever/spell=8679','https://www.wowhead.com/forever/spell=8686','https://www.wowhead.com/forever/spell=8688','https://www.wowhead.com/forever/spell=11338','https://www.wowhead.com/forever/spell=11339','https://www.wowhead.com/forever/spell=2823','https://www.wowhead.com/forever/spell=2824','https://www.wowhead.com/forever/spell=11355','https://www.wowhead.com/forever/spell=11356','https://www.wowhead.com/forever/spell=13219','https://www.wowhead.com/forever/spell=13225','https://www.wowhead.com/forever/spell=13226']
for rule in models['rogue']['modifiers']:
 if rule.get('talent')=='vilePoisons':
  if rule['field']=='directBonus':rule['targets']=['instantPoison']
  elif rule['field']=='periodicBonus':rule['targets']=['deadlyPoison']
k,b=buff('rogue','Venom',duration=6,resource='energy',poisonDamageBonus=.3,poisonChanceBonus=.1);b['level']=40;b['spendCombo']=True;b['minCombo']=1;b['durationPerCombo']=3;b['cost']=25;b['gcd']=1

# Flat cost stacks are created by Rupture ticks, consumed by Backstab/Hemorrhage.
proc('rogue','ThousandCuts','tick',['rupture'],buff='thousandCuts',duration=row('rogue','ThousandCutsTriggered').get('DurationMs',0)/1000,maxStacks=5,cooldown=1.9)
append(models['rogue'],'buffRules',dict(buff='thousandCuts',consumeOn=['backstab','hemorrhage'],costFlatPerStack=row('rogue','ThousandCutsTriggered')['Effects'][0].get('BasePoints',0),consumeCharges=True,consumeAllStacks=True,autoPriority=False))
k=support('rogue','Quietus');append(models['rogue'],'conditionalModifiers',dict(talent=k,field='damage',values=vals('rogue','Quietus'),targets=['sinisterStrike','ghostlyStrike','hemorrhage'],targetBelow=35))

# Druid stat deltas and a bleed-sensitive melee-special multiplier.
k=support('druid','HeartOfTheWild');append(models['druid'],'attributeModifiers',dict(talent=k,field='intellect',values=vals('druid','HeartOfTheWild')))
mod('druid','ImprovedStarfire','cast',['starfire'],scale=1000)
k=support('druid','RendAndTear');append(models['druid'],'conditionalModifiers',dict(talent=k,field='damage',values=vals('druid','RendAndTear'),requiresBleed=True,attackTypes=['melee'],excludeWhite=True))
k=support('druid','BloodFrenzy');append(models['druid'],'genericProcs',dict(talent=k,key=k,chanceValues=vals('druid','BloodFrenzy'),onCrit=True,meleeOnly=True,forms=['cat'],sources=['claw','shred','rake'],comboGain=1))
append(models['druid'],'genericProcs',dict(talent=k,key=k,chanceValues=vals('druid','BloodFrenzy'),onCrit=True,meleeOnly=True,forms=['bear'],resource='rage',resourceGain=5))
k,b=buff('druid','Berserk',duration=15,forms=['cat','bear'],resource='energy');b['cooldown']=180;b['level']=40;b['gcd']=0
append(models['druid'],'buffRules',dict(buff=k,buffCritPerStack=1,damageOn=['claw','shred','rake'],consumeCharges=False,autoPriority=False))
for n in ['FeralCharge','WildGrowth']:
 support('druid',n,'Movement/healing are outside stationary single-target DPS scope.')
support('paladin','VoiceOfTruth','Silence/interrupt immunity has no effect without those encounter events.')
for b,ident in zip(models['paladin']['abilities']['consecration'],D['classes']['paladin']['ConsecrationTriggered']['ids']):
 r=D['spells'][str(ident)];base,bonus=r['Effects'][:2]
 b.update(duration=8,tickEvery=1,tickBase=base.get('BasePoints',0)+bonus.get('BasePoints',0),tickCoef=bonus.get('SPCoef',0),periodicCrit=True,tickRolls=True,tickAsDirect=True,applyRegardlessOfHit=True)
 b['beforeTickDebuff']=dict(key='consecratedGround',duration=row('paladin','ConsecratedGroundTriggered').get('DurationMs',0)/1000,charges=1e9,affectedSchools=['holy'],talent='consecratedGround',damageBonusValues=vals('paladin','ConsecratedGround'))
support('paladin','ConsecratedGround')
k=support('paladin','SanctifiedJudgement');models['paladin']['sealRefund']=dict(talent=k,chanceValues=vals('paladin','SanctifiedJudgement'),refundValues=[v*10/9 for v in vals('paladin','SanctifiedJudgement',1)])
k,b=buff('paladin','SwiftJudgement',duration=1e9);b['resetCooldownKeys']=['judgement'];b['requiresCooldownActive']='judgement';b['requiresBuffGroup']='seal'
append(models['paladin'],'buffRules',dict(buff=k,consumeOn=['judgement'],costOverride=0,consumeCharges=True,autoPriority=False))
k,rs=attack('paladin','SealOfCommand')
pr=D['spells']['20424']['Effects'][0]
for b,jid in zip(rs,D['classes']['paladin']['JudgementOfCommand']['ids']):
 j=D['spells'][str(jid)];de=D['spells'][str(int(j['Effects'][0]['BasePoints']))]['Effects'][0]
 b.pop('base',None);b.pop('max',None);b.pop('directScaling',None);b.update(kind='buff',duration=30,grantsBuff=dict(key=k,duration=30,charges=1,group='seal'),sealProc=dict(spellKey='sealOfCommandProc',ppm=7,icd=1),judgement=dict(base=de.get('BasePoints',0)/2,max=de.get('BasePoints',0)/2,coef=de.get('SPCoef',0),scaling=dict(base=de.get('BasePoints',0),variance=de.get('Variance',0),perLevel=de.get('PPL',0),start=de.get('SpellLevel',20),cap=de.get('MaxLevel',60)),scale=.5))
procAbility=dict(key='sealOfCommandProc',id=20424,name='Seal of Command proc',rank=1,level=1,alwaysKnown=True,school='holy',attackType='melee',resource='mana',cost=0,cast=0,gcd=0,base=0,max=0,coef=pr.get('SPCoef',0),weaponDamage=dict(hand='mainhand',normalized=False,multiplier=pr.get('BasePoints',70)/100),passive=True)
models['paladin']['abilities']['sealOfCommandProc']=[procAbility]
append(models['paladin'],'modifiers',dict(talent='improvedSeals',field='weaponPercentBonus',values=vals('paladin','ImprovedSeals'),targets=['sealOfCommandProc']))
# Seal selection generates alternatives without changing the quest route or requiring a new window.
models['paladin']['sealChoices']=['sealOfRighteousness','sealOfCommand']
k,rs=attack('paladin','LightsVigil')
for b,ident in zip(rs,[1310914,1311592,1311598]):
 de=next(e for e in D['spells'][str(ident)]['Effects']if e['Type']=='E_SCHOOL_DAMAGE');sk='vigilStrike'+str(b['rank'])
 r=D['spells'][str(b['id'])];b.pop('base',None);b.pop('max',None);b.update(kind='buff',duration=30,pausesMelee=True,grantsBuff=dict(key='lightsVigil',duration=30,charges=1,triggerSpell='holyShock',strikeKey=sk,refundShare=r['Effects'][1].get('BasePoints',0)/100,resetTriggerCooldown=True))
 child=dict(key=sk,id=ident,name="Light's Vigil strike",rank=1,level=1,alwaysKnown=True,passive=True,school='holy',attackType='spell',resource='mana',cost=0,cast=0,gcd=0,base=de.get('BasePoints',0),max=de.get('BasePoints',0),coef=de.get('SPCoef',0),directScaling=dict(base=de.get('BasePoints',0),variance=de.get('Variance',0),perLevel=de.get('PPL',0),start=de.get('SpellLevel',b['level']),cap=de.get('MaxLevel',60)))
 models['paladin']['abilities'][sk]=[child]
append(models['paladin']['search'],'optionalAbilities',dict(key=k,maintainBuff=k))
k,rs=attack('druid','PrimalBite',forms=['bear'],weaponDamage=dict(hand='mainhand',normalized=False,multiplier=1),resetCooldownIfBuff='berserk')
models['druid']['rotationProfiles']['bear']['priority'].insert(0,k)
# Eclipse grants two charges per completed Wrath; a completed Starfire consumes one.
proc('druid','Eclipse','cast',['wrath'],buff='eclipse',duration=row('druid','EclipseTriggered').get('DurationMs',0)/1000,maxStacks=4,stackGain=2)
append(models['druid'],'buffRules',dict(buff='eclipse',consumeOn=['starfire'],castFlatValues=vals('druid','Eclipse',1,1000),talent='eclipse',consumeCharges=True,consumeStacks=True,autoPriority=False))
proc('druid','NaturesGrace','crit',['wrath','starfire','moonfire','insectSwarm'],buff='naturesGrace',duration=3,buffCastHaste=.1,buffGCDFactor=.9,buffGCDSpells=['wrath','starfire','moonfire','insectSwarm'])
# Vengeance stacks from any direct crit, including seal procs.
proc('paladin','Vengeance','crit',buff='vengeance',duration=30,maxStacks=3,buffDamagePerStackValues=vals('paladin','Vengeance'),buffDamageSchools=['holy','physical'])
proc('warrior','Enrage','incomingHit',buff='enrage',duration=12,chanceValues=[row('warrior','Enrage').get('ProcChance',0)/100]*len(vals('warrior','Enrage')),buffDamagePerStackValues=vals('warrior','Enrage'),buffDamageSchools=['physical'])
k,rs=attack('warrior','SpearingStrike',forms=['battle'],weaponDamage=dict(hand='mainhand',normalized=True,multiplier=row('warrior','SpearingStrike')['Effects'][1].get('BasePoints',0)/100),mobDamageBonus=dict(types=['giant','dragonkin'],multiplier=1+row('warrior','SpearingStrike')['Effects'][2].get('BasePoints',0)))
append(models['warrior']['search'],'optionalAbilities',dict(key=k))
k,b=buff('warrior','BerserkerRage',duration=10,forms=['berserker'],resource='rage');b.pop('requiredTalent',None);b['completeResource']=dict(resource='rage',talent='improvedBerserkerRage',values=vals('warrior','ImprovedBerserkerRage',0,10))
support('warrior','ImprovedBerserkerRage')
k,b=buff('druid','ShiftingPower',duration=.01,forms=['cat']);b['completeResource']=dict(resource='energy',amount=next(e.get('BasePoints',0)for e in row('druid','ShiftingPower')['Effects']if e['Type']=='E_ENERGIZE'),itemBonuses={'8345':20});b['maxResourceFraction']=.5
# These have no damage contribution in a fixed-form single-target fight with no incoming attacks.
for c,names in {'paladin':['Illumination','IronCreed','Reckoning','ShieldSpecialization','HolyShield'],'warrior':['ImprovedTacticalMastery','Vanguard','ImprovedShieldBash','ShieldSpecialization','MasterOfDefense','SweepingStrikes','ConcussionBlow'],'druid':['NaturalReaction','MoonkinForm','LeaderOfThePack'],'hunter':['TrueshotAura']}.items():
 for n in names:
  support(c,n,'Captured static buff or no effect in fixed-form, single-target damage-only encounters. Incoming avoidance/healing/form changes are excluded.')
  append(models[c],'encounterUnsupportedTalents',n[0].lower()+n[1:])
mod('rogue','FlawlessExecution','cost',['eviscerate'],scale=1)
k,rs=attack('rogue','GhostlyStrike',weaponDamage=dict(hand='mainhand',normalized=False,multiplier=1.25),weaponMultipliersBySubclass={'15':1.8})
append(models['rogue']['search'],'optionalAbilities',dict(key=k))
support('rogue','Riposte','Requires a parried incoming attack; has no effect without incoming attacks.')
append(models['rogue'],'encounterUnsupportedTalents','riposte')
# Preparation resets every class cooldown. The optimizer can place it after active cooldowns.
k,b=buff('rogue','Preparation',duration=.01,resource='energy');b['resetClassCooldowns']=True;b['requiresCooldownKeys']=['adrenalineRush','bladeFlurry','coldBlood']
# No stealth model is inferred from ordinary weapon attacks: opener-only talents remain explicit guards.
mod('enhancement','ShamanisticFocus','cost',['earthShock','flameShock','frostShock','lightningShield'],op='multiply')
proc('enhancement','ElementalDevastation','crit',sourceAttackTypes=['spell'],buff='elementalDevastation',duration=10,buffCritPerStackValues=vals('enhancement','ElementalDevastation'),damageAttackTypes=['melee'])
proc('enhancement','ImprovedStormstrike','cast',['stormstrike'],chanceValues=vals('enhancement','ImprovedStormstrike'),buff='improvedStormstrike',duration=row('enhancement','ImprovedStormstrikeTriggered').get('DurationMs',0)/1000,buffCastingRegen=row('enhancement','ImprovedStormstrikeTriggered')['Effects'][0].get('BasePoints',0)/100)
append(models['enhancement'],'encounterUnsupportedTalents','improvedStormstrike')
support('enhancement','ElementalWeapons')
models['enhancement']['windfuryAPValues']=vals('enhancement','ElementalWeapons',2)
for c,n,critTypes,armorTypes,extraTypes in [('warrior','Weaponmaster',[0,1,6],[4,5,10],[7,8]),('rogue','HackAndSlash',[15,13],[4],[0,7])]:
 k=support(c,n);append(models[c],'weaponTalentRules',dict(talent=k,critTypes=critTypes,critValues=vals(c,n),armorTypes=armorTypes,armorValues=vals(c,n,1),armorMainhandOnly=c=='warrior'))
 append(models[c],'genericProcs',dict(talent=k,key=k,chanceValues=vals(c,n,2),weaponSubclasses=extraTypes,meleeOnly=True,extraAttacks=1,extraMainhand=True,whiteExtra=True,icd=.2 if c=='rogue'else 0))
k,rs=attack('warrior','Overpower',required=False,forms=['battle'],weaponDamage=dict(hand='mainhand',normalized=True,multiplier=1),noActiveDefense=True,requiresBuff='overpowerReady',consumeBuff='overpowerReady')
append(models['warrior']['search'],'optionalAbilities',dict(key=k,requiresBuff='overpowerReady'))
append(models['warrior'],'procs',dict(key='overpowerReady',trigger='targetDodge',chanceValues=[1],constant=1,buff='overpowerReady',duration=5))
mod('warrior','ImprovedOverpower','physicalCritBonus',['overpower'])
proc('warrior','Bloodthrill','hit',chanceValues=vals('warrior','Bloodthrill'),sourceAttackTypes=['melee'],sourceHand='mainhand',requiresAura='rend',buff='overpowerReady',duration=6)
proc('paladin','Vindication','hit',sourceAttackTypes=['melee'],buff='vindication',duration=row('paladin','VindicationTriggered').get('DurationMs',0)/1000,buffAPMultiplierValues=vals('paladin','Vindication'))
k,b=buff('hunter','Intimidation',actorCritBonus=1,consumeOnActorHit=True);b['requiresPet']=True
# Keep Intimidation optional: source finds the GCD/base-mana cost can outweigh its single crit.
models['hunter']['cooldownAbilities'].remove(k);append(models['hunter']['search'],'optionalAbilities',dict(key=k))
support('hunter','Frenzy');models['hunter']['unsupportedPetTalents']={};models['hunter']['petFrenzy']=dict(chanceValues=vals('hunter','Frenzy'),duration=8,attackHaste=.3)
k,rs=attack('hunter','MongooseBite',required=False,requiresMeleeRange=True,requiresBuff='defensiveState',consumeBuff='defensiveState',weaponDamage=dict(hand='mainhand',normalized=True,multiplier=1),ignoreHaste=True)
for b in rs:b['damageDot']=dict(key='laceratingStrikes',talent='laceratingStrikes',fraction=.4,duration=21,tickEvery=3,periodicCrit=True)
append(models['hunter']['search'],'optionalAbilities',dict(key=k,requiresBuff='defensiveState'))
proc('hunter','ExposePrey','hit',sourceAttackTypes=['melee','ranged'],encounterFlag='huntersMark',chanceValues=vals('hunter','ExposePrey'),buff='defensiveState',duration=10)
support('hunter','LaceratingStrikes')
k,rs=attack('hunter','SummonHawk',attackType='melee',apType='ranged',apCoef=.05,ignoreHaste=True,alwaysHit=True)
for b in rs:
 b['cast']=0;b['temporaryAttacker']=dict(key='summonHawk',maxSlots=D['spells'][str(b['id'])]['Effects'][2].get('BasePoints',2),baseFraction=.35,duration=18,every=2.5,realRangedHaste=True)
append(models['hunter']['search'],'optionalAbilities',dict(key=k))
k,rs=attack('rogue','Ambush',required=False,requiresStealthOrBuff='cutthroat',breakStealth=True,consumeBuff='cutthroat',behindRequired=True,weaponSubclasses=[15],weaponDamage=dict(hand='mainhand',normalized=True,multiplier=2.5),noActiveDefense=True)
append(models['rogue']['search'],'optionalAbilities',dict(key=k,requiresBuffOrStealth='cutthroat'))
proc('rogue','Cutthroat','hit',['backstab'],chanceValues=vals('rogue','Cutthroat'),buff='cutthroat',duration=10)
proc('rogue','Initiative','hit',['ambush','garrote'],chanceValues=vals('rogue','Initiative'),comboGain=1)
k,rs=attack('rogue','Garrote',required=False,requiresStealth=True,breakStealth=True,behindUnlessTalent='dirtyDeeds',noActiveDefense=True,bleed=True,tickAPCoef=.03,comboGain=1)
for b in rs:b.pop('base',None);b.pop('max',None)
append(models['rogue']['search'],'optionalAbilities',dict(key=k))
mod('rogue','ImprovedAmbush','physicalCritBonus',['ambush'])
mod('rogue','DirtyDeeds','cost',['ambush','garrote'],scale=1)
k,b=buff('rogue','Premeditation',duration=.01,resource='energy');b['requiresStealth']=True;b['completeResource']=dict(resource='combo',amount=2)
k,b=buff('rogue','Vanish',duration=1e9,resource='energy');b.pop('requiredTalent',None);b['grantsBuff']['key']='stealth';b['grantsBuff']['pausesOwnerAutos']=True;b['requiresCooldownKeys']=['ambush'];models['rogue']['cooldownAbilities'].remove(k)
append(models['rogue']['search'],'optionalAbilities',dict(key=k))
for key,rs in models['rogue']['abilities'].items():
 if key in ['sinisterStrike','backstab','mutilate','hemorrhage','ghostlyStrike','eviscerate','rupture']: 
  for b in rs:b['breakStealth']=True
for rule in models['rogue']['modifiers']:
 if rule.get('talent')in ['opportunity','lethality']:rule['targets'].append('ambush')
k,rs=attack('rogue','ExposeArmor',required=False,spendCombo=True,minCombo=1,grantsDebuff=dict(key='exposeArmor',duration=30,charges=1e9,armorGroup='major',armorPerCombo=450))
for b in rs:
 b.pop('base',None);b.pop('max',None);b['grantsDebuff']['armorPerCombo']=abs(D['spells'][str(b['id'])]['Effects'][0].get('PointsPerResource',0));b['fullComboRefund']=dict(talent='improvedExposeArmor',values=vals('rogue','ImprovedExposeArmor',1,1))
append(models['rogue']['search'],'optionalAbilities',dict(key=k,minCombo=5,maintainDebuff='exposeArmor'))
mod('rogue','ImprovedExposeArmor','cost',['exposeArmor'],scale=1)

# Scope-only exclusions cannot be used to silently certify an incoming-damage simulation.
for c,names in {'priest':['Martyrdom'],'hunter':['ImprovedAspectOfTheMonkey'],'druid':['FeralCharge','WildGrowth'],'paladin':['VoiceOfTruth']}.items():
 for n in names:append(models[c],'encounterUnsupportedTalents',n[0].lower()+n[1:])

for c,m in models.items():
 m['revision']=str(m.get('revision','reference'))+'-expanded-1.11.0'
 # A single active talent is gated by the actual talent tier and learned spell, not the level
 # used by the DBC damage effect (several Forever talent rows state SpellLevel 60).
 cls='shaman'if c=='enhancement'else c
 trees=json.loads((DEV/'talent_trees'/f'{cls}.json').read_text())
 levels={t['fieldName']:10+5*t['location']['rowIdx']for tree in trees for t in tree['talents']}
 for rs in m.get('abilities',{}).values():
  if len(rs)==1 and rs[0].get('requiredTalent')in levels:rs[0]['level']=levels[rs[0]['requiredTalent']]
 path=ROOT/'Classes'/('shaman_melee.lua'if c=='enhancement'else c+'.lua')
 if c=='enhancement':
  write_model(path,'-- Declarative Enhancement extension; all scoring uses CombatEngine.\nFUSLiveData.shaman.specs={"elemental","enhancement","restoration"}\nFUSLiveData.shaman.combatModes={enhancement='+lua(m)+'}\n');continue
 write_model(path,'-- Source-backed declarative class model; shared engine performs all scoring.\nFUSLiveData=FUSLiveData or {}\nFUSLiveData['+lua(c)+']='+lua(m)+'\n')
(DEV/'implemented_rules.json').write_text(json.dumps(changes,indent=2))
report=json.loads((DEV/'module_coverage.json').read_text())
for c,m in models.items():
 if c in report:
  report[c]['guardedTalents']=m.get('unsupportedTalents',{})
  report[c]['abilityFamilies']=len(m.get('abilities',{}))
  report[c]['ranks']=sum(len(rs)for rs in m.get('abilities',{}).values())
  report[c]['encounterExcludedTalents']=m.get('encounterUnsupportedTalents',[])
(DEV/'module_coverage.json').write_text(json.dumps(report,indent=2))
print('Extended',len(changes),'source-backed rules/scopes')
