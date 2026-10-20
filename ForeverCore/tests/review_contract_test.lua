-- Regressions involving the real cache, simulation service and HUD together.
local root=assert(arg[1])
dofile(root..'/_dev/harness/wowmock.lua');dofile(root..'/_dev/harness/gameapi.lua')
local function loadAddon(addon)
 for line in io.lines(root..'/'..addon..'/'..addon..'.toc')do
  local file=line:gsub(string.char(13),''):gsub(string.char(92),'/'):match('^%s*([^#].-%.lua)%s*$')
  if file then assert(loadfile(root..'/'..addon..'/'..file))(addon,{})end
 end
end
loadAddon('ForeverSimBridge');loadAddon('ForeverCoreBridge')
UnitClass=function()return'Mage','MAGE',8 end
UnitLevel=function()return 60 end
MOCK.Fire('PLAYER_LOGIN');MOCK.Advance(.5,.05)
local C,Sim,Loot,HUD=ForeverCoreClient,ForeverCoreClient.Sim,ForeverCoreClient.Loot,ForeverSimHUD
C.queue={};C.pending=nil;C.engineRevision='review-engine'
ForeverCoreBridgeDB.sim=nil
local snapshot={class='MAGE',level=60,race='Troll',equipped={{id=100,slot='head',link='item:100'}},talents={},spells={{id=133}}}
FUSLive.capture=function()return snapshot end
C.simRevision=C.simRevision+1
local ctx=C.SimCharacterContext()
assert(ctx,'a real character context')
local before=C.SimCacheContext()
Sim.SetRotation({rotation='fire',context=ctx,engine=C.engineRevision,priority={{spellId=133}}})
assert(C.SimCharacterContext()==ctx,'choosing a rotation does not change its character context')
assert(C.SimCacheContext()~=before,'item comparisons do include the chosen rotation')
assert(not Sim.IsStale(Sim.Rotation()) and C.ActiveRotation()=='fire','a new rotation is immediately usable')
assert(select(2,HUD.Rows())=='engine','HUD follows the newly computed rotation')
Loot.cands={{id=100,pool='head',entry={state='ok',pct=99}}};Loot.context=C.SimCacheContext()
snapshot.equipped[1].id=101;snapshot.equipped[1].link='item:101';C.simRevision=C.simRevision+1
assert(Sim.IsStale(Sim.Rotation()) and C.ActiveRotation()==nil,'changed gear stops reuse of an old rotation')
assert(select(2,HUD.Rows())=='basic','HUD falls back when its simulation is stale')
local candidates=Loot.Candidates()
assert(not(candidates[1]and candidates[1].entry and candidates[1].entry.pct==99),'loot drops old values after gear changed')

-- Broken item metadata must not starve the entire remaining candidate list.
local cands={}
for i=1,80 do cands[i]={id=i,tries=7,pool='head',sources={}}end
cands[81]={id=81,pool='head',sources={}}
Loot.Candidates=function()return cands end
local calls=0
C.ItemResult=function(link)calls=calls+1;assert(link=='item:81');return{state='ok',pct=1,delta=1}end
local p=Loot.Poll(80)
assert(calls==1 and p.failed==80 and p.ready==1,'exhausted metadata retries leave room for later items')

local node=Sim.Model().talentTrees[1].talents[1]
local e={t=1,r=node.row,c=node.column,n=1}
assert(not Sim.Valid({e,e}),'duplicate talent places are rejected')
assert(not Sim.Valid({{t=1,r=node.row,c=node.column,n=.5}}),'fractional ranks are rejected')
assert(Sim.Import('FSB1:mage:'..Sim.Signature({e})..';')==nil,'trailing garbage is not silently imported')
assert(Sim.Import('FSB1:mage:1.0.1=1;;1.0.2=1')==nil,'empty text entries are not silently dropped')

UnitPower=function()return 30 end;UnitPowerMax=function()return 100 end
local mana={currentManaPercent={}}
assert(HUD.Condition({cmp={op='OpLt',lhs=mana,rhs={const={val='40%'}}}})==true,'APL percentages use fractions')
assert(HUD.Condition({cmp={op='OpLt',lhs=mana,rhs={const={val='20%'}}}})==false,'mana comparison is not always true')
assert(HUD.Condition({cmp={op='OpLt',lhs={const={val='-1s'}},rhs={const={val='0s'}}}})==true,'signed APL times retain their sign')

local UI=ForeverSimUI
UI.Window();UI.SelectTab('removed-old-tab')
assert(UI.activeTab==UI.Tabs()[1].key,'an obsolete saved tab falls back to a real tab')
assert(#MOCK.errors==0,MOCK.errors[1]and MOCK.errors[1].msg or'')
io.write('review contract tests passed\n')
