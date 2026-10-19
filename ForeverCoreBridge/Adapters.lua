local C=ForeverCoreClient
local itemSlots={head=0,neck=1,shoulder=2,back=3,chest=4,wrist=5,hands=6,waist=7,legs=8,feet=9,finger1=10,finger2=11,trinket1=12,trinket2=13,mainhand=14,offhand=15,ranged=16,HeadSlot=0,NeckSlot=1,ShoulderSlot=2,BackSlot=3,ChestSlot=4,WristSlot=5,HandsSlot=6,WaistSlot=7,LegsSlot=8,FeetSlot=9,Finger0Slot=10,Finger1Slot=11,Trinket0Slot=12,Trinket1Slot=13,MainHandSlot=14,SecondaryHandSlot=15,RangedSlot=16}
function C.ItemCandidate(item,reference)
 local metadata={};for _,key in ipairs({'slot','minLevel','faction','itemClass','itemSubclass','weaponClass','weaponSubclass','armorType','equipLoc','twoHanded','unique','uniqueEquip'})do metadata[key]=item[key]end
 -- Variants of a known item (item bonus ids such as "of Agility", or a random suffix) have their own stats;
 -- the PC must not take its record of the base item for them.
 local variant,variantKey=false,nil
 if C.NormalizeLink then
  local key=C.NormalizeLink(item.link or(type(reference)=='string'and reference or item.id))
  local parts={};for field in(tostring(key)..':'):gmatch('([^:]*):')do parts[#parts+1]=field end
  -- parts[1] is "item", so link field n is parts[n+1]: suffix = field 7, number of bonus ids = field 13
  local suffix=tonumber(parts[8])or 0
  local bonuses=tonumber(parts[14])or 0
  if suffix~=0 or bonuses>0 then variant,variantKey=true,key end
 end
 return{slot=itemSlots[item.slot],spec={id=item.id},link=item.link or(type(reference)=='string'and reference or nil),twoHanded=item.twoHanded,name=item.name,metadata=metadata,snapshot=C.clean(item),variant=variant or nil,variantKey=variantKey}
end
local function nsFDQ()return _G.ForeverCoreFDQ end
local function enabled()return ForeverCoreBridgeDB and ForeverCoreBridgeDB.enabled~=false end
C.ExternalEnabled=enabled
local function read(fn,...)
 if type(fn)~='function'then return nil end
 local ok,v=pcall(fn,...);if ok and C.public(v)then return v end
end
local function identity()
 local _,class=UnitClass('player');local _,race=UnitRace('player')
 return{class=class,race=race,faction=read(UnitFactionGroup,'player'),level=read(UnitLevel,'player'),guid=read(UnitGUID,'player'),active={},completed={},ready={},inventory={},professions={},spells={},buffs={},group=read(IsInGroup)==true,partySize=read(GetNumGroupMembers)or 1,instance={}}
end
function C.Capture(kind)
 if InCombatLockdown and InCombatLockdown()then error('Profil nur ausserhalb des Kampfes lesen')end
 local ns=nsFDQ();local M=ns and ns.Model;local s
 if M and M.graph and M.db and ns.Character and ns.Character.Read then s=ns.Character.Read(M.graph,M.db)else s=identity()end
 s=C.clean(s);if s then for _,key in ipairs({'active','ready','completed','spells'})do for id,value in pairs(s[key]or{})do if value==false then s[key][id]=nil end end end end;if not s or not s.class or not s.race or not s.level then error('Profil nicht oeffentlich lesbar')end
 s.knownQuests='';if M and M.graph then local ids={};for id in pairs(M.graph.nodes or{})do ids[#ids+1]=id end;table.sort(ids);s.knownQuests=table.concat(ids,',')end;s.completionEvidence=C.extraCompleted or{};for id,value in pairs(C.extraCompleted or{})do s.completed[id]=value end
 s.questObjectives={};for id in pairs(s.active or{})do s.questObjectives[id]=C.clean(read(C_QuestLog and C_QuestLog.GetQuestObjectives,id))end
 s.guid=read(UnitGUID,'player');s.route=nil;s.routeResume=nil;s.dungeonState=nil;s.observedXP=s.observedXP or{};s.instance=s.instance or{}
 if M and M.db then
  s.mode=M.db.settings and M.db.settings.mode or'balanced'
  s.routeDB={settings=C.clean(M.db.settings),done=C.clean(M.db.done),phases=C.clean(M.db.phases),routeProgress=C.clean(M.db.routeProgress),completedPlans=C.clean(M.db.completedPlans),routeSkips=C.clean(M.db.routeSkips),skipHistory=C.clean(M.db.skipHistory),skipContexts=C.clean(M.db.skipContexts),deferred=C.clean(M.db.deferred),routeRecovery=C.clean(M.db.routeRecovery),routeTravel=C.clean(M.db.routeTravel),routeTravelVisits=C.clean(M.db.routeTravelVisits),buffs=C.clean(M.db.buffs),observedXP=C.clean(M.db.observedXP),dungeonRuns=C.clean(M.db.dungeonRuns)}
 end
 if kind=='sim'or kind=='item'or kind=='rotation'or kind=='talents'or kind=='talent-build'or kind=='talent-next'or kind=='weights'or kind=='analysis'or kind=='leveling'then
  local P=FUSLive;if not P or not P.capture then error('ForeverSim fehlt')end
  s.sim=C.clean(P.capture(true));if not s.sim then error('SIM-Snapshot nicht lesbar')end
  local actualFree=read(GetUnspentTalentPoints)
  if actualFree==nil then actualFree=tonumber(s.sim.unspentTalentPoints)end
  if actualFree==nil then
   -- Mirror the UI's bounded level-based fallback when the client exposes
   -- no free-point API, so the displayed budget and engine budget agree.
   local spent=0
   for _,tree in ipairs(s.sim.talents or{})do
    for _,entry in ipairs(tree.entries or{})do spent=spent+(tonumber(entry.rank)or 0)end
   end
   local bonus=P.talentBonus and P.talentBonus()or 0
   local budget=math.max(0,math.min(51,(tonumber(s.sim.level)or 9)-9+bonus))
   actualFree=math.max(0,budget-spent)
   s.sim.unspentTalentPointsEstimated=true
  end
  s.sim.unspentTalentPoints=actualFree
  local model=FUSLiveData and FUSLiveData[string.lower(s.sim.class or'')];s.sim.equipmentRules=C.clean(model and model.equipmentRules);local byKey={}
  for _,tree in ipairs(model and model.talentTrees or{})do for _,node in ipairs(tree.talents or{})do byKey[node.key]=node end end
  for _,tree in ipairs(s.sim.talents or{})do for _,entry in ipairs(tree.entries or{})do local node=byKey[entry.classKey];if node then entry.modelSpellID=node.spellId end end end
  -- The installed engine manifest may lack spellRankFamilies. Export only rank
  -- chains from the class model so the PC can match level-60 APL IDs to the
  -- actual learned spellbook IDs; never infer learned spells from player level.
  local families={}
  for _,ranks in pairs(model and model.abilities or{})do
   local chain={}
   for _,rank in ipairs(ranks)do
    local id=tonumber(rank.id)
    if id and id>0 then chain[#chain+1]={id=id,rank=tonumber(rank.rank)or #chain+1}end
   end
   table.sort(chain,function(a,b)return a.rank<b.rank end)
   if #chain>0 then
    local ids={}
    for _,entry in ipairs(chain)do ids[#ids+1]=entry.id end
    for _,id in ipairs(ids)do families[tostring(id)]=ids end
   end
  end
  s.sim.spellRankFamilies=families

  -- Preserve real item identity including suffixes, but never the enchant: worn and new items are both valued
  -- without enchants, otherwise the worn item would always look better.
  for _,item in ipairs(s.sim.equipped or{})do
   local id=GetInventorySlotInfo and GetInventorySlotInfo(item.slot)
   if id then item.link=C.WithoutEnchant(read(GetInventoryItemLink,'player',id))end
  end
 end
 C.latestState=s;return s
end
function C.ApplyRoute(result,issue)
 local ns=nsFDQ();local M=ns and ns.Model
 if issue then if M and M.state then M.state.coreError=issue end;return end
 if type(result)~='table'or type(result.chapters)~='table'then return end
 local changed=false;C.extraCompleted=C.extraCompleted or{};for _,id in ipairs(result.completionQueries or{})do local done=read(C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted,id);if type(done)=='boolean'then if done and not C.extraCompleted[id]then changed=true end;C.extraCompleted[id]=done end end;if changed then C.MarkChanged();return end
 C.lastRoute=result;result.stale=false
 if M then
  M.chapters=result.chapters;M.bi=tonumber(result.bi)or 1;M.si=tonumber(result.si)or 1
  M.state=C.latestState or M.state;M.state.route=result.route or{status=result.status};M.state.dungeonState=result.dungeonState or{};M.state.coreError=nil
  if result.prep then M.prep=result.prep end
  for k,v in pairs(result.routeDB or{})do M.db[k]=v end
  -- Redraw via the existing passive UI update loop. Never call its planner.
  M.coreRevision=C.revision
 end
end
function C.ApplySim(result,issue,silent)
 C.lastSim=result
 if issue then C.Say(issue)end
 local P=FUSLive;if not P or not P.app then return end
 if not issue and result and not result.candidateDps and result.priority and result.dps and result.dps>0 then
  local liveSpells=C.latestState and C.latestState.sim and C.latestState.sim.spells
  local choice=P.rotationHUD and P.rotationHUD.SetExternalPriority and P.rotationHUD.SetExternalPriority(result.priority,liveSpells)or{policies={}}
  local view={engine='MythicSim Go',dps=result.dps,baselineDps=result.baselineDps or result.dps,percentOfStart=result.pct or 100,improvementPercent=(result.pct or 100)-100,accepted=(result.pct or 100)>100,choice=choice,candidatesTested=#(result.candidates or{}),warnings=result.warnings}
  P.lastRotation=view;P.stale=false;ForeverSimBridgeDB.rotationResult=view
  P.app.state.rotation={revision=P.revision,result=view}
 end
 if silent then return end
 local run=C.simRun
 if not run then C.ShowResult(result,issue);return end
 if issue then run.status='error';run.error={code='FOREVERCORE',message=issue}
 else run.status='complete';run.result=result;run.phase='MythicSim fertig';run.completed=date and date('%H:%M')or'' end
 if P.app.state.simulation==run then P.app.Refresh()end;C.ShowResult(result,issue)
end
local function startSim(kind,payload,route)
 local P=FUSLive
 if P and P.app then P.app.Open(route or'rotation');C.simRun={status='running',kind=kind,phase='ForeverCore / MythicSim',revision=P.revision};P.app.state.simulation=C.simRun;P.app.Refresh()end
 local run=C.simRun;if not C.Request(kind,payload,function(result,issue)if run==C.simRun then C.ApplySim(result,issue)end end)then C.ApplySim(nil,'Auftrag konnte nicht gestartet werden')end
end
function C.InstallAdapters()
 local ns=nsFDQ();local M=ns and ns.Model
 if M and not C.originalRebuild then
  C.originalRebuild=M.Rebuild
  M.Rebuild=function(...)
   if not enabled()then return C.originalRebuild(...)end
   if not M.graph or not M.db then return end
   local ok,state=pcall(C.Capture,'route')
   if ok and state then M.anchor={x=state.x,y=state.y,map=state.map};M.state=state;M.state.route=C.lastRoute and C.lastRoute.route or{status='ForeverCore berechnet die Route'}end
   if not C.lastRoute then M.chapters={{id='core-wait',name='ForeverCore verbinden',lv={1,60},steps={}}};M.bi=1;M.si=1 end
   -- Rebuild is a redraw, not a state change: never bump the revision here.
   -- Only request a first route when none exists yet.
   if not C.lastRoute and not C.pending and #C.queue==0 then C.MarkChanged(true,2) end
  end
 end
 local P=FUSLive
 if P and P.actions and not C.originalActions then
  C.originalActions={RunRotation=P.actions.RunRotation,CompareItem=P.actions.CompareItem,RunLeveling=P.actions.RunLeveling}
  P.actions.RunRotation=function()
   if not enabled()then return C.originalActions.RunRotation()end
   -- Candidate APLs are selected from the pinned MythicSim data in ForeverCore.
   startSim('rotation',{autoRotations=true},'rotation')
  end
  P.actions.CompareItem=function(reference)
   if not enabled()then return C.originalActions.CompareItem(reference)end
   local ok,item=pcall(P.readItem,tonumber(reference)or reference,'ForeverCore')
   if not ok or not item then C.Say('Itemdaten noch nicht geladen');return end
   local candidate=C.ItemCandidate(item,reference);if candidate.slot==nil then C.Say('Itemslot nicht unterstuetzt');return end
   startSim('item',{items={candidate}},'gear')
  end
  P.actions.RunLeveling=function()
   if not enabled()then return C.originalActions.RunLeveling()end
   local settings=ForeverSimBridgeDB and ForeverSimBridgeDB.leveling or{}
   startSim('leveling',{benchmark=true,targetHealth=settings.targetHealth,targetLevel=settings.targetLevel,downtime=settings.moveSeconds},'rotation')
  end
  if P.leveling and not C.originalLevelingOptimize then C.originalLevelingOptimize=P.leveling.Optimize;P.leveling.Optimize=function(...)if not enabled()then return C.originalLevelingOptimize(...)end;return P.actions.RunLeveling()end end
  -- Legacy entry points must not silently start the previous Lua combat engine.
  C.originalOptimize=P.optimizeNow
  P.optimizeNow=function(...)if not enabled()then return C.originalOptimize(...)end;return P.actions.RunRotation()end
 end
end

function C.ApplyLeveling(result,issue)C.ApplySim(result,issue)end
function C.ShowResult(result,issue)
 local P=FUSLive;if P and P.dashboard and P.dashboard.Show then P.dashboard.Show('more')end;local host=P and P.dashboard and P.dashboard.MoreHost and P.dashboard.MoreHost()
 if not host then C.Say(issue or(result and string.format('MythicSim: %.2f DPS',result.dps or 0))or'Kein Ergebnis');return end
 if not C.resultView then
  local f=CreateFrame('Frame',nil,host,'BackdropTemplate');f:SetAllPoints(host);f:SetFrameLevel(host:GetFrameLevel()+20)
  if f.SetBackdrop then f:SetBackdrop({bgFile='Interface\\Tooltips\\UI-Tooltip-Background'});f:SetBackdropColor(.025,.035,.065,1)end
  f.title=f:CreateFontString(nil,'OVERLAY','GameFontNormalLarge');f.title:SetPoint('TOPLEFT',24,-24);f.title:SetText('ForeverCore · MythicSim')
  f.body=f:CreateFontString(nil,'OVERLAY','GameFontHighlight');f.body:SetPoint('TOPLEFT',24,-65);f.body:SetWidth(680);f.body:SetJustifyH('LEFT');f.body:SetJustifyV('TOP')
  local close=CreateFrame('Button',nil,f,'UIPanelButtonTemplate');close:SetSize(160,26);close:SetPoint('BOTTOMLEFT',24,20);close:SetText('Zurueck');close:SetScript('OnClick',function()f:Hide()end)
  C.resultView=f
 end
 local text
 if not issue and result and type(result.candidateDps)=='number' then
  local delta=tonumber(result.delta)or 0
  local pct=tonumber(result.percent)or 0
  if delta>0 then text=string.format('Besser als aktuell: %+.2f DPS (%+.2f %%)',delta,pct)
  elseif delta<0 then text=string.format('Aktuelles Item behalten: %.2f DPS weniger (%.2f %%)',math.abs(delta),pct)
  else text='Kein gemessener DPS-Unterschied. Aktuelle Ausrüstung behalten.'end
 elseif not issue and result and result.rows then
  local lines={'MythicSim · Level-Benchmark',result.source or'Explizite Gegnerdaten',''}
  for _,row in ipairs(result.rows)do lines[#lines+1]=string.format('%s: %.2f DPS · %.1f s rechnerische Kampfzeit · %.1f Gegner/Stunde',row.name or'Ziel',row.dps or 0,row.timeToKill or 0,row.killsPerHour or 0)end
  lines[#lines+1]='EP/Stunde ohne passende NPC-Daten nicht bekannt.';text=table.concat(lines,'\n')
 elseif not issue and result and result.actions then
  local lines={string.format('MythicSim: %.2f DPS',result.dps or 0),'Schaden und Einsaetze pro simuliertem Kampf:',''}
  for _,row in ipairs(result.actions)do local id=row.id or{};local spell=read(C_Spell and C_Spell.GetSpellInfo,id.spellId);lines[#lines+1]=string.format('%s · %s: %.1f Schaden · %.2f Einsaetze',row.actor or'?',spell and spell.name or tostring(id.spellId or id.otherId or'?'),row.damage or 0,row.casts or 0)end
  lines[#lines+1]='';lines[#lines+1]=result.comparison or'';text=table.concat(lines,'\n')
 elseif issue then text='Berechnung nicht verfuegbar\n\n'..tostring(issue)
 else
  local lines={string.format('Start: %.2f DPS · 100 %%',result.baselineDps or 0),string.format('Auswahl: %s · %.2f DPS · %.2f %%',result.selected or'baseline',result.dps or 0,result.pct or 100),'','Verglichene Kandidaten:'}
  for _,row in ipairs(result.candidates or{})do lines[#lines+1]=string.format('%s: %.2f DPS · %.2f %%',row.name or'Kandidat',row.dps or 0,row.pct or 0)end
  lines[#lines+1]='';lines[#lines+1]=result.scenario or'';lines[#lines+1]='Engine: '..tostring(result.engineRevision or'');text=table.concat(lines,'\n')
 end
 if result and result.warnings and #result.warnings>0 then text=text..'\n\n'..table.concat(result.warnings,'\n')end
 C.resultView.body:SetText(text);C.resultView:Show()
end

-- Reuse finished calculations across quest-log opens, /reload and restarts.
-- Only stable simulator inputs are fingerprinted; opening a UI is not a change.
local cacheRevision,cacheContext
-- Only what really changes an item comparison belongs into the cache key: class, level, gear, talents,
-- spellbook, encounter and static hunter equipment. Buffs, auras, current resources, consumables,
-- temporary weapon enchants, forms and live pet stats must never invalidate stored results.
local function stableSim(sim)
 local hunter=type(sim.hunter)=='table' and sim.hunter or nil
 local pet=type(sim.pet)=='table' and sim.pet or nil
 local hpet=hunter and type(hunter.pet)=='table' and hunter.pet or nil
 return {class=sim.class,level=sim.level,race=sim.race,faction=sim.faction,equipped=sim.equipped,talents=sim.talents,
  spells=sim.spells,encounter=sim.encounter,dualWield=sim.dualWield,
  petKind=pet and {type=pet.type,level=pet.level} or nil,
  ammo=hunter and hunter.ammo or nil,quiver=hunter and hunter.quiver or nil,
  petFamily=hpet and {family=hpet.family,familyId=hpet.familyId,level=hpet.level} or nil}
end
C.StableSim=stableSim
function C.SimCacheContext()
 if not C.engineRevision or C.engineRevision=='' then return nil end
 local P=FUSLive
 if not P or not P.capture then return nil end
 local revision=tostring(C.simRevision)..'/'..tostring(P.revision)..'/'..C.engineRevision
 if cacheRevision==revision then return cacheContext end
 local ok,snapshot=pcall(P.capture,true)
 if not ok or type(snapshot)~='table' then return nil end
 local sim=stableSim(C.clean(snapshot))
 -- Right after the login the hunter quiver can still be unreadable. A key computed from that half-loaded state
 -- would differ from the real one and poison the result cache, so there is no key until it is readable.
 if type(sim.quiver)=='table' and sim.quiver.status=='unreadable' then return nil end
 local serialized=C.json({engine=C.engineRevision,guid=read(UnitGUID,'player') or read(UnitName,'player'),sim=sim})
 -- Two directional CRC values and length, so accidental key collisions are
 -- extremely unlikely; every item also has its own exact candidate signature.
 cacheContext=tostring(#serialized)..':'..tostring(C.crc(serialized))..':'..tostring(C.crc(serialized:reverse()))
 cacheRevision=revision
 return cacheContext
end
local function persistentItems()
 ForeverCoreBridgeDB=ForeverCoreBridgeDB or{}
 local db=ForeverCoreBridgeDB
 if type(db.simItemCache)~='table' or db.simItemCache.version~=6 then
  db.simItemCache={version=6,entries={},order={}}
 end
 return db.simItemCache
end
local function findItem(context,key)
 if not context then return nil end
 return persistentItems().entries[context..'/'..key]
end
local function storeItem(context,key,record)
 if not context then return end
 local db=persistentItems();local full=context..'/'..key
 if db.entries[full]==nil then db.order[#db.order+1]=full end
 db.entries[full]=record
 while #db.order>1200 do db.entries[table.remove(db.order,1)]=nil end
end

-- Automatically recommend the best LEGAL next point, using one MythicSim batch job.
-- Only outside combat; the normal talent tree remains the sole point-allocation UI.
-- Search the best complete distribution of available TOTAL talent points.
-- The server uses MythicSim to compare mixed trees; no per-point winner is shown.
function C.RecommendTalents(force)
 local function fail(reason)
  C.lastTalentAdvice={state='unsupported',reason=reason}
  if force then C.Say('Talente: '..reason)end
  return false
 end
 if not enabled()then return fail('ForeverCore-Verbindung deaktiviert: /fc on')end
 if InCombatLockdown and InCombatLockdown()then return fail('Nur ausserhalb des Kampfes berechnen')end
 local P=_G.FUSLive
 if not P or type(P.capture)~='function'then return fail('ForeverSim / Charakterdaten fehlen')end
 local ok,snap=pcall(P.capture,true)
 if not ok or not snap or type(snap.talents)~='table'then return fail('Talentprofil nicht lesbar; /reload versuchen')end
 local level=tonumber(snap.level)
 if not level or level<10 or level>60 then return fail('Talentvergleich nur Level 10-60')end
 local ranks,spent={},0
 for _,tree in ipairs(snap.talents)do
  for _,entry in ipairs(tree.entries or{})do
   if type(entry.classKey)=='string' and type(entry.rank)=='number' and entry.rank>0 then
    ranks[#ranks+1]=entry.classKey..'='..entry.rank
    spent=spent+entry.rank
   end
  end
 end
 table.sort(ranks)
 local free=tonumber(snap.unspentTalentPoints)
 if not free then free=tonumber(read(GetUnspentTalentPoints))end
 if not free then
  -- No fictitious points: only use visible level/real spent count.
  local budget=math.max(0,math.min(51,level-9+(P.talentBonus and P.talentBonus()or 0)))
  free=math.max(0,budget-spent)
 end
 local total=spent+free
 if total<1 then C.lastTalentAdvice={state='no-points',reason='Noch keine Talentpunkte verfuegbar'};return false end
 local items={}
 for _,entry in ipairs(snap.equipped or{})do items[#items+1]=tostring(entry.slot or'')..'='..tostring(entry.link or entry.id or'')end
 table.sort(items)
 local token=table.concat({tostring(snap.class),tostring(level),tostring(total),
    table.concat(ranks,','),table.concat(items,','),tostring(C.SimCacheContext() or P.revision)},':')
 if C.lastTalentAdvice and C.lastTalentAdvice.state=='busy' and C.talentAdviceToken==token then return true end
 if not force and C.talentAdviceToken==token and C.lastTalentAdvice and C.lastTalentAdvice.state=='ok' then return true end
 local persisted=ForeverCoreBridgeDB and ForeverCoreBridgeDB.talentAdviceCache
 if not force and C.engineRevision and persisted and persisted.token==token
    and persisted.advice and persisted.advice.state=='ok' then
  C.talentAdviceToken=token;C.lastTalentAdvice=C.clean(persisted.advice)
  return true
 end
 C.talentAdviceToken=token
 C.lastTalentAdvice={state='busy',points=total}
 -- Do not separately optimize each talent tree. The full combined build is searched.
 if not C.Request('talent-build',{},function(result,issue)
  if C.talentAdviceToken~=token then return end
  if issue or not result or result.status~='ok' or type(result.build)~='table' then
   C.lastTalentAdvice={state='unsupported',reason=issue or 'Kombinierte Skillung nicht berechenbar',points=total}
  else
   C.lastTalentAdvice={state='ok',build=result.build,points=result.points,
    dps=result.dps,delta=result.delta,percent=result.percent,
    baselineDps=result.base,requiresRespec=result.requiresRespec==true,
    exhaustive=result.exhaustive==true,tested=result.tested,cached=result.cached==true}
   if C.engineRevision then
    ForeverCoreBridgeDB.talentAdviceCache={token=token,advice=C.clean(C.lastTalentAdvice)}
   end
  end
  -- App.Refresh only refreshes the advanced shell. Repaint the actual
  -- shared talent page so the player immediately sees the returned build.
  if P.dashboard and P.dashboard.Refresh then P.dashboard.Refresh()
  elseif P.app and P.app.Refresh then P.app.Refresh()end
 end)then C.talentAdviceToken=nil;return fail(tostring(C.status or 'MythicSim-Warteschlange voll'))end
 return true
end

-- Shared external item cache for tooltip, quest rewards and gear comparison.
local externalItems,externalRevision={},nil
-- Links from the auction house, bags and tooltips carry extra numbers (unique id, level) that do not change
-- the comparison. Only item id, enchant, gems and random suffix identify the item.
local function normalizeLink(link)
 local text=tostring(link)
 local body=text:match('item:([%-%d:]*)')
 if not body then return text end
 local parts={};for field in(body..':'):gmatch('([^:]*):')do parts[#parts+1]=field end
 local out={}
 for i=1,7 do local v=parts[i];if v==nil or v==''then v='0'end;out[i]=v end
 -- Enchants never count: an enchanted item is the same item as the plain one and is valued without the enchant.
 out[2]='0'
 -- A random suffix ("of Agility" in older clients) is only half the identity: the unique id decides how strong
 -- the stats are (+3 or +4 Agility), and the client cannot read them without it.
 if(tonumber(out[7])or 0)~=0 then local u=parts[8];if u==nil or u==''then u='0'end;out[8]=u end
 -- The Forever client marks variants like "of Agility" with item bonus ids (field 13 = how many, then the ids).
 -- Without them the link names the plain base item. The viewer-specific fields in between (spec, mask,
 -- context) are left out so the same item gives the same key everywhere.
 local bonuses=tonumber(parts[13])or 0
 if bonuses>0 then
  out[8]=out[8] or '0';out[9]=(parts[9]~=nil and parts[9]~='')and parts[9]or'0';out[10]='0';out[11]='0';out[12]='0';out[13]=tostring(bonuses)
  for i=1,bonuses do local v=parts[13+i];if v==nil or v==''then v='0'end;out[13+i]=v end
 end
 return 'item:'..table.concat(out,':')
end
C.NormalizeLink=normalizeLink
-- The same link with an empty enchant field ("item:10518:1887:..." -> "item:10518::..."); everything else stays.
function C.WithoutEnchant(link)
 if type(link)~='string' then return link end
 return(link:gsub('item:(%-?%d+):%-?%d*','item:%1:',1))
end
local function stripVolatile(candidate)
 if type(candidate)~='table'then return candidate end
 local copy={};for k,v in pairs(candidate)do copy[k]=v end
 if copy.link then copy.link=normalizeLink(copy.link)end
 if type(copy.snapshot)=='table'then
  local snap={};for k,v in pairs(copy.snapshot)do snap[k]=v end
  if snap.link then snap.link=normalizeLink(snap.link)end
  copy.snapshot=snap
 end
 return copy
end
local function itemSignature(candidate,link)
 -- What identifies a comparison: the item (id, enchant, gems, random suffix) and where it goes. Tooltip text,
 -- names and link noise differ between bags, quest windows and the auction house for the very same item.
 local c=type(candidate)=='table' and candidate or{}
 local value=C.json({link=normalizeLink(link),slot=c.slot,twoHanded=c.twoHanded==true,id=c.spec and c.spec.id})
 return tostring(#value)..':'..tostring(C.crc(value))..':'..tostring(C.crc(value:reverse()))
end
local function itemEntry(item,r)
 local pct=tonumber(r.percent)or 0
 local delta=tonumber(r.delta)or 0
 local status=pct>0 and'upgrade'or(pct<0 and'downgrade'or'equal')
 return {state='ok',pct=pct,delta=delta,status=status,
  result={eligible=true,percent=pct,delta=delta,status=status,item=item,
   dps=r.candidateDps,baselineDps=r.baselineDps,warnings=r.warnings,targetArmorEstimated=r.targetArmorEstimated}}
end
function C.CachedItemComparison(item,candidate,link)
 local context=C.SimCacheContext()
 local key=itemSignature(candidate,link or item.link or item.id)
 local record=findItem(context,key)
 return record and itemEntry(item,record)or nil,context,key
end
function C.StoreItemComparison(context,key,result)
 if not result or type(result.candidateDps)~='number' or type(result.baselineDps)~='number' then return end
 storeItem(context,key,{percent=result.percent,delta=result.delta,baselineDps=result.baselineDps,
  candidateDps=result.candidateDps,warnings=C.clean(result.warnings),
  targetArmorEstimated=result.targetArmorEstimated})
end
-- Errors like "ammo could not be read" happen when the client has not loaded the item tooltips yet
-- (first requests after login). They are not a verdict about the item: try again a few times.
function C.IsTransientIssue(issue)return type(issue)=='string' and issue:find('gelesen werden',1,true)~=nil end

-- Item requests are collected for a moment and sent as ONE job (the PC compares up to 24 candidates
-- per job). A job costs one pixel cycle (~4-6 s), so three quest rewards no longer take three cycles.
-- Items the character cannot wear are sorted out here, because a single unwearable candidate makes
-- the PC reject the whole job. If a batch still fails, every item is requested on its own.
local BATCH_MAX,BATCH_WAIT=24,0.35
local pendingBatch={}
local blockedWords={'Benötigt','nicht tragbar','Falsche Fraktion','Zweihand','Einzigartig','Nur fuer','Waffenfertigkeit'}
local function wearableVerdict(reason)
 for _,w in ipairs(blockedWords)do if tostring(reason):find(w,1,true)then return 'blocked' end end
 return 'unmodeled'
end
local function notifyItems()local P=FUSLive;if P and P.itemScore and P.itemScore.Changed then P.itemScore.Changed()end end
local function applyResult(rec,r)
 C.StoreItemComparison(rec.context,rec.signature,r)
 local done=itemEntry(rec.item,r)
 for k,v in pairs(done)do rec.entry[k]=v end
end
local function retryLater(rec,issue)
 C.itemRetries=C.itemRetries or{};local rk=rec.key..'#'..tostring(rec.revision);local tries=(C.itemRetries[rk] or 0)+1
 if tries>4 then return false end
 C.itemRetries[rk]=tries
 if rec.table[rec.key]==rec.entry then rec.table[rec.key]=nil end
 -- the failed capture already asked the client for the tooltip data; ask again shortly
 if C_Timer and C_Timer.After then C_Timer.After(3,notifyItems)end
 return true
end
local markFailed -- defined below, used here
local function finishSingle(rec,result,issue)
 if rec.revision~=C.simRevision then return end
 if C.IsTransientIssue(issue) and retryLater(rec,issue) then return end
 if issue or not result then rec.entry.state='unmodeled';rec.entry.reason=issue or'Keine Antwort';markFailed(rec,rec.entry.reason)
 else applyResult(rec,result) end
 notifyItems()
end
-- Only the item id (plus the small eligibility data) travels first; the PC asks for the full item
-- snapshot (stats, tooltip data) only for items its engine database does not know ("need").
local function leanCandidate(c)local t={};for k,v in pairs(c)do if k~='snapshot'then t[k]=v end end;return t end
-- A failed item is not asked again for a while (also not after a state change that clears the item list), and an
-- item whose data the client has not loaded is not sent at all: the PC can only refuse it.
C.failedItems=C.failedItems or{}
local function clockNow()return GetTime and GetTime()or 0 end
function markFailed(rec,reason,ageSeconds)
 C.failedItems[rec.key]={t=clockNow()-(ageSeconds or 0),reason=reason}
end
local function incompleteItem(rec)
 local it=rec.item;if type(it)~='table'then return false end
 if it.statsComplete==false then return true end
 if(it.itemClass==2 or it.weaponClass==2)and type(it.weapon)~='table'then return true end
 return false
end
local function deferIncomplete(rec)
 rec.entry.state='unmodeled';rec.entry.reason='Itemdaten noch nicht geladen; neuer Versuch gleich'
 markFailed(rec,rec.entry.reason,45) -- expires after 15 s
 if C_Item and C_Item.RequestLoadItemDataByID and rec.item and rec.item.id then pcall(C_Item.RequestLoadItemDataByID,rec.item.id)end
 if C_Timer and C_Timer.After then C_Timer.After(15,notifyItems)end
end
local function sendSingle(rec)
 local sent=rec.full and rec.candidate or leanCandidate(rec.candidate)
 local accepted=C.Request('item',{items={sent}},function(result,issue)
  local row=type(result)=='table' and type(result.candidates)=='table' and result.candidates[1]
  if row and row.need and not rec.full then
   if rec.revision==C.simRevision then
    if incompleteItem(rec)then deferIncomplete(rec);notifyItems();return end
    rec.full=true;return sendSingle(rec)
   end;return
  end
  finishSingle(rec,result,issue)
 end)
 if not accepted and rec.table[rec.key]==rec.entry then rec.table[rec.key]=nil end
end
local function sendBatch(recs)
 if #recs==1 then return sendSingle(recs[1])end
 local candidates={};for i,rec in ipairs(recs)do candidates[i]=rec.full and rec.candidate or leanCandidate(rec.candidate)end
 -- partial: the PC answers each candidate on its own, an item it cannot compute only marks itself
 local accepted=C.Request('item',{items=candidates,partial=true},function(result,issue)
  local live={};for _,rec in ipairs(recs)do if rec.revision==C.simRevision then live[#live+1]=rec end end
  if #live==0 then return end
  local rows=type(result)=='table' and result.candidates
  if issue or type(rows)~='table' or #rows<#recs or type(result.baselineDps)~='number' then
   if C.IsTransientIssue(issue) then
    for _,rec in ipairs(live)do if not retryLater(rec,issue)then rec.entry.state='unmodeled';rec.entry.reason=issue end end
    notifyItems()
   else
    -- one bad item must not poison the others: ask for each item on its own
    for _,rec in ipairs(live)do sendSingle(rec)end
   end
   return
  end
  local needs={}
  for i,rec in ipairs(recs)do
   if rec.revision==C.simRevision then
    local row=rows[i];local pct,dps=tonumber(row and row.pct),tonumber(row and row.dps)
    if row and row.need and not rec.full then
     if incompleteItem(rec)then deferIncomplete(rec) else rec.full=true;needs[#needs+1]=rec end
    elseif row and row.error then rec.entry.state='unmodeled';rec.entry.reason=tostring(row.error);markFailed(rec,rec.entry.reason)
    elseif pct and dps then
     applyResult(rec,{percent=pct-100,delta=dps-result.baselineDps,candidateDps=dps,baselineDps=result.baselineDps,
      warnings=result.warnings,targetArmorEstimated=result.targetArmorEstimated})
    else rec.entry.state='unmodeled';rec.entry.reason=(row and row.error)or'Keine Antwort' end
   end
  end
  if #needs>0 then sendBatch(needs)end;notifyItems()
 end)
 if not accepted then for _,rec in ipairs(recs)do if rec.table[rec.key]==rec.entry then rec.table[rec.key]=nil end end end
end
local function flushItems()
 local recs=pendingBatch;pendingBatch={}
 local group={}
 for _,rec in ipairs(recs)do
  if rec.revision==C.simRevision then group[#group+1]=rec;if #group==BATCH_MAX then sendBatch(group);group={} end end
 end
 if #group>0 then sendBatch(group)end
end
C.FlushItems=flushItems
local function queueItem(rec)
 pendingBatch[#pendingBatch+1]=rec
 if #pendingBatch>=BATCH_MAX or not(C_Timer and C_Timer.After)then return flushItems()end
 if not C.batchScheduled then
  C.batchScheduled=true
  C_Timer.After(BATCH_WAIT,function()C.batchScheduled=false;flushItems()end)
 end
end
-- Wearing rules (level, faction, armor/weapon proficiency, two-hand, unique): the same rules the PC applies.
-- Copied from Optimizers.lua without the Lua-model checks (the engine knows more items than the Lua model).
-- Skill rank of the player by name (professions, riding ...). Returns rank (nil = does not have it), known (false when
-- the client offers no way to ask).
function C.PlayerSkill(name)
 if type(GetNumSkillLines)=='function' and type(GetSkillLineInfo)=='function' then
  local ok,count=pcall(GetNumSkillLines)
  if ok and type(count)=='number' then
   for i=1,count do
    local okI,skillName,isHeader,_,rank=pcall(GetSkillLineInfo,i)
    if okI and not isHeader and skillName==name then return tonumber(rank)or 0,true end
   end
   return nil,true
  end
 end
 -- clients with the profession panel: GetProfessions() gives the indices of the learned professions
 if type(GetProfessions)=='function' and type(GetProfessionInfo)=='function' then
  local ok,a,b,c,d,e=pcall(GetProfessions)
  if ok then
   for _,index in ipairs({a,b,c,d,e})do
    local okI,skillName,_,rank=pcall(GetProfessionInfo,index)
    if okI and skillName==name then return tonumber(rank)or 0,true end
   end
   return nil,true
  end
 end
 return nil,false
end
-- Weapon skills are learned at a weapon master. true / false when the player's skill list shows it, nil when it cannot be
-- told (no skill API, or no weapon skill of the list is recognisable, e.g. because of different names).
function C.WeaponSkillKnown(subclass)
 if type(subclass)~='number' or type(GetItemSubClassInfo)~='function' then return nil end
 local ok,wanted=pcall(GetItemSubClassInfo,2,subclass);if not ok or type(wanted)~='string' or wanted=='' then return nil end
 local _,known=C.PlayerSkill(wanted);if not known then return nil end
 local rank=C.PlayerSkill(wanted);if rank then return true end
 -- the skill list must show at least one other weapon skill, otherwise its names cannot be compared
 for sub=0,20 do
  if sub~=subclass then
   local okI,name=pcall(GetItemSubClassInfo,2,sub)
   if okI and type(name)=='string' and name~='' and C.PlayerSkill(name) then return false end
  end
 end
 return nil
end
-- Requirements that do not depend on the level: restricted to other classes, or a profession the player lacks.
-- preview (dungeon drops): the skill rank does not count, the profession itself does.
local function requirementVerdict(item,preview)
 if type(item.allowedClasses)=='table' and #item.allowedClasses>0 then
  local mine=UnitClass and select(1,UnitClass('player'))
  local allowed=false
  for _,c in ipairs(item.allowedClasses)do if c==mine then allowed=true end end
  if mine and not allowed then return 'Nur fuer andere Klassen' end
 end
 if type(item.allowedRaces)=='table' and #item.allowedRaces>0 then
  local mine=UnitRace and select(1,UnitRace('player'))
  local allowed=false
  for _,r in ipairs(item.allowedRaces)do if r==mine then allowed=true end end
  if mine and not allowed then return 'Nur fuer andere Voelker' end
 end
 local need=item.requiresSkill
 if type(need)=='table' and need.name then
  local rank,known=C.PlayerSkill(need.name)
  if known then
   if rank==nil then return 'Benötigt Beruf '..tostring(need.name)..' (nicht erlernt)' end
   if not preview and rank<(need.rank or 0) then return 'Benötigt '..tostring(need.name)..' '..tostring(need.rank)..' (hast '..rank..')' end
  end
 end
end
C.RequirementVerdict=requirementVerdict
local function wearingRules(data,p,item,equipped,preview)
 -- preview (dungeon drops): the level requirement and the level of the armor tiers do not count
 if not preview and(item.minLevel or 1)>p.level then return 'Benötigt Level '..item.minLevel end
 if item.faction and item.faction~=p.faction then return 'Falsche Fraktion'end
 local rules=data.equipmentRules;if not rules then return 'Tragbarkeitsregeln fehlen'end
 -- levels 5-9 use the armor tiers of level 10 (the class tables start there)
 local maxArmor=0 for _,tier in ipairs(rules.armorTiers or {})do if preview or math.max(p.level,10)>=tier.minLevel then maxArmor=tier.maxSubclass end end
 local armor=item.itemSubclass or ({cloth=1,leather=2,mail=3,plate=4})[string.lower(item.armorType or '')]
 if item.slot~='back'and item.slot~='offhand'and armor and armor>=1 and armor<=4 and(not item.itemClass or item.itemClass==4)and armor>maxArmor then return 'Rüstung nicht tragbar'end
 if item.slot=='offhand'and equipped.mainhand and equipped.mainhand.twoHanded then return 'Zweihandwaffe angelegt'end
 if item.slot=='mainhand'or item.slot=='offhand'or item.slot=='ranged'then
  local wc,ws=item.weaponClass or item.itemClass,item.weaponSubclass or item.itemSubclass
  if wc==nil or ws==nil then return 'Waffentyp nicht erkannt'end
  local function contains(a,v)for _,x in ipairs(a or {})do if x==v then return true end end return false end
  local permitted=wc==2 and contains(rules.weaponSubclasses,ws)
  if item.slot=='ranged'then permitted=wc==2 and contains(rules.rangedSubclasses,ws)end
  if item.slot=='offhand'then permitted=(wc==2 and rules.dualWield and(preview or p.dualWield==true)and contains(rules.weaponSubclasses,ws))or wc==4 and(item.equipLoc=='INVTYPE_HOLDABLE'or(rules.shield and ws==6))end
  if not permitted then return 'Waffe oder Nebenhand nicht tragbar'end
  if item.twoHanded and not contains(rules.twoHandSubclasses,ws)then return 'Zweihand-Regeln fehlen'end
 end
 for slot,other in pairs(equipped)do if slot~=item.slot and(item.uniqueEquip or item.unique)and item.id==other.id then return 'Einzigartig anlegbar'end end
end
local verdictCache={}
local function localVerdict(item,preview)
 local P=FUSLive
 if not(P and P.capture and P.normalizeSnapshot)then return nil end
 if verdictCache.rev~=C.simRevision or not verdictCache.profile then
  verdictCache={rev=C.simRevision}
  local ok,snap=pcall(P.capture,true);if not ok or type(snap)~='table' then return nil end
  local ok2,profile=pcall(P.normalizeSnapshot,snap);if not ok2 or type(profile)~='table' then return nil end
  verdictCache.profile=profile;verdictCache.data=FUSLiveData and FUSLiveData[profile.class]
 end
 local profile,data=verdictCache.profile,verdictCache.data
 if not data then return nil end
 local ok3,reason=pcall(wearingRules,data,profile,item,profile.equipped or{},preview)
 if ok3 and reason then return reason end
end
-- preview=true: dungeon drops. They are computed even when the level is not reached yet; only the class decides
-- what is usable. Such entries live under their own key so a normal hover never sees them.
local function coreItem(link,preview)
 local P=FUSLive
 if externalRevision~=C.simRevision then externalItems={};externalRevision=C.simRevision end
 local key=tostring(link)..(preview and'#preview'or'')
 if externalItems[key]then return externalItems[key]end
 local failed=C.failedItems and C.failedItems[key]
 if failed and(GetTime and GetTime()or 0)-failed.t<60 then return{state='unmodeled',reason=failed.reason}end
 -- ForeverSimBridge (reads the items) is not loaded for this character: nothing can be said about the item
 if not(P and P.readItem)then return nil end
 -- The item is read and sent without its enchant (enchants never count); the key stays the link that was asked for.
 local plain=C.WithoutEnchant(link)
 local ok,item=pcall(P.readItem,plain,'MythicSim')
 if not ok or not item then return nil end
 local candidate=C.ItemCandidate(item,plain)
 if candidate.slot==nil then return{state='none'}end
 if preview then candidate.ignoreLevel=true end
 local level=read(UnitLevel,'player')
 if not level or level<5 or level>60 then return{state='unmodeled',reason='MythicSim unterstuetzt Stufe 5-60 (5-9 genaehert)'}end
 -- A profession or class requirement comes before the cache: an old result must not make such an item look usable
 local requirement=requirementVerdict(item,preview)
 if requirement then local entry={state='blocked',reason=requirement};externalItems[key]=entry;return entry end
 local reused,context,signature=C.CachedItemComparison(item,candidate,plain)
 if reused then externalItems[key]=reused;return reused end
 local reason=localVerdict(item,preview)
 if reason then
  local entry={state=wearableVerdict(reason),reason=reason};externalItems[key]=entry;return entry
 end
 -- Items without any stat that matters for this class cannot change the damage: answer 0 % right away,
 -- both for the auction house export and for hovering (no simulation, no pixel job).
 if C.AH and C.AH.Irrelevant then
  local why=C.AH.Irrelevant(item)
  if why then
   if C.collectOnly then return{state='irrelevant',reason=why}end
   local entry={state='ok',pct=0,delta=0,status='equal',reason=why,result={eligible=true,percent=0,delta=0,status='equal',item=item}}
   externalItems[key]=entry;return entry
  end
 end
 -- Auction house export: collect the complete records instead of queueing pixel jobs
 if C.collectOnly then C.collectOnly[#C.collectOnly+1]={candidate=candidate,context=context,signature=signature,item=item,link=link};return{state='busy'}end
 -- With the pixel transport switched off nothing can answer: say so instead of waiting forever
 if ForeverCoreBridgeDB and ForeverCoreBridgeDB.pixelOff then
  return{state='unmodeled',reason='Noch nicht berechnet. Pixel ist aus: im Auktionshaus FC Scan und FC Berechnen (dann /reload), oder /fc pixel an.'}
 end
 local entry={state='busy'};externalItems[key]=entry
 queueItem({key=key,entry=entry,item=item,candidate=candidate,context=context,signature=signature,revision=C.simRevision,table=externalItems})
 return entry
end
C.ItemResult=coreItem
local installBase=C.InstallAdapters
C.InstallAdapters=function()
 installBase();local P=FUSLive;if not P or C.extraInstalled then return end;C.extraInstalled=true
 if P.itemScore then
  local oldGet,oldPeek=P.itemScore.Get,P.itemScore.Peek
  P.itemScore.Get=function(link)if not enabled()then return oldGet(link)end;return coreItem(link)end
  P.itemScore.Peek=function(link)if not enabled()then return oldPeek(link)end;return externalRevision==C.simRevision and externalItems[tostring(link)]or nil end
 end
 -- Unsupported legacy calculations cannot silently use a different combat engine.
 if P.cancelJobs then P.cancelJobs('Berechnung an ForeverCore uebergeben')end
 local enqueue=P.enqueue
 P.enqueue=function(fn,done,valid,priority)
  if not enabled()then return enqueue(fn,done,valid,priority)end
  if done then done(nil,'Diese Berechnung ist noch nicht an MythicSim angebunden.')end
 end
 if P.app and P.app.Open then
  local open=P.app.Open
  P.app.Open=function(...)if C.resultView then C.resultView:Hide()end;return open(...)end
 end
end
