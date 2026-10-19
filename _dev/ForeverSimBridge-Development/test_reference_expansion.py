"""Source-equation and event-order tests, independent of selected optimizer rotations."""
from pathlib import Path
BASE=Path(__file__).resolve().parent
exec((BASE/'test_universal_modules.py').read_text().split('\nfor c in [')[0])
L.execute('''
function referenceProfile(cls,form,talents)
 local _,_,p=universalFixture(cls,60,form)
 p.talents={{entries={}}};for key,rank in pairs(talents or {})do p.talents[1].entries[#p.talents[1].entries+1]={classKey=key,name=key,rank=rank}end
 p.stats.meleeHitPct=100;p.stats.meleeCritPct=0;p.stats.rangedCritPct=0;p.stats.expertise=100
 for _,school in ipairs({'holy','shadow','nature','arcane','fire','frost'})do p.stats[school..'Crit']=0 end
 p.stats.weapons.mainhand={min=40,max=40,speed=2,normalizedSpeed=1.7,subclass=15,form=form or'caster'}
 p.stats.weapons.offhand={min=30,max=30,speed=1.5,normalizedSpeed=1.7,subclass=15,form=form or'caster'}
 p.bossPlus=0;p.encounter={armor=0,levelDifference=0,baseHitPct=100,damageModel='mean',levelResistance=false}
 return p
end
function referenceRun(cls,p,policies,duration,cp)
 local spec=FUSLive.compile(FUSLiveData[cls],p,FUSLive.combine(p.equipped),{policies=policies},duration or 20,7331)
 spec.autoAttacks={};spec.resources.combo=cp or 0;spec.trace=true
 return FUSLive.run(spec),spec
end
local P=FUSLive
-- 5 points guarantee a 25-energy return after landing; a miss consumes no CP and returns no proc energy.
local p=referenceProfile('rogue',nil,{relentlessStrikes=1})
local r,s=referenceRun('rogue',p,{{key='eviscerate',minCombo=5}},.01,5)
assert(math.abs(r.energyEnd-(100-s.abilities.eviscerate.cost+25))<.001)
s.abilities.eviscerate.attackTable.miss=1;r=P.run(s);assert(r.comboEnd==5)
-- Early Demise adds exactly 30 percentage points at <=20%, never above the threshold.
p=referenceProfile('priest',nil,{earlyDemise=2});local _,s=referenceRun('priest',p,{},1)
assert(s.conditionalModifiers[1].value==.3 and s.conditionalModifiers[1].targetBelow==20)
-- Inner Focus works even when the next spell is unaffordable without the buff.
p=referenceProfile('priest',nil,{innerFocus=1});p.stats.mana=1;p.stats.manaRegen=0
r,s=referenceRun('priest',p,{{key='innerFocus',maintainBuff='innerFocus'},{key='smite'}},5)
assert(r.bySpell.smite and r.bySpell.smite.casts==1);assert(r.manaEnd>=0)
local paid;for _,e in ipairs(r.events)do if e.kind=='start'and e.key=='smite'then paid=e.amount end end;assert(paid==0)
-- PI applies a 20% magic damage bonus; it does not accelerate the cast.
p=referenceProfile('priest',nil,{powerInfusion=1});p.stats.mana=10000
r,s=referenceRun('priest',p,{{key='powerInfusion',maintainBuff='powerInfusion'},{key='smite'}},3)
local first;for _,e in ipairs(r.events)do if e.kind=='damage'and e.key=='smite'then first=e;break end end
assert(first);assert(math.abs(first.amount-(s.abilities.smite.base+s.abilities.smite.coef*s.abilities.smite.sp)*1.2)<1e-8)
-- Captured AP already includes Careful Aim; only compared-item intellect adds AP again.
p=referenceProfile('hunter',nil,{carefulAim=5});p.stats.critPerIntellect=.02
s=P.compile(FUSLiveData.hunter,p,{int=10},{policies={}},1,7331);assert(s.abilities.aimedShot.ap==p.stats.rangedAttackPower+10)
-- Serpent Sting is excluded from Ranged Weapon Specialization.
p=referenceProfile('hunter',nil,{rangedWeaponSpecialization=5});local _,s=referenceRun('hunter',p,{},1)
assert(math.abs(s.abilities.aimedShot.directMult-1.05)<1e-8);assert(s.abilities.serpentSting.periodicMult==1)
-- Eclipse grants 2 stacks, a Starfire removes one; proc timestamps and cast durations are observable.
p=referenceProfile('druid','caster',{eclipse=3});p.stats.mana=10000
r,s=referenceRun('druid',p,{{key='wrath',maxUses=1},{key='starfire'}},12)
local starts={};for _,e in ipairs(r.events)do if e.kind=='start'and e.key=='starfire'then starts[#starts+1]=e.t end end
assert(#starts>=2);assert(math.abs(starts[2]-starts[1]-(s.abilities.starfire.cast-.5))<1e-8)
-- Berserk guarantees builder crits; Bite remains unaffected, and Primal Bite resets only under Berserk.
p=referenceProfile('druid','cat',{berserk=1});r,s=referenceRun('druid',p,{{key='berserk',maintainBuff='berserk'},{key='claw'}},5)
assert(r.bySpell.claw.crits==r.bySpell.claw.hits)
-- Mutilate adds 2 CP once, deals two hand strikes after a single avoidance check.
p=referenceProfile('rogue',nil,{mutilate=1});r,s=referenceRun('rogue',p,{{key='mutilate'}},.01)
assert(r.comboEnd==2);assert(r.bySpell['mutilate:mainhand']and r.bySpell['mutilate:offhand'])
local expected=(67+40+300/14*1.7)*.75+(67+(30+300/14*1.7)*.5)*.75
assert(math.abs(r.total-expected)<1e-8,r.total..' '..expected)
-- A poison proc comes only from its imbued hand and goes through magic hit/crit/resistance.
p=referenceProfile('rogue',nil,{improvedPoisons=5});p.weaponEnchants={mainhand=625,offhand=0}
s=P.compile(FUSLiveData.rogue,p,P.combine({}),{policies={{key='sinisterStrike'}}},30,7331);s.trace=true;r=P.run(s)
assert(r.bySpell.instantPoison and r.bySpell.instantPoison.damage>0)
for _,rule in ipairs(s.genericProcs)do if rule.spellKey then assert(rule.hand=='mainhand')end end
-- Unknown enchant IDs remain blocked instead of silently losing damage.
p.weaponEnchants.mainhand=123456;assert(P.coverage(FUSLiveData.rogue,p):find('123456'))
-- A real weapon replacement has no inherited temporary poison enchant.
p.weaponEnchants.mainhand=625
s=P.compile(FUSLiveData.rogue,p,{weaponItems={mainhand={id=99,weapon={min=40,max=40,speed=2,subclass=15}}}},{policies={}},1,7331)
for _,rule in ipairs(s.genericProcs)do assert(rule.spellKey~='instantPoison')end
''')
print('PASS: reference talent equations, free-cast resource selection, spell-only bonuses, Eclipse stacks, Berserk, Mutilate gating and poison hand/swap rules.')
L.execute('''
local P=FUSLive
local p=referenceProfile('paladin',nil,{consecratedGround=2})
local r,s=referenceRun('paladin',p,{{key='consecration',maxUses=1}},1.01)
local c=s.abilities.consecration
assert(r.bySpell.consecration.ticks==1)
local expected=(c.tickBase+c.tickCoef*c.sp)*c.periodicMult*1.1
assert(math.abs(r.bySpell.consecration.damage-expected)<1e-8)
-- The seal's actual paid cost is the refund basis; rank 3 uses source's 10/9 log correction.
p=referenceProfile('paladin',nil,{sanctifiedJudgement=3})
r,s=referenceRun('paladin',p,{{key='sealOfRighteousness',maxUses=1},{key='judgement',requiresBuffGroup='seal'}},2)
local refund;for _,e in ipairs(r.events)do if e.key=='sanctifiedJudgement'and e.kind=='resource'then refund=e.amount end end
assert(refund and math.abs(refund-s.abilities.sealOfRighteousness.cost*2/3)<1e-8)
-- Light's Vigil replaces Holy Shock damage, returns mana and resets the shared Shock cooldown.
p=referenceProfile('paladin',nil,{lightsVigil=1,holyShock=1});p.stats.mana=10000
r,s=referenceRun('paladin',p,{{key='lightsVigil',maxUses=1},{key='holyShock'}},7)
assert(r.bySpell.vigilStrike3 and r.bySpell.vigilStrike3.casts==1)
assert(r.bySpell.holyShock and r.bySpell.holyShock.casts>=2)
-- Command has a separate 7 PPM weapon proc with a 1-second ICD and rank-matched judgement.
p=referenceProfile('paladin',nil,{sealOfCommand=1});p.stats.mana=10000
s=P.compile(FUSLiveData.paladin,p,P.combine({}),{policies={{key='sealOfCommand',maintainBuff='sealOfCommand'}}},60,7331);s.trace=true;r=P.run(s)
assert(r.bySpell.sealOfCommandProc and r.bySpell.sealOfCommandProc.damage>0)
local previous=-10;for _,e in ipairs(r.events)do if e.kind=='damage'and e.key=='sealOfCommandProc'then assert(e.t-previous>=1);previous=e.t end end
-- Weaponmaster conditions are per hand; armor-ignore shares add instead of multiplying.
p=referenceProfile('warrior',nil,{weaponmaster=5});p.stats.weapons.mainhand.subclass=0;p.stats.weapons.offhand.subclass=15
local _,s=referenceRun('warrior',p,{},1);assert(math.abs(s.abilities['auto:mainhand'].crit-.05)<1e-8);assert(s.abilities['auto:offhand'].crit==0)
p=referenceProfile('rogue',nil,{hackAndSlash=5,serratedBlades=3});p.stats.weapons.mainhand.subclass=4;p.encounter.armor=1000
local _,s=referenceRun('rogue',p,{},1);assert(math.abs(s.targetArmor-760)<1e-8)
-- Expose Armor is 450 per CP at rank 5, and Improved Expose returns 2 CP only on a five-point spend.
p=referenceProfile('rogue',nil,{improvedExposeArmor=2});p.encounter.armor=3000
r,s=referenceRun('rogue',p,{{key='exposeArmor',minCombo=5}},.01,5);assert(r.comboEnd==2 and s.abilities.exposeArmor.cost==15)
-- Hunter cooldowns affect the pet, not the owner's weapon damage.
p=referenceProfile('hunter',nil,{bestialWrath=1,frenzy=5});p.stats.mana=10000;p.petActive=true;p.petType='cat'
p.pet={type='cat',level=60,critPct=100,hasSpellbook=true,knownSpellRanks={bite={8},claw={8}},melee={baseDps=40,swing=2,includesModifiers=true}}
r,s=referenceRun('hunter',p,{{key='bestialWrath',maintainBuff='bestialWrath'}},10)
assert(r.bySpell['pet:melee'].casts>=6 and r.bySpell['pet:melee'].damage>0)
local found=false;for _,e in ipairs(r.events)do if e.kind=='buff'and e.key=='petFrenzy'then found=true end end;assert(found)
-- A hawk arrives once and keeps attacking independently; its slots are capped by the source row.
p=referenceProfile('hunter',nil,{summonHawk=1});p.stats.mana=10000
r,s=referenceRun('hunter',p,{{key='summonHawk'}},20)
assert(r.bySpell['summonHawk:swings']and r.bySpell['summonHawk:swings'].casts>r.bySpell.summonHawk.casts)
-- Premeditation is gated by stealth, and an Ambush breaks stealth and gains its actual combo points.
p=referenceProfile('rogue',nil,{premeditation=1,initiative=3});p.stealthed=true
r,s=referenceRun('rogue',p,{{key='premeditation',maxUses=1},{key='ambush'}},.01)
assert(r.comboEnd==4 and r.bySpell.ambush.casts==1)
p.stealthed=false;r,s=referenceRun('rogue',p,{{key='premeditation'},{key='ambush'}},1);assert(not r.bySpell.ambush and r.comboEnd==0)
-- The former DBC level-60 placeholder does not hide a learned Ghostly Strike at level 20.
p=referenceProfile('rogue');p.level=20;p.talents={{entries={{name='Ghostly Strike',classKey='ghostlyStrike',rank=1}}}};assert(#P.ranks(FUSLiveData.rogue,p,'ghostlyStrike')==1)
''')
print('PASS: ground debuff timing, seal refunds, Vigil/Shock replacement, Command ICD, weapon conditions, armor debuff CP, pet Frenzy, temporary attackers and stealth gating.')

import json
changes=json.loads((BASE/'implemented_rules.json').read_text())
seen=set();count=0
for change in changes:
 cls=change['class']
 if cls=='enhancement':continue
 key=change['talent'][0].lower()+change['talent'][1:]
 if (cls,key)in seen:continue
 seen.add((cls,key));data=L.globals().FUSLiveData[cls]
 definition=next((v for _,v in data.talentDefinitions.items()if v['key'].lower()==key.lower()),None)
 if definition is None:continue
 for rank in range(1,int(definition['maxRank'])+1):
  talents=L.table_from({definition['key']:rank})
  for form in (['caster','cat','bear','moonkin']if cls=='druid'else [None]):
   p=L.globals().referenceProfile(cls,form,talents)
   choices=L.globals().FUSLive.candidates(data,p)
   spec=L.globals().FUSLive.compile(data,p,L.globals().FUSLive.combine(p['equipped']),choices[1],3,7331)
   result=L.globals().FUSLive.run(spec)
   assert result['manaEnd']>=0 and result['energyEnd']>=0 and result['rageEnd']>=0 and result['comboEnd']>=0
   count+=1
print(f'PASS: {count} talent-rank/form execution cases with no illegal resource states.')
L.execute((root/'Classes/shaman_melee.lua').read_text())
L.execute('''
local P=FUSLive
local _,_,p=universalFixture('hunter',60)
p.class='shaman';p.spec='enhancement';p.petActive=false;p.pet=nil;p.weaponEnchants={mainhand=1669,offhand=0}
p.knownSpellRanks={stormstrike={1},lightningBolt={10},chainLightning={4},earthShock={7},flameShock={6},lightningShield={7}}
p.talents={{entries={{name='Stormstrike',classKey='stormstrike',rank=1},{name='Elemental Weapons',classKey='elementalWeapons',rank=3},{name='Shamanistic Focus',classKey='shamanisticFocus',rank=1},{name='Elemental Devastation',classKey='elementalDevastation',rank=3},{name='Improved Stormstrike',classKey='improvedStormstrike',rank=2}}}}
p.encounter={armor=0,levelDifference=0,baseHitPct=100,levelResistance=false};p.bossPlus=0
p.stats.meleeHitPct=100;p.stats.expertise=100;p.stats.natureCrit=100;p.stats.mana=10000
assert(not P.coverage(FUSLiveData.shaman,p))
local s=P.compile(FUSLiveData.shaman,p,P.combine({}),{policies={{key='stormstrike'},{key='earthShock'}}},20,7331);s.trace=true
assert(math.abs(s.abilities.earthShock.cost-s.abilities.earthShock.baseCost*.55)<1e-8)
local windfury;for _,rule in ipairs(s.genericProcs)do if rule.key=='weaponProc:mainhand'then windfury=rule end end
assert(windfury and math.abs(windfury.attackPowerBonus-333*1.4)<1e-8)
local r=P.run(s);assert(r.total>0 and r.manaEnd>=0)
local focus,devastation=false,false;for _,e in ipairs(r.events)do if e.kind=='buff'and e.key=='improvedStormstrike'then focus=true elseif e.kind=='buff'and e.key=='elementalDevastation'then devastation=true end end
assert(focus and devastation)
''')
print('PASS: Enhancement Elemental Weapons AP, permanent Shamanistic Focus cost, Improved Stormstrike regen and melee-only Elemental Devastation proc.')
