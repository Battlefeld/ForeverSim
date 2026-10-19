-- Random-suffix items: the stat table of the client may describe only the base item; the tooltip lines complete it.
local root=assert(arg[1]);dofile(root..'/_dev/harness/wowmock.lua');dofile(root..'/_dev/harness/gameapi.lua')
local function loadAddon(addon)
 for line in io.lines(root..'/'..addon..'/'..addon..'.toc')do
  local file=line:gsub(string.char(13),''):gsub(string.char(92),'/'):match('^%s*([^#].-%.lua)%s*$')
  if file then assert(loadfile(root..'/'..addon..'/'..file))(addon,{})end
 end
end
loadAddon('ForeverSimBridge')
MOCK.Fire('PLAYER_LOGIN');MOCK.Advance(.5,.05)
local P=FUSLive
ITEM_MOD_AGILITY_SHORT='Agility';ITEM_MOD_STAMINA_SHORT='Stamina'
MOCK.items[6512]={name="Disciple's Robe",quality=2,ilvl=10,req=8,class='Armor',sub='Cloth',loc='INVTYPE_ROBE',classID=4,subID=1,
 stats={RESISTANCE0_NAME=25},tooltip={{"Disciple's Robe of Agility"},{'Chest','Cloth'},{'25 Armor'},{'+4 Agility'},{'Requires Level 8'}}}
-- the base item link: nothing to add
local base=P.readItem('|cff1eff00|Hitem:6512::::::::12:::::::|h[Disciple'..string.char(39)..'s Robe]|h|r','Test')
assert(base and (base.rawStats.ITEM_MOD_AGILITY_SHORT or 0)==0,'a link without suffix is not touched')
-- the same item with random suffix -5 ("of Agility"): the tooltip says +4 Agility
local suffixed=P.readItem('|cff1eff00|Hitem:6512:0:0:0:0:0:-5:123456:12:::::::|h[Disciple'..string.char(39)..'s Robe of Agility]|h|r','Test')
assert(suffixed and suffixed.rawStats.ITEM_MOD_AGILITY_SHORT==4,'tooltip stat is picked up: '..tostring(suffixed and suffixed.rawStats.ITEM_MOD_AGILITY_SHORT))
assert((suffixed.stats.agi or 0)==4 or suffixed.stats.agi==nil,'agility also in the model stats if the model has the stat')
io.write('suffix stats tests passed\n')
