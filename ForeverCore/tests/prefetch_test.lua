-- Prefetch asks for quest rewards first, then bag items, each once per simulation state, at most LIMIT, and
-- never in combat or with the connection paused.
local root=assert(arg[1]);dofile(root..'/_dev/harness/wowmock.lua');dofile(root..'/_dev/harness/gameapi.lua')
for _,file in ipairs({'Protocol.lua','Bridge.lua','Adapters.lua','Prefetch.lua'})do assert(loadfile(root..'/ForeverCoreBridge/'..file))('ForeverCoreBridge',{})end
local C=ForeverCoreClient
local P=assert(C.Prefetch,'prefetch missing')
ForeverCoreBridgeDB=ForeverCoreBridgeDB or{};ForeverCoreBridgeDB.enabled=true
-- a quest log with one header and two quests, and two bags
local quests={{header=true},{choices={'|Hitem:100|h[A]|h','|Hitem:101|h[B]|h'},rewards={'|Hitem:102|h[C]|h'}},{choices={},rewards={'|Hitem:100|h[A]|h'}}}
local selected=3
GetNumQuestLogEntries=function()return #quests end
GetQuestLogTitle=function(i)return 'q'..i,1,nil,quests[i].header end
GetQuestLogSelection=function()return selected end
SelectQuestLogEntry=function(i)selected=i end
GetNumQuestLogChoices=function()return #(quests[selected].choices or{})end
GetNumQuestLogRewards=function()return #(quests[selected].rewards or{})end
GetQuestLogItemLink=function(kind,k)local q=quests[selected];return(kind=='choice'and q.choices or q.rewards)[k]end
C_Container={GetContainerNumSlots=function(bag)return bag==0 and 3 or 0 end,GetContainerItemLink=function(bag,slot)return({'|Hitem:200|h[D]|h','|Hitem:999|h[Potion]|h','|Hitem:101|h[B]|h'})[slot]end}
IsEquippableItem=function(link)return not tostring(link):find('999',1,true)end
C_Item=C_Item or{};C_Item.IsEquippableItem=IsEquippableItem
local asked={}
C.ItemResult=function(link)asked[#asked+1]=link;return{state='busy'}end
selected=3
local links=P.Links()
assert(#links==4,'expected 4 wearable links, got '..#links)
assert(links[1]:find('100')and links[2]:find('101')and links[3]:find('102')and links[4]:find('200'),'quest rewards first, then bags, each once')
assert(selected==3,'the quest log selection was not restored')
assert(P.Run()==4 and #asked==4,'first run must ask for every item')
assert(P.Run()==0 and #asked==4,'the same state must not ask again')
C.simRevision=C.simRevision+1
assert(P.Run()==4,'a new state must ask again')
P.LIMIT=2;C.simRevision=C.simRevision+1;asked={}
assert(P.Run()==2,'the limit must hold')
P.LIMIT=48;C.simRevision=C.simRevision+1
InCombatLockdown=function()return true end
assert(P.Run()==0,'nothing in combat');InCombatLockdown=function()return false end
ForeverCoreBridgeDB.prefetch=false
assert(P.Run()==0,'switched off');ForeverCoreBridgeDB.prefetch=nil
ForeverCoreBridgeDB.pixelOff=true
assert(P.Run()==0,'pixel transport off');ForeverCoreBridgeDB.pixelOff=nil
print('prefetch tests passed')
