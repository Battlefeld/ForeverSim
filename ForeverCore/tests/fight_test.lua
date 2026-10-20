-- The fight check after a boss: what is counted, what is shown and what is left out.
local root=assert(arg[1]);dofile(root..'/_dev/harness/wowmock.lua');dofile(root..'/_dev/harness/gameapi.lua')
local function loadAddon(addon)
 for line in io.lines(root..'/'..addon..'/'..addon..'.toc')do
  local file=line:gsub(string.char(13),''):gsub(string.char(92),'/'):match('^%s*([^#].-%.lua)%s*$')
  if file then assert(loadfile(root..'/'..addon..'/'..file))(addon,{})end
 end
end
loadAddon('ForeverSimBridge');loadAddon('ForeverCoreBridge')
UnitClass=function(u)if u=='player'then return'Mage','MAGE',8 end end
UnitLevel=function()return 60 end
MOCK.Fire('PLAYER_LOGIN');MOCK.Advance(.5,.05)
IsPlayerSpell=function()return true end
local HUD=assert(ForeverSimHUD);local FC=assert(ForeverSimFight,'fight check not loaded')
local C=ForeverCoreClient
ForeverSimBridgeDB.hud=nil
local A,B,Cc=1001,1002,1003
C.Sim.Store().rotation={name='fire',priority={{spellId=A},{spellId=B},{spellId=Cc}}}
local combat=false;InCombatLockdown=function()return combat end;UnitAffectingCombat=function()return combat end

-- summary maths ---------------------------------------------------------------------------------------------------------
local s=FC.Summarize({name='X',start=100,finish=160,success=true,counted=10,followed=9,idle=2.5,procs={
 {id=A,at=110,hideAt=112,casts={111}},{id=B,at=120,hideAt=124,casts={}},{id=Cc,at=130,hideAt=131,casts={131.8}}}})
assert(s.duration==60 and s.followedPct==90 and s.procTotal==3 and s.procUsed==2,'followed 90 %, 2 of 3 procs: '..s.followedPct..' '..s.procUsed)
assert(#s.missed==1 and s.missed[1].id==B and s.missed[1].at==20,'the missed proc and its time')
assert(FC.Clock(61.4)=='1:01' and FC.Clock(0)=='0:00')
assert(FC.Summarize({name='X',start=0,finish=5,counted=0,followed=0,idle=0,procs={}}).followedPct==nil,'nothing counted: no percentage')

-- a fight: the HUD queue is [A,B,Cc]; the player follows it, misses a proc ----------------------------------------------------
HUD.lastItems={{id=A,state='ready'},{id=B,state='ready'}}
MOCK.Fire('ENCOUNTER_START',1234,'Baron Rivendare',1,5)
assert(FC.Active())
local t0=GetTime()
local function cast(id,top,second,gap)
 MOCK.Advance(gap or 1.5,.1)
 HUD.lastItems={top,second}
 MOCK.Fire('UNIT_SPELLCAST_SUCCEEDED','player','guid',id)
end
cast(A,{id=A,state='ready'},{id=B,state='ready'})                -- followed
cast(B,{id=B,state='ready'},{id=A,state='ready'})                -- followed
cast(Cc,{id=A,state='ready'},{id=B,state='ready'})               -- not followed
cast(A,{id=A,state='wait'},{id=B,state='ready'},1.6)            -- top is waiting; cast of the second counts as followed
cast(B,{id=A,state='wait'},{id=B,state='ready'},6)               -- a long pause: idle time
cast(999,{id=A,state='ready'},nil)                               -- a spell that is not part of the rotation: not counted
-- procs: one used, one missed
MOCK.Fire('SPELL_ACTIVATION_OVERLAY_GLOW_SHOW',B);MOCK.Advance(.5,.1)
MOCK.Fire('SPELL_ACTIVATION_OVERLAY_GLOW_HIDE',B);MOCK.Fire('UNIT_SPELLCAST_SUCCEEDED','player','guid',B)     -- hide first, then the cast
MOCK.Advance(2,.1)
MOCK.Fire('SPELL_ACTIVATION_OVERLAY_GLOW_SHOW',Cc);MOCK.Advance(5,.1);MOCK.Fire('SPELL_ACTIVATION_OVERLAY_GLOW_HIDE',Cc)   -- expired unused
MOCK.Advance(12,.5)
-- a cast with a start event uses the queue as it was at the start
MOCK.Fire('UNIT_SPELLCAST_START','player','guid',A);HUD.lastItems={{id=B,state='ready'}}
MOCK.Fire('ENCOUNTER_END',1234,'Baron Rivendare',1,5,1)
assert(not FC.Active())
local sum=FC.last
assert(sum and sum.success and sum.counted==6 and sum.followed==4,'counted 6 rotation casts, 4 followed: '..tostring(sum and sum.counted)..'/'..tostring(sum and sum.followed))
assert(sum.procTotal==2 and sum.procUsed==1 and sum.missed[1].id==Cc,'one proc used, one missed: '..tostring(sum.procUsed))
assert(sum.idle>4 and sum.idle<7,'idle time from the long pause: '..sum.idle)
local panel=_G.ForeverSimFightCheck
assert(panel and panel:IsShown(),'the panel is shown after the boss')
assert(panel.title:GetText()=='Kampf vorbei' and panel.sub:GetText():find('Baron Rivendare',1,true),'header')
assert(panel.big:GetText()=='67 %','without a damage meter the big number is the followed share: '..panel.big:GetText())
assert(panel.note:GetText():find('verpasst',1,true),'missed proc named: '..panel.note:GetText())
MOCK.Advance(11,.5);assert(not panel:IsShown(),'the panel fades after 10 s')

-- too short a fight: nothing shown
FC.last=nil;panel:Hide()
MOCK.Fire('ENCOUNTER_START',1,'Kurz');MOCK.Advance(3,.5);MOCK.Fire('ENCOUNTER_END',1,'Kurz',1,5,1)
assert(not panel:IsShown(),'a fight of 3 seconds is not evaluated')
-- off in the settings
HUD.Config().fightCheck=false
MOCK.Fire('ENCOUNTER_START',2,'Lang');HUD.lastItems={{id=A,state='ready'}}
for i=1,5 do MOCK.Advance(3,.5);MOCK.Fire('UNIT_SPELLCAST_SUCCEEDED','player','guid',A)end
MOCK.Fire('ENCOUNTER_END',2,'Lang',1,5,1)
assert(not panel:IsShown(),'switched off: no panel');HUD.Config().fightCheck=true
-- a damage meter that answers
C_DamageMeter={GetCombatSessionFromType=function()return{combatSources={{isLocalPlayer=false,amountPerSecond=9999},{isLocalPlayer=true,amountPerSecond=1712}}}end}
Enum=Enum or{};Enum.DamageMeterSessionType={Current=1};Enum.DamageMeterType={Dps=1}
assert(FC.ReadDps()==1712,'dps of the local player from the damage meter')
local originalNumber=FUSLive.publicNumber
FUSLive.publicNumber=function(v)if v==1712 then return nil end;return originalNumber(v)end
assert(FC.ReadDps()==nil,'a nonpublic meter number has no numeric fallback')
FUSLive.publicNumber=originalNumber
C.Sim.Store().results.live={dps=1842}
MOCK.Fire('ENCOUNTER_START',3,'Mit Meter');HUD.lastItems={{id=A,state='ready'}}
for i=1,5 do MOCK.Advance(3,.5);MOCK.Fire('UNIT_SPELLCAST_SUCCEEDED','player','guid',A)end
MOCK.Fire('ENCOUNTER_END',3,'Mit Meter',1,5,1)
assert(panel:IsShown() and panel.big:GetText()=='1.712' and panel.bigNote:GetText():find('1.842',1,true),'dps and sim shown: '..panel.big:GetText()..' / '..panel.bigNote:GetText())
assert(panel.rows[1].label:GetText()=='Erreicht' and panel.rows[1].value:GetText()=='93 %','reached 93 %: '..tostring(panel.rows[1].value:GetText()))
C_DamageMeter={GetCombatSessionFromType=function()error('not available')end};assert(FC.ReadDps()==nil,'a failing meter is ignored')
C_DamageMeter=nil
-- a wipe says so
panel:Hide()
MOCK.Fire('ENCOUNTER_START',4,'Wipe');HUD.lastItems={{id=A,state='ready'}}
for i=1,5 do MOCK.Advance(3,.5);MOCK.Fire('UNIT_SPELLCAST_SUCCEEDED','player','guid',A)end
MOCK.Fire('ENCOUNTER_END',4,'Wipe',1,5,0)
assert(panel:IsShown() and panel.title:GetText()=='Kampf nicht geschafft')
assert(#MOCK.errors==0,'no errors: '..tostring(MOCK.errors[1]))
for tag,n in pairs(MOCK.unknownMethods)do error('unknown widget method '..tag..' x'..n)end
io.write('fight ok\n')
