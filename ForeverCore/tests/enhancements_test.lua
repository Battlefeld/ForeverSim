local root=assert(arg[1])
dofile(root..'/_dev/harness/wowmock.lua');dofile(root..'/_dev/harness/gameapi.lua')
for _,addon in ipairs({'ForeverSimBridge','ForeverCoreBridge'})do
 for line in io.lines(root..'/'..addon..'/'..addon..'.toc')do
  local f=line:gsub(string.char(13),''):gsub(string.char(92),'/'):match('^%s*([^#].-%.lua)%s*$')
  if f then assert(loadfile(root..'/'..addon..'/'..f))(addon,{})end
 end
end
UnitClass=function()return'Mage','MAGE' end;UnitLevel=function()return 60 end
MOCK.Fire('PLAYER_LOGIN');MOCK.Advance(.5,.05)
local C=ForeverCoreClient;local E=C.Enhancements;local S=C.Sim;local UI=ForeverSimUI
local enchant=24
GetInventoryItemID=function(_,slot)if slot==5 then return 10021 end end
GetInventoryItemLink=function(_,slot)if slot==5 then return'|Hitem:10021:'..enchant..':0:0|h[Weste]|h'end end
assert(E.CaptureEnchants().chest==24,'capture the real enchant independently of stripped item links')
local captured=C.Capture('enhancements')
assert(captured.sim.enhancementEnchants.chest==24,'enhancement job includes actual current effects')
for _,item in ipairs(captured.sim.equipped or{})do assert(not item.link:find(':24:',1,true),'normal item links still strip enchants')end
local jobs={};C.Request=function(kind,payload,cb,opts)jobs[#jobs+1]={kind=kind,payload=payload,cb=cb,opts=opts};return true end
UI.Window();UI.Open('loot');local state=UI.loot
state.viewEnch.__scripts.OnClick(state.viewEnch)
state.enchRun.__scripts.OnClick(state.enchRun)
local job=jobs[#jobs];assert(job.kind=='enhancements'and E.running and job.opts.timeout==1200)
assert(E.Run()==false,'do not enqueue duplicate runs')
job.cb({baselineDps=100,recommendations={{slot='chest',name='Beste Brust-VZ',pct=4,delta=4},{slot='food',name='Bestes Essen',pct=2,delta=2}},foods={{name='Bestes Essen',effect='14 Spell Damage',pct=2}},tested=90,skipped={unmodeled=68},failed=0})
assert(not E.running and E.Result())
local found=false
for _,row in ipairs(state.enchRows)do if row.label:GetText()=='Brust'then found=row.name:GetText()=='Beste Brust-VZ'and row.status:GetText():find('4',1,true)end end
assert(found,'show best VZ per slot and DPS gain')
assert(state.foodRows[1]:GetText():find('Bestes Essen',1,true),'food shown')
assert(state.enchRankRows[1].name:GetText():find('Beste Brust',1,true),'largest gain first')
assert(state.enchRight:IsShown()and not state.gearRight:IsShown(),'separate VZ ranking and gear details')
enchant=25;local _,stale=E.Result();assert(stale,'changing only the enchant invalidates VZ results')
UI.lootRefresh();assert(state.enchSummary:GetText():find('veraltet',1,true))
state.viewGear.__scripts.OnClick(state.viewGear);assert(state.gearRight:IsShown()and not state.enchRight:IsShown())
assert(#MOCK.errors==0,'UI errors')
for method in pairs(MOCK.unknownMethods)do error('unknown widget method '..method)end
io.write('enhancements UI and bridge passed\n')
