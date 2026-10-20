-- The "Beute" tab: filters, the Pre-BiS paper doll, the selected slot, the enchant view, the lock below level 50.
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
local C=ForeverCoreClient;local Sim=C.Sim;local Loot=C.Loot;local UI=assert(ForeverSimUI)
C.queue={};C.pending=nil;C.Say=function()end
ForeverCoreBridgeDB.sim=nil
C_Item.GetItemInfoInstant=function()return nil end;GetItemInfoInstant=C_Item.GetItemInfoInstant
local worn={[5]=1111,[15]=2222,[1]=3333}
GetInventoryItemID=function(u,slot)return worn[slot]end
GetInventoryItemLink=function(u,slot)if not worn[slot]then return nil end;return'|cff0070dd|Hitem:'..worn[slot]..':'..(slot==5 and 2564 or 0)..':0:0|h[Getragen '..worn[slot]..']|h|r'end
Sim.Store().presets={gear={{name='Pre-BiS',items={{slot=4,id=8001},{slot=10,id=8002}}}},talents={},builds={},layout={}}
local values={[8001]=3.9,[8002]=1.1}
C.ItemResult=function(link)local id=tonumber(link:match('item:(%d+)'));return{state='ok',pct=values[id]or((id%7)-4)*0.3,delta=1}end
local jobs={};C.Request=function(kind,payload,cb)jobs[#jobs+1]={kind=kind,cb=cb};return true end

UI.Window();UI.Open('loot')
local S=UI.loot
assert(S.left and S.mid and S.right and not S.locked and #MOCK.errors==0,'built: '..tostring(MOCK.errors[1]))
assert(S.slots.chest and S.slots.finger2 and S.slots.ranged,'a widget for every slot')
-- the weights were asked for when the tab opened
local wj;for _,j in ipairs(jobs)do if j.kind=='weights'then wj=j end end
assert(wj,'weights job sent')
wj.cb({rows={{key='StatSpellDamage',perPoint=1},{key='StatSpellCritRating',perPoint=.5},{key='StatIntellect',perPoint=.25}}})
assert(S.weightRows[1].frame:IsShown() and S.weightRows[1].name:GetText()=='Zauberschaden' and S.weightRows[4].frame:IsShown()==false,'weights shown')
-- values arrive by polling
MOCK.Advance(.1,.05);Loot.Poll(10000);UI.lootRefresh()
local chest=S.slots.chest
assert(chest.name:GetText()~='' and chest.gain:GetText()=='+3,9 %','the best chest item and its gain: '..tostring(chest.gain:GetText()))
assert(chest.star:IsShown(),'a star for the MythicSim item')
assert(S.total:GetText():find('%%')and S.totalNote:GetText():find('Upgrade',1,true),'total: '..S.total:GetText()..' / '..S.totalNote:GetText())
-- a slot without an upgrade shows what is worn
local head=S.slots.head
assert(head.gain:GetText()=='schon bestes' or head.gain:GetText():find('%%'),'head: '..tostring(head.gain:GetText()))
-- selecting a slot fills the right column
chest.__scripts.OnClick(chest)
assert(S.sel=='chest' and S.detailTitle:GetText()=='BRUST','detail title: '..S.detailTitle:GetText())
assert(S.itemGain:GetText():find('3,9',1,true) and S.itemWorn:GetText():find('Getragen',1,true),'detail: '..S.itemGain:GetText()..' / '..S.itemWorn:GetText())
assert(S.itemSources:GetText():find('MythicSim',1,true),'sources: '..S.itemSources:GetText())
assert(S.farmRows[1].frame:IsShown() and S.farmRows[1].value:GetText():find('/Lauf',1,true),'a place to farm: '..tostring(S.farmRows[1].value:GetText()))
-- filters
local function check(label)for _,c in ipairs(S.checks)do if c.text:GetText()==label then return c end end;error('no check '..label)end
local before=#Loot.Candidates()
local c=check('Dungeon-Beute');c.__scripts.OnClick(c);assert(Loot.Filter().dungeon==false and #Loot.Candidates()<before,'dungeons switched off')
c.__scripts.OnClick(c);assert(Loot.Filter().dungeon==true)
-- run everything
S.run.__scripts.OnClick(S.run)
assert(Loot.running or Loot.LastRun(),'the run started')
local guard=0;while Loot.running and guard<200 do guard=guard+1;MOCK.Advance(3,1)end
assert(not Loot.running and S.runInfo:GetText():find('Items',1,true),'run info: '..S.runInfo:GetText())
-- the enchant view
S.viewEnch.__scripts.OnClick(S.viewEnch)
assert(S.enchBox:IsShown() and not S.gearBox:IsShown(),'second view')
local seenChest,seenHead
for _,r in ipairs(S.enchRows)do
 if r.frame:IsShown()then
  if r.label:GetText()=='Brust'then seenChest=r.status:GetText()end
  if r.label:GetText()=='Kopf'then seenHead=r.status:GetText()end
 end
end
assert(seenChest=='verzaubert' and seenHead=='keine Verzauberung','enchant state from the item link: '..tostring(seenChest)..' / '..tostring(seenHead))
assert(S.enchSummary:GetText():find('nicht verzaubert',1,true) or S.enchSummary:GetText():find('noch nicht',1,true),'summary: '..S.enchSummary:GetText())
S.viewGear.__scripts.OnClick(S.viewGear);assert(S.gearBox:IsShown() and not S.enchBox:IsShown())
-- below level 50 only a notice
local def;for _,t in ipairs(UI.Tabs())do if t.key=='loot'then def=t end end
level=40;local page=CreateFrame('Frame',nil,UIParent)
for k in pairs(S)do S[k]=nil end;S.slots={};S.weightRows={};S.altRows={};S.farmRows={};S.enchRows={}
def.build(page);assert(UI.loot.locked and not UI.loot.left,'level 40: notice only')
level=60;def.show(page);assert(UI.loot.left and not UI.loot.locked,'level 60 builds the tab')
assert(#MOCK.errors==0,'no errors: '..tostring(MOCK.errors[1]))
for tag,n in pairs(MOCK.unknownMethods)do error('unknown widget method '..tag..' x'..n)end
io.write('loot tab ok\n')
