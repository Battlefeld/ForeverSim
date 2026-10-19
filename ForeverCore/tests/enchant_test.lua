-- Enchants never count: not on new items and not on the worn gear (otherwise the worn item would always win).
local root=assert(arg[1]);dofile(root..'/_dev/harness/wowmock.lua');dofile(root..'/_dev/harness/gameapi.lua')
local function loadAddon(addon)
 for line in io.lines(root..'/'..addon..'/'..addon..'.toc')do
  local file=line:gsub(string.char(13),''):gsub(string.char(92),'/'):match('^%s*([^#].-%.lua)%s*$')
  if file then assert(loadfile(root..'/'..addon..'/'..file))(addon,{})end
 end
end
loadAddon('ForeverSimBridge');loadAddon('ForeverCoreBridge')
MOCK.Fire('PLAYER_LOGIN');MOCK.Advance(.5,.05)
local C=ForeverCoreClient;local P=FUSLive
-- every worn item carries the enchant 1887
local plainLink=GetInventoryItemLink
GetInventoryItemLink=function(unit,slot)
 local link=plainLink(unit,slot)
 if type(link)~='string' then return link end
 return(link:gsub('item:(%d+):%-?%d*','item:%1:1887',1))
end
assert(tostring(GetInventoryItemLink('player',5)):find(':1887',1,true),'the test gear is enchanted')
-- the snapshot of the sim addon reads the worn items without the enchant
local snap=P.capture(true)
assert(type(snap.equipped)=='table' and #snap.equipped>0,'worn items read')
for _,it in ipairs(snap.equipped)do
 assert(not tostring(it.link):find('1887',1,true),'worn item without enchant in the snapshot: '..tostring(it.link))
end
-- the job state for the PC has the worn links without the enchant
local ok,state=pcall(C.Capture,'item')
assert(ok and type(state)=='table' and type(state.sim)=='table','job state captured: '..tostring(state))
local seen=0
for _,it in ipairs(state.sim.equipped or{})do
 if it.link then seen=seen+1;assert(not tostring(it.link):find('1887',1,true),'worn link sent without enchant: '..tostring(it.link))end
end
assert(seen>0,'worn links are sent')
-- new items too
assert(C.WithoutEnchant('|Hitem:10518:1887::::::::12:1485|h')=='|Hitem:10518:::::::::12:1485|h','only the enchant field is emptied')
assert(C.WithoutEnchant('item:42')=='item:42','a bare id stays')
io.write('enchant tests passed\n')
