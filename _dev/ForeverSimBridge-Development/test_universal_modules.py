from pathlib import Path
from lupa.lua51 import LuaRuntime
L=LuaRuntime(unpack_returned_tuples=True);root=Path(__file__).resolve().parent.parent
for name in [f'Classes/{c}.lua'for c in ['warlock','mage','shaman','warrior','paladin','hunter','rogue','priest','druid']]+['CombatEngine.lua','UniversalRules.lua','Optimizers.lua']:
 L.execute((root/name).read_text())
L.execute('''function universalFixture(cls,level,form,talents)
 local P=FUSLive;local data=FUSLiveData[cls];local spells={}
 for key,ranks in pairs(data.abilities)do for _,r in ipairs(ranks)do if r.level<=level then spells[#spells+1]={id=r.id,rank=r.rank}end end end
 local stats={mana=2500,health=3000,intellect=100,spirit=80,attackPower=300,rangedAttackPower=350,meleeCritPct=10,rangedCritPct=12,holyCrit=8,fireCrit=8,frostCrit=8,shadowCrit=8,natureCrit=8,arcaneCrit=8,holyPower=100,firePower=100,frostPower=100,shadowPower=100,naturePower=100,arcanePower=100,manaRegen=10,castingManaRegen=0,energy=100,rage=0,weapons={mainhand={min=40,max=60,speed=2,normalizedSpeed=2.4,subclass=15,form=form or 'caster'},ranged={min=50,max=80,speed=2.8,normalizedSpeed=2.8}}}
 local p=P.normalizeSnapshot({class=cls,weaponEnchants={mainhand=0,offhand=0},level=level,form=form,stats=stats,spells=spells,talents=talents or {},encounter={armor=1000,levelDifference=2,mobType='undead'},equipped={}})
 local issue=P.coverage(data,p);assert(not issue,issue)
 local candidates=P.candidates(data,p);assert(#candidates>0,cls..': no candidates')
 local c=candidates[1];local spec=P.compile(data,p,P.combine({}),c,60,7331);spec.trace=true
 local r=P.run(spec);assert(r.dps>0,cls..': no damage');assert(r.manaEnd>=0 and r.energyEnd>=0 and r.rageEnd>=0 and r.comboEnd>=0);return r,spec,p
end''')
for c in ['priest','paladin','hunter','rogue','warrior','druid']:
 for level in [10,13,30,60]:
  r,s,p=L.globals().universalFixture(c,level,None,None)
  print(c,level,round(r['dps'],2),r['steps'])
for form in ['cat','bear','moonkin']:
 r,s,p=L.globals().universalFixture('druid',60,form,None);print('druid',form,round(r['dps'],2))
# Float32 intermediate rounding/floor follows the reference client accessor exactly.
L.execute('assert(FUSLive.clientAverage({base=15,perLevel=.2,start=1,cap=5},60)==15);assert(FUSLive.clientAverage({base=30,perLevel=1.8,start=1,cap=7},60)==40)')
print('PASS: all six modules and three druid forms execute independently in the common Lua engine.')
# Behavioral tests against source equations, independent of optimizer rank ordering.
L.execute('''
local P=FUSLive
local _,_,p=universalFixture('rogue',60)
local stats=P.combine({});p.stats.weapons.mainhand={min=40,max=40,speed=2,normalizedSpeed=2.4,subclass=15};p.stats.attackPower=140;p.stats.meleeCritPct=0;p.stats.meleeHitPct=100;p.stats.expertise=100;p.encounter={armor=0,levelDifference=0};p.bossPlus=0
local choice={policies={{key='sinisterStrike'}}};local spec=P.compile(FUSLiveData.rogue,p,stats,choice,1,7331);spec.autoAttacks={};spec.trace=true
local r=P.run(spec);local a=spec.abilities.sinisterStrike
-- Source: bonus + normalized main hand, AP / 14 * 2.4; no physical SP contribution.
assert(math.abs(r.total-(a.base+40+140/14*2.4))<1e-8)
assert(r.comboEnd==1);assert(r.energyEnd==100-a.cost+10)
-- A forced miss gives back the client's 80% cost and never creates combo points.
spec.abilities.sinisterStrike.attackTable.miss=1;r=P.run(spec)
assert(r.comboEnd==0 and r.total==0);assert(math.abs(r.energyEnd-math.min(100,100-a.cost*.2+10))<1e-8)
local _,_,wp=universalFixture('warrior',60)
wp.stats.weapons.mainhand={min=40,max=40,speed=2,normalizedSpeed=2.4};wp.stats.meleeHitPct=100;wp.stats.meleeCritPct=0;wp.stats.expertise=100;wp.bossPlus=0;wp.encounter={armor=0,levelDifference=0}
spec=P.compile(FUSLiveData.warrior,wp,stats,{policies={}},10,7331);spec.trace=true;r=P.run(spec)
assert(r.bySpell['auto:mainhand'].casts==5);assert(math.abs(r.rageEnd-5*3.46*2)<1e-8)
wp.stats.rage=100;spec=P.compile(FUSLiveData.warrior,wp,stats,{policies={{key='heroicStrike'}}},10,7331);spec.trace=true;r=P.run(spec)
assert(r.bySpell.heroicStrike.casts==5);assert(not r.bySpell['auto:mainhand']);assert(math.abs(r.rageEnd-(100-5*spec.abilities.heroicStrike.cost))<1e-8)
local timestamps={};for _,e in ipairs(r.events)do if e.kind=='damage'and e.key=='heroicStrike'then timestamps[#timestamps+1]=e.t end end
assert(#timestamps==5 and timestamps[2]==2 and timestamps[5]==8)
-- Cat/Bear ability sets follow the actual form and never mix incompatible resources.
for _,form in ipairs({'cat','bear','moonkin'})do local rr,ss,pp=universalFixture('druid',60,form);for _,pol in ipairs(ss.policies)do local aa=ss.abilities[pol.key];if aa.kind~='wait'then assert(aa.resource==ss.resource)end end end
-- A Cat's learned Bite and Claw are scheduled independently using focus, beside hunter attacks.
local _,_,hp=universalFixture('hunter',60);hp.petActive=true;hp.petType='cat';hp.pet={type='cat',level=60,critPct=5,hasSpellbook=true,knownSpellRanks={bite={8},claw={8}},melee={baseDps=40,swing=2,includesModifiers=true}}
assert(not P.coverage(FUSLiveData.hunter,hp));spec=P.compile(FUSLiveData.hunter,hp,stats,{policies={{key='autoAttack'}}},30,7331);r=P.run(spec)
assert(r.bySpell['pet:melee'].damage>0 and r.bySpell['pet:bite'].damage>0 and r.bySpell['pet:claw'].damage>0)
-- Eligibility checks use the actual class and the client's known dual wield status.
local item={id=1,name='Leather',slot='chest',stats={},armorType='leather',itemClass=4,itemSubclass=2}
local _,_,pr=universalFixture('priest',60);assert(P.checkEligibility(FUSLiveData.priest,pr,item,{})=='Rüstung nicht tragbar')
local _,_,ro=universalFixture('rogue',10);assert(not P.checkEligibility(FUSLiveData.rogue,ro,item,{}))
local oh={id=2,name='Dagger',slot='offhand',stats={},weaponClass=2,weaponSubclass=15,equipLoc='INVTYPE_WEAPON'}
assert(P.checkEligibility(FUSLiveData.rogue,ro,oh,{})~=nil);ro.dualWield=true;assert(not P.checkEligibility(FUSLiveData.rogue,ro,oh,{}))
-- New modules keep the existing level-10 gate and don't pretend an unknown talent is modeled.
pr.level=9;assert(P.coverage(FUSLiveData.priest,pr):find('Level 10'));pr.level=60
pr.talents={{entries={{name='Made-up talent',rank=1}}}};assert(P.coverage(FUSLiveData.priest,pr):find('Talentregel fehlt'))
''')
print('PASS: normalized AP damage, energy regeneration/refunds, combo gain, normalized white rage, queued swing replacement/timing, form resources, hunter pet focus and class equipment restrictions.')
L.execute('''
local P=FUSLive
local _,_,p=universalFixture('rogue',60)
p.stats.attackPower=300;p.stats.meleeCritPct=0;p.stats.meleeHitPct=100;p.stats.expertise=100;p.bossPlus=0;p.encounter={armor=0,levelDifference=0,damageModel='mean',levelResistance=false}
local spec=P.compile(FUSLiveData.rogue,p,P.combine({}),{policies={{key='eviscerate'}}},1,7331);spec.autoAttacks={};spec.resources.combo=5
local r=P.run(spec)
assert(math.abs(r.total-(108+170*5+.03*5*300))<1e-8);assert(r.comboEnd==0)
local _,_,d=universalFixture('druid',60,'cat');d.stats.attackPower=300;d.stats.meleeCritPct=0;d.stats.meleeHitPct=100;d.stats.expertise=100;d.bossPlus=0;d.encounter={armor=999999,levelDifference=0,damageModel='mean',levelResistance=false}
spec=P.compile(FUSLiveData.druid,d,P.combine({}),{policies={{key='rip',maintain=true,minCombo=5}}},12,7331);spec.autoAttacks={};spec.resources.combo=5;r=P.run(spec)
assert(r.bySpell.rip.ticks==6);assert(math.abs(r.total-(15+25.5*5+.01*4*300)*6)<1e-8)
-- Penance has three bolts, including the immediate bolt; it does not inherit a faster channel from haste.
local _,_,pr=universalFixture('priest',60);pr.stats.hastePct=100;pr.stats.holyCrit=0;pr.stats.holyPower=0;pr.talents={{entries={{name='Penance',classKey='penance',rank=1}}}};pr.encounter={armor=0,levelDifference=0,baseHitPct=100,levelResistance=false};pr.bossPlus=0
spec=P.compile(FUSLiveData.priest,pr,P.combine({}),{policies={{key='penance'}}},2.01,7331);spec.trace=true;r=P.run(spec)
assert(r.bySpell.penance.ticks==3);local times={};for _,e in ipairs(r.events)do if e.kind=='tick'and e.key=='penance'then times[#times+1]=e.t end end;assert(times[1]==0 and times[2]==1 and times[3]==2)
''')
print('PASS: reference Eviscerate damage equation, Rip CP/AP cap and armor bypass, Penance three-bolt timing with haste.')
L.execute((root/'Classes/shaman_melee.lua').read_text())
L.execute('''
local P=FUSLive;local _,_,p=universalFixture('shaman',60)
p.spec='enhancement';p.weaponEnchants={mainhand=1669,offhand=0};p.knownSpellRanks.stormstrike={1};p.talents={{entries={{name='Stormstrike',classKey='stormstrike',rank=1},{name='Maelstrom Weapon',classKey='maelstromWeapon',rank=5},{name='Flurry',classKey='flurry',rank=5}}}}
assert(not P.coverage(FUSLiveData.shaman,p));local choices=P.candidates(FUSLiveData.shaman,p);assert(#choices>0)
local spec=P.compile(FUSLiveData.shaman,p,P.combine({}),choices[1],120,7331);spec.trace=true
local r=P.run(spec);assert(r.total>0 and r.bySpell.stormstrike and r.bySpell['weaponProc:mainhand']and r.bySpell.lightningBolt)
assert(r.bySpell['weaponProc:mainhand'].casts%2==0)
local procs=0;for _,e in ipairs(r.events)do if e.kind=='buff'and e.key=='maelstromWeapon'then procs=procs+1 end end;assert(procs>0)
-- An unknown imbue fails closed; it is never interpreted as an unenchanted weapon.
p.weaponEnchants.mainhand=999999;assert(P.coverage(FUSLiveData.shaman,p):find('Waffenverzauberungsregel fehlt'))
''')
print('PASS: Enhancement mode, Stormstrike, separate Windfury attacks, Maelstrom stacks/casts, unknown imbue guard.')
# Independent float32 oracle for all imported client effects, at five representative levels.
import json,math,struct
source=json.loads((Path(__file__).resolve().parent/'reference-data.json').read_text())
def f32(v):return struct.unpack('f',struct.pack('f',v))[0]
count=0
for spell in source['spells'].values():
 for effect in spell['Effects']:
  e={k:effect.get(k,0)for k in ['BasePoints','PPL','SpellLevel','MaxLevel']}
  for level in [1,10,13,30,60]:
   cap=e['MaxLevel'];delta=max(0,(min(level,cap)if cap>0 else level)-e['SpellLevel'])
   want=math.floor(f32(f32(e['BasePoints'])+f32(f32(delta)*f32(e['PPL']))))
   got=L.globals().FUSLive.clientAverage(L.table_from(e),level)
   assert got==want,(spell['ID'],effect.get('Index',0),level,got,want)
   count+=1
print(f'PASS: {count} imported-effect/level calculations exactly match the independent float32 client-value oracle.')
L.execute('''
local P=FUSLive;local _,_,p=universalFixture('priest',60)
p.form='shadow';p.talents={{entries={{name='Mind Flay',classKey='mindFlay',rank=1},{name='Shadowform',classKey='shadowform',rank=1},{name='Shadow Weaving',classKey='shadowWeaving',rank=3},{name='Darkness',classKey='darkness',rank=5}}}}
assert(not P.coverage(FUSLiveData.priest,p));local candidates=P.candidates(FUSLiveData.priest,p);assert(#candidates>0)
for _,c in ipairs(candidates)do for _,pol in ipairs(c.policies)do assert(pol.key~='smite'and pol.key~='holyFire')end end
local spec=P.compile(FUSLiveData.priest,p,P.combine({}),{policies={{key='shadowWordPain',maintain=true},{key='mindFlay'}}},30,7331);spec.trace=true;local r=P.run(spec);assert(r.total>0)
local maxStacks=0;for _,e in ipairs(r.events)do if e.kind=='debuff'and e.key=='shadowWeaving'then maxStacks=math.max(maxStacks,e.amount)end end
assert(maxStacks==5)
-- Arcane and Frostfire were already modeled in the existing Mage module; both remain executable.
for _,mode in ipairs({'arcane','frost'})do local data=FUSLiveData.mage;local spells={};for _,ranks in pairs(data.abilities)do for _,a in ipairs(ranks)do if a.level<=60 and not a.requiredTalent and not a.requiredItem then spells[#spells+1]={id=a.id,rank=a.rank}end end end;local pr=P.normalizeSnapshot({class='mage',level=60,spells=spells,stats={},equipped={},spec=mode});local c=P.candidates(data,pr)[1];assert(c);assert(P.run(P.compile(data,pr,{},c,60,7331)).total>0)end
''')
print('PASS: Shadowform ability legality, Shadow Weaving stacking and retained Mage Arcane/Frost execution.')
L.execute('''
local P=FUSLive;local _,_,p=universalFixture('warrior',60);p.stats.rage=100;p.stats.meleeCritPct=0;p.stats.meleeHitPct=100;p.stats.expertise=100;p.stats.meleeHastePct=25;p.stats.hastePct=25;p.encounter={armor=0,levelDifference=0};p.bossPlus=0
local spec=P.compile(FUSLiveData.warrior,p,P.combine({}),{policies={}},10,7331);local r=P.run(spec);assert(r.bySpell['auto:mainhand'].casts==7)
-- A two-handed swap removes the previously equipped offhand from both stats and swing scheduling.
p.stats.weapons.offhand={min=10,max=15,speed=2,normalizedSpeed=1.7,subclass=15};p.equipped={mainhand={id=1,stats={},weaponClass=2},offhand={id=2,stats={},weaponClass=2}}
local gear={mainhand={id=3,name='Two hand',stats={},weaponClass=2,twoHanded=true,weapon={min=100,max=120,speed=3,normalizedSpeed=3.3}}}
spec=P.compile(FUSLiveData.warrior,p,P.combine(gear),{policies={}},10,7331);assert(#spec.autoAttacks==1 and not spec.abilities['auto:offhand'])
-- Flurry haste and rolling Deep Wounds use the generic queue; damage is never passed to a reference engine.
p.equipped={};p.stats.weapons.offhand=nil;p.stats.meleeCritPct=100;p.stats.hastePct=0;p.stats.meleeHastePct=0;p.talents={{entries={{name='Flurry',classKey='flurry',rank=5},{name='Deep Wounds',classKey='deepWounds',rank=3},{name='Anger Management',classKey='angerManagement',rank=1}}}}
assert(not P.coverage(FUSLiveData.warrior,p));spec=P.compile(FUSLiveData.warrior,p,P.combine({}),{policies={}},30,7331);spec.trace=true;r=P.run(spec);assert(r.bySpell.deepWounds and r.bySpell.deepWounds.ticks>0);assert(r.bySpell['auto:mainhand'].casts>15)
''')
print('PASS: haste timing without double application, two-handed removal of offhand, generic Flurry/Deep Wounds/Anger Management.')
