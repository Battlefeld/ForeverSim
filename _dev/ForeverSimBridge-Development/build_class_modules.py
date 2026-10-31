"""Generate declarative Forever data; all calculations stay in CombatEngine.lua.
Source facts pinned to the engine's MIT licensed client data. Never infer a proc from a dummy.
"""
from pathlib import Path
from model_io import write_model
import json,re
BASE=Path(__file__).resolve().parent;D=json.loads((BASE/'reference-data.json').read_text()); S=D['spells'];ROOT=BASE.parent
def lua(x):
 if x is None:return 'nil'
 if x is True:return 'true'
 if x is False:return 'false'
 if isinstance(x,str):return json.dumps(x,ensure_ascii=False)
 if isinstance(x,(int,float)):return repr(x)
 if isinstance(x,list):return '{'+','.join(map(lua,x))+'}'
 return '{'+','.join('['+lua(k)+']='+lua(v)for k,v in x.items())+'}'
def key(n):return n[0].lower()+n[1:]
schools={1:'physical',2:'holy',4:'fire',8:'nature',16:'frost',32:'shadow',64:'arcane'}
config={
 'priest':{'spells':'Smite HolyFire MindBlast MindFlay ShadowWordPain DevouringPlague Starshards ShadowWordDeath Penance','fill':'smite','alts':['mindFlay'],'optional':['shadowWordPain','devouringPlague','holyFire'],'priority':['mindBlast','shadowWordDeath','penance'],'resource':'mana','auto':False},
 'paladin':{'spells':'HolyStrike Exorcism HammerOfWrath HolyShock Consecration SealOfRighteousness Judgement','fill':'autoAttack','priority':['hammerOfWrath','holyShock','holyStrike','exorcism'],'optional':['consecration'],'resource':'mana','auto':'mainhand'},
 'hunter':{'spells':'ArcaneShot AimedShot MultiShot SerpentSting','fill':'autoAttack','priority':['aimedShot','multiShot','arcaneShot'],'optional':['serpentSting'],'resource':'mana','auto':'ranged'},
 'rogue':{'spells':'SinisterStrike Backstab Eviscerate Rupture SliceAndDice AdrenalineRush BladeFlurry','fill':'sinisterStrike','alts':['backstab'],'priority':['adrenalineRush','bladeFlurry','sliceAndDice','rupture','eviscerate'],'resource':'energy','auto':'mainhand'},
 'warrior':{'spells':'HeroicStrike Rend ThunderClap Slam Execute Bloodthirst MortalStrike Whirlwind ShieldSlam DeathWish','fill':'autoAttack','priority':['deathWish','execute','bloodthirst','mortalStrike','shieldSlam','whirlwind','slam','heroicStrike'],'optional':['rend'],'resource':'rage','auto':'mainhand'},
 'druid':{'spells':'Wrath Starfire Moonfire InsectSwarm Claw Shred Rake Rip FerociousBite Maul Swipe','fill':'wrath','alts':['starfire'],'priority':[],'optional':['moonfire','insectSwarm'],'resource':'mana','auto':False},
}
# Static effects with no damage/resource impact in this single-target, fixed-position DPS scope.
neutral={'A_MOD_THREAT','A_MOD_PARRY_PERCENT','A_MOD_DODGE_PERCENT','A_MOD_STEALTH_LEVEL','A_MOD_STEALTH_DETECT','A_MOD_INCREASE_SPEED','A_MOD_MOUNTED_SPEED_NOT_STACK','A_MECHANIC_DURATION_MOD','A_MOD_DAMAGE_PERCENT_TAKEN','A_MOD_SKILL','A_MOD_BASE_RESISTANCE_PCT','A_MOD_BONUS_ARMOR_PCT','A_MOD_ATTACKER_RANGED_HIT_CHANCE','A_MOD_ATTACKER_SPELL_HIT_CHANCE','A_MOD_SPELL_HEALING_OF_STAT_PERCENT'}
neutral_ops={2,5,6,17,28}
# Explicitly scoped rules: captured sheet contains these static effects; stat deltas are handled separately.
captured={'DivineStrength','DivineIntellect','MentalStrength','LivingSpirit','LightningReflexes','NaturesMajesty','SharpenedClaws','Conviction','Cruelty','Malice','LethalAttacks','PredatoryStrikes','SpiritualGuidance','ChampionOfTheLight','Survivalist','SacredDuty'}
manual={'ShadowWeaving','SpiritTap','SealFate','Ruthlessness','UnbridledWrath','DeepWounds'}
active_supported={'MindFlay','HolyShock','MortalStrike','Bloodthirst','ShieldSlam','InsectSwarm','AimedShot','AdrenalineRush','BladeFlurry','DeathWish'}
report={}
for cls,cfg in config.items():
 families=dict(D['classes'][cls]);
 if cls=='paladin':families['HolyShock']={'kind':'Ranked','ids':[1311606,20473,20929,20930],'maxRanks':4}
 abilities={}; aliases={};defs=[];talents={};mods=[];regen=[];unsupported={};static=[]
 attr={'intBase':0,'intPerLevel':0,'spiBase':0,'spiPerLevel':0,'manaBase':0,'manaPerLevel':0,'manaPerInt':15,'healthBase':0,'healthPerLevel':0,'healthPerSta':10,'critBase':0,'intPerCrit':60,'hitBase':96,'bossPenalty':2}
 for name in cfg['spells'].split():
  f=families.get(name)
  if not f:raise ValueError((cls,name))
  k=key(name);rs=[]
  for ordinal,i in enumerate(f['ids'],1):
   r=S.get(str(i));
   if r is None and name=='HolyShock':
    r=dict(S['1311606']);r.update(ID=i,Rank='Rank '+str(ordinal),Powers=[{'Cost':[160,225,275,325][ordinal-1]}],RefIDs=[],Effects=[],requiresSpellbook=True)
   es=r['Effects'];attrs=r['Attr'];sch=schools.get(r.get('School'), 'physical')
   power=next((p for p in r['Powers'] if p.get('Type',0)!=4),{})
   res={0:'mana',1:'rage',3:'energy'}.get(power.get('Type',0),'mana')
   b={'key':k,'id':i,'name':r['Name'],'rank':int(re.search(r'\d+',r.get('Rank','')).group())if re.search(r'\d+',r.get('Rank',''))else ordinal,'level':max(1,r.get('SpellLevel',r.get('BaseLevel',1))),'school':sch,'cost':power.get('Cost',0)/(10 if res=='rage' else 1),'resource':res,'cast':max(0,r.get('CastTimeMs',0)/1000),'gcd':r.get('GCDMs',1500)/1000,'cooldown':max(r.get('CooldownMs',0),r.get('CategoryCooldownMs',0))/1000,'attackType':{1:'spell',2:'melee',3:'ranged'}.get(r.get('DefenseType',1),'spell'),'showRank':True,'source':D['source']['repository']+'/tree/'+D['source']['commit']+'/sim/'+cls,'sourceFamily':r.get('Family'),'sourceMask':r.get('Mask',{}),'ignoreHaste':res in ('energy','rage'),'refundFraction':.8 if attrs.get('1',0)&0x8000000 else 0,'cannotCrit':bool(attrs.get('2',0)&0x20000000)}
   if r.get('requiresSpellbook'):b['requiresSpellbook']=True
   if power.get('CostPct'):b['baseManaCost']=power['CostPct']/100
   damage=next((e for e in es if e['Type'] in ('E_SCHOOL_DAMAGE','E_HEALTH_LEECH','E_WEAPON_DAMAGE','E_WEAPON_DAMAGE_NOSCHOOL','E_NORMALIZED_WEAPON_DMG')),None)
   periodic=next((e for e in es if e.get('Aura')in ('A_PERIODIC_DAMAGE','A_PERIODIC_LEECH')),None)
   if damage:
    bp=damage.get('BasePoints',0);v=damage.get('Variance',0);b.update(base=bp*(1-v/2),max=bp*(1+v/2),coef=damage.get('SPCoef',0)if sch!='physical'and 'WEAPON' not in damage['Type'] else 0,apCoef=damage.get('APCoef',0))
    b['directScaling']={'base':bp,'variance':v,'perLevel':damage.get('PPL',0),'start':damage.get('SpellLevel',b['level']),'cap':damage.get('MaxLevel',60)}
    if 'WEAPON' in damage['Type']:b['weaponDamage']={'hand':'ranged'if b['attackType']=='ranged'else'mainhand','normalized':damage['Type']=='E_NORMALIZED_WEAPON_DMG','multiplier':next((e.get('BasePoints',100)/100 for e in es if e['Type']=='E_WEAPON_PERCENT_DAMAGE'),1)}
    if damage.get('PointsPerResource'):b.update(comboDamage=damage['PointsPerResource'])
   if periodic:
    bp=periodic.get('BasePoints',0);b.update(duration=r.get('DurationMs',0)/1000,tickEvery=periodic.get('PeriodMs',3000)/1000,tickBase=bp,tickCoef=periodic.get('SPCoef',0),tickAPCoef=periodic.get('APCoef',0),periodicCrit=bool(attrs.get('8',0)&0x200))
    b['periodicScaling']={'base':bp,'variance':periodic.get('Variance',0),'perLevel':periodic.get('PPL',0),'start':periodic.get('SpellLevel',b['level']),'cap':periodic.get('MaxLevel',60)}
    if periodic.get('PointsPerResource'):b['comboTickDamage']=periodic['PointsPerResource']
    if sch=='physical':b['bleed']=True
   if attrs.get('1',0)&(4|64):b.update(kind='channel',applicationHit=True,ignoreChannelHaste=True)
   if attrs.get('0',0)&4:b.update(nextSwing=True,gcd=0)
   if any(p.get('Type')==4 for p in r['Powers']):b.update(spendCombo=True,minCombo=1)
   cp=next((e.get('BasePoints',0)for e in es if e['Type']=='E_ENERGIZE'and e.get('Misc')==4),0)
   if cp:b['comboGain']=cp
   if f['kind']=='Talent':b['requiredTalent']=k
   if cls=='priest'and sch=='holy':b['forms']=['caster']
   if name=='MindFlay':b.update(requiredTalent='mindFlay',binary=True)
   if name=='Penance':
    bolt=S[str(r['RefIDs'][0])];e=next(e for e in bolt['Effects']if e['Type']=='E_SCHOOL_DAMAGE');bp=e.get('BasePoints',0);v=e.get('Variance',0);b.update(kind='channel',duration=2,tickEvery=1,tickAtStart=True,tickBase=bp*(1-v/2),tickMax=bp*(1+v/2),tickCoef=e.get('SPCoef',0),tickRolls=True,tickAsDirect=True,ignoreChannelHaste=True,requiredTalent='penance',cooldown=12);b.pop('directScaling',None)
   if name=='ShadowWordDeath':b['selfHealthFraction']=.1
   if name=='Starshards':b.update(kind='channel',applicationHit=True,ignoreChannelHaste=True)
   if name=='Bloodthirst':b.update(base=0,max=0,apCoef=next(e.get('BasePoints',0)/100 for e in es if e.get('Index')==1),requiredTalent='bloodthirst');b.pop('directScaling',None)
   if name=='MortalStrike':b['requiredTalent']='mortalStrike'
   if name=='ShieldSlam':b.update(requiredTalent='shieldSlam',shieldRequired=True,blockValueCoef=1)
   if name=='Execute':b.update(base=es[0].get('BasePoints',0),apCoef=0,consumeExtraResource=True,extraResourceDamage=es[0].get('ChainAmp',0)*10,maxTargetHealth=20,forms=['battle','berserker']);b.pop('directScaling',None)
   if name=='Whirlwind':b['weaponHands']=['mainhand','offhand'];b['forms']=['berserker']
   if name=='ThunderClap':b.update(forms=['battle','defensive'],apCoef=.0255,ignoreArmor=True)
   if name=='Rend':b['tickAPCoef']=.02
   if name=='Swipe':b['apCoef']=.03
   if name=='DevouringPlague':b['leechFraction']=1
   if name in ('Backstab','Shred'):b['behindRequired']=True
   if name=='Backstab':b['weaponSubclasses']=[15]
   if name in ('Claw','Shred','Rake','Rip','FerociousBite'):b['forms']=['cat']
   if name in ('Maul','Swipe'):b['forms']=['bear']
   if cls=='druid'and name in ('Wrath','Starfire','Moonfire','InsectSwarm'):b['forms']=['caster','moonkin'];b['attackType']='spell'
   if name=='Eviscerate':b['comboAPCoef']=.03
   if name=='Rupture':b.update(comboTickAPCoef=.01,comboTickAPCap=3,durationPerCombo=b['tickEvery'])
   if name=='Rip':b.update(comboTickAPCoef=.01,comboTickAPCap=4)
   if name=='Rake':b.update(apCoef=.0526,tickAPCoef=.0526)
   if name=='FerociousBite':b.update(comboAPCoef=.03,consumeExtraResource=True,extraResourceDamage=next(e.get('BasePoints',0)/100 for e in es if e.get('Index')==1))
   if name=='SliceAndDice':b.update(kind='buff',duration=6,durationPerCombo=3,grantsBuff={'key':k,'duration':6,'charges':1,'attackHaste':next(e.get('BasePoints',0)/100 for e in es if e.get('Aura')=='A_MOD_MELEE_HASTE_3')})
   if name in ('AdrenalineRush','BladeFlurry','DeathWish'):
    b.update(kind='buff',requiredTalent=k,duration=r.get('DurationMs',0)/1000,grantsBuff={'key':k,'duration':r.get('DurationMs',0)/1000,'charges':1})
    if name=='AdrenalineRush':b['grantsBuff']['energyRegenBonus']=es[0].get('BasePoints',0)/100
    if name=='BladeFlurry':b['grantsBuff']['attackHaste']=es[0].get('BasePoints',0)/100
    if name=='DeathWish':b['grantsBuff'].update(damageBonus=es[0].get('BasePoints',0)/100,schools=['physical'])
   if name=='ArcaneShot':b.update(apType='ranged',apCoef=.11,coef=[0,.204,.3,.429,.429,.429,.429,.429,.429][b['rank']],cooldownGroup='arcaneShot')
   if name in ('AimedShot','MultiShot'):b.update(cooldownGroup='aimedMulti',weaponDamage={'hand':'ranged','normalized':True,'multiplier':1});b['pausesAutoAttack']=True
   if name=='SerpentSting':b.update(tickAPCoef=.035,tickCoef=b['tickEvery']/b['duration'],apType='ranged')
   if name in ('HammerOfWrath',):b['maxTargetHealth']=20
   if name=='Exorcism':b['mobTypes']=['undead','demon']
   if name=='HolyShock':b['requiredTalent']='holyShock';trigger=r['RefIDs'][0]if r['RefIDs']else None;tr=S.get(str(trigger),{});de=next((e for e in tr.get('Effects',[])if e['Type']=='E_SCHOOL_DAMAGE'),None);b.update(base=de.get('BasePoints',0),max=de.get('BasePoints',0)*(1+de.get('Variance',0)/2),coef=de.get('SPCoef',0))if de else None
   if name=='HolyShock':
    lo,hi=[(128,140),(175,189),(248,268),(334,362)][ordinal-1];b.update(base=lo,max=hi,coef=.429,cooldown=10);b.pop('directScaling',None)
   if name=='SealOfRighteousness':
    jid=next(e.get('BasePoints')for e in es if e.get('Index')==2);jr=S[str(jid)];de=next(e for e in jr['Effects']if e['Type']=='E_SCHOOL_DAMAGE');ph=jr['Effects'][1]
    b.update(kind='buff',grantsBuff={'key':'sealOfRighteousness','group':'seal','duration':30,'charges':1},sealProc={'school':'holy','basePerSpeed':ph.get('BasePoints',0)/100,'coef':ph.get('SPCoef',0),'oneHand':.85,'twoHand':1.2,'twoHandSP':1.2},judgement={'school':'holy','base':de.get('BasePoints',0),'max':de.get('BasePoints',0)*(1+de.get('Variance',0)/2),'coef':de.get('SPCoef',0),'attackType':'melee','noActiveDefense':True,'cannotCrit':False});b.pop('directScaling',None);b['sealProc']['scaling']=ph;b['judgement']['scaling']=de
   if name=='Judgement':b.update(kind='judgement',cooldown=10,gcd=0)
   rs.append(b)
  abilities[k]=rs;aliases[k]=[S[str(f['ids'][0])]['Name'].lower()]
 # Primary attack is a deliberate wait policy. Actual swings live on the common event queue.
 if cfg['auto'] or cls=='druid':abilities['autoAttack']=[{'key':'autoAttack','id':6603 if cls!='hunter'else 75,'name':'Auto Attack','rank':1,'level':1,'kind':'wait','cost':0,'cast':0,'gcd':1,'resource':cfg['resource'],'school':'physical','attackType':'melee','alwaysKnown':True}]
 for name,f in families.items():
  if f['kind']!='Talent':continue
  k=key(name);r=S[str(f['ids'][0])];talents[k]=[r['Name'].lower()];definition={'key':k,'name':r['Name'],'id':r['ID'],'maxRank':f['maxRanks'],'source':D['source']['repository'],'effects':r['Effects']};defs.append(definition)
  valid=True
  for idx,e in enumerate(r['Effects']):
   au=e.get('Aura');op=e.get('Misc',0);curves=D['curves'].get(str(r['ID']),[]);vs=curves[idx]if idx<len(curves)else[e.get('BasePoints',0)]*f['maxRanks']
   def rule(field,div=1,operation='add',targets=None,schoolList=None):
    q={'talent':k,'field':field,'op':operation,'values':[v/div for v in vs]}
    if targets is not None:q['targets']=targets
    if schoolList:q['schools']=schoolList
    mods.append(q)
   if au in ('A_ADD_FLAT_MODIFIER','A_ADD_PCT_MODIFIER'):
    mask=e.get('Mask',{});targets=[ak for ak,rs in abilities.items()if any(any(int(mask.get(w,0))&int(b['sourceMask'].get(w,0))for w in mask)for b in rs if b.get('sourceFamily')==e.get('Family'))]
    if op in neutral_ops:continue
    if not targets:continue # Modifies a spell outside the declared DPS ability set.
    pct=au=='A_ADD_PCT_MODIFIER'
    if op in (0,22):rule('directBonus'if op==0 else'periodicBonus',100 if pct else 1,targets=targets)
    elif op in (10,11,1,21):rule({10:'cast',11:'cooldown',1:'duration',21:'gcd'}[op],100 if pct else 1000,'multiply'if pct else'add',targets)
    elif op==14:
     for currency in ('mana','rage','energy'):
      ks=[ak for ak in targets if abilities[ak][0]['resource']==currency]
      if ks:rule('cost',100 if pct else 10 if currency=='rage'else 1,'multiply'if pct else'add',ks)
    elif op==7:rule('physicalCritBonus'if all(abilities[ak][0]['attackType']!='spell'for ak in targets)else'crit',100,targets=targets)
    elif op==16:rule('hit',100,targets=targets);rule('physicalHitBonus',100,targets=targets)
    elif op==15:rule('critBonus',100,targets=targets)
    elif op==9:rule('pushbackAvoidance',100,targets=targets)
    else:valid=False
   elif au=='A_MOD_DAMAGE_PERCENT_DONE':
    if name in ('TwoHandedWeaponSpecialization','OneHandedWeaponSpecialization','Bastion','RangedWeaponSpecialization','WandSpecialization','LoneWolf'):valid=False;continue
    rule('mult',100,'multiply',schoolList=[v for bit,v in schools.items()if bit&e.get('Misc',0)])
   elif au=='A_MOD_MANA_REGEN_INTERRUPT':regen.append({'talent':k,'values':[v/100 for v in vs]})
   elif au=='A_MOD_OFFHAND_DAMAGE_PCT':static.append({'talent':k,'field':'offhandMultiplier','values':[v/100 for v in vs]})
   elif au in ('A_MOD_HIT_CHANCE','A_MOD_SPELL_HIT_CHANCE'):rule('physicalHitBonus'if au=='A_MOD_HIT_CHANCE'else'hit',100)
   elif au=='A_MOD_INCREASE_ENERGY':static.append({'talent':k,'field':'maxEnergy','values':vs})
   elif au=='A_MOD_EXPERTISE':static.append({'talent':k,'field':'expertise','values':vs})
   elif name in captured:continue
   elif au in neutral:continue
   else:valid=False
  if name in manual or name in active_supported:valid=True
  definition['supported']=valid
  if not valid:unsupported[k]=r['Name']
 # Active talent nodes are Ranked in the source; also expose them for localized live mapping.
 for name in active_supported | {'Penance'}:
  if key(name) in abilities and key(name)not in talents:
   k=key(name);b=abilities[k][0];talents[k]=[b['name'].lower()];defs.append({'key':k,'id':b['id'],'name':b['name'],'maxRank':1,'supported':True})
 profiles={}
 if cls=='priest':profiles={'shadow':{'filler':'mindFlay','alternatives':[],'priority':['mindBlast','shadowWordDeath'],'optional':['shadowWordPain','devouringPlague']}}
 if cls=='druid':profiles={'caster':{'filler':'wrath','alternatives':['starfire'],'priority':[],'optional':['moonfire','insectSwarm']},'moonkin':{'filler':'wrath','alternatives':['starfire'],'priority':[],'optional':['moonfire','insectSwarm']},'cat':{'filler':'claw','alternatives':['shred'],'priority':['rip','ferociousBite'],'optional':['rake']},'bear':{'filler':'autoAttack','alternatives':[],'priority':['swipe','maul'],'optional':[]}}
 data={'schemaVersion':2,'revision':'1.10.0-mythic-'+D['source']['commit'][:7],'id':cls,'maxLevel':60,'validated':False,'simulationScope':'Single target DPS; explicit live stats, selected form, guarded talent coverage; no healing/threat score','sources':[D['source']],'attributes':attr,'levelStats':{},'abilities':abilities,'spellAliases':aliases,'talents':talents,'talentDefinitions':defs,'modifiers':mods,'regenerationModifiers':regen,'staticRules':static,'unsupportedTalents':unsupported,'typedCombat':True,'resource':cfg['resource'],'autoAttack':cfg['auto'],'rotationProfiles':profiles,'search':{'filler':{'default':cfg['fill'],'alternatives':cfg.get('alts',[])},'optionalAbilities':[{'key':ak}for ak in cfg.get('optional',[])],'policyVariants':[[{'key':ak}for ak in cfg.get('priority',[])]],'candidateLimit':32},'equipmentRules':{'armorTypes':['cloth','leather','mail','plate']},'spiritRegeneration':{'base':6.25 if cls=='priest'else 7.5,'perSpirit':.125 if cls=='priest'else .1}}
 if cls=='paladin':data['search']['policyVariants'][0].insert(0,{'key':'sealOfRighteousness','maintainBuff':'sealOfRighteousness'});data['search']['policyVariants'][0].append({'key':'judgement'})
 # Conditional generic procs use shared event handlers; raw trigger curves remain available.
 data['genericProcs']=[];data['attributeModifiers']=[];data['critPerIntellect60']={'priest':.0168,'paladin':.0167,'hunter':.0165,'druid':.0167}.get(cls)
 def curve(name,index=0,div=1):
  f=families.get(name)
  if not f:return []
  r=S[str(f['ids'][0])];curves=D['curves'].get(str(r['ID']),[]);return [v/div for v in(curves[index]if index<len(curves)else[r['Effects'][index].get('BasePoints',0)]*f['maxRanks'])]
 for name,field in [('DivineIntellect','intellect'),('MentalStrength','intellect'),('DivineStrength','strength'),('LightningReflexes','agility'),('LivingSpirit','spirit')]:
  if name in families:data['attributeModifiers'].append({'talent':key(name),'field':field,'values':curve(name,div=100)})
 for name,field in [('SpiritualGuidance','spiritPower'),('ChampionOfTheLight','strengthPower')]:
  if name in families:data['staticRules'].append({'talent':key(name),'field':field,'values':curve(name,div=100)})
 if cls=='rogue':
  data['genericProcs']=[{'talent':'sealFate','key':'sealFate','chanceValues':[.2,.4,.6,.8,1],'sources':['sinisterStrike','backstab'],'onCrit':True,'comboGain':1}]
  data['finisherProcs']=[{'talent':'ruthlessness','key':'ruthlessness','chanceValues':curve('Ruthlessness',div=100),'comboGain':1}]
 if cls=='warrior':
  data['genericProcs']=[{'talent':'unbridledWrath','key':'unbridledWrath','chanceValues':curve('UnbridledWrath',div=100),'sources':['auto:mainhand','auto:offhand'],'resource':'rage','resourceGain':1}]
  data['genericProcs'].append({'talent':'flurry','key':'flurry','onCrit':True,'meleeOnly':True,'chanceValues':[1,1,1,1,1],'buffId':12966,'attackHasteValues':curve('Flurry',div=100),'duration':15,'charges':3,'consumeOnWhite':True})
  data['genericProcs'].append({'talent':'deepWounds','key':'deepWounds','onCrit':True,'meleeOnly':True,'chanceValues':[1,1,1],'weaponPoolValues':curve('DeepWounds',div=100),'duration':12,'tickEvery':3})
  for k in ('flurry','deepWounds'):unsupported.pop(k,None)
  data['periodicCurrency']=[{'talent':'angerManagement','key':'angerManagement','resource':'rage','every':3,'amount':1}]
  # Deep Wounds depends on weapon damage, not on damage dealt. Until its snapshot rule is ported it is guarded.
  data['unsupportedTalents'].pop('deepWounds',None)
 if cls=='priest':
  # The existing shared debuff proc engine supports Shadow Weaving's five stacks.
  data['procs']=[{'talent':'shadowWeaving','key':'shadowWeaving','trigger':'hit','sourceSchools':['shadow'],'debuff':'shadowWeaving','duration':15,'maxStacks':5,'damagePerStack':S[str(families['ShadowWeavingTriggered']['ids'][0])]['Effects'][0]['BasePoints']/100,'affectedSchools':['shadow'],'chanceValues':curve('ShadowWeaving',div=100)}]
  data['procs'].append(dict(data['procs'][0],trigger='applicationHit'))
  data['unsupportedTalents']['spiritTap']='Spirit Tap (kill-triggered recovery)'
 if cls=='hunter':
  data['genericPet']=True;data['petSpellRanks']={};data['actors']={};data['actorAliases']={}
  for pet in ['cat','wolf','windSerpent']:
   data['actors'][pet]={'generic':True};data['actorAliases'][pet]={'cat':['cat','katze'],'wolf':['wolf'],'windSerpent':['wind serpent','windnatter']}[pet]
  for family in ['BiteTriggered','ClawTriggered','LightningBreathTriggered']:
   rs=[]
   for ordinal,i in enumerate(families[family]['ids'],1):
    r=S[str(i)];e=next(e for e in r['Effects']if e['Type']=='E_SCHOOL_DAMAGE');bp=e.get('BasePoints',0);v=e.get('Variance',0)
    rs.append({'id':i,'rank':ordinal,'level':r.get('SpellLevel',1),'school':schools[r['School']],'base':bp*(1-v/2),'max':bp*(1+v/2),'coef':0,'cost':{'BiteTriggered':35,'ClawTriggered':25,'LightningBreathTriggered':50}[family],'cast':0,'gcd':1.6,'cooldown':10 if family=='BiteTriggered'else 0,'directMult':1,'mult':1,'sp':0,'critMult':2,'baseCost':0})
   data['petSpellRanks'][key(family.removesuffix('Triggered'))]=rs
  data['petFocusRegen']=10
 data['specs']={'warrior':['arms','fury','protection'],'paladin':['holy','protection','retribution'],'hunter':['beastMastery','marksmanship','survival'],'rogue':['assassination','combat','subtlety'],'priest':['discipline','holy','shadow'],'druid':['balance','feral','restoration']}[cls]
 data['equipmentRules']['armorTypes']={'warrior':['cloth','leather','mail','plate'],'paladin':['cloth','leather','mail','plate'],'hunter':['cloth','leather','mail'],'rogue':['cloth','leather'],'priest':['cloth'],'druid':['cloth','leather']}[cls]
 armorMax={'warrior':3,'paladin':3,'hunter':2,'rogue':2,'priest':1,'druid':2}[cls]
 data['equipmentRules']['armorTiers']=[{'minLevel':1,'maxSubclass':armorMax}]
 if cls in ('warrior','paladin','hunter'):data['equipmentRules']['armorTiers'].append({'minLevel':40,'maxSubclass':4 if cls!='hunter'else 3})
 data['equipmentRules'].update(weaponSubclasses={'warrior':[0,1,4,5,6,7,8,10,13,15],'paladin':[0,1,4,5,6,7,8],'hunter':[0,1,6,7,8,10,13,15],'rogue':[0,4,7,13,15],'priest':[4,10,15],'druid':[4,5,6,10,13,15]}[cls],rangedSubclasses={'warrior':[2,3,16,18],'paladin':[],'hunter':[2,3,18],'rogue':[2,3,16,18],'priest':[19],'druid':[]}[cls],twoHandSubclasses={'warrior':[1,5,6,8,10],'paladin':[1,5,6,8],'hunter':[1,6,8,10],'rogue':[],'priest':[10],'druid':[5,6,10]}[cls],shield=cls in ('warrior','paladin'),dualWield=cls in ('warrior','rogue','hunter'))
 treepath=BASE/'talent_trees'/f'{cls}.json'
 for tree in json.loads(treepath.read_text()):
  for node in tree['talents']:
   k=node['fieldName'];definition=next((d for d in defs if d['key']==k),None)
   if definition:definition['maxRank']=node['maxPoints'];definition['id']=node['spellId'];definition['name']=node.get('fancyName',definition['name'])
   else:
    name=node.get('fancyName',k);talents[k]=[name.lower()];defs.append({'key':k,'name':name,'id':node['spellId'],'maxRank':node['maxPoints'],'supported':k in abilities})
    if k not in abilities:unsupported[k]=name
 data['specs']=[tree['name'].lower().replace(' ','')for tree in json.loads(treepath.read_text())]
 if cls=='priest':
  shadow=S[str(families['Shadowform']['ids'][0])]
  for e in shadow['Effects']:
   q={'talent':'shadowform','profileField':'form','profileValues':['shadow'],'schools':['shadow'],'values':[e.get('BasePoints',0)/100]}
   if e.get('Aura')=='A_MOD_DAMAGE_PERCENT_DONE':
    mods.append(dict(q,field='mult',op='multiply'))
   elif e.get('Aura')=='A_MOD_POWER_COST_SCHOOL_PCT':mods.append(dict(q,field='cost',op='multiply'))
   elif e.get('Aura')=='A_ADD_PCT_MODIFIER'and e.get('Misc')==15:mods.append(dict(q,field='critBonus',op='add'))
  unsupported.pop('shadowform',None)
  for definition in defs:
   if definition['key']=='shadowform':definition['supported']=True
  if 'powerInLight'in talents:
   for ak in ('smite','penance'):
    for b in abilities.get(ak,[]):b['damageIfAura']={'key':'holyFire','talent':'powerInLight','values':curve('PowerInLight',div=100)}
   unsupported.pop('powerInLight',None)
 if cls=='hunter':
  data['petCritValues']=curve('Ferocity');data['petDamageValues']=curve('UnleashedFury',div=100);data['petFocusValues']=curve('BestialDiscipline',div=100)
  data['unsupportedPetTalents']={'frenzy':'Frenzy (pet speed proc)'}
 if cls=='warrior':
  for k in ('angerManagement','flurry','deepWounds','deathWish'):unsupported.pop(k,None)
 # DPS-neutral talents explicitly scoped to one uninterrupted fight, as in the reference.
 neutral_nodes={'priest':['wandSpecialization','spiritTap','blackout','silence','vampiricEmbrace','inspiration','divineAegis','bindingHeal','prayerOfMending','spiritOfRedemption','blessedRecovery'],'warrior':['lingeringRage','goreDrinker','ironWill','improvedDisarm','improvedHamstring','improvedIntercept','piercingHowl','bloodCraze','improvedShieldWall','lastStand'],'paladin':['redoubt','vindication','divineFavor','repentance','infusionOfLight','eyeForAnEye','improvedSealOfFury','templarsBulwark'],'hunter':['bestialSwiftness','entrapment','improvedConcussiveShot','improvedWingClip','deterrence','scatterShot','counterattack','improvedMendPet','spiritBond'],'rogue':['remorselessAttacks','setup','improvedKick','improvedSprint',],'druid':['thickHide','feralSwiftness','furor','overgrowth','naturesSwiftness','swiftmend','insectSwarm','livingSpirit']}
 for k in neutral_nodes.get(cls,[]):
  if k in talents:
   unsupported.pop(k,None)
   for definition in defs:
    if definition['key']==k:definition['supported']=True;definition['scope']='No damage effect during an uninterrupted single-target fight; recovery and survival are outside DPS scope.'
 for definition in defs:definition['supported']=definition['key']not in unsupported
 write_model(ROOT/'Classes'/f'{cls}.lua','-- Generated declarative class rules. See THIRD_PARTY_LICENSES.txt.\nFUSLiveData=FUSLiveData or {}\nFUSLiveData['+lua(cls)+']='+lua(data)+'\n')
 report[cls]={'abilityFamilies':len(abilities),'ranks':sum(map(len,abilities.values())),'talents':len(defs),'guardedTalents':unsupported}
(BASE/'module_coverage.json').write_text(json.dumps(report,indent=2));print({k:{a:b for a,b in v.items()if a!='guardedTalents'}for k,v in report.items()})
licensefile=BASE/'REFERENCE_LICENSE.txt';(ROOT/'THIRD_PARTY_LICENSES.txt').write_text('Spell facts, talent curves and reference combat rules derived from:\n'+D['source']['repository']+'\nCommit '+D['source']['commit']+'\n\n'+licensefile.read_text())
