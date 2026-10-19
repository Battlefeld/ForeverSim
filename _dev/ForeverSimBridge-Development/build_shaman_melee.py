from pathlib import Path
from model_io import write_model
import json
BASE=Path(__file__).resolve().parent;D=json.loads((BASE/'reference-data.json').read_text());S=D['spells'];F=D['classes']['shaman']
def lua(x):
 if x is True:return 'true'
 if x is False:return 'false'
 if x is None:return 'nil'
 if isinstance(x,str):return json.dumps(x,ensure_ascii=False)
 if isinstance(x,(int,float)):return repr(x)
 if isinstance(x,list):return '{'+','.join(map(lua,x))+'}'
 return '{'+','.join('['+lua(k)+']='+lua(v)for k,v in x.items())+'}'
r=S[str(F['Stormstrike']['ids'][0])]
storm={'key':'stormstrike','id':r['ID'],'name':r['Name'],'level':r['SpellLevel'],'rank':1,'school':'physical','attackType':'melee','resource':'mana','cost':r['Powers'][0]['Cost'],'cast':0,'gcd':1.5,'ignoreHaste':True,'cooldown':8,'requiredTalent':'stormstrike','applicationAttackGate':True,'triggeredWeaponHit':True,'base':0,'max':0,'coef':0,'weaponDamage':{'hand':'mainhand','normalized':False,'multiplier':1},'grantsDebuff':{'key':'stormstrike','duration':12,'charges':1,'damageBonus':.2,'affectedSpells':['lightningBolt','chainLightning','earthShock']}}
enchant={}
for ordinal,i in enumerate(F['WindfuryWeapon']['ids']):
 cast=S[str(i)];trigger=S[str(F['WindfuryWeaponTriggered']['ids'][ordinal])]
 enchant[str(cast['Effects'][0]['Misc'])]={'type':'extraAttacks','chance':.2,'icd':1.5,'extraAttacks':2,'attackPowerScaling':trigger['Effects'][0],'rank':ordinal+1,'source':D['source']}
# Passive Rockbiter is already in the captured weapon damage; there is no additional proc.
for i in F['RockbiterWeapon']['ids']:enchant[str(S[str(i)]['Effects'][0]['Misc'])]={'type':'captured'}
mode={'critPerIntellect60':.0169,'typedCombat':True,'autoAttack':'mainhand','resource':'mana','validated':False,'abilityOverrides':{'stormstrike':[storm],'autoAttack':[{'key':'autoAttack','id':6603,'name':'Auto Attack','level':1,'rank':1,'alwaysKnown':True,'kind':'wait','school':'physical','attackType':'melee','resource':'mana','cost':0,'cast':0,'gcd':1}]},'search':{'filler':{'default':'autoAttack'},'optionalAbilities':[{'key':'flameShock'},{'key':'searingTotem'}],'policyVariants':[[{'key':'stormstrike'},{'key':'earthShock'},{'key':'lightningBolt','requiresBuff':'maelstromWeapon','minBuffStacks':5}]],'candidateLimit':24},'genericProcs':[{'talent':'flurry','key':'flurry','buffId':16257,'onCrit':True,'meleeOnly':True,'chanceValues':[1,1,1,1,1],'attackHasteValues':[v/100 for v in D['curves']['16256'][0]],'duration':15,'charges':3,'consumeOnWhite':True},{'talent':'maelstromWeapon','key':'maelstromWeapon','buffId':408505,'meleeOnly':True,'ppmPerRank':2,'duration':30,'charges':1,'maxStacks':5,'castMultiplierValues':[v/100 for v in D['curves']['408498'][0]],'consumeOn':['lightningBolt']}], 'weaponEnchantRules':enchant,'unsupportedTalents':{'shamanisticFocus':'Shamanistic Focus','elementalDevastation':'Elemental Devastation','improvedStormstrike':'Improved Stormstrike','elementalWeapons':'Elemental Weapons'},'simulationScope':'Enhancement single target DPS; declared proc rules, guarded unmodeled talents/enchantments'}
root=BASE.parent;write_model(root/'Classes/shaman_melee.lua','-- Declarative melee extension; one shared combat engine.\nFUSLiveData.shaman.specs={"elemental","enhancement","restoration"}\nFUSLiveData.shaman.combatModes={enhancement='+lua(mode)+'}\n')
