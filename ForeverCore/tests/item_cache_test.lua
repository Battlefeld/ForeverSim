-- Regression: buffs/auras/pets/forms/zoning must never invalidate item results.
-- Only level, worn gear and talent ranks may.
local root=assert(arg[1]);dofile(root..'/_dev/harness/wowmock.lua');dofile(root..'/_dev/harness/gameapi.lua')
local function loadAddon(addon)
 local ns={}
 for line in io.lines(root..'/'..addon..'/'..addon..'.toc')do
  local file=line:gsub('\r',''):gsub('\\','/'):match('^%s*([^#].-%.lua)%s*$')
  if file then assert(loadfile(root..'/'..addon..'/'..file))(addon,ns)end
 end
end
loadAddon('ForeverSimBridge');loadAddon('ForeverCoreBridge')
MOCK.Fire('PLAYER_LOGIN');MOCK.Advance(.5,.05)
local P=FUSLive;assert(P and P.stateSignature,'signature API missing')
MOCK.Fire('PLAYER_EQUIPMENT_CHANGED');MOCK.Advance(.5,.05)   -- first sight establishes the baseline
local rev=P.revision
for _,e in ipairs({'UNIT_AURA','UNIT_PET','UPDATE_SHAPESHIFT_FORM','UNIT_INVENTORY_CHANGED','SPELLS_CHANGED','PLAYER_ENTERING_WORLD','ZONE_CHANGED_NEW_AREA','BAG_UPDATE_DELAYED','QUEST_LOG_UPDATE','PLAYER_REGEN_ENABLED'})do
 for i=1,5 do MOCK.Fire(e,'player');MOCK.Advance(.2,.05)end
end
assert(P.revision==rev,'noise events invalidated results: revision '..rev..' -> '..P.revision)
-- A real gear change must invalidate.
local oldLink=GetInventoryItemLink
GetInventoryItemLink=function(u,slot)if slot==8 then return '|cff1eff00|Hitem:2000:0:0:0|h[Boots]|h|r'end;return oldLink and oldLink(u,slot)end
MOCK.Fire('PLAYER_EQUIPMENT_CHANGED');MOCK.Advance(.2,.05)
assert(P.revision>rev,'real gear change did not invalidate')
-- A level-up must invalidate.
local rev2=P.revision;local oldLevel=UnitLevel;UnitLevel=function(u)return (oldLevel(u) or 1)+1 end
MOCK.Fire('PLAYER_LEVEL_UP');MOCK.Advance(.2,.05)
assert(P.revision>rev2,'level up did not invalidate')
io.write('item cache tests passed\n')
