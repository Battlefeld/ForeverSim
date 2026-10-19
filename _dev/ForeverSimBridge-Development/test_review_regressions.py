"""Behavioral regressions found in the repository-wide offline review."""
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from wowmock_ui import load_addon

lua = load_addon()
lua.execute(r'''
local P=FUSLive
local scheduler
for _,f in ipairs(frames)do if f.scripts.OnUpdate then
 for i=1,30 do local key=debug.getupvalue(f.scripts.OnUpdate,i);if not key then break end;if key=='queue'then scheduler=f end end
end end
assert(scheduler,'Scheduler fehlt')
local starts,finished,urgent,callbacks=0,0,0,0
P.enqueue(function()starts=starts+1;coroutine.yield();finished=finished+1;return 42 end,function(v,e)assert(v==42 and not e);callbacks=callbacks+1 end)
scheduler.scripts.OnUpdate()
P.enqueue(function()urgent=urgent+1 end,function()end,nil,true)
for i=1,8 do scheduler.scripts.OnUpdate()end
assert(starts==1 and finished==1 and urgent==1 and callbacks==1,'Unterbrochener Job wurde neu gestartet')
local cancelled,busy=0,true
local function done(v,e)assert(v==nil and e);cancelled=cancelled+1;busy=false end
P.enqueue(function()coroutine.yield();return true end,done)
scheduler.scripts.OnUpdate();P.invalidate();scheduler.scripts.OnUpdate()
assert(cancelled==1 and not busy and P.pendingJobs()==0,'Aktiver Job meldet Abbruch nicht')
P.enqueue(function()error('Darf nicht laufen')end,done);P.invalidate();scheduler.scripts.OnUpdate()
assert(cancelled==2,'Wartender Job meldet Abbruch nicht')
P.enqueue(function()end,done);P.invalidate();P.cancelJobs();assert(cancelled==3)
-- A callback failure must not break the next queued job.
P.enqueue(function()return true end,function()error('callback regression fixture')end)
local survived=false;P.enqueue(function()survived=true end,function()end)
for i=1,3 do scheduler.scripts.OnUpdate()end
assert(survived and P.lastLiveError:find('callback regression fixture'))
-- Zero attack interval means no incoming attacks. Positive incoming attacks still guard missing rules.
local data=FUSLiveData.hunter
local p={level=30,class='hunter',weaponEnchants={mainhand=0,offhand=0},talents={{entries={{name='Trueshot Aura',classKey='trueshotAura',rank=1}}}},stats={health=1000,intellect=50,spirit=50,mana=1000,rangedCritPct=5,rangedAttackPower=100,weapons={ranged={min=10,max=20,speed=2}}},encounter={hitEvery=0}}
assert(not P.coverage(data,p));p.encounter.hitEvery=2;p.encounter.incomingDamage=30
assert(P.coverage(data,p):find('trueshotAura'))
GetItemInfo=function()return 'Test Shield',nil,2,20,10,'Armor','Shields',1,'INVTYPE_SHIELD',nil,1,4,6 end
C_Item=nil;GetItemStats=function()return {}end
local create=CreateFrame;CreateFrame=function(kind,...)local f=create(kind,...);if kind=='GameTooltip'then f.NumLines=function()return 0 end end;return f end
local shield=P.readItem('item:123','test');assert(shield and shield.slot=='offhand' and shield.itemSubclass==6)
P.stale=false;P.rotationHUD.stale=false;local rev=P.revision
for _,f in ipairs(frames)do if f.events.UPDATE_SHAPESHIFT_FORM and f.scripts.OnEvent then f.scripts.OnEvent(f,'UPDATE_SHAPESHIFT_FORM')end end
assert(P.revision>rev and P.stale and P.rotationHUD.stale,'Formwechsel lässt alte Rotation gültig')
print('PASS: Scheduler resume/cancellation/callback isolation, shield capture, zero incoming damage, shapeshift invalidation.')
''')

# Captured stats must survive a talent comparison; only modeled deltas change.
lua2 = load_addon()
lua2.execute(r'''
local P=FUSLive
local p={class='mage',level=60,talents={{entries={{classKey='arcaneMind',name='Arcane Mind',rank=5}}}},liveTalentRanks={arcaneMind=0},stats={intellect=200,spirit=100,mana=4000,health=2000,firePower=250,fireCrit=10,manaRegen=20,castingManaRegen=0}}
local q=P.applyTalentStatDeltas(FUSLiveData.mage,p)
assert(math.abs(q.stats.intellect-220)<1e-8 and math.abs(q.stats.mana-4300)<1e-8)
assert(q.stats.firePower==250 and p.stats.intellect==200)
q=P.copy(p);q.talents={{entries={{classKey='criticalMass',name='Critical Mass',rank=3}}}};q=P.applyTalentStatDeltas(FUSLiveData.mage,q);assert(q.stats.fireCrit==16)
-- Source-backed physical attribute conversion differs by class.
local fixture={id='rogue',talents={agility={},strength={}},attributeModifiers={{talent='agility',field='agility',values={.1}},{talent='strength',field='strength',values={.1}}},attributes={}}
local physical={level=60,liveTalentRanks={},talents={{entries={{classKey='agility',rank=1},{classKey='strength',rank=1}}}},stats={strength=100,agility=100,attackPower=500}}
local physicalResult=P.applyAttributeTalentDeltas(fixture,physical)
assert(math.abs(physicalResult.stats.attackPower-520)<1e-8,'Schurke: Stärke und Beweglichkeit geben je 1 AP')
fixture.id='hunter';physicalResult=P.applyAttributeTalentDeltas(fixture,physical)
assert(math.abs(physicalResult.stats.attackPower-520)<1e-8,'Jäger: Stärke und Beweglichkeit geben je 1 Nahkampf-AP')
fixture.id='warrior';physicalResult=P.applyAttributeTalentDeltas(fixture,physical)
assert(math.abs(physicalResult.stats.attackPower-520)<1e-8,'Krieger: Stärke gibt 2 AP')
fixture.id='shaman';fixture.talents.mentalDexterity={};fixture.talentStatRules={{talent='mentalDexterity',perRank={apPerInt=.33}}}
fixture.attributeModifiers={{talent='agility',field='intellect',values={.1}}}
physical.stats={intellect=100,attackPower=500};physical.liveTalentRanks={mentalDexterity=3};physical.talents={{entries={{classKey='agility',rank=1},{classKey='mentalDexterity',rank=3}}}}
physicalResult=P.applyTalentStatDeltas(fixture,physical)
assert(math.abs(physicalResult.stats.attackPower-509.9)<1e-8,'Mental Dexterity muss auch auf neues Intellekt bei gleichem Talentrang reagieren')
local live={class='mage',level=60,talents={},hasSpellbook=true,knownSpellRanks={fireball={1}},stats={}}
local plan=P.copy(live);plan.talents={{entries={{classKey='pyroblast',name='Pyroblast',rank=1}}}}
P.talentBuild.grantAbilities(FUSLiveData.mage,plan)
assert(not live.knownSpellRanks.pyroblast and #P.ranks(FUSLiveData.mage,plan,'pyroblast')>0)
assert(not plan.knownSpellRanks.frostbolt,'Entwurf darf keine Trainerzauber erfinden')
local count=0;for _,r in ipairs(FUSLiveData.warrior.staticRules)do if r.talent=='dualWieldSpecialization'and r.field=='offhandMultiplier'then count=count+1;assert(r.values[5]==.25)end end
assert(count==1,'Nebenhandbonus doppelt registriert')
print('PASS: preserved live stats, intellect/mana/crit deltas, planned capstone spells, one warrior offhand rule.')
''')

lua3=load_addon()
lua3.execute(r'''
local P=FUSLive
local p=P.normalizeSnapshot({class='WARLOCK',level=60,spells={{id=11668,rank=7},{id=25307,rank=10}},stats={mana=10000,health=5000,intellect=200,spirit=100},equipped={},encounter={armor=0,levelDifference=0,baseHitPct=100,levelResistance=false}})
local spec=P.compile(FUSLiveData.warlock,p,P.combine({}),{policies={{key='immolate',maintain=true,refreshAtCastTime=true},{key='shadowBolt'}}},18,7331)
spec.procs={};spec.tapKey=nil;spec.trace=true
local a=spec.abilities.immolate;a.cast=2;a.duration=6;a.tickEvery=2;a.base=0;a.max=0;a.tickBase=10;a.tickMax=10;a.coef=0;a.tickCoef=0;a.sp=0;a.hit=1;a.crit=0;a.cost=0;a.directMult=1;a.periodicMult=1;a.exclusiveGroup='fixture-dot'
local b=spec.abilities.shadowBolt;b.cast=1;b.gcd=1;b.base=0;b.max=0;b.coef=0;b.hit=1;b.crit=0;b.cost=0
local r=P.run(spec);local starts,ticks={},{}
for _,e in ipairs(r.events)do if e.kind=='start'and e.key=='immolate'then starts[#starts+1]=e.t elseif e.kind=='tick'and e.key=='immolate'then ticks[#ticks+1]=e.t end end
assert(starts[2]==6 and starts[3]==12,'DoT-Erneuerung muss zum Ablauf landen')
assert(#ticks==8 and ticks[3]==8,'Letzter Tick darf nicht abgeschnitten werden')
for _,key in ipairs({'warlock','mage','shaman','warrior','paladin','hunter','rogue','priest','druid'})do
 for _,field in ipairs({'modifiers','staticRules','contextModifiers','genericProcs'})do
  local seen={};for _,rule in ipairs(FUSLiveData[key][field]or {})do local id=P.canonical(rule);assert(not seen[id],key..': doppelte Regel in '..field);seen[id]=true end
 end
end
print('PASS: cast-time DoT renewal keeps the final tick; no duplicate class combat rules.')
''')

lua4=load_addon()
lua4.execute(r'''
local P=FUSLive
local data=FUSLiveData.rogue;local spells={}
for _,ranks in pairs(data.abilities)do for _,r in ipairs(ranks)do if r.level<=60 then spells[#spells+1]={id=r.id,rank=r.rank}end end end
local dagger={id=11,name='Dagger',slot='mainhand',stats={},weaponClass=2,weaponSubclass=15,equipLoc='INVTYPE_WEAPON',weapon={min=40,max=40,speed=2,subclass=15,normalizedSpeed=1.7}}
local sword={id=12,name='Sword',slot='mainhand',stats={},weaponClass=2,weaponSubclass=7,equipLoc='INVTYPE_WEAPON',weapon={min=60,max=60,speed=2.4,subclass=7,normalizedSpeed=2.4}}
local stats={mana=0,health=3000,intellect=100,spirit=80,attackPower=300,meleeCritPct=0,meleeHitPct=100,expertise=100,energy=100,weapons={mainhand=dagger.weapon}}
for _,school in ipairs({'holy','fire','frost','shadow','nature','arcane'})do stats[school..'Power']=0;stats[school..'Crit']=0 end
local p=P.normalizeSnapshot({class='ROGUE',level=60,spells=spells,stats=stats,equipped={dagger},weaponEnchants={mainhand=0,offhand=0},encounter={armor=0,levelDifference=0,baseHitPct=100,levelResistance=false}})
assert(#P.ranks(data,p,'backstab')>0)
local preview=P.copy(p);preview.comparisonGear={mainhand=sword};assert(#P.ranks(data,preview,'backstab')==0)
P.durations={1};P.weights={1}
local result=P.compareSlot(data,p,p.equipped,sword,{choice={policies={{key='backstab'}}}})
assert(result.eligible and result.rotationChangedRequired and result.newChoice)
for _,pol in ipairs(result.newChoice.policies)do assert(pol.key~='backstab')end
assert(p.equipped.mainhand.id==11 and p.comparisonGear==nil,'Vergleich darf Liveausrüstung nicht verändern')
print('PASS: dagger-to-sword comparison chooses a legal new rotation and preserves worn gear.')
''')
