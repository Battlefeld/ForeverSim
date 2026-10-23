-- The combat HUD: the queue (cooldowns, DoTs, look-ahead), procs, the picture (flow, hero, past) and the settings.
local root=assert(arg[1]);dofile(root..'/_dev/harness/wowmock.lua');dofile(root..'/_dev/harness/gameapi.lua')
local function loadAddon(addon)
 for line in io.lines(root..'/'..addon..'/'..addon..'.toc')do
  local file=line:gsub(string.char(13),''):gsub(string.char(92),'/'):match('^%s*([^#].-%.lua)%s*$')
  if file then assert(loadfile(root..'/'..addon..'/'..file))(addon,{})end
 end
end
loadAddon('ForeverSimBridge');loadAddon('ForeverCoreBridge')
UnitClass=function(u)if u=='player'then return'Mage','MAGE',8 end end
local level=60;UnitLevel=function()return level end
MOCK.Fire('PLAYER_LOGIN');MOCK.Advance(.5,.05)
local HUD=assert(ForeverSimHUD,'HUD logic not loaded')
local C=ForeverCoreClient
ForeverSimBridgeDB.hud=nil

-- the game: cooldowns, auras, spells ---------------------------------------------------------------------------------
local cd={}              -- id -> seconds left
local baseCd={}          -- id -> own cooldown in ms
local combat=false
local targetDot={}       -- id -> seconds left on the target
local usableNot={}
C_Spell.GetSpellCooldown=function(id)
 local left=cd[id]or 0
 if left>0 then return{startTime=GetTime()-1,duration=left+1,isEnabled=true}end
 return{startTime=0,duration=0,isEnabled=true}
end
C_Spell.IsSpellUsable=function(id)return not usableNot[id],false end
C_Spell.GetSpellInfo=function(id)return{name='Zauber '..id,iconID=100000+id,castTime=1500}end
GetSpellBaseCooldown=function(id)return baseCd[id]or 0,1500 end
InCombatLockdown=function()return combat end
UnitAffectingCombat=function()return combat end
local realExists=UnitExists
UnitExists=function(u)if u=='target'then return true end;return realExists(u)end
UnitCanAttack=function()return true end
C_UnitAuras.GetAuraDataByIndex=function(unit,i,filter)
 if unit~='target'or filter~='HARMFUL'then return nil end
 local n=0
 for id,left in pairs(targetDot)do n=n+1;if n==i then return{spellId=id,name='Zauber '..id,sourceUnit='player',expirationTime=GetTime()+left}end end
end
MOCK.knownSpellIDs=setmetatable({},{__index=function()return true end})

-- layout ------------------------------------------------------------------------------------------------------------
local n1,h1=HUD.Layout(1,false),HUD.Layout(1,true)
assert(n1.x==0 and n1.size==104 and h1.size==150,'the spell to press is big, a proc makes it bigger')
for i=2,6 do
 local a,b=HUD.Layout(i,false),HUD.Layout(i,true)
 assert(b.size<a.size and b.alpha<a.alpha,'with a proc the others shrink and fade: '..i)
 assert(a.x>HUD.Layout(i-1,false).x,'the queue runs to the right')
end
assert(HUD.PastLayout(1,false).x<0 and HUD.PastLayout(2,false).x<HUD.PastLayout(1,false).x and HUD.PastLayout(3,false)==nil)

-- the queue ---------------------------------------------------------------------------------------------------------------
local A,B,Cc,D=1001,1002,1003,1004
baseCd[Cc]=8000
local rows={
 {spellId=B,condition={['not']={val={auraIsActive={auraId={spellId=B},sourceUnit={type='CurrentTarget'}}}}}},   -- a DoT
 {spellId=Cc},                                                                                                          -- 8 s cooldown
 {spellId=A},                                                                                                           -- filler
}
local items=HUD.Build(rows,6)
assert(#items==6 and items[1].id==B and items[2].id==Cc and items[3].id==A,'DoT first, cooldown spell second, filler after: '..items[1].id..','..items[2].id..','..items[3].id)
assert(items[4].id==A and items[5].id==A,'the filler is repeated while the others are busy')
for i=2,6 do assert(items[i].id~=B,'the DoT is not offered again while it runs (look-ahead)')end
assert(items[1].state=='ready' and items[1].icon==100000+B)
-- the DoT is on the target: not offered at all; once it runs low it comes back in the look-ahead
targetDot[B]=20;items=HUD.Build(rows,6);assert(items[1].id==Cc,'a running DoT is skipped')
targetDot[B]=1;items=HUD.Build(rows,6)
local seenB;for i,it in ipairs(items)do if it.id==B then seenB=i end end
assert(not seenB or seenB>1,'a DoT with 1 s left is not first yet: '..tostring(seenB))
targetDot[B]=nil
-- cooldowns
cd[Cc]=5;items=HUD.Build(rows,4);assert(items[1].id==B and items[2].id==A,'a spell on cooldown is passed over: '..items[2].id)
cd[Cc]=1.2;cd[B]=3;cd[A]=2.4
items=HUD.Build({rows[1],rows[2],rows[3]},3)
assert(items[1].id==Cc and items[1].state=='wait' and math.abs(items[1].delay-1.2)<.01,'nothing ready: the one that is next is shown as waiting')
cd={};usableNot[Cc]=true;items=HUD.Build({rows[2],rows[3]},1);assert(items[1].id==A,'an unusable spell (no mana) is not offered now');usableNot={}
-- a cast spell is not offered again within a moment (cooldown not yet updated)
HUD.OnCast(B);items=HUD.Build(rows,2);assert(items[1].id==Cc,'just cast: skipped for a moment');MOCK.Advance(1,.1);HUD.ClearCasts()
-- a DoT that is being cast is not offered again; the queue is what comes after the cast
UnitCastingInfo=function()return'Zauber',nil,nil,(GetTime()-1)*1000,(GetTime()+1)*1000,false,'c',false,B end
items=HUD.Build(rows,3);assert(items[1].id==Cc and items[2].id==A,'while B is cast, the queue starts after it: '..items[1].id)
UnitCastingInfo=nil
-- engine conditions
local cmpRows={{spellId=D,condition={cmp={op='OpLt',lhs={spellTimeToReady={spellId=Cc}},rhs={const={val=1}}}}},{spellId=A}}
cd[Cc]=0;items=HUD.Build(cmpRows,1);assert(items[1].id==D,'cooldown comparison is true')
cd[Cc]=4;items=HUD.Build(cmpRows,1);assert(items[1].id==A,'cooldown comparison is false');cd={}
local unknown={{spellId=D,condition={somethingNew={}}},{spellId=A}}
items=HUD.Build(unknown,1);assert(items[1].id==A,'a condition the HUD cannot read keeps the spell out')
-- hidden (secret) values are never used
local secret={}
local realSecret=issecretvalue
issecretvalue=function(v)return v==secret end
C_Spell.GetSpellCooldown=function(id)return id==A and secret or{startTime=0,duration=0,isEnabled=true}end
items=HUD.Build({{spellId=A},{spellId=B}},1);assert(items[1].id==B,'a hidden cooldown is skipped')
C_Spell.GetSpellCooldown=function(id)local left=cd[id]or 0;if left>0 then return{startTime=GetTime()-1,duration=left+1,isEnabled=true}end;return{startTime=0,duration=0,isEnabled=true}end
issecretvalue=realSecret
-- an aura whose identity is hidden counts as present, not as missing
C_UnitAuras.GetAuraDataByIndex=function(unit,i,filter)if unit=='target'and filter=='HARMFUL'and i==1 then return{spellId=secret,name=secret,sourceUnit=secret,expirationTime=secret}end end
issecretvalue=function(v)return v==secret end
items=HUD.Build({rows[1],rows[3]},1);assert(items[1].id==A,'a DoT that cannot be identified is not proposed again: '..items[1].id)
issecretvalue=realSecret
C_UnitAuras.GetAuraDataByIndex=function(unit,i,filter)
 if unit~='target'or filter~='HARMFUL'then return nil end
 local n=0
 for id,left in pairs(targetDot)do n=n+1;if n==i then return{spellId=id,name='Zauber '..id,sourceUnit='player',expirationTime=GetTime()+left}end end
end
-- a spell the character no longer has is left out; when nothing is known the list stays
IsPlayerSpell=function(id)return id~=Cc end
items=HUD.Build({rows[2],rows[3]},1);assert(items[1].id==A,'an unlearned spell is not offered')
IsPlayerSpell=function()return false end
items=HUD.Build({rows[2],rows[3]},1);assert(#items==1,'if nothing is known the list is used as it is')
IsPlayerSpell=function()return true end
-- automatic action when nothing else is possible (Auto Shot)
items=HUD.Build({{spellId=75,automatic=true}},3);assert(#items==1 and items[1].auto,'only an automatic action: it is shown')

-- procs -----------------------------------------------------------------------------------------------------------------------
MOCK.Fire('SPELL_ACTIVATION_OVERLAY_GLOW_SHOW',Cc)
assert(HUD.ProcSince(Cc),'a lit-up spell is a proc')
local list=HUD.WithProcs(HUD.Build(rows,4),rows)
assert(list[1].id==Cc and list[1].proc,'the proc spell comes first')
MOCK.Fire('SPELL_ACTIVATION_OVERLAY_GLOW_HIDE',Cc);assert(not HUD.ProcSince(Cc))
-- a proc the rotation did not offer yet
MOCK.Fire('SPELL_ACTIVATION_OVERLAY_GLOW_SHOW',D)
list=HUD.WithProcs(HUD.Build({{spellId=A}},3),{{spellId=D},{spellId=A}})
assert(list[1].id==D and list[1].proc,'a lit-up spell of the rotation is offered even before its turn')
MOCK.Fire('SPELL_ACTIVATION_OVERLAY_GLOW_HIDE',D)
MOCK.Fire('SPELL_ACTIVATION_OVERLAY_GLOW_SHOW',secret);assert(next(HUD.glow)==nil,'a hidden id is ignored')
C_SpellActivationOverlay={IsSpellOverlayed=function(id)return id==A end}
assert(HUD.ProcSince(A),'IsSpellOverlayed is used when the client has it');C_SpellActivationOverlay=nil;HUD.glow[A]=nil

-- basic rotation for the levels without a simulation ---------------------------------------------------------------------
local basic=HUD.BasicRows();assert(#basic>=2,'a mage has basic spells: '..#basic)
for _,r in ipairs(basic)do assert(type(r.spellId)=='number')end
level=1;local few=HUD.BasicRows();assert(#few<=#basic,'fewer spells at level 1');level=60
local gotRows,source=HUD.Rows();assert(source=='basic')
C.Sim.Store().rotation={name='fire',priority={{spellId=A},{spellId=B}}}
gotRows,source=HUD.Rows();assert(source=='engine' and #gotRows==2,'the simulated rotation wins')

-- the picture ------------------------------------------------------------------------------------------------------------------
local frame=assert(HUD.frame)
assert(not frame:IsShown(),'hidden out of combat')
local function slotCells()local out={};for _,c in ipairs(MOCK.frames)do if c.rays and c.glow and c.edge then out[#out+1]=c end end;return out end
combat=true;MOCK.Fire('PLAYER_REGEN_DISABLED');MOCK.Advance(.6,.05)
assert(frame:IsShown(),'shown in combat')
local shown={};for _,c in ipairs(slotCells())do if c:IsShown()then shown[#shown+1]=c end end
assert(#shown>=2,'queue drawn: '..#shown)
table.sort(shown,function(a,b)local _,_,_,x1=a:GetPoint();local _,_,_,x2=b:GetPoint();return x1<x2 end)
local _,_,_,x1=shown[1]:GetPoint();assert(math.abs(x1)<3,'the first spell rests in the middle: '..x1)
assert(shown[1]:GetWidth()>95,'the spell to press is big: '..shown[1]:GetWidth())
assert(not shown[1].glow:IsShown(),'no glow without a proc')
-- a proc takes over
MOCK.Fire('SPELL_ACTIVATION_OVERLAY_GLOW_SHOW',B);MOCK.Advance(.6,.05)
local hero;for _,c in ipairs(slotCells())do if c:IsShown()and c.glow:IsShown()then hero=c end end
assert(hero and hero:GetWidth()>140,'the proc grows: '..tostring(hero and hero:GetWidth()))
for _,c in ipairs(slotCells())do if c:IsShown()and c~=hero then assert(c:GetWidth()<hero:GetWidth()/2+1 and c:GetAlpha()<.6,'the others shrink and fade: '..c:GetWidth()..' '..c:GetAlpha())end end
-- pressing it: the spell goes out to the left, the glow ends
MOCK.Fire('SPELL_ACTIVATION_OVERLAY_GLOW_HIDE',B)
MOCK.Fire('UNIT_SPELLCAST_SUCCEEDED','player','guid',B);cd[B]=0
MOCK.Advance(1,.05)
local anyGlow;for _,c in ipairs(slotCells())do if c:IsShown()and c.glow:IsShown()then anyGlow=c end end
assert(not anyGlow,'no glow after the proc was used')
local leftOf=0;for _,c in ipairs(slotCells())do if c:IsShown()then local _,_,_,x=c:GetPoint();if x<-100 then leftOf=leftOf+1 end end end
assert(leftOf>=1,'the spell just cast slid out to the left: '..leftOf)
-- out of combat the HUD fades away
combat=false;MOCK.Fire('PLAYER_REGEN_ENABLED');MOCK.Advance(1.2,.05)
assert(not frame:IsShown(),'hidden again after the fight')

-- settings -------------------------------------------------------------------------------------------------------------------------
local cfg=HUD.Config();assert(cfg.enabled and cfg.locked and cfg.queue==4,'defaults')
cfg.queue=99;assert(HUD.Config().queue==5,'the queue length is limited');cfg.queue=0;assert(HUD.Config().queue==1);cfg.queue=3
cfg.enabled=false;combat=true;MOCK.Fire('PLAYER_REGEN_DISABLED');MOCK.Advance(.5,.05);assert(not frame:IsShown(),'switched off: nothing shown');cfg.enabled=true;combat=false;MOCK.Fire('PLAYER_REGEN_ENABLED');MOCK.Advance(1,.05)
-- unlocked out of combat: preview to place it, and drag
assert(HUD.SetLocked(false) and not frame:IsShown()==false,'unlocked: the HUD shows a preview')
MOCK.Advance(.5,.05);assert(frame:IsShown())
frame.__scripts.OnDragStart(frame);frame.__scripts.OnDragStop(frame)
assert(HUD.SetLocked(true));MOCK.Advance(1,.05);assert(not frame:IsShown(),'locked again: hidden')
combat=true;assert(not HUD.SetLocked(false),'no unlocking during a fight');combat=false
-- an unlocked HUD takes no clicks during a fight
HUD.SetLocked(false);combat=true;MOCK.Fire('PLAYER_REGEN_DISABLED');MOCK.Advance(.3,.05)
assert(not HUD.frame:IsMouseEnabled(),'no mouse on the HUD in combat')
combat=false;MOCK.Fire('PLAYER_REGEN_ENABLED');MOCK.Advance(.3,.05);assert(HUD.frame:IsMouseEnabled(),'mouse back after the fight (unlocked)');HUD.SetLocked(true)
-- demo of a proc (to judge the HUD without a fight)
HUD.Demo('proc',2);MOCK.Advance(.6,.05)
local heroDemo;for _,c in ipairs(slotCells())do if c:IsShown()and c.glow:IsShown()then heroDemo=c end end
assert(frame:IsShown() and heroDemo,'the demo shows a proc')
MOCK.Advance(4,.1);assert(not frame:IsShown(),'the demo ends')
HUD.ResetPosition()
-- key bindings
GetActionInfo=function(slot)if slot==1 then return'spell',A end end
GetBindingKey=function(name)if name=='ACTIONBUTTON1'then return'SHIFT-2'end end
HUD.RebuildKeys();assert(HUD.KeyFor({id=A})=='S2','key text of the button')
-- slash commands
local say={};local oldPrint=print;print=function(...)say[#say+1]=table.concat({...},' ')end
SlashCmdList.FOREVERSIMBRIDGE('hud');assert(HUD.Config().enabled==false,'/fus hud switches off');SlashCmdList.FOREVERSIMBRIDGE('hud');assert(HUD.Config().enabled==true)
SlashCmdList.FOREVERSIMBRIDGE('hud verschieben');assert(HUD.Config().locked==false);SlashCmdList.FOREVERSIMBRIDGE('hud fixieren');assert(HUD.Config().locked==true)
SlashCmdList.FOREVERSIMBRIDGE('hud procc');MOCK.Advance(.7,.05);assert(HUD.frame:IsShown(),'/fus hud procc shows a demo');MOCK.Advance(8,.1)
SlashCmdList.FOREVERSIMBRIDGE('hud reset');print=oldPrint
assert(#say>=3,'the commands answer in the chat')
assert(#MOCK.errors==0,'no errors: '..tostring(MOCK.errors[1]))
for tag,n in pairs(MOCK.unknownMethods)do error('unknown widget method '..tag..' x'..n)end
io.write('hud ok\n')
