-- Prefetch: the items the player is about to look at are compared before they are hovered. After a change of gear,
-- talents or level (a new simulation state), when the quest log or the bags change and after a fight, the quest
-- rewards of the quests in the log (choices first) and the wearable items in the bags are asked for through the
-- usual item path (C.ItemResult: one cache, jobs of up to 24 items). Then hovering, accepting or handing in a quest
-- finds the result in the cache at once. At most LIMIT new items per simulation state (two jobs, two reply slots);
-- nothing in combat, nothing with the pixel transport off or the connection paused. /fc prefetch aus|an.
local C=ForeverCoreClient
local P={done={},rev=nil,count=0,LIMIT=48,DELAY=4}
C.Prefetch=P

local function db()ForeverCoreBridgeDB=ForeverCoreBridgeDB or{};return ForeverCoreBridgeDB end
local function call(fn,...)if type(fn)~='function'then return nil end;local ok,a,b,c=pcall(fn,...);if ok then return a,b,c end end
local function equippable(link)
 local f=(C_Item and C_Item.IsEquippableItem)or IsEquippableItem
 if type(f)~='function'then return true end
 return call(f,link)==true
end

function P.Enabled()
 local d=db()
 if not C.ItemResult or d.enabled==false or d.prefetch==false or d.pixelOff then return false end
 if InCombatLockdown and InCombatLockdown()then return false end
 return true
end

-- The reward links of the quests in the log: the choices, then the fixed rewards. The quest log selection the
-- player had is put back.
local function questRewards(out)
 local entries=call(GetNumQuestLogEntries)
 if type(entries)~='number' or entries<1 or type(SelectQuestLogEntry)~='function' or type(GetQuestLogItemLink)~='function' then return end
 local before=call(GetQuestLogSelection)
 for i=1,entries do
  local _,_,_,header=call(GetQuestLogTitle,i)
  if not header then
   call(SelectQuestLogEntry,i)
   for _,kind in ipairs({'choice','reward'})do
    local n=call(kind=='choice'and GetNumQuestLogChoices or GetNumQuestLogRewards)or 0
    for k=1,n do local link=call(GetQuestLogItemLink,kind,k);if link then out[#out+1]=link end end
   end
  end
 end
 if before then call(SelectQuestLogEntry,before)end
end

local function bagItems(out)
 local slots=(C_Container and C_Container.GetContainerNumSlots)or GetContainerNumSlots
 local linkOf=(C_Container and C_Container.GetContainerItemLink)or GetContainerItemLink
 if type(slots)~='function' or type(linkOf)~='function' then return end
 for bag=0,4 do
  for slot=1,(call(slots,bag)or 0)do
   local link=call(linkOf,bag,slot)
   if link then out[#out+1]=link end
  end
 end
end

-- The links to compare, quest rewards first, each once, only what can be worn.
function P.Links()
 local raw,seen,out={},{},{}
 questRewards(raw);bagItems(raw)
 for _,link in ipairs(raw)do
  local key=C.NormalizeLink and C.NormalizeLink(link)or link
  if not seen[key]and equippable(link)then seen[key]=true;out[#out+1]=link end
 end
 return out
end

-- Run asks for the items not known yet; it returns how many it queued.
function P.Run()
 P.scheduled=false
 if not P.Enabled()then return 0 end
 if P.rev~=C.simRevision then P.rev=C.simRevision;P.done={};P.count=0 end
 local n=0
 for _,link in ipairs(P.Links())do
  if P.count>=P.LIMIT then break end
  local key=C.NormalizeLink and C.NormalizeLink(link)or link
  if not P.done[key]then
   P.done[key]=true
   local ok,entry=pcall(C.ItemResult,link)
   if ok and type(entry)=='table' and entry.state=='busy' then P.count=P.count+1;n=n+1 end
  end
 end
 return n
end

function P.Schedule()
 if P.scheduled then return end
 P.scheduled=true
 if C_Timer and C_Timer.After then C_Timer.After(P.DELAY,P.Run)else P.Run()end
end

local frame=CreateFrame and CreateFrame('Frame')
if frame then
 for _,event in ipairs({'PLAYER_ENTERING_WORLD','QUEST_LOG_UPDATE','QUEST_ACCEPTED','BAG_UPDATE_DELAYED','PLAYER_EQUIPMENT_CHANGED','PLAYER_LEVEL_UP','PLAYER_REGEN_ENABLED','PLAYER_TALENT_UPDATE'})do pcall(frame.RegisterEvent,frame,event)end
 frame:SetScript('OnEvent',function()P.Schedule()end)
end
