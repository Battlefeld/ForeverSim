-- Relevant-item-only live scheduling; no bag/ordinary-drop simulation.
local P=FUSLive;local queue={};local active=nil;local frame=CreateFrame('Frame');local spent,maxSlice=0,0
local clock=debugprofilestop or function()return GetTime()*1000 end
local sliceStart=0;local budget=1.0;local sliceActions=0
-- P.jobBudgetMs lets an open, out-of-combat dashboard use more time per frame.
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
 f:SetSize(255,59)
 f:SetFrameStrata('DIALOG')
 local bg=f:CreateTexture(nil,'BACKGROUND');bg:SetAllPoints();bg:SetColorTexture(.03,.03,.04,.94)
 f.label=f:CreateFontString(nil,'OVERLAY','GameFontNormalSmall');f.label:SetPoint('TOPLEFT',7,-5);f.label:SetWidth(243);f.label:SetHeight(13);f.label:SetWordWrap(false);f.label:SetJustifyH('LEFT')
 f.icons={};f.rules=f:CreateFontString(nil,'OVERLAY','GameFontNormalSmall');f.rules:SetPoint('BOTTOMLEFT',7,4);f.rules:SetWidth(243);f.rules:SetHeight(12);f.rules:SetWordWrap(false);f.rules:SetJustifyH('LEFT')
 for i=1,7 do local icon=f:CreateTexture(nil,'ARTWORK');icon:SetSize(20,20);icon:SetPoint('TOPLEFT',7+(i-1)*24,-21);f.icons[i]=icon end
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
 else f:SetPoint('TOPRIGHT',UIParent,'TOPRIGHT',-25,-190-(f.slot or 0)*66);f:SetWidth(255) end
end
local function safeSpellIcon(ref)
 if P.spellDisplay then local _,icon=P.spellDisplay(ref);return icon end
 local f=GetSpellTexture
 if type(f)=='function' then local ok,icon=pcall(f,ref);if ok then return icon end end
 if type(GetSpellInfo)=='function' then
  local ok,_,_,icon=pcall(GetSpellInfo,ref)
  if ok then return icon end
 end
 return nil
end
local function display(rollID,result,err,profile)
 if P.itemScore then P.itemScore.ClearMarks('roll'..rollID) end
 local f=panel(rollID);place(f,rollID);f:SetScript('OnEnter',nil);f:SetScript('OnLeave',nil);f:Show();for _,i in ipairs(f.icons)do i:Hide()end f.rules:SetText('')
 if err then f.label:SetText('|cffffaa66'..uiProblem(err)..'|r');return end
 if not result.eligible then f.label:SetText('|cffffaa66'..(result.reason or 'Nicht bewertbar')..'|r');return end
 local pct=result.percent and (string.format('%+.1f %% DPS',result.percent):gsub('%.',',',1))or 'Kein Vergleich';local color=result.status=='upgrade'and '80ff80'or(result.status=='downgrade'and 'ff8080'or 'ddddaa')
 f.label:SetText('ForeverSim: |cff'..color..pct..'|r')
 if result.status=='upgrade' and P.itemScore then local gl,i=P.itemScore.RollFrame(rollID);local need=P.itemScore.RollNeedButton(gl,i);if need then P.itemScore.ClearMarks('roll'..rollID);P.itemScore.GoldBorder('roll'..rollID,need,3) end end
 for i,policy in ipairs(result.newChoice.policies)do if i>7 then break end local names=((FUSLiveData[profile.class]or {}).spellAliases or P.spellAliases)[policy.key]or {policy.key};local icon
  for _,s in ipairs(profile.spells or {})do for _,name in ipairs(names)do if s.name and string.lower(s.name)==name then icon=safeSpellIcon(s.id or s.name);break end end if icon then break end end
  if icon then f.icons[i]:SetTexture(icon);f.icons[i]:Show()end
 end
 f:SetScript('OnEnter',function(self)if P.explainItem and GameTooltip then GameTooltip:SetOwner(self,'ANCHOR_RIGHT');GameTooltip:SetText('SIM-Entscheidung');for _,line in ipairs(P.explainItem(result))do GameTooltip:AddLine(line,.8,.8,.7,true)end;GameTooltip:Show()end end)
 f:SetScript('OnLeave',function()if GameTooltip then GameTooltip:Hide()end end)
 if #result.rotationRules>0 then local r=result.rotationRules[1];f.rules:SetText(r.text or r.buff)else f.rules:SetText('Prioritäten · Boss 60 / 90 / 120 s')end
end
local function current()
 local snap=P.capture and P.capture(true)if not snap then error('Charakterdaten fehlen')end local profile=P.normalizeSnapshot(snap);profile.spells=snap.spells
 local data=FUSLiveData[profile.class]if not data then error('Klassenmodul fehlt',0)end local issue=P.coverage(data,profile)if issue then error(issue,0)end
 return data,profile
end
local function evaluate(item,done,stillValid)
 local data,profile;local ok,err=pcall(function()data,profile=current()end)if not ok then done(nil,err);return end
 P.enqueue(function()local stats=P.combine(profile.equipped);local chosen=(not P.stale and P.lastRotation and P.lastRotation.choice) or nil;local base=P.best(data,profile,stats,chosen);local result=P.compare(data,profile,profile.equipped,item,base);result.profile=profile;return result end,done,stillValid,true)
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
 f:SetScript('OnEnter',nil);f:SetScript('OnLeave',nil)
 f.rules:SetText('');for _,icon in ipairs(f.icons)do icon:Hide()end
 evaluate(item,function(result,err)
  if rolls[id]~=token then return end
  display(id,result,err,result and result.profile or {})
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
 P.invalidate();if P.rotationHUD then P.rotationHUD.invalidate()end;clearLabels();for id in pairs(rolls)do pendingRolls[id]=true end;rolls={}
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
P.optimizeNow=function()
 if ForeverSimBridgeDB and ForeverSimBridgeDB.rotationGoal=='leveling' and P.leveling then P.leveling.Optimize(true);return end
 local level=UnitLevel and UnitLevel('player')
 if level and level<P.minSimLevel() then print('Forever SIM: '..P.levelMessage(level));return end
 local ok,data,p=pcall(current)if not ok then print('Forever SIM: '..tostring(data));return end
 P.enqueue(function()
  local stats=P.combine(p.equipped)
  local start=P.candidates(data,p)[1]
  if not start then error('Keine gelernte Startrotation') end
  local searched=P.best(data,p,stats,start)
  local candidates={searched.choice}
  if p.level>=30 and P.tuneRotation then
   local tuned=P.tuneRotation(data,p,stats,searched.choice,{rounds=1,finalists=4,
     seeds={31211,48817,81721},validationSeeds={178651,191789,205279,219103,232369,247301,260849,274073}})
   if tuned.accepted then candidates[#candidates+1]=tuned.choice end
  end
  local bestDiff,selected=0,P.copy(start)
  local baseDps=0
  local seen={}
  for _,choice in ipairs(candidates)do
   local id=P.canonical(choice)
   if not seen[id]then
    seen[id]=true
    local comparison=P.paired(data,p,stats,start,stats,choice,12,13)
    baseDps=comparison.baselineDps
    if comparison.difference>bestDiff then bestDiff=comparison.difference;selected=P.copy(choice)end
   end
  end
  -- Scoring every finalist with the same comparison seeds: original is always 100%.
  if baseDps==0 then baseDps=P.score(data,p,stats,start,12,13)end
  local accepted=bestDiff>0
  return {choice=selected,dps=baseDps+bestDiff,baselineDps=baseDps,
    percentOfStart=baseDps>0 and(100*(baseDps+bestDiff)/baseDps)or 100,
    improvementPercent=baseDps>0 and(100*bestDiff/baseDps)or 0,
    accepted=accepted,status=accepted and 'improvement' or 'start_preserved',
    candidatesTested=searched.candidatesTested,rotationRules=searched.rotationRules}
 end,function(r,err)
  if err then print('Forever SIM: '..err);return end
  if not r or not r.choice then print('Forever SIM: Keine gültige Rotation.');return end
  P.stale=false;P.lastRotation=r
  -- Only serialize small optimizer output, never the entire simulation/character snapshot.
  ForeverSimBridgeDB.rotationResult={choice=P.copy(r.choice),dps=r.dps,baselineDps=r.baselineDps,percentOfStart=r.percentOfStart,accepted=r.accepted}
  if P.rotationHUD then P.rotationHUD.configure(data,p,r) end
  print(string.format('Forever SIM: %.1f DPS · %.2f%% der Startrotation · %d Kandidaten (Teilmodell)',r.dps,r.percentOfStart or 100,r.candidatesTested))
 end)
end
P.pendingJobs=function()return #queue+(active and 1 or 0)end
-- Cancel cooperative jobs between slices. Notify owners so their busy flags clear.
P.cancelJobs=function(reason)
 local cancelled=queue;queue={}
 if active then table.insert(cancelled,1,active);active=nil end
 for _,job in ipairs(cancelled)do discard(job,reason or 'Berechnung abgebrochen.')end
end

-- Schedule first live optimization after login, never while fighting.
local login=CreateFrame('Frame');login:RegisterEvent('PLAYER_ENTERING_WORLD');login:RegisterEvent('PLAYER_REGEN_ENABLED');login:RegisterEvent('PLAYER_EQUIPMENT_CHANGED')
local awaiting=false;local refreshToken=0
login:SetScript('OnEvent',function(_,event)
 if P.passiveSafetyMode and P.passiveSafetyMode() then return end
 if event=='PLAYER_ENTERING_WORLD' or event=='PLAYER_EQUIPMENT_CHANGED' then awaiting=true end
 if not awaiting then return end
 refreshToken=refreshToken+1;local token=refreshToken
 local function submit()
  if token~=refreshToken then return end
  if P.passiveSafetyMode and P.passiveSafetyMode()then return end
  if InCombatLockdown and InCombatLockdown() then return end
  awaiting=false
  local ok,data,p=pcall(current)
  if ok and data and p and p.level>=10 then P.optimizeNow() end
 end
 if C_Timer and C_Timer.After then C_Timer.After(2,submit)else submit()end
end)

