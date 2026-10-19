-- /fc dungeon: drops of the current dungeon by boss with drop chance and DPS gain
local root=assert(arg[1]);dofile(root..'/_dev/harness/wowmock.lua');dofile(root..'/_dev/harness/gameapi.lua')
local function loadAddon(addon)
 for line in io.lines(root..'/'..addon..'/'..addon..'.toc')do
  local file=line:gsub(string.char(13),''):gsub(string.char(92),'/'):match('^%s*([^#].-%.lua)%s*$')
  if file then assert(loadfile(root..'/'..addon..'/'..file))(addon,{})end
 end
end
loadAddon('ForeverSimBridge');loadAddon('ForeverCoreBridge')
MOCK.Fire('PLAYER_LOGIN');MOCK.Advance(.5,.05)
local C=ForeverCoreClient;local D=C.DungeonReport
assert(D and D.Report,'dungeon report module loaded')
local lines={};C.Say=function(t)lines[#lines+1]=tostring(t)end
local function text()return table.concat(lines,' | ')end
-- no instance: a hint, no error
_G.ForeverSimDungeonAPI={InstanceContext=function()return nil end}
assert(D.Report()==false and text():find('Kein bekannter Dungeon',1,true),'outside a dungeon: '..text())
-- a fake dungeon with two bosses
local sources={[11]={{dungeon='Ragefire Chasm',boss='Taragaman',chance=12}},[12]={{dungeon='Ragefire Chasm',boss='Taragaman',chance=30}},[13]={{dungeon='Ragefire Chasm',boss='Oggleflint',chance=8.5}},[14]={{dungeon='Other Place',boss='Elsewhere',chance=5}}}
_G.ForeverSimDungeonAPI={
 InstanceContext=function()return{name='Ragefire Chasm',items={11,12,13,14},level=12}end,
 Sources=function(id)return sources[id]end}
local results={[11]={state='ok',pct=2.5,delta=1.2},[12]={state='ok',pct=0,delta=0},[13]={state='ok',pct=-1,delta=-0.5},[14]={state='ok',pct=9,delta=4}}
C.ItemResult=function(link)local id=tonumber(tostring(link):match('item:(%d+)'));return results[id]or{state='busy'}end
lines={}
assert(D.Report()==true)
local t=text()
assert(t:find('Ragefire Chasm: 4 Drops',1,true),'summary: '..t)
assert(t:find('Taragaman',1,true) and t:find('+2.50',1,true) and t:find('Drop 12 %',1,true),'upgrade with boss and chance: '..t)
assert(not t:find('Oggleflint',1,true),'downgrades are hidden by default: '..t)
-- the item of another dungeon is not listed under its own boss as if it belonged here
assert(t:find('3 Drops',1,true) or t:find('4 Drops',1,true),'counted')
lines={};D.Report(true)
assert(text():find('Oggleflint',1,true) and text():find('-1.00',1,true) and text():find('Drop 8,5 %',1,true),'everything with "alle": '..text())
-- values still being computed: the report waits and then prints
results[11]=nil
lines={};D.Report()
assert(text():find('werden berechnet',1,true),'waits for pending values: '..text())
results[11]={state='ok',pct=2.5,delta=1.2}
MOCK.Advance(5,.1)
assert(text():find('+2.50',1,true),'prints once the values are ready: '..text())
assert(text():find('Stand der 4 Drops',1,true),'the breakdown line is printed: '..text())
-- items without readable data are sorted: not equipment / unsupported slot do not wait, unloaded ones do
do
 lines={}
 _G.ForeverSimDungeonAPI={
  InstanceContext=function()return{name='Ragefire Chasm',items={21,22,23},level=12}end,
  Sources=function(id)return{{dungeon='Ragefire Chasm',boss='Bazzalan',chance=10}}end}
 C.ItemResult=function()return nil end
 C_Item=C_Item or{}
 local factsById={[21]={21,'Consumable','Potion','',nil,0,1},[22]={22,'Armor','Misc','INVTYPE_THROWN',nil,4,0},[23]=nil}
 C_Item.GetItemInfoInstant=function(id)local f=factsById[id];if f then return f[1],f[2],f[3],f[4],f[5],f[6],f[7]end end
 C_Item.GetItemInfo=function(id)if id==22 then return 'Throwing Thing' end end
 D.Report(false,1);MOCK.Advance(14,.1)
 local t=text()
 assert(t:find('keine Ausruestung 1',1,true) and t:find('Slot nicht unterstuetzt 1',1,true) and t:find('Daten nicht geladen 1',1,true),'classified: '..t)
 assert(t:find('Throwing Thing',1,true) and t:find('INVTYPE_THROWN',1,true),'examples show name and slot: '..t)
 assert(t:find('(1 noch offen)',1,true),'only the unloaded item is still open: '..t)
end
-- recipes and patterns are not equipment: nothing to wait for
do
 lines={}
 _G.ForeverSimDungeonAPI={
  InstanceContext=function()return{name='Ragefire Chasm',items={31,32},level=12}end,
  Sources=function(id)return{{dungeon='Ragefire Chasm',boss='Bazzalan',chance=10}}end}
 C.ItemResult=function()return nil end
 C_Item=C_Item or{}
 C_Item.GetItemInfoInstant=function(id)return id,'Recipe','Leatherworking','INVTYPE_NON_EQUIP_IGNORE',nil,9,5 end
 C_Item.GetItemInfo=function(id)return 'Pattern: Gloves' end
 D.Report(false,1,true);MOCK.Advance(2,.1)
 assert(text():find('keine Ausruestung 2',1,true) and not text():find('noch offen',1,true),'recipes are not equipment and do not keep the list waiting: '..text())
end
-- the automatic list waits in the background until the values are there and prints once
do
 lines={}
 _G.ForeverSimDungeonAPI={
  InstanceContext=function()return{name='Ragefire Chasm',items={41},level=12}end,
  Sources=function(id)return{{dungeon='Ragefire Chasm',boss='Bazzalan',chance=10}}end}
 local ready=false
 C.ItemResult=function()if ready then return{state='ok',pct=3,delta=1}end;return{state='busy'}end
 C_Item=C_Item or{};C_Item.GetItemInfoInstant=nil;C_Item.GetItemInfo=nil
 D.Report(false,1,true)
 MOCK.Advance(30,.5)
 assert(not text():find('verbessern',1,true),'while values are missing the automatic list prints nothing final: '..text())
 ready=true
 MOCK.Advance(8,.5)
 assert(text():find('+3.00',1,true),'once the values are there the list appears by itself: '..text())
end
io.write('dungeon report tests passed\n')
