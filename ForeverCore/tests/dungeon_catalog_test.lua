-- Dungeon catalog of the simulator: dungeon list, bosses, instance detection, drop chances, pre-calculation.
local root=assert(arg[1]);dofile(root..'/_dev/harness/wowmock.lua');dofile(root..'/_dev/harness/gameapi.lua')
local function loadAddon(addon)
 local ns={}
 for line in io.lines(root..'/'..addon..'/'..addon..'.toc')do
  local file=line:gsub('\r',''):gsub('\\','/'):match('^%s*([^#].-%.lua)%s*$')
  if file then assert(loadfile(root..'/'..addon..'/'..file))(addon,ns)end
 end
end
loadAddon('ForeverSimBridge');loadAddon('ForeverCoreBridge')
UnitLevel=function()return 60 end
MOCK.Fire('PLAYER_LOGIN');MOCK.Advance(.5,.05)
assert(not _G.ForeverCoreFDQ and not _G.ForeverDungeonQuestAPI,'this test runs without ForeverDungeonQuest')
local api=_G.ForeverSimDungeonAPI;assert(api and api.schema==2,'simulator dungeon API missing')
-- list and bosses
local list=api.ListDungeons();assert(#list>=25,'dungeon list too short: '..#list)
local byKey={};for _,d in ipairs(list)do byKey[d.key]=d end
assert(byKey.dm and byKey.brd and byKey.scholo and byKey.thanes,'expected dungeons missing')
assert(byKey.dm.min==17 and byKey.dm.max==26,'level range of the Deadmines')
local bosses=api.ListBosses('dm');assert(#bosses>=5 and bosses[1].level~=nil,'Deadmines bosses with levels')
assert(#api.ListBosses('Blackrock Depths')>=5,'boss lookup by name')
-- instance detection
local function enter(name,id,mapID)
 GetInstanceInfo=function()return name,'party',1,'',5,0,false,id,0 end
 IsInInstance=function()return true,'party' end
 if mapID then C_Map=C_Map or{};C_Map.GetBestMapForUnit=function()return mapID end end
end
enter('Blackrock Depths',230);local brd=api.InstanceContext()
assert(brd and brd.instance and #brd.items>=100 and brd.level==60,'BRD context')
enter('The Deadmines',36);local dm=api.InstanceContext();assert(dm and #dm.items>=45,'Deadmines context: '..tostring(dm and #dm.items))
enter('Dire Maul',429);local dmaul=api.InstanceContext();assert(dmaul and #dmaul.items>#api.Context('dme').items,'wings of Dire Maul are merged')
enter('Scarlet Monastery',189,302);local sm=api.InstanceContext();assert(sm and sm.name:find('Graveyard',1,true),'scarlet wing by map: '..tostring(sm and sm.name))
enter('Sunken Temple',0);assert(api.InstanceContext(),'name fallback for an unknown instance id')
enter('Nowhere',99999);assert(api.InstanceContext()==nil,'unknown instance has no context')
IsInInstance=function()return false,'none' end;assert(api.InstanceContext()==nil,'no context outside instances')
-- drop chances and loot candidates
local anyChance
for _,d in ipairs(FUSLiveDungeonData.dungeons)do for _,g in ipairs(d.groups)do for _,it in ipairs(g.items)do if it[4]and not anyChance then anyChance=it[1] end end end end
assert(anyChance and api.ChanceText(anyChance):find('Drop%-Chance'),'chance text')
local cands=api.LootCandidates(30,40);assert(#cands>0 and #cands<=40,'loot candidates');for _,c in ipairs(cands)do assert(c.requiredLevel<=30 and c.requiredLevel>=18,'candidate level window')end
io.write('dungeon catalog tests passed ('..#list..' dungeons)\n')
