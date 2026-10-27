-- Read-only adapters for Blizzard's tracker. Hooks preserve its original scripts.
local FR=ForeverRoutes
local call=FR.Call
local tooltip,model
local bindings=setmetatable({},{__mode='k'})
function FR.HideQuestTooltip()
 if tooltip then tooltip:Hide()end;if model then model:Hide();call(model.ClearModel,model)end
end
function FR.ShowQuestTooltip(owner,q,index)
 if type(q)~='number'or q<=0 then return end
 if not tooltip then tooltip=CreateFrame('GameTooltip','ForeverRoutesQuestTooltip',UIParent,'GameTooltipTemplate')end
 tooltip:SetOwner(owner,'ANCHOR_RIGHT');tooltip:ClearLines()
 local name=C_QuestLog and call(C_QuestLog.GetTitleForQuestID,q)
 local meta=FR.Meta(q)
 tooltip:AddLine(name or(meta and meta.name)or('Quest '..q),.953,.78,.357)
 local objs=FR.Objectives({q=q})
 if index and objs[index]then tooltip:AddLine(objs[index].text or'Questziel',1,1,1,true)
 else for _,o in ipairs(objs)do tooltip:AddLine(o.text or'Questziel',o.finished and .31 or 1,o.finished and .89 or 1,o.finished and .43 or 1,true)end end
 local step=FR.Advance()
 if step and step.q==q then
  tooltip:AddLine('Route: '..FR.Text(step),.56,.64,.76,true)
  local hint=FR.Blocked(step)or FR.TravelHint(step);if hint then tooltip:AddLine(hint,1,.78,.36,true)end
 end
 -- A model is shown only for an explicit NPC id, never inferred from the objective count.
 local objective=index and FR.ObjectiveMeta(q,index)
 local npc=objective and objective.kind~='item'and objective.kind~='object'and objective.id
 if not npc and not index and step and step.q==q then npc=step.npc end
 if type(npc)=='number'and npc>0 then
  if not model then model=CreateFrame('PlayerModel','ForeverRoutesQuestModel',UIParent);model:SetSize(145,165);model:SetFrameStrata('TOOLTIP')end
  model:ClearAllPoints();model:SetPoint('TOPLEFT',tooltip,'BOTTOMLEFT',0,-3);call(model.ClearModel,model)
  call(model.SetCreature,model,npc);model:Show()
 elseif model then model:Hide();call(model.ClearModel,model)end
 tooltip:Show()
end
-- The adapter may be used by supported third-party trackers as well.
function FR.BindQuestLine(line,q,index,native)
 if not line or not line.HookScript or type(q)~='number'then return end
 local existing=bindings[line]
 if not existing then
  existing={};bindings[line]=existing
  line:HookScript('OnEnter',function(self)local b=bindings[self];if b and b.q then FR.ShowQuestTooltip(self,b.q,b.index)end end)
  line:HookScript('OnLeave',FR.HideQuestTooltip)
  line:HookScript('OnHide',FR.HideQuestTooltip)
 end
 existing.q,existing.index,existing.native=q,index,native
end
function FR.ScanQuestTracker()
 if call(InCombatLockdown)==true then return end
 -- Clear recycled blocks first; a reused frame must never retain another quest's identity.
 for _,b in pairs(bindings)do if b.native then b.q,b.index=nil,nil end end
 local tracker=QuestObjectiveTracker
 local blocks=tracker and tracker.usedBlocks
 if type(blocks)=='table'then
  for key,block in pairs(blocks)do
   if type(block)=='table'then
    local q=block.questID or block.id
    if type(q)~='number'and type(key)=='number'then q=key end
    if type(q)=='number'and FR.OnQuest(q)then
     FR.BindQuestLine(block.Header or block,q,nil,true)
     for _,line in pairs(type(block.lines)=='table'and block.lines or{})do
      if type(line)=='table'and type(line.objectiveIndex)=='number'then FR.BindQuestLine(line,q,line.objectiveIndex,true)end
     end
    end
   end
  end
 end
 -- Legacy WatchFrame exposes a quest-log index on the actual watch line.
 for i=1,100 do
  local line=_G['QuestWatchLine'..i]
  if line then
   local q=line.questID
   if not q and type(line.questLogIndex)=='number'and GetQuestLogTitle then local _,_,_,_,_,_,_,id=call(GetQuestLogTitle,line.questLogIndex);q=id end
   if type(q)=='number'and FR.OnQuest(q)then FR.BindQuestLine(line,q,line.objectiveIndex,true)end
  end
 end
end
