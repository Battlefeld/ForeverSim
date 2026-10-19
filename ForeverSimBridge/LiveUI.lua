-- Relevant-item-only live scheduling; no bag/ordinary-drop simulation.
local P=FUSLive;local queue={};local active=nil;local frame=CreateFrame('Frame');local spent,maxSlice=0,0
local clock=debugprofilestop or function()return GetTime()*1000 end
local sliceStart=0;local budget=1.0;local sliceActions=0
-- P.jobBudgetMs lets a caller use more time per frame.
P.checkpoint=function()sliceActions=sliceActions+1;if active and ((debugprofilestop and clock()-sliceStart>=(P.jobBudgetMs or budget))or(not debugprofilestop and sliceActions>=3))then coroutine.yield()end end
P.metrics={jobs=0,frames=0,maxSliceMs=0,cancelled=0}
local function valid(job)return job.revision==P.revision and(not job.valid or job.valid())end
local function complete(job,result,err)
 if job.completed then return end
 job.completed=true
 if type(job.done)=='function' then local ok,problem=pcall(job.done,result,err);if not ok then P.lastLiveError=tostring(problem)end end
end
local function discard(job,reason)
 P.metrics.cancelled=P.metrics.cancelled+1;complete(job,nil,reason or 'Kontext geändert – erneut berechnen.')
end
function P.enqueue(fn,done,stillValid,priority)
 local job={revision=P.revision,fn=fn,done=done,valid=stillValid,priority=priority};if priority then table.insert(queue,1,job)else queue[#queue+1]=job end;return job
end
frame:SetScript('OnUpdate',function()
 if InCombatLockdown and InCombatLockdown()then return end
 if not active then while #queue>0 do local j=table.remove(queue,1)if valid(j)then active=j;active.co=active.co or coroutine.create(j.fn);break else discard(j) end end end
 if not active then return end
 if not valid(active)then local job=active;active=nil;discard(job);return end
 -- Roll/quest decisions preempt a long dungeon pre-cache job between Lua yields.
 if not active.priority and queue[1] and queue[1].priority then table.insert(queue,2,active);active=nil;return end
 sliceStart=clock();sliceActions=0;local ok,result=coroutine.resume(active.co);spent=clock()-sliceStart;maxSlice=math.max(maxSlice,spent);P.metrics.frames=P.metrics.frames+1;P.metrics.maxSliceMs=maxSlice
 if not ok then local job=active;active=nil;complete(job,nil,tostring(result))
 elseif coroutine.status(active.co)=='dead'then local job=active;active=nil;P.metrics.jobs=P.metrics.jobs+1;if valid(job)then complete(job,result)else discard(job)end end
end)
-- Blizzard's reward and roll controls may be protected. Never attach frames,
-- store addon fields or install scripts on them; our own read-only HUDs only.
local panels={}
local panelPool={}
local nextPanelIndex=0
local function belowMinimumLevel()
 local level=UnitLevel and UnitLevel('player')
 if P.publicNumber then level=P.publicNumber(level)end
 return type(level)=='number' and level<P.minSimLevel()
end
local function uiProblem(err)
 P.lastLiveError=tostring(err or 'Unbekannter SIM-Fehler')
 return 'SIM derzeit nicht verfügbar'
end
local function inCombat()
 return InCombatLockdown and InCombatLockdown()==true
end
local function panel(rollID)
 if panels[rollID] then return panels[rollID] end
 local reused=table.remove(panelPool)
 if reused then panels[rollID]=reused;return reused end
 local slot=nextPanelIndex
 nextPanelIndex=nextPanelIndex+1
 local f=CreateFrame('Frame',nil,UIParent)
 f.slot=slot
 f:SetSize(255,22)
 f:SetFrameStrata('DIALOG')
 local bg=f:CreateTexture(nil,'BACKGROUND');bg:SetAllPoints();bg:SetColorTexture(.03,.03,.04,.94)
 f.label=f:CreateFontString(nil,'OVERLAY','GameFontNormalSmall');f.label:SetPoint('TOPLEFT',7,-5);f.label:SetWidth(243);f.label:SetHeight(13);f.label:SetWordWrap(false);f.label:SetJustifyH('LEFT')
 f:EnableMouse(false) -- never swallow clicks meant for Blizzard's roll buttons
 f:Hide()
 panels[rollID]=f
 return f
end
-- The score sits directly under Blizzard's roll window (GroupLootFrameN); without it, in the old column at the screen edge.
local function place(f,rollID)
 local gl=P.itemScore and P.itemScore.RollFrame(rollID)
 f:ClearAllPoints()
 if gl then f:SetPoint('TOPLEFT',gl,'BOTTOMLEFT',0,-2);f:SetWidth(math.max(255,gl:GetWidth()or 255))
 else f:SetPoint('TOPRIGHT',UIParent,'TOPRIGHT',-25,-190-(f.slot or 0)*28);f:SetWidth(255) end
end
local function display(rollID,result,err)
 if P.itemScore then P.itemScore.ClearMarks('roll'..rollID) end
 local f=panel(rollID);place(f,rollID);f:Show()
 if err then f.label:SetText('|cffffaa66'..uiProblem(err)..'|r');return end
 if not result.eligible then f.label:SetText('|cffffaa66'..(result.reason or 'Nicht bewertbar')..'|r');return end
 local pct=result.percent and (string.format('%+.1f %% DPS',result.percent):gsub('%.',',',1))or 'Kein Vergleich';local color=result.status=='upgrade'and '80ff80'or(result.status=='downgrade'and 'ff8080'or 'ddddaa')
 f.label:SetText('ForeverSim: |cff'..color..pct..'|r')
 if result.status=='upgrade' and P.itemScore then local gl,i=P.itemScore.RollFrame(rollID);local need=P.itemScore.RollNeedButton(gl,i);if need then P.itemScore.ClearMarks('roll'..rollID);P.itemScore.GoldBorder('roll'..rollID,need,3) end end
end
local function current()
 local snap=P.capture and P.capture(true)if not snap then error('Charakterdaten fehlen')end local profile=P.normalizeSnapshot(snap);profile.spells=snap.spells
 local data=FUSLiveData[profile.class]if not data then error('Klassenmodul fehlt',0)end local issue=P.coverage(data,profile)if issue then error(issue,0)end
 return data,profile
end
local function evaluate(item,done,stillValid)
 local data,profile;local ok,err=pcall(function()data,profile=current()end)if not ok then done(nil,err);return end
 P.enqueue(function()local stats=P.combine(profile.equipped);local base=P.best(data,profile,stats,nil);local result=P.compare(data,profile,profile.equipped,item,base);result.profile=profile;return result end,done,stillValid,true)
end
local rolls={}
local function requestRoll(id)
 -- With ForeverCore connected the roll value comes from MythicSim (ForeverCoreBridge, UIPanels.lua), the same
 -- number the dungeon list shows; the old in-game estimate stays the fallback without ForeverCore.
 local core=_G.ForeverCoreClient
 if core and core.ExternalEnabled and core.ExternalEnabled() and core.UI and core.UI.ShowRoll then
  if panels[id] then panels[id]:Hide() end
  return true
 end
 -- Some loot events arrive during combat. Defer all UI/item inspection until
 -- the client has left combat and protected/secret values are no longer needed.
 if inCombat() then return false end
 if belowMinimumLevel() then
  if panels[id] then panels[id]:Hide() end
  return true
 end
 local link=GetLootRollItemLink and GetLootRollItemLink(id)
 if not link then return false end
 local item=P.readItem and P.readItem(link,'Dungeon-Würfelfenster')
 if not item then return false end
 local token={};rolls[id]=token
 local f=panel(id);place(f,id);f:Show();f.label:SetText('ForeverSim: wird berechnet …')
 evaluate(item,function(result,err)
  if rolls[id]~=token then return end
  display(id,result,err)
 end,function()
  -- Do not inspect or mutate Blizzard roll frames. Only use public roll API.
  if rolls[id]~=token or inCombat() then return false end
  return not GetLootRollTimeLeft or (GetLootRollTimeLeft(id) or 0)>0
 end)
 return true
end
-- Quest rewards: percentages sit on Blizzard's own reward buttons (ItemScore.lua draws the marks).
local function clearQuestLabels() if P.itemScore then P.itemScore.ClearMarks('quest') end end
local events=CreateFrame('Frame')
for _,e in ipairs({'PLAYER_REGEN_DISABLED','PLAYER_REGEN_ENABLED','START_LOOT_ROLL','CANCEL_LOOT_ROLL','GET_ITEM_INFO_RECEIVED','PLAYER_LEVEL_UP','PLAYER_EQUIPMENT_CHANGED','SPELLS_CHANGED','CHARACTER_POINTS_CHANGED','LEARNED_SPELL_IN_TAB','PLAYER_ENTERING_WORLD','PLAYER_TALENT_UPDATE'})do pcall(events.RegisterEvent,events,e)end
local pendingRolls={}
local function later(fn)
 local function guarded()if not(P.itemScore and P.itemScore.Enabled())then return end;fn()end
 if C_Timer and C_Timer.After then C_Timer.After(0,guarded)else guarded()end
end
local function clearLabels()
 for id,f in pairs(panels)do f:Hide();panelPool[#panelPool+1]=f;panels[id]=nil end
 if P.itemScore then P.itemScore.ClearMarks('roll') end
 clearQuestLabels()
end
local function invalidate()
 P.invalidate();clearLabels();for id in pairs(rolls)do pendingRolls[id]=true end;rolls={}
 later(function()for id in pairs(pendingRolls)do if requestRoll(id)then pendingRolls[id]=nil end end end)
 if P.itemScore then P.itemScore.Changed()end
end
events:SetScript('OnEvent',function(_,e,id)
 if not(P.itemScore and P.itemScore.Enabled())then return end
 if e=='PLAYER_REGEN_DISABLED' then clearLabels();return
 elseif e=='PLAYER_REGEN_ENABLED' then
  later(function()
   if inCombat() then return end
   for roll in pairs(pendingRolls)do if requestRoll(roll)then pendingRolls[roll]=nil end end
  end)
  return
 elseif e=='START_LOOT_ROLL'then pendingRolls[id]=true;later(function()if requestRoll(id)then pendingRolls[id]=nil end end)
 elseif e=='CANCEL_LOOT_ROLL'then
  if P.itemScore then P.itemScore.ClearMarks('roll'..tostring(id)) end
  rolls[id]=nil;pendingRolls[id]=nil
  if panels[id]then panels[id]:Hide();panelPool[#panelPool+1]=panels[id];panels[id]=nil end
 elseif e=='GET_ITEM_INFO_RECEIVED'then if not inCombat() then for roll in pairs(pendingRolls)do if requestRoll(roll)then pendingRolls[roll]=nil end end end
 elseif P.stateChanged(events) then invalidate()end
end)
P.pendingJobs=function()return #queue+(active and 1 or 0)end
-- Cancel cooperative jobs between slices. Notify owners so their busy flags clear.
P.cancelJobs=function(reason)
 local cancelled=queue;queue={}
 if active then table.insert(cancelled,1,active);active=nil end
 for _,job in ipairs(cancelled)do discard(job,reason or 'Berechnung abgebrochen.')end
end

