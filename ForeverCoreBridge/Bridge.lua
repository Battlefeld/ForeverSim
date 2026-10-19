local C=ForeverCoreClient
local P=C.protocol
C.queue={};C.sequence=0;C.slot=1;C.revision=0;C.simRevision=0;C.status='ForeverCore starten';C.session=tostring(time and time()or 0)..':'..tostring(math.floor((GetTime and GetTime()or 0)*1000))
local pixels={};local lastPaint={};local ticker=CreateFrame('Frame');local untilFrame,untilInbox=0,0
-- Keep the entire transmission strip invisible while no frame is being sent.
local function clear()if C.pixelFrame then C.pixelFrame:Hide()end end
-- The PC reads a cell as "1" when R+G+B >= 384 (mid grey). "low" keeps both levels close to
-- mid grey (about 112 and 143 of 255, margin +-45 on the sum) so the strip is a faint grey bar
-- instead of a flickering black/white one. /fc pixel normal|low switches; a timeout while "low"
-- falls back to "normal" automatically.
C.pixelLevels={normal={0,1},low={0.44,0.56}}
-- Seconds each frame stays on screen. The PC samples every 40 ms, so 0.10 s is read reliably and halves
-- the time of a full pass (35 frames = 3.5 s instead of 6.3 s). A timeout restores 0.18 s.
function C.FrameSeconds()
 local v=ForeverCoreBridgeDB and tonumber(ForeverCoreBridgeDB.pixelFrame)
 if v and v>=.05 and v<=.5 then return v end
 return .10
end
function C.PixelStyle()
 local s=ForeverCoreBridgeDB and ForeverCoreBridgeDB.pixelStyle
 if s=='normal' then return 'normal' end
 return 'low'
end
local function paint(message)
 local lv=C.pixelLevels[C.PixelStyle()];local lo,hi=lv[1],lv[2]
 -- Only repaint bytes that changed (remote improvement); a style/size change forces a full repaint.
 local key=C.PixelStyle()..'/'..tostring(P.cell)
 if C.paintKey~=key then C.paintKey=key;for k in pairs(lastPaint)do lastPaint[k]=nil end end
 for byte=1,P.bytes do
  local b=message:byte(byte)or 0
  if lastPaint[byte]~=b then
   lastPaint[byte]=b
   for bit=0,7 do local v=math.floor(b/2^(7-bit))%2==1 and hi or lo;pixels[(byte-1)*8+bit+1]:SetColorTexture(v,v,v,1)end
  end
 end
 -- Show only after every pixel is populated, never a blank dark strip.
 if C.pixelFrame then C.pixelFrame:Show()end
end
local function makePixels()
 local scale=UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()or 1;local size=P.cell/math.max(.01,scale)
 local f=CreateFrame('Frame',nil,UIParent);f:SetFrameStrata('TOOLTIP');f:SetSize(P.columns*size,P.rows*size);f:SetPoint('TOPLEFT',UIParent,'TOPLEFT',0,0);f:EnableMouse(false)
 for i=0,P.columns*P.rows-1 do local t=f:CreateTexture(nil,'OVERLAY');t:SetSize(size,size);t:SetPoint('TOPLEFT',f,'TOPLEFT',i%P.columns*size,-math.floor(i/P.columns)*size);pixels[i+1]=t end
 C.pixelFrame=f;clear()
end
-- Cell size in desktop pixels (1-8; the PC decoder calibrates 1..8 automatically). The strip always
-- keeps its 128:1 shape: 1 -> 512x4 px, 2 -> 1024x8 px (default), 3 -> 1536x12 px ...
local function layoutPixels()
 local scale=UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()or 1;local size=P.cell/math.max(.01,scale)
 if not C.pixelFrame then return end
 C.pixelFrame:SetSize(P.columns*size,P.rows*size)
 for i=0,P.columns*P.rows-1 do local t=pixels[i+1];if t then t:SetSize(size,size);t:ClearAllPoints();t:SetPoint('TOPLEFT',C.pixelFrame,'TOPLEFT',i%P.columns*size,-math.floor(i/P.columns)*size)end end
end
function C.ApplyPixelCell(n)
 n=tonumber(n);if not n or n<1 or n>8 then return false,'Zellgroesse 1 bis 8 (Standard 2)' end
 n=math.floor(n+.5)
 local physical=GetPhysicalScreenSize and select(1,GetPhysicalScreenSize())or((GetScreenWidth and GetScreenWidth()or 0)*(UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()or 1))
 if type(physical)=='number' and physical>0 and P.columns*n>physical then return false,'Zu breit fuer den Bildschirm (maximal '..math.max(1,math.floor(physical/P.columns))..')' end
 P.cell=n;if ForeverCoreBridgeDB then ForeverCoreBridgeDB.pixelCell=n end
 layoutPixels();return true
end
function C.Say(s)C.status=s;if C.statusLabel then C.statusLabel:SetText(s..' · Slots '..math.max(0,P.slots-C.slot+1))end end
-- Hard change (gear, level, talents, ...): invalidates in-flight results.
-- Soft change (noisy events like quest/bag/pet updates): only schedules a refresh,
-- never bumps the revision, so running jobs are not thrown away.
local MIN_AUTO_GAP=6
local function now()return GetTime and GetTime()or 0 end
function C.MarkChanged(soft,delay)
 if not soft then C.revision=C.revision+1;if C.lastRoute then C.lastRoute.stale=true end end
 -- Never extend a running countdown: constant event spam must not starve the refresh.
 local d=delay or 2.0
 if C.dirty then C.debounce=math.min(C.debounce or d,d) else C.debounce=d end
 C.dirty=true
end
-- Routes need a quest/route addon (ForeverDungeonQuest exports _G.ForeverCoreFDQ). Without it the
-- simulator never sends route jobs; the route glue below stays dormant until such an addon returns.
function C.RouteAvailable()return _G.ForeverCoreFDQ~=nil end
function C.RequestRoute()
 if not C.RouteAvailable()then C.Say('Routen: kein Quest-/Routen-Addon geladen (ForeverDungeonQuest wird neu gebaut)');return false end
 return C.Request('route',nil,C.ApplyRoute)
end
function C.Request(kind,payload,callback,opts)
 if ForeverCoreBridgeDB and ForeverCoreBridgeDB.pixelOff and not(opts and opts.export)then return false end
 if kind=='item' and #C.queue>=5 then return false end
 if #C.queue>=24 then C.Say('Warteschlange voll; laufende Berechnungen abwarten');return false end
 if C.slot>P.slots then C.Say('Antwortslots verbraucht: /reload erforderlich');return false end
 for _,job in ipairs(C.queue)do if job.kind==kind and(kind=='route'or kind=='ping'or kind=='rotation')then return false end end
 if C.pending and C.pending.kind==kind and(kind=='route'or kind=='ping'or kind=='rotation')then return false end
 C.queue[#C.queue+1]={kind=kind,payload=payload or{},callback=callback,timeout=opts and opts.timeout,tuning=opts and opts.tuning,export=opts and opts.export};return true
end
-- Data the client may not deliver yet (right after the login or /reload). The PC refuses a whole state when one
-- of these is missing, and then every job fails, so the job waits and tries again shortly. Class independent:
--   worn items without stats / weapon damage, the hunter quiver and ammunition, the hunter pet, and the demon
--   of a warlock (snapshot field petLive). Only an explicit "unreadable" counts; "none" is a valid answer.
-- Returns a reason text and the ids of items the client should load, or nil when everything is readable.
function C.StateUnreadyReason(sim)
 if type(sim)~='table' then return nil end
 local why,ids={}, {}
 if type(sim.equipped)=='table' then
  local names={}
  for _,it in pairs(sim.equipped)do
   -- fishing poles and mining picks (weapon subclass 14 / 20) carry no damage values and never will
   if type(it)=='table' and(it.statsComplete==false or(it.itemClass==2 and it.itemSubclass~=14 and it.itemSubclass~=20 and type(it.weapon)~='table'))then
    ids[#ids+1]=it.id;names[#names+1]=tostring(it.name or it.id)
   end
  end
  if #names>0 then why[#why+1]='angelegte Items ('..table.concat(names,', ')..')' end
 end
 local h=sim.hunter
 if type(h)=='table' then
  if type(h.quiver)=='table' and h.quiver.status=='unreadable' then why[#why+1]='Koecher/Munitionsbeutel' end
  if type(h.ammo)=='table' and h.ammo.status=='unreadable' then why[#why+1]='Munition' end
  if sim.petActive and type(h.pet)=='table' and h.pet.status=='unreadable' then why[#why+1]='Begleiter' end
 end
 if sim.petActive and type(sim.petLive)=='table' and sim.petLive.status=='unreadable' then why[#why+1]='Daemon' end
 if #why==0 then return nil end
 return table.concat(why,', '),ids
end
function C.ExportSlot()return(P.slots or 2048)-248 end
local receivePing -- defined further down, used when the first job of a session needs a ping
local function begin()
 if C.pending or #C.queue==0 then return end
 if InCombatLockdown and InCombatLockdown()then return end
 local job=table.remove(C.queue,1);local ok,state=true,{}
 -- Nothing is painted at login any more. The connection is checked once, right before the first real job
 -- (the ping answer tells which features the running ForeverCore.exe has, e.g. state references).
 if C.needPing and job.kind~='ping' and job.kind~='sources' then
  C.needPing=false
  table.insert(C.queue,1,job)
  job={kind='ping',payload={},callback=function(result)receivePing(result)end}
 end
 if job.kind~='ping'and job.kind~='sources'then ok,state=pcall(C.Capture or function()return{}end,job.kind)end
 if not ok or not state then C.Say('Charakterdaten nicht lesbar');if job.callback then job.callback(nil,'Charakterdaten nicht lesbar')end;return end
 -- Simulation jobs consume only the SIM snapshot; route databases can exceed 40 KB.
 if job.kind~='route'and type(state.sim)=='table'then state={sim=state.sim}end
 -- Unreadable character data (see C.StateUnreadyReason): wait and try again; an export is not stored half-read.
 if job.kind~='route' and type(state.sim)=='table' then
  local reason,ids=C.StateUnreadyReason(state.sim)
  if reason then
   job.readyTries=(job.readyTries or 0)+1
   for _,id in ipairs(ids or{})do if id and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID,id)end end
   if job.readyTries<=8 and C_Timer and C_Timer.After then
    C.Say('Charakterdaten noch nicht lesbar: '..reason..'; neuer Versuch in 3 s ('..job.readyTries..'/8)')
    C_Timer.After(3,function()table.insert(C.queue,1,job)end)
    return
   end
   if job.export then C.Say('Charakterdaten nicht lesbar ('..reason..'): Export abgebrochen, bitte nochmal FC Berechnen');return end
   C.Say('Charakterdaten unvollstaendig gelesen ('..reason..'): Auftrag wird trotzdem gesendet')
  end
 end
 -- The character state (about 10 KB) is sent once; afterwards the PC is asked to reuse it by key, which turns
 -- a hover job from ~45 frames into ~3. The key is the stable-state hash that also keys the result cache.
 local stateKey
 if job.kind~='route'and job.kind~='ping'and job.kind~='sources'and type(state.sim)=='table'and C.SimCacheContext then
  local okKey,key=pcall(C.SimCacheContext);if okKey and type(key)=='string'and key~=''then stateKey=key end
 end
 job.stateKey=stateKey
 local sendState=state
 -- only when the running ForeverCore.exe has said in its ping answer that it understands state references
 if stateKey and C.stateRefOK and not job.export and not job.noStateRef and C.stateKnown==stateKey then sendState=nil end
 job.stateOmitted=sendState==nil
 C.sequence=C.sequence+1;job.sequence=C.sequence;job.revision=tostring(job.kind=='route' and C.revision or C.simRevision);job.elapsed=0;job.part=0
 local message=C.json({schema=3,session=C.session,sequence=job.sequence,revision=job.revision,kind=job.kind,replyStart=job.export and C.ExportSlot() or C.slot,stateKey=stateKey,state=sendState,payload=job.payload})
 if job.export then if C.StoreExport then C.StoreExport(job,message)end;return end
 if #message>65536 then C.Say('Charakterpaket zu gross');if job.callback then job.callback(nil,'Charakterpaket zu gross')end;return end
 job.message=message;job.frames=math.ceil(#message/P.payload);job.id=C.crc(C.session..':'..job.sequence);C.pending=job;untilFrame=0;untilInbox=2;C.Say('Berechnung: '..job.kind)
end
local function deliver()
 local p=C.pending;if not p then return end
 if C.slot>P.slots then C.pending=nil;clear();C.Say('Antwortslots verbraucht: /reload erforderlich');if p.callback then p.callback(nil,'Antwortslots verbraucht')end;return end
 if InCombatLockdown and InCombatLockdown()then return end
 local name='FC3_S'..string.format('%04d',C.slot);C.slot=C.slot+1;ForeverCore_Reply=nil
 local loader=C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
 if not loader then C.pending=nil;clear();C.Say('LoadAddOn fehlt');return end
 local ok,loaded=pcall(loader,name);if not ok or not loaded then return end
 local r=ForeverCore_Reply
 if type(r)~='table'or r.schema~=3 or r.session~=(p.session or C.session) or r.sequence~=p.sequence or r.revision~=p.revision or r.kind~=p.kind then return end
 C.pending=nil;clear()
 if p.kind=='route'and ForeverCoreBridgeDB.enabled==false then C.Say('Externe Planung pausiert');return end
 if r.status~='ok' and tostring(r.message or''):find('STATE_UNKNOWN',1,true)then
  -- the PC restarted or forgot the state: send it in full once more, in front of everything else
  C.stateKnown=nil;if ForeverCoreBridgeDB then ForeverCoreBridgeDB.stateKnown=nil end
  table.insert(C.queue,1,{kind=p.kind,payload=p.payload,callback=p.callback,timeout=p.timeout,tuning=p.tuning,noStateRef=true})
  return
 end
 if r.status=='ok' and p.stateKey then C.stateKnown=p.stateKey;if ForeverCoreBridgeDB then ForeverCoreBridgeDB.stateKnown=p.stateKey end end
 if r.status~='ok' and p.stateOmitted then C.stateKnown=nil;if ForeverCoreBridgeDB then ForeverCoreBridgeDB.stateKnown=nil end end
 if r.status~='ok'then C.Say(r.message or 'Berechnung fehlgeschlagen');if p.callback then p.callback(nil,r.message)end;return end
 if p.kind~='ping'and p.kind~='sources'and not p.resumed and p.revision~=tostring(p.kind=='route' and C.revision or C.simRevision)then C.Say('Zustand geaendert: Ergebnis verworfen');C.MarkChanged(true,2);if p.callback then p.callback(nil,'Zustand geaendert')end;return end
 C.Say('Verbunden · '..p.kind..' fertig');if p.callback then p.callback(r.result)end
end
function receivePing(result)
 if type(result)~='table' then return end
 C.stateRefOK=result.stateRefs==true
 if ForeverCoreBridgeDB then ForeverCoreBridgeDB.stateRefOK=C.stateRefOK or nil end
 local revision=result.engineRevision
 if type(revision)=='string' and revision~='' then
  if C.engineRevision~=revision then
   local had=C.engineRevision
   C.itemCacheContext=nil;C.engineRevision=revision
   if ForeverCoreBridgeDB then ForeverCoreBridgeDB.lastEngineRevision=revision end
   -- A different engine invalidates stored comparisons; a first-time confirmation does not.
   if had then C.MarkChanged() end
  end
 end
end
-- Automatic strip tuning: try the least noticeable variant first; the first one the PC can read
-- is stored. Each probe is a short ping, so a missing ForeverCore.exe costs about 80 s once.
local PIXEL_CANDIDATES={{cell=1,style='low'},{cell=2,style='low'},{cell=2,style='normal'},{cell=3,style='normal'}}
function C.StartPixelTune(i)
 i=i or 1;local cand=PIXEL_CANDIDATES[i]
 if not cand or not ForeverCoreBridgeDB or ForeverCoreBridgeDB.enabled==false or ForeverCoreBridgeDB.pixelOff then return end
 C.ApplyPixelCell(cand.cell);ForeverCoreBridgeDB.pixelStyle=cand.style;C.tuning=i
 C.Say(string.format('Pixelstreifen wird angepasst (%d/%d) ...',i,#PIXEL_CANDIDATES))
 local queued=C.Request('ping',{},function(result)
  if result then
   ForeverCoreBridgeDB.pixelTuned={cell=cand.cell,style=cand.style};C.tuning=nil
   receivePing(result);C.Say(string.format('Pixelstreifen: Zelle %d (%dx%d px), Kontrast %s (automatisch)',cand.cell,P.columns*cand.cell,P.rows*cand.cell,cand.style))
  elseif PIXEL_CANDIDATES[i+1] then C.StartPixelTune(i+1)
  else
   C.tuning=nil;C.ApplyPixelCell(2);ForeverCoreBridgeDB.pixelStyle='low';ForeverCoreBridgeDB.pixelFrame=.18
   C.Say('Pixelstreifen: keine Verbindung - laeuft ForeverCore.exe? (/fc pixel auto wiederholt die Anpassung)')
  end
 end,{timeout=20,tuning=true})
 if not queued then C.tuning=nil end
end
local function makeStatus()
 local f=CreateFrame('Frame',nil,UIParent,'BackdropTemplate');f:SetSize(520,140);f:SetPoint('CENTER');if f.SetBackdrop then f:SetBackdrop({bgFile='Interface\\Tooltips\\UI-Tooltip-Background'});f:SetBackdropColor(.025,.04,.08,.96)end
 local title=f:CreateFontString(nil,'OVERLAY','GameFontNormalLarge');title:SetPoint('TOPLEFT',14,-14);title:SetText('ForeverCore 0.6.0 · Verbindung')
 C.statusLabel=f:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');C.statusLabel:SetPoint('TOPLEFT',14,-43);C.statusLabel:SetWidth(490);C.statusLabel:SetJustifyH('LEFT')
 local function button(text,x,fn)local b=CreateFrame('Button',nil,f,'UIPanelButtonTemplate');b:SetSize(115,25);b:SetPoint('BOTTOMLEFT',x,15);b:SetText(text);b:SetScript('OnClick',fn)end
 button('Verbindung',14,function()C.Request('ping',{},receivePing)end);button('Route',140,function()C.RequestRoute()end);button('Simulation',266,function()C.Request('sim',{},C.ApplySim)end);button('Schliessen',392,function()f:Hide()end)
 C.window=f;f:Hide();C.Say(C.status)
end
ticker:RegisterEvent('PLAYER_LOGIN')
for _,event in ipairs({'QUEST_LOG_UPDATE','QUEST_TURNED_IN','QUEST_ACCEPTED','PLAYER_LEVEL_UP','PLAYER_EQUIPMENT_CHANGED','PLAYER_TALENT_UPDATE','TRAIT_CONFIG_UPDATED','SKILL_LINES_CHANGED','SPELLS_CHANGED','BAG_UPDATE_DELAYED','ZONE_CHANGED_NEW_AREA','GROUP_ROSTER_UPDATE','UNIT_PET','UNIT_LEVEL','PET_UI_UPDATE'})do pcall(ticker.RegisterEvent,ticker,event)end
ticker:SetScript('OnEvent',function(_,event,questId)
 if event=='UNIT_LEVEL' and questId~='player' and questId~='pet' then return end
 if event=='UNIT_PET' and questId~='player' then return end
 if event=='QUEST_TURNED_IN'and type(questId)=='number'and C.public(questId)then C.extraCompleted=C.extraCompleted or{};C.extraCompleted[questId]=true end
 if event=='PLAYER_LOGIN'then ForeverCoreBridgeDB=ForeverCoreBridgeDB or{enabled=true};C.engineRevision=C.engineRevision or ForeverCoreBridgeDB.lastEngineRevision;do local c=tonumber(ForeverCoreBridgeDB.pixelCell);if c and c>=1 and c<=8 then P.cell=math.floor(c)end end;makePixels();makeStatus();if C.InstallAdapters then C.InstallAdapters()end;C.MarkChanged();if ForeverCoreBridgeDB.enabled then if ForeverCoreBridgeDB.pixelTuned then C.stateRefOK=ForeverCoreBridgeDB.stateRefOK==true;C.stateKnown=ForeverCoreBridgeDB.stateKnown;C.needPing=not C.stateRefOK else C.StartPixelTune(1) end end;return end
 -- Noisy events fire constantly (quest log refreshes, bag updates, pet bar):
 -- refresh later and without invalidating running jobs.
 if event=='QUEST_LOG_UPDATE' or event=='BAG_UPDATE_DELAYED' or event=='PET_UI_UPDATE' or event=='SKILL_LINES_CHANGED' then
  C.MarkChanged(true,5);return
 end
 if event=='GROUP_ROSTER_UPDATE' or event=='ZONE_CHANGED_NEW_AREA' then C.MarkChanged(true,3);return end
 C.MarkChanged(false,1.5)
 -- Sim results depend on gear, level, talents, spellbook and pet; quest/bag/zone events only touch the route.
 if event=='PLAYER_LEVEL_UP' or event=='PLAYER_EQUIPMENT_CHANGED' or event=='PLAYER_TALENT_UPDATE'
   or event=='TRAIT_CONFIG_UPDATED' or event=='SPELLS_CHANGED' or event=='UNIT_PET' or event=='UNIT_LEVEL' then C.simRevision=C.simRevision+1 end
end)
ticker:SetScript('OnUpdate',function(_,elapsed)
 if not C.pixelFrame then return end
 if C.dirty then C.debounce=(C.debounce or 0)-elapsed;if C.debounce<=0 and not C.pending and #C.queue==0 and now()-(C.lastAutoAt or -1e9)>=MIN_AUTO_GAP then C.dirty=false;C.lastAutoAt=now();if ForeverCoreBridgeDB and ForeverCoreBridgeDB.enabled~=false and C.RouteAvailable()then C.Request('route',nil,C.ApplyRoute)end end end
 -- Re-simulate meaningful character changes only when idle and outside combat.
 -- Results refresh the rotation silently; opening a menu is never required.
 if C.autoRotationDirty and not C.pending and #C.queue==0 and not C.dirty
   and now()>=(C.autoRotationAt or 0) and now()-(C.lastAutoAt or -1e9)>=MIN_AUTO_GAP
   and ForeverCoreBridgeDB and ForeverCoreBridgeDB.enabled~=false and not(InCombatLockdown and InCombatLockdown())then
  C.autoRotationDirty=false;C.lastAutoAt=now()
  C.Request('rotation',{autoRotations=true},function(result,issue)
   if C.ApplySim then C.ApplySim(result,issue,true)end
  end)
 end
 begin();local p=C.pending;if not p then return end
 p.elapsed=p.elapsed+elapsed;untilFrame=untilFrame-elapsed;untilInbox=untilInbox-elapsed
 if untilFrame<=0 and not p.noPaint and not(InCombatLockdown and InCombatLockdown())then
  local start=p.part*P.payload+1;paint(C.frame(p.id,p.part,p.frames,p.message:sub(start,start+P.payload-1)));p.part=(p.part+1)%p.frames;untilFrame=C.FrameSeconds()
 end
 if untilInbox<=0 then untilInbox=(p.elapsed>=p.frames*C.FrameSeconds()) and 1 or 2;deliver()end
 if C.pending and p.elapsed>(p.timeout or 180) then C.pending=nil;clear();C.stateKnown=nil;if ForeverCoreBridgeDB then ForeverCoreBridgeDB.stateKnown=nil end
  if p.tuning or p.resumed then
   -- probing a pixel strip variant: the callback decides about the next variant
  elseif C.FrameSeconds()<.18 and ForeverCoreBridgeDB then ForeverCoreBridgeDB.pixelFrame=.18;ForeverCoreBridgeDB.pixelTuned=nil;C.Say('Zeitlimit: Bilddauer auf 0,18 s zurueckgestellt (/fc pixel tempo schnell zum Testen)')
  elseif C.PixelStyle()=='low' and ForeverCoreBridgeDB then ForeverCoreBridgeDB.pixelStyle='normal';ForeverCoreBridgeDB.pixelTuned=nil;C.Say('Zeitlimit: Pixelstreifen auf normalen Kontrast gestellt (/fc pixel auto zum erneuten Anpassen)')
  elseif P.cell~=2 and ForeverCoreBridgeDB then C.ApplyPixelCell(2);ForeverCoreBridgeDB.pixelTuned=nil;C.Say('Zeitlimit: Streifengroesse auf Standard 2 gestellt')
  else C.Say('Zeitlimit: ForeverCore/Fenstermodus pruefen') end
  if p.callback then p.callback(nil,'Zeitlimit')end end
end)
-- One public entry point for ForeverCore, ForeverSim and ForeverDungeonQuest.
-- Preserve /fus and /fdq as compatibility aliases; the player only needs /fc.
local function openMain(section)
 local sim=_G.FUSLive
 if sim and sim.app and sim.app.Open then sim.app.Open(section or 'overview');return true end
 return false
end
local function openQuests()
 local ns=_G.ForeverCoreFDQ
 if ns and ns.OverviewUI and ns.OverviewUI.Show then ns.OverviewUI.Show();return true end
 if ns and ns.GuideUI and ns.GuideUI.Show then ns.GuideUI.Show();return true end
 return false
end
SLASH_FOREVERCORE1='/fc'
SlashCmdList.FOREVERCORE=function(msg)
 msg=(msg or''):lower():gsub('^%s+',''):gsub('%s+$','')
 if msg=='' or msg=='ui' or msg=='home' then
  if not openMain('overview') and C.window then C.window:Show();C.Say('ForeverSim nicht geladen')end
 elseif msg=='gear' or msg=='items' then
  if not openMain('gear')then C.Say('ForeverSim nicht geladen')end
 elseif msg=='talents' or msg=='talente' then
  if not openMain('talents')then C.Say('ForeverSim nicht geladen')end
 elseif msg=='rotation' or msg=='rota' then
  if not openMain('rotation')then C.Say('ForeverSim nicht geladen')end
 elseif msg=='quests' or msg=='quest' or msg=='guide' then
  if not openMain('quests') and not openQuests()then C.Say('Quests: ForeverDungeonQuest ist nicht installiert (wird neu gebaut)')end
 elseif msg=='dungeons' or msg=='dungeon' then
  if not openMain('dungeons')then C.Say('ForeverSim nicht geladen')end
 elseif msg=='advanced' or msg=='erweitert' then
  if not openMain('diagnostics')then C.Say('ForeverSim nicht geladen')end
 elseif msg=='status' then
  if C.window then C.window:Show();C.Say(C.status)end
 elseif msg=='ping'then C.Request('ping',{},receivePing)
 elseif msg=='route'then C.RequestRoute()
 elseif msg=='sim'then C.Request('sim',{},C.ApplySim)
 elseif msg=='leveling'then if _G.FUSLive and FUSLive.actions then FUSLive.actions.RunLeveling()end
 elseif msg=='test'and C.Diagnose then C.Diagnose()
 elseif msg=='sources'then C.Request('sources',{},function(result)C.lastSources=result;if result and result.message then C.Say(result.message)end end)
 elseif msg:match('^pixel %a+ %d+$') and (msg:match('^pixel size')or msg:match('^pixel breite')or msg:match('^pixel groesse')) then
  local ok,why=C.ApplyPixelCell(msg:match('%d+$'));if ok then ForeverCoreBridgeDB.pixelTuned={manual=true}; C.Say(string.format('Pixelstreifen: Zelle %d px = %dx%d px',P.cell,P.columns*P.cell,P.rows*P.cell)) else C.Say(why) end
 elseif msg=='pixel aus' or msg=='pixel an' then
  ForeverCoreBridgeDB.pixelOff=(msg=='pixel aus') or nil
  clear()
  local text=ForeverCoreBridgeDB.pixelOff and 'Pixelstreifen AUS: es wird nichts mehr gemalt, Hover-Berechnungen laufen nicht ueber den PC. Auktionshaus (FC Scan/FC Berechnen mit /reload) geht weiter.' or 'Pixelstreifen wieder AN (ForeverCore.exe ohne -keine-aufnahme starten).'
  C.Say(text);if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage('|cff66ccffForeverCore:|r '..text)end
 elseif msg=='pixel tempo schnell' or msg=='pixel tempo normal' then ForeverCoreBridgeDB.pixelFrame=(msg=='pixel tempo schnell') and .10 or .18;ForeverCoreBridgeDB.pixelTuned={manual=true};C.Say('Bilddauer: '..tostring(C.FrameSeconds())..' s')
 elseif msg=='pixel auto' then ForeverCoreBridgeDB.pixelTuned=nil;C.StartPixelTune(1)
 elseif msg=='pixel low' or msg=='pixel normal' then ForeverCoreBridgeDB.pixelTuned={manual=true};ForeverCoreBridgeDB.pixelStyle=msg:match('%a+$');C.Say('Pixelstreifen: '..C.PixelStyle())
 elseif msg=='off'then ForeverCoreBridgeDB.enabled=false;C.dirty=false;C.autoRotationDirty=false;C.queue={};C.Say('Externe Planung pausiert')
 elseif msg=='on'then ForeverCoreBridgeDB.enabled=true;C.MarkChanged()
 else if C.window then C.window:Show();C.Say('Unbekannter Befehl; /fc startet das Hauptfenster')end end
end
