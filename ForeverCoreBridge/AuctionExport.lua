-- Auction house bulk path.
--   FC Scan / /fc ah scan      read the auction house (the whole list if the client offers ReplicateItems,
--                              otherwise what the browse results show); remember every wearable item
--   FC Berechnen / /fc ah calc build ONE job with all wearable items, store it in the SavedVariables;
--                              the player types /reload, ForeverCore.exe computes everything and answers
--                              through the usual slots
--   /fc ah top [n]             best upgrades with price
--   /fc ah key <item link>     shows the cache key of a link and whether a stored result exists
--   /fc ah diag | clear        client capabilities | forget everything
-- Nothing here runs by itself except harvesting what the auction house already shows (no query is sent).
local C=ForeverCoreClient
local AH={};C.AH=AH
local MAX_KEEP,MAX_EXPORT,VERSION=8000,400,5
local SKIP_LOC={INVTYPE_BAG=true,INVTYPE_AMMO=true,INVTYPE_QUIVER=true,INVTYPE_TABARD=true,INVTYPE_BODY=true,INVTYPE_NON_EQUIP=true,INVTYPE_NON_EQUIP_IGNORE=true}
local function db()ForeverCoreBridgeDB=ForeverCoreBridgeDB or{};return ForeverCoreBridgeDB end
-- Every scan attempt is noted with its time and result (last 30), so the real rule behind the wait can be
-- read from the data: /fc ah scans
local function logScan(kind,detail)
 local d=db();d.ahScanLog=type(d.ahScanLog)=='table' and d.ahScanLog or{}
 local log=d.ahScanLog
 log[#log+1]={t=time and time()or 0,kind=kind,detail=detail,boot=GetTime and math.floor(GetTime())or 0}
 while #log>30 do table.remove(log,1)end
end
AH.LogScan=logScan
-- C.Say only updates a status label. C.Chat (UI.lua) decides what goes into the chat window: answers to typed
-- commands and problems always, the rest only when the player wants every message. loud: always into the chat.
local function say(text,loud)
 AH.lastMessage=tostring(text)
 if C.Chat then return C.Chat(text,loud)end
 if C.Say then C.Say(text)end
 if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then DEFAULT_CHAT_FRAME:AddMessage('|cff66ccffForeverCore:|r '..tostring(text))end
end
-- Windows that show the list (UI) register here and are told when scan, calculation or results change.
AH.listeners={}
function AH.OnChanged(fn)AH.listeners[#AH.listeners+1]=fn end
local function changed()for _,fn in ipairs(AH.listeners)do pcall(fn)end end
AH.Changed=changed
-- items[key]=lowest price, results[key]={pct,delta}. The key is the normalised item link, so random-suffix
-- variants of one item id ("of the Bear" ...) stay separate. A new VERSION empties older data.
-- The list is kept per character: what the scan keeps depends on class and level (armor type, weapons).
local function charKey()
 local ok,guid=pcall(UnitGUID,'player');if ok and guid then return tostring(guid)end
 local name=UnitName and UnitName('player');return tostring(name or'unknown')
end
local function store()
 local d=db()
 d.ah=nil -- first layout: one list for the whole account
 if type(d.ahChars)~='table' then d.ahChars={}end
 local key=charKey();local s=d.ahChars[key]
 if type(s)~='table' or s.version~=VERSION or type(s.items)~='table' then
  s={version=VERSION,time=0,items={},count=0,results={}};d.ahChars[key]=s
 end
 -- Enchants never count (C.NormalizeLink): enchanted entries of older scans are merged into the plain item once,
 -- keeping the lower price; their results were calculated with the enchant and are dropped.
 if not s.plainKeys and C.NormalizeLink then
  local moved={}
  for k,price in pairs(s.items)do
   local plain=C.NormalizeLink(k)
   if plain~=k then moved[#moved+1]={from=k,to=plain,price=price}end
  end
  for _,m in ipairs(moved)do
   s.items[m.from]=nil;s.results=s.results or{};s.results[m.from]=nil
   local old=s.items[m.to]
   if old==nil then s.items[m.to]=m.price
   else s.count=math.max(0,(s.count or 0)-1);if(tonumber(m.price)or 0)>0 and((tonumber(old)or 0)==0 or m.price<old)then s.items[m.to]=m.price end end
  end
  s.plainKeys=true
 end
 return s
end
AH.Store=store
-- MythicSim calculates levels 10 to 60 and needs ForeverSimBridge (item reading, class data). Returns a reason text
-- when this character cannot be calculated, nil when everything is there.
function AH.CannotCalculate()
 local level=tonumber(UnitLevel and UnitLevel('player'))
 if level and level<5 then return string.format('MythicSim rechnet ab Stufe 5 (aktuell Stufe %d).',level)end
 if not(FUSLive and FUSLive.readItem)then return 'ForeverSimBridge ist fuer diesen Charakter nicht geladen (Addon-Liste der Charakterauswahl pruefen).'end
 local _,token=UnitClass('player')
 local data=FUSLiveData and(FUSLiveData[token]or FUSLiveData[tostring(token):lower()])
 if not(data and data.equipmentRules)then return 'Keine Klassendaten fuer '..tostring(token)..' (ForeverSimBridge geladen? Stufe 10 erreicht?).'end
 return nil
end
local function idOf(link)return tonumber(tostring(link):match('item:(%d+)'))end
local equipCache={}
local function isEquipment(id)
 local known=equipCache[id];if known~=nil then return known end
 local fn=(C_Item and C_Item.GetItemInfoInstant)or GetItemInfoInstant
 local result=true
 if type(fn)=='function' then
  local ok,_,_,_,loc=pcall(fn,id)
  result=ok and type(loc)=='string' and loc~='' and not SKIP_LOC[loc] or false
 end
 equipCache[id]=result;return result
end
-- What this character can wear, from the data the client has at once (item class and subclass):
-- armor type up to what the class and level allow, weapon types the class can use.
local function scanVerdict(id)
 local fn=(C_Item and C_Item.GetItemInfoInstant)or GetItemInfoInstant
 if type(fn)~='function' then return nil end
 local ok,_,_,_,loc,_,classID,subID=pcall(fn,id);if not ok then return nil end
 local _,token=UnitClass('player');local level=math.max(tonumber(UnitLevel and UnitLevel('player'))or 1,10) -- class tables start at level 10
 local data=FUSLiveData and(FUSLiveData[token]or FUSLiveData[tostring(token):lower()])
 local rules=data and data.equipmentRules;if not rules then return nil end
 local function contains(list,v)for _,x in ipairs(list or{})do if x==v then return true end end return false end
 if classID==4 then
  if subID and subID>=1 and subID<=4 and loc~='INVTYPE_CLOAK' then
   local maxArmor=0;for _,tier in ipairs(rules.armorTiers or{})do if level>=tier.minLevel then maxArmor=tier.maxSubclass end end
   if subID>maxArmor then return 'armor' end
  elseif subID==6 and not rules.shield then return 'armor' end
 elseif classID==2 then
  if not(contains(rules.weaponSubclasses,subID)or contains(rules.rangedSubclasses,subID))then return 'weapon' end
 end
 return nil
end
-- Stats that change the DAMAGE of this class (the tool is about DPS only: no healing, no tanking; mana
-- regeneration counts where mana limits the casting).
-- Hybrids keep every offensive stat, because the spec depends on talents; an item is only dropped when it has none of the listed stats at all.
-- Spirit and mana regeneration count for every class that casts from mana: faster regeneration means more casts
-- in a long fight, which the simulation models. Only warrior (rage) and rogue (energy) do without.
local OFFENSE={'STRENGTH','AGILITY','INTELLECT','SPIRIT','MANA_REGENERATION','ATTACK_POWER','SPELL_POWER','SPELL_DAMAGE_DONE','ARCANE_DAMAGE','FIRE_DAMAGE','FROST_DAMAGE','SHADOW_DAMAGE','NATURE_DAMAGE','HOLY_DAMAGE','CRIT_RATING','HIT_RATING','HASTE_RATING','EXPERTISE_RATING','ARMOR_PENETRATION','SPELL_PENETRATION'}
local MELEE={'AGILITY','STRENGTH','ATTACK_POWER','CRIT_RATING','HIT_RATING','HASTE_RATING','EXPERTISE_RATING','ARMOR_PENETRATION'}
local CASTER={'INTELLECT','SPIRIT','MANA_REGENERATION','SPELL_POWER','SPELL_DAMAGE_DONE','ARCANE_DAMAGE','FIRE_DAMAGE','FROST_DAMAGE','SHADOW_DAMAGE','NATURE_DAMAGE','HOLY_DAMAGE','CRIT_RATING','HIT_RATING','HASTE_RATING','SPELL_PENETRATION'}
local PRIEST=CASTER
local HUNTER={'INTELLECT','SPIRIT','MANA_REGENERATION'};for _,v in ipairs(MELEE)do HUNTER[#HUNTER+1]=v end
local RELEVANT={HUNTER=HUNTER,ROGUE=MELEE,WARRIOR=MELEE,MAGE=CASTER,WARLOCK=CASTER,PRIEST=PRIEST}
function AH.Irrelevant(item)
 if type(item)~='table' or type(item.rawStats)~='table' or item.hasUnmodeledEffects then return nil end
 local slot=item.slot
 if slot=='mainhand' or slot=='offhand' or slot=='ranged' then return nil end -- weapon damage always counts
 local _,token=UnitClass('player')
 local patterns=RELEVANT[token] or OFFENSE
 local any=false
 for key,value in pairs(item.rawStats)do
  any=true
  if (tonumber(value)or 0)>0 then for _,pattern in ipairs(patterns)do if tostring(key):find(pattern,1,true)then return nil end end end
 end
 if not any then return nil end -- nothing known about the item: let the simulation decide
 return 'keine passenden Werte'
end
-- Returns 'new' | 'known' | 'ignored' (no equipment / no id) | 'armor' | 'weapon' | 'full'.
local function remember(id,price,link)
 id=tonumber(id) or idOf(link)
 if not id or id<=0 then return 'ignored' end
 local key=C.NormalizeLink((type(link)=='string' and link:find('item:',1,true)) and link or('item:'..id))
 local s=store();local old=s.items[key]
 price=tonumber(price)or 0
 if old==nil then
  if not isEquipment(id) then return 'ignored' end
  local verdict=scanVerdict(id);if verdict then return verdict end
  if s.count>=MAX_KEEP then return 'full' end
  s.count=s.count+1;s.items[key]=price;return 'new',key
 end
 if price>0 and(old==0 or price<old)then s.items[key]=price end
 return 'known',key
end
AH.Remember=remember
local function harvestBrowse()
 if not(C_AuctionHouse and C_AuctionHouse.GetBrowseResults)then return 0 end
 local ok,results=pcall(C_AuctionHouse.GetBrowseResults)
 if not ok or type(results)~='table' then return 0 end
 local n=0
 for _,r in ipairs(results)do
  local key=r and r.itemKey
  if key and remember(key.itemID,r.minPrice)=='new' then n=n+1 end
 end
 if n>0 then store().time=time and time()or 0 end
 return n
end
-- The whole list in time slices, so the client does not freeze.
local function readReplicate()
 if AH.reading then return end
 AH.reading=true
 local total=(C_AuctionHouse.GetNumReplicateItems and C_AuctionHouse.GetNumReplicateItems())or 0
 local index=0
 local stat={new=0,known=0,ignored=0,armor=0,weapon=0,full=0}
 local qty={}
 store().level=tonumber(UnitLevel and UnitLevel('player'))
 local clock=debugprofilestop or function()return 0 end
 local function step()
  -- at most ~3 ms per frame, so the game stays playable while thousands of entries are read
  local started=clock();local i=index
  while i<total and (i-index<20 or clock()-started<3) and i-index<300 do
   local info={pcall(C_AuctionHouse.GetReplicateItemInfo,i)}
   if info[1]then
    local price=tonumber(info[11])or 0;if price<=0 then price=tonumber(info[9])or 0 end
    local link
    if C_AuctionHouse.GetReplicateItemLink then local okLink,value=pcall(C_AuctionHouse.GetReplicateItemLink,i);if okLink and type(value)=='string'then link=value end end
    local r,key=remember(info[18],price,link);stat[r]=(stat[r]or 0)+1
    if key then qty[key]=(qty[key]or 0)+1 end -- auctions per item: two non-unique rings need two offers
   end
   i=i+1
  end
  index=i
  if index<total and C_Timer and C_Timer.After then C_Timer.After(0,step)
  else
   AH.scanning=false;AH.reading=false;store().time=time and time()or 0;db().ahLastScan=time and time()or 0;db().ahRetryUntil=nil;AH.scannedThisSession=true;store().qty=qty
   logScan('ok',string.format('%d eintraege',total))
   local wearable=stat.new+stat.known+stat.full
   local _,token=UnitClass('player')
   say(string.format('Auktionshaus gelesen: %d Eintraege. Keine Ausruestung: %d. Fuer deine Klasse (%s, Stufe %s) nicht tragbar: %d Ruestung, %d Waffen. Tragbar: %d Eintraege (%d neu, %d schon bekannt). Gemerkt: %d Kandidaten.%s',
    total,stat.ignored,tostring(token),tostring(UnitLevel and UnitLevel('player')),stat.armor,stat.weapon,wearable,stat.new,stat.known,store().count,stat.full>0 and(' Merkgrenze erreicht: '..stat.full..' nicht gemerkt.')or''))
   say('Weiter mit FC Berechnen.')
   changed()
  end
 end
 step()
end
-- The full scan works reliably only right after a complete restart of the game (not after /reload), and no
-- fixed wait can be named, so the button is never locked. ScanWait stays for callers and always answers 0.
function AH.ScanWait()return 0 end
function AH.RefreshScanButton()
 local b=AH.scanButton;if not b then return end
 local wait=AH.ScanWait()
 if wait>0 then
  if b.Disable then b:Disable()end
  b:SetText(string.format('Scan in %d:%02d',math.floor(wait/60),wait%60))
 else
  if b.Enable then b:Enable()end
  -- Observed: a full scan is answered after a complete restart of the game, but often not after /reload.
  local label='Scannen'
  if AH.reloaded then label='Scan (Neustart)'
  elseif AH.scannedThisSession then label='Gescannt' end
  b:SetText(label)
 end
end
function AH.Scan()
 local blocked=AH.CannotCalculate()
 if blocked then say('Hinweis: '..blocked..' Der Scan liest die Liste, kann sie aber nicht nach Klasse filtern.')end
 if not(AuctionHouseFrame and AuctionHouseFrame.IsShown and AuctionHouseFrame:IsShown())then say('Auktionshaus oeffnen, dann FC Scan');return false end
 if C_AuctionHouse and C_AuctionHouse.ReplicateItems then
  local inMemory=((C_AuctionHouse.GetNumReplicateItems and tonumber(C_AuctionHouse.GetNumReplicateItems()))or 0)>0
  AH.scanning=true;AH.reading=false
  logScan('start',string.format('liste im speicher=%s',tostring(inMemory)))
  say('Auktionshaus wird gelesen ... (klappt nach einem kompletten Neustart von WoW; nach /reload bleibt die Antwort oft aus)')
  local function count()local ok,n=pcall(C_AuctionHouse.GetNumReplicateItems or function()return 0 end);return ok and tonumber(n)or 0 end
  local ok,err=pcall(C_AuctionHouse.ReplicateItems)
  if not ok then AH.scanning=false;say('ReplicateItems fehlgeschlagen: '..tostring(err));return false end
  -- The event may not fire on this client (or the request was throttled and the old list is still there):
  -- also look at the list size once per second and read it as soon as it is non-empty and stable.
  local waited,last=0,-1
  local function poll()
   if not AH.scanning or AH.reading then return end
   waited=waited+1;local n=count()
   if n>0 and n==last then readReplicate();return end
   last=n
   if waited>=20 then
    AH.scanning=false
    logScan('keine antwort',string.format('listeneintraege=%d',n))
    say(string.format('Keine Antwort vom Server (Listeneintraege: %d). Der Gesamtscan geht nach einem kompletten Neustart von WoW, nach /reload oft nicht. Die gemerkte Liste (%d Kandidaten) bleibt gespeichert: FC Berechnen geht auch ohne neuen Scan.',n,store().count))
    return
   end
   C_Timer.After(1,poll)
  end
  if C_Timer and C_Timer.After then C_Timer.After(1,poll)end
  return true
 end
 say('Dieser Client kennt keinen Gesamtscan: durchsuche die Kategorien (Ruestung, Waffen); angezeigte Treffer werden automatisch gemerkt ('..store().count..' bisher).')
 harvestBrowse();return false
end
-- Build the job from everything remembered. Items the client has not loaded yet are requested and
-- skipped this time; items that cannot be worn or are already cached cost nothing.
-- Reading item data (tooltips) is slow, so it runs in small time slices instead of one long freeze.
local function bucket(reason)
 reason=tostring(reason or'')
 if reason:find('Beruf',1,true) or reason:find(' hast ',1,true)then return 'Beruf' end
 if reason:find('Waffenfertigkeit',1,true)then return 'Waffenfertigkeit' end
 if reason:find('Nur fuer',1,true)then return 'Klasse' end
 if reason:find('Level',1,true)then return 'Level' end
 if reason:find('Fraktion',1,true)then return 'Fraktion' end
 if reason:find('stung',1,true)then return 'Ruestung' end
 if reason:find('Waffe',1,true)or reason:find('Nebenhand',1,true)or reason:find('Zweihand',1,true)then return 'Waffe/Nebenhand' end
 if reason:find('Einzigartig',1,true)then return 'Einzigartig' end
 return 'Sonstiges'
end
local function finishCalculate(collected,counts)
 local parts={}
 for name,n in pairs(counts.blocked)do parts[#parts+1]=name..' '..n end
 table.sort(parts)
 say(string.format('Pruefung von %d gemerkten Items: %d nicht tragbar%s, %d ohne passende Werte fuer deine Klasse, %d schon berechnet, %d ohne Slot/nicht unterstuetzt, %d vom Spiel noch nicht geladen, %d werden berechnet.',
  counts.total,counts.blockedTotal,#parts>0 and(' ('..table.concat(parts,', ')..')')or'',counts.irrelevant,counts.cached,counts.other,counts.unread,#collected))
 if #collected==0 then
  if counts.unread>0 then say('Die nicht geladenen Items fordert das Spiel jetzt an; in ein paar Sekunden nochmal FC Berechnen.')
  else say('Nichts zu berechnen.')end
  return false
 end
 local cands,sigs,keys={}, {}, {}
 for i,rec in ipairs(collected)do cands[i]=rec.candidate;sigs[i]=rec.signature;keys[i]=rec.link end
 AH.exportMeta={context=collected[1].context,sigs=sigs,keys=keys}
 local accepted=C.Request('item',{items=cands,partial=true},nil,{export=true})
 if not accepted then say('Warteschlange voll');AH.exportMeta=nil;return false end
 return true
end
-- The character data goes into the job once. Right after the game start the hunter quiver can still be
-- unreadable (tooltips not loaded); the PC would reject the whole job, so wait until it is readable.
local function stateReady()
 local P=FUSLive;if not(P and P.capture)then return true end
 local ok,snap=pcall(P.capture,true)
 if not ok or type(snap)~='table' then return false,'Charakterdaten noch nicht lesbar' end
 local reason=C.StateUnreadyReason and C.StateUnreadyReason(snap)
 if reason then return false,'Charakterdaten noch nicht lesbar: '..reason end
 return true
end
function AH.Calculate(attempt)
 local blocked=AH.CannotCalculate()
 if blocked then say(blocked);return false end
 if AH.calculating and not attempt then say('Die Auswertung laeuft schon ...');return false end
 if not C.engineRevision or C.engineRevision==''then say('Erst mit dem PC verbinden: /fc ping (ForeverCore.exe muss laufen)');return false end
 if C.pending or #C.queue>0 then say('Es laeuft noch eine Berechnung; gleich nochmal versuchen');return false end
 local ready,why=stateReady()
 if not ready then
  attempt=(attempt or 0)+1
  if attempt<=6 and C_Timer and C_Timer.After then
   AH.calculating=true
   say(string.format('%s; neuer Versuch in 3 s (%d/6) ...',why,attempt))
   C_Timer.After(3,function()AH.Calculate(attempt)end)
   return true
  end
  AH.calculating=false
  say(why..'. Bitte kurz warten (Tasche und Koecher oeffnen hilft) und FC Berechnen nochmal druecken.')
  return false
 end
 local s=store();local keys={}
 for key in pairs(s.items)do keys[#keys+1]=key end
 table.sort(keys,function(a,b)local pa,pb=s.items[a],s.items[b];if pa~=pb then return pa<pb end;return a<b end)
 if #keys==0 then say('Nichts gemerkt: erst FC Scan');return false end
 local clock=debugprofilestop or function()return 0 end
 local collected,index={},1
 local unreadKeys,tries={},0
 local counts={total=#keys,blocked={},blockedTotal=0,cached=0,other=0,unread=0,irrelevant=0}
 local savedLevel=tonumber(s.level);local level=tonumber(UnitLevel and UnitLevel('player'))
 if savedLevel and level and savedLevel~=level then say(string.format('Hinweis: Seit dem Scan hat sich deine Stufe geaendert (%d -> %d); neu scannen, damit auch neu tragbare Ruestung dabei ist.',savedLevel,level))end
 AH.calculating=true
 say(string.format('Auswertung von %d Items startet (kann einige Sekunden dauern) ...',#keys))
 local function slice()
  local started=clock();local startRevision=C.simRevision
  C.collectOnly=collected
  local ok,err=pcall(function()
   while index<=#keys and #collected<MAX_EXPORT and(clock()-started<4 or index%8~=1)do
    local key=keys[index];index=index+1
    local e=C.ItemResult(key)
    if e==nil then
     counts.unread=counts.unread+1;unreadKeys[#unreadKeys+1]=key
     local id=idOf(key);if id and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID,id)end
    elseif e.state=='ok'then
     counts.cached=counts.cached+1
     -- results from the item cache (earlier jobs, hovering) also belong into the list, top and report
     if type(e.pct)=='number'then s.results[key]={pct=e.pct,delta=tonumber(e.delta)or 0}end
    elseif e.state=='irrelevant'then
     counts.irrelevant=counts.irrelevant+1
     s.results[key]={pct=0,delta=0}
    elseif e.state=='blocked'then
     s.results[key]=nil -- an older result of an item that is blocked now (profession, class) must not stay in the lists
     local name=bucket(e.reason);counts.blocked[name]=(counts.blocked[name]or 0)+1;counts.blockedTotal=counts.blockedTotal+1
    elseif e.state~='busy'then counts.other=counts.other+1 end
   end
  end)
  C.collectOnly=nil
  if not ok then AH.calculating=false;say('Auswertung abgebrochen: '..tostring(err));return end
  if C.simRevision~=startRevision then AH.calculating=false;say('Der Charakter hat sich waehrend der Auswertung geaendert; bitte nochmal.');return end
  if index<=#keys and #collected<MAX_EXPORT and C_Timer and C_Timer.After then C_Timer.After(0,slice);return end
  -- Items the client had to load first: ask again a few times instead of making the player press twice.
  if index>#keys and #unreadKeys>0 and tries<3 and #collected<MAX_EXPORT and C_Timer and C_Timer.After then
   tries=tries+1;keys=unreadKeys;unreadKeys={};counts.unread=0;index=1
   say(string.format('%d Items sind noch nicht geladen; neuer Versuch in 3 s (%d/3) ...',#keys,tries))
   C_Timer.After(3,slice);return
  end
  AH.calculating=false
  if index<=#keys then counts.total=counts.total-(#keys-index+1) end
  finishCalculate(collected,counts)
  changed()
 end
 slice()
 return true
end
-- Called by Bridge.lua instead of painting the pixel strip.
function C.StoreExport(job,message)
 local meta=AH.exportMeta;AH.exportMeta=nil
 if not meta then return end
 local d=db()
 d.ahJob={json=message,session=C.session,sequence=job.sequence,revision=job.revision,context=meta.context,sigs=meta.sigs,keys=meta.keys,time=time and time()or 0}
 -- ReloadUI is protected on this client (an addon may not call it), so the player types /reload.
 say(string.format('%d Items uebertragen. Tippe jetzt |cffffd200/reload|r: dabei schreibt WoW die Datei, ForeverCore.exe rechnet, und danach kommt das Ergebnis.',#meta.keys))
end
local function applyResults(job,result,issue)
 local d=db()
 if issue or type(result)~='table' or type(result.candidates)~='table' or type(result.baselineDps)~='number' then
  say('Auktionshaus-Auswertung fehlgeschlagen: '..tostring(issue or'keine Antwort'))
  if C.IsTransientIssue(issue) then say('Das war nur ein Lesefehler beim Spielstart: FC Berechnen nochmal druecken.')end
  d.ahJob=nil;return
 end
 if C.SimCacheContext()~=job.context then
  say('Charakter oder Ausruestung hat sich seit dem Auftrag geaendert; Ergebnis verworfen. FC Berechnen nochmal.');d.ahJob=nil;return
 end
 local s=store();local stored,failed,better,same,worse=0,0,0,0,0
 local reasons,reasonCount={},0
 for i,row in ipairs(result.candidates)do
  local pct,dps=tonumber(row.pct),tonumber(row.dps)
  if pct and dps and not row.error and not row.need then
   C.StoreItemComparison(job.context,job.sigs[i],{percent=pct-100,delta=dps-result.baselineDps,candidateDps=dps,baselineDps=result.baselineDps,warnings=result.warnings,targetArmorEstimated=result.targetArmorEstimated})
   local key=job.keys and job.keys[i]
   if key then key=C.NormalizeLink and C.NormalizeLink(key)or key;s.results[key]={pct=pct-100,delta=dps-result.baselineDps} end
   stored=stored+1
   if pct-100>0.005 then better=better+1 elseif pct-100<-0.005 then worse=worse+1 else same=same+1 end
  else
   failed=failed+1
   -- why it could not be computed (numbers and item ids are folded together so equal reasons add up)
   local text=tostring(row.error or(row.need and 'Itemdaten fehlen (need)')or'keine Antwort'):gsub('Item %d+: ',''):gsub('%d+','N')
   if not reasons[text]then reasons[text]=0;reasonCount=reasonCount+1 end
   reasons[text]=reasons[text]+1
   local id=job.keys and job.keys[i]
   if id then s.failed=s.failed or{};s.failed[id]=text end
  end
 end
 d.ahJob=nil
 local P=FUSLive;if P and P.itemScore and P.itemScore.Changed then P.itemScore.Changed()end
 say(string.format('Auktionshaus fertig: %d Items berechnet (%d besser, %d gleich, %d schlechter), %d nicht berechenbar. /fc ah top zeigt die besten.',stored,better,same,worse,failed))
 if failed>0 then
  local list={};for text,n in pairs(reasons)do list[#list+1]={text=text,n=n}end
  table.sort(list,function(a,b)return a.n>b.n end)
  for i=1,math.min(3,#list)do say(string.format('  nicht berechenbar (%d): %s',list[i].n,list[i].text))end
 end
 changed()
end
-- The result may arrive before the character data is readable again (hunter quiver right after the reload).
-- Applying it then would compare against a wrong key, so wait a few seconds first.
local function tryApply(job,result,issue,attempt)
 attempt=attempt or 1
 if not issue and type(result)=='table' and C.SimCacheContext()==nil and attempt<10 and C_Timer and C_Timer.After then
  if attempt==1 then say('Ergebnis liegt bereit; warte, bis die Charakterdaten (Koecher) lesbar sind ...')end
  C_Timer.After(3,function()tryApply(job,result,issue,attempt+1)end)
  return
 end
 applyResults(job,result,issue)
end
local function formatPrice(copper)
 copper=tonumber(copper)or 0
 if copper<=0 then return 'kein Preis' end
 return string.format('%dg %ds',math.floor(copper/10000),math.floor((copper%10000)/100))
end
local function linkOf(key)
 local fn=(C_Item and C_Item.GetItemInfo)or GetItemInfo
 if type(fn)~='function' then return nil end
 local ok,name,link=pcall(fn,key)
 if ok and type(link)=='string' then return link end
 return nil
end
-- /fc ah top [n]: the best upgrade for EVERY slot (n per slot, default 1; rings and trinkets show at least 2).
-- Several variants of one base item ("of the Bear", "of the Monkey") count as one item: the best variant is shown
-- and the others are counted. Names the client has not loaded yet are requested and the list is printed again
-- shortly afterwards.
local SLOT_ORDER={'Kopf','Hals','Schulter','Ruecken','Brust','Handgelenk','Haende','Taille','Beine','Fuesse','Ring','Schmuck','Waffe (einhaendig)','Waffe (zweihaendig)','Nebenhand','Fernkampf'}
local SLOT_OF={INVTYPE_HEAD='Kopf',INVTYPE_NECK='Hals',INVTYPE_SHOULDER='Schulter',INVTYPE_CLOAK='Ruecken',INVTYPE_CHEST='Brust',INVTYPE_ROBE='Brust',
 INVTYPE_WRIST='Handgelenk',INVTYPE_HAND='Haende',INVTYPE_WAIST='Taille',INVTYPE_LEGS='Beine',INVTYPE_FEET='Fuesse',INVTYPE_FINGER='Ring',INVTYPE_TRINKET='Schmuck',
 INVTYPE_WEAPON='Waffe (einhaendig)',INVTYPE_WEAPONMAINHAND='Waffe (einhaendig)',INVTYPE_2HWEAPON='Waffe (zweihaendig)',
 INVTYPE_WEAPONOFFHAND='Nebenhand',INVTYPE_HOLDABLE='Nebenhand',INVTYPE_SHIELD='Nebenhand',
 INVTYPE_RANGED='Fernkampf',INVTYPE_RANGEDRIGHT='Fernkampf',INVTYPE_THROWN='Fernkampf',INVTYPE_RELIC='Fernkampf'}
local function slotOf(key)
 local id=idOf(key);local fn=(C_Item and C_Item.GetItemInfoInstant)or GetItemInfoInstant
 if not id or type(fn)~='function' then return 'Sonstiges' end
 local ok,_,_,_,loc=pcall(fn,id)
 return ok and SLOT_OF[loc]or'Sonstiges'
end
-- The rows of the list: { {slot=, key=, id=, pct=, delta=, price=, variants=} ... } in slot order, plus the number of
-- improvements, of different items, and of names the client has not loaded yet (they are requested).
-- Results stored before a requirement was known (profession, class, race) must not be shown. Only the rows about to
-- be shown are checked (a few tooltip reads); a blocked item is removed with all its variants and the next one moves
-- up. Items the client has not loaded cannot be checked and stay.
local function usable(key)
 local P=FUSLive
 if not(P and P.readItem and C.RequirementVerdict)then return true end
 local ok,item=pcall(P.readItem,key,'MythicSim')
 if not ok or type(item)~='table' then return true end
 local okVerdict,verdict=pcall(C.RequirementVerdict,item)
 return not(okVerdict and verdict),item
end
function AH.TopRows(count)
 local s=store()
 local perSlot=math.max(1,tonumber(count)or 1)
 -- best variant per base item id
 local bestOfItem,variants,total={}, {}, 0
 local keysOf={}
 for key,r in pairs(s.results or{})do
  if r.pct>0.005 then
   total=total+1
   local id=idOf(key) or key
   keysOf[id]=keysOf[id]or{};table.insert(keysOf[id],key)
   variants[id]=(variants[id]or 0)+1
   local old=bestOfItem[id]
   if not old or r.pct>old.pct then bestOfItem[id]={key=key,id=id,pct=r.pct,delta=r.delta,price=s.items[key]or 0} end
  end
 end
 local bySlot,distinct={},0
 for id,row in pairs(bestOfItem)do
  distinct=distinct+1
  row.variants=variants[id]-1
  local slot=slotOf(row.key)
  bySlot[slot]=bySlot[slot]or{};local list=bySlot[slot];list[#list+1]=row
 end
 local order={};for _,name in ipairs(SLOT_ORDER)do order[#order+1]=name end;if bySlot['Sonstiges']then order[#order+1]='Sonstiges'end
 local chosen,missing={}, 0
 for _,slot in ipairs(order)do
  local list=bySlot[slot]
  if list then
   table.sort(list,function(a,b)return a.pct>b.pct end)
   local limit=(slot=='Ring' or slot=='Schmuck')and math.max(2,perSlot)or perSlot
   local taken=0
   for _,row in ipairs(list)do
    if taken>=limit then break end
    local fine,item=usable(row.key)
    if fine then
     taken=taken+1;row.slot=slot;chosen[#chosen+1]=row
     -- Two rings (trinkets) are worn: when the best one is not unique and the auction house has it at least twice
     -- (or the count is unknown), wearing it twice beats showing a second, weaker item.
     if taken==1 and(slot=='Ring' or slot=='Schmuck')and type(item)=='table' and not item.unique and not item.uniqueEquip then
      local offers=type(s.qty)=='table' and s.qty[row.key]or nil
      if offers==nil or offers>=2 then row.twice=true;row.offers=offers;taken=taken+1 end
     end
     if not linkOf(row.key)then
      missing=missing+1
      if row.id and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID,tonumber(row.id))end
     end
    else
     for _,k in ipairs(keysOf[row.id]or{row.key})do s.results[k]=nil;total=total-1 end
     distinct=distinct-1
    end
   end
  end
 end
 return chosen,total,distinct,missing
end
AH.LinkOf=linkOf;AH.FormatPrice=formatPrice
-- loud: the list was asked for by a typed command (it is printed again after the names loaded, still into the chat)
function AH.Top(count,again,loud)
 if loud==nil then loud=C.UI and C.UI.inCommand or false end
 local chosen,total,distinct,missing=AH.TopRows(count)
 if total==0 then say('Keine Verbesserungen gespeichert (erst FC Scan, dann FC Berechnen).',loud);return end
 if missing>0 and not again and C_Timer and C_Timer.After then
  say(string.format('%d Itemnamen werden vom Spiel geladen ...',missing),loud)
  C_Timer.After(1.5,function()AH.Top(count,true,loud)end);return
 end
 say(string.format('Das Beste fuer jeden Platz (%d Verbesserungen, %d verschiedene Items):',total,distinct),loud)
 for _,row in ipairs(chosen)do
  local link=linkOf(row.key)or('Item '..tostring(idOf(row.key)))
  local extra=row.variants>0 and string.format('  (+%d weitere Varianten)',row.variants)or''
  if row.twice then extra=extra..(row.offers and string.format('  (2x tragen: nicht einzigartig, %d im AH)',row.offers)or'  (2x tragen: nicht einzigartig)')end
  say(string.format('%s: %s  +%.2f %% (%+.1f DPS)  %s%s',row.slot,link,row.pct,row.delta or 0,formatPrice(row.price),extra),loud)
 end
end
-- /fc ah report: per kind of item (cloth, leather, cloak, jewelry, weapons ...) how many were remembered,
-- calculated, better, equal, worse, and the best gain. Shows at a glance whether a kind was left out.
local GROUPS={'Stoff','Leder','Kette','Platte','Schild','Umhang (Ruecken)','Hals/Ring/Schmuck/Sonstiges','Waffen','Anderes'}
local function groupOf(key)
 local id=idOf(key);local fn=(C_Item and C_Item.GetItemInfoInstant)or GetItemInfoInstant
 if not id or type(fn)~='function' then return 'Anderes' end
 local ok,_,_,_,loc,_,classID,subID=pcall(fn,id);if not ok then return 'Anderes' end
 if loc=='INVTYPE_CLOAK' then return 'Umhang (Ruecken)' end
 if classID==4 then
  if subID==1 then return 'Stoff' elseif subID==2 then return 'Leder' elseif subID==3 then return 'Kette' elseif subID==4 then return 'Platte' elseif subID==6 then return 'Schild' end
  return 'Hals/Ring/Schmuck/Sonstiges'
 end
 if classID==2 then return 'Waffen' end
 return 'Anderes'
end
function AH.Report()
 local s=store();local g={}
 for _,name in ipairs(GROUPS)do g[name]={kept=0,done=0,better=0,same=0,worse=0,best=nil} end
 for key in pairs(s.items)do g[groupOf(key)].kept=g[groupOf(key)].kept+1 end
 for key,r in pairs(s.results or{})do
  local e=g[groupOf(key)];e.done=e.done+1
  if r.pct>0.005 then e.better=e.better+1 elseif r.pct<-0.005 then e.worse=e.worse+1 else e.same=e.same+1 end
  if not e.best or r.pct>e.best then e.best=r.pct end
 end
 say(string.format('Bericht (%d gemerkte Kandidaten). Spalten: gemerkt / berechnet (besser, gleich, schlechter) / bester Gewinn',s.count))
 for _,name in ipairs(GROUPS)do
  local e=g[name]
  if e.kept>0 or e.done>0 then
   say(string.format('%s: %d / %d (%d, %d, %d) / %s',name,e.kept,e.done,e.better,e.same,e.worse,e.best and string.format('%+.2f %%',e.best)or'-'))
  end
 end
 say('Differenz zwischen gemerkt und berechnet: zu hohe Stufe, keine passenden Werte oder noch nicht berechnet (FC Berechnen).')
 -- items the last job could not compute, by reason
 local reasons,total={},0
 for key,text in pairs(s.failed or{})do if s.results[key]==nil then reasons[text]=(reasons[text]or 0)+1;total=total+1 end end
 if total>0 then
  local list={};for text,n in pairs(reasons)do list[#list+1]={text=text,n=n}end
  table.sort(list,function(a,b)return a.n>b.n end)
  say(string.format('Nicht berechenbar (%d):',total))
  for i=1,math.min(5,#list)do say(string.format('  %d x %s',list[i].n,list[i].text))end
 end
end
-- After the reload: take over the waiting job. The PC writes its answer into a window of 128 slots that
-- no other job uses (C.ExportSlot); the normal slot counter is restored afterwards.
function AH.Resume(attempt)
 attempt=attempt or 1
 local job=db().ahJob
 if type(job)~='table' or not job.session or type(job.sigs)~='table' then return end
 if (time and time() or 0)-(tonumber(job.time)or 0)>900 then db().ahJob=nil;return end
 if type(job.json)~='string' or not job.json:find('"replyStart":'..C.ExportSlot(),1,true) then db().ahJob=nil;say('Alter Auktionshaus-Auftrag verworfen (anderes Antwortfenster). Bitte FC Berechnen nochmal.');return end
 if C.pending then
  -- the start-up ping is still running: try again shortly
  if attempt<20 and C_Timer and C_Timer.After then C_Timer.After(2,function()AH.Resume(attempt+1)end)end
  return
 end
 local saved=C.slot;C.slot=C.ExportSlot()
 C.pending={kind='item',sequence=job.sequence,revision=job.revision,session=job.session,resumed=true,noPaint=true,
  elapsed=0,part=0,frames=1,message='',id=0,timeout=240,
  callback=function(result,issue)C.slot=saved;tryApply(job,result,issue,1)end}
 say('Auktionshaus-Auftrag wartet auf ForeverCore.exe ...')
end
function AH.Command(arg)
 local cmd,rest=tostring(arg or''):match('^%s*(%S*)%s*(.-)%s*$')
 cmd=(cmd or''):lower()
 if cmd=='scan' then AH.Scan()
 elseif cmd=='calc' or cmd=='berechnen' then AH.Calculate()
 elseif cmd=='top' then AH.Top(tonumber(rest))
 elseif cmd=='report' or cmd=='bericht' then AH.Report()
 elseif cmd=='diag' then
  local A=C_AuctionHouse
  local n=A and A.GetNumReplicateItems and select(2,pcall(A.GetNumReplicateItems))
  say(string.format('C_AuctionHouse=%s ReplicateItems=%s Link=%s GetNumReplicateItems=%s Fenster=%s Leiste=%s gemerkt=%d',type(A),type(A and A.ReplicateItems),type(A and A.GetReplicateItemLink),tostring(n),tostring(_G.AuctionHouseFrame and _G.AuctionHouseFrame:IsShown()),tostring(AH.bar~=nil),store().count))
 elseif cmd=='scans' then
  local log=db().ahScanLog
  if type(log)~='table' or #log==0 then say('Noch kein Scan protokolliert.');return end
  local nowT=time and time()or 0
  for i=math.max(1,#log-9),#log do
   local e=log[i]
   say(string.format('%s  %s  (%s)  vor %d Min.',date and date('%H:%M:%S',e.t)or tostring(e.t),tostring(e.kind),tostring(e.detail),math.floor((nowT-e.t)/60)))
  end
 elseif cmd=='worn' then
  -- /fc ah worn: what the addon reads from every worn weapon and why a weapon may stay "unreadable"
  local P=FUSLive
  local function tipLines(setter)
   local ok,lines=pcall(function()
    local tip=_G.ForeverCoreAHScan
    if not tip then tip=CreateFrame('GameTooltip','ForeverCoreAHScan',nil,'GameTooltipTemplate') end
    tip:SetOwner(UIParent,'ANCHOR_NONE');tip:ClearLines();setter(tip)
    local out={}
    for i=1,math.min(tip:NumLines(),12)do
     local a=_G['ForeverCoreAHScanTextLeft'..i];local b=_G['ForeverCoreAHScanTextRight'..i]
     local l=a and a:GetText()or'';local r=b and b:GetText()or''
     if l~='' or r~='' then out[#out+1]=l..(r~='' and('  '..r)or'')end
    end
    return out
   end)
   return ok and lines or{}
  end
  local fnLink=(C_Item and C_Item.GetItemLink)
  for slot=1,19 do
   local link=GetInventoryItemLink and GetInventoryItemLink('player',slot)
   if link then
    local ok,item=pcall(P.readItem,link,'MythicSim')
    if ok and type(item)=='table' and (item.itemClass==2 or item.weaponClass==2) then
     local w=item.weapon
     say(string.format('Slot %d %s (%s): vollstaendig=%s Waffenwerte=%s Spezialeffekt=%s',slot,tostring(item.name),tostring(item.id),tostring(item.statsComplete),
      type(w)=='table' and string.format('%s-%s Tempo %s',tostring(w.min),tostring(w.max),tostring(w.speed))or'FEHLEN',tostring(item.hasUnmodeledEffects)))
     say('  Link roh: '..tostring(link):gsub('|','||'))
     say('  Tooltip per Link: '..table.concat(tipLines(function(t)t:SetHyperlink(link)end),' | '))
     say('  Tooltip am Slot:  '..table.concat(tipLines(function(t)if t.SetInventoryItem then t:SetInventoryItem('player',slot)end end),' | '))
    elseif not ok then say('Slot '..slot..': lesen fehlgeschlagen: '..tostring(item))end
   end
  end
 elseif cmd=='find' then
  -- /fc ah find <part of a name>: what the auction house list really contains for such items
  local needle=rest:lower()
  if needle=='' then say('Beispiel: /fc ah find Disciple');return end
  if not(C_AuctionHouse and C_AuctionHouse.GetNumReplicateItems and C_AuctionHouse.GetReplicateItemInfo)then say('Dieser Client hat keine Gesamtliste (FC Scan zuerst).');return end
  local total=tonumber(C_AuctionHouse.GetNumReplicateItems())or 0
  if total==0 then say('Keine Liste im Speicher: im Auktionshaus erst FC Scan.');return end
  local index,found,shown=0,0,0
  local clock=debugprofilestop or function()return 0 end
  local function raw(text)return tostring(text):gsub('|','||')end
  local function step()
   local started=clock();local i=index
   while i<total and(i-index<50 or clock()-started<3)and i-index<500 do
    local info={pcall(C_AuctionHouse.GetReplicateItemInfo,i)}
    local name=info[1] and tostring(info[2]or'')or''
    if name:lower():find(needle,1,true)then
     found=found+1
     if shown<6 then
      shown=shown+1
      local link='-'
      if C_AuctionHouse.GetReplicateItemLink then local okLink,value=pcall(C_AuctionHouse.GetReplicateItemLink,i);if okLink then link=raw(value)end end
      say(string.format('#%d Name="%s" itemID=%s Preis=%s Link=%s',i,name,tostring(info[18]),tostring(info[11]),link))
     end
    end
    i=i+1
   end
   index=i
   if index<total and C_Timer and C_Timer.After then C_Timer.After(0,step)
   else say(string.format('%d Treffer fuer "%s" in %d Eintraegen (gezeigt: %d).',found,rest,total,shown))end
  end
  step()
 elseif cmd=='item' then
  -- /fc ah item <item link>: what the addon reads from this item and what it concludes from it
  local P=FUSLive;local ok,item=pcall(P.readItem,rest,'MythicSim')
  if not ok or type(item)~='table' then say('Item nicht lesbar (Link nach /fc ah item einfuegen, Shift-Klick)');return end
  local stats={};for k,v in pairs(item.rawStats or{})do stats[#stats+1]=tostring(k):gsub('^ITEM_MOD_',''):gsub('_SHORT$','')..'='..tostring(v)end
  table.sort(stats)
  say('Link roh: '..tostring(rest):gsub('|','||'))
  say(string.format('Item %s %s: Slot=%s Stufe>=%s Ruestung=%s Qualitaet=%s',tostring(item.id),tostring(item.name),tostring(item.slot),tostring(item.minLevel),tostring(item.armorType),tostring(item.quality)))
  say('Werte: '..(#stats>0 and table.concat(stats,', ') or'KEINE gelesen')..'  | vollstaendig='..tostring(item.statsComplete)..' Spezialeffekt='..tostring(item.hasUnmodeledEffects))
  -- what the tooltip itself says (the stats shown to the player), line by line
  do
   local ok2,lines=pcall(function()
    local tip=_G.ForeverCoreAHScan
    if not tip then tip=CreateFrame('GameTooltip','ForeverCoreAHScan',nil,'GameTooltipTemplate');tip:SetOwner(UIParent,'ANCHOR_NONE') end
    tip:ClearLines();tip:SetOwner(UIParent,'ANCHOR_NONE');tip:SetHyperlink(rest)
    local out={}
    for i=1,math.min(tip:NumLines(),16)do
     local left=_G['ForeverCoreAHScanTextLeft'..i];local right=_G['ForeverCoreAHScanTextRight'..i]
     local a=left and left:GetText()or'';local b=right and right:GetText()or''
     if a~='' or b~='' then out[#out+1]=(a..(b~='' and('  '..b)or''))end
    end
    return out
   end)
   if ok2 and type(lines)=='table' and #lines>0 then say('Tooltip: '..table.concat(lines,' | ')) else say('Tooltip nicht lesbar: '..tostring(lines)) end
  end
  do
   local req=item.requiresSkill;local cls=item.allowedClasses;local races=item.allowedRaces
   local rank,known=nil,nil;if req and C.PlayerSkill then rank,known=C.PlayerSkill(req.name)end
   say(string.format('Voraussetzungen: Beruf=%s Klassen=%s Voelker=%s | Beruf bei dir=%s (abfragbar=%s; GetNumSkillLines=%s GetProfessions=%s) | Muster Beruf=%s | Urteil=%s',
    req and(tostring(req.name)..' '..tostring(req.rank))or'keine',cls and table.concat(cls,',')or'keine',races and table.concat(races,',')or'keine',tostring(rank),tostring(known),type(GetNumSkillLines),type(GetProfessions),tostring(_G.ITEM_MIN_SKILL),tostring((C.RequirementVerdict(item)) or "keins")))
  end
  local why=AH.Irrelevant(item)
  local candidate=C.ItemCandidate(item,rest)
  local entry=C.CachedItemComparison(item,candidate,rest)
  say(string.format('Urteil: %s | gespeichertes Ergebnis: %s',why and('KEINE passenden Werte fuer deine Klasse ('..why..')')or'Werte sind relevant',entry and string.format('%+.2f %% (%+.2f DPS)',entry.pct or 0,entry.delta or 0)or'keins'))
 elseif cmd=='key' then
  -- /fc ah key <item link>: shows the cache key of this link and whether a stored result exists
  local P=FUSLive;local ok,item=pcall(P.readItem,rest,'MythicSim')
  if not ok or not item then say('Item nicht lesbar (Link nach /fc ah key einfuegen, Shift-Klick)');return end
  local candidate=C.ItemCandidate(item,rest)
  local entry,context,key=C.CachedItemComparison(item,candidate,rest)
  local same,total=0,0
  local cache=ForeverCoreBridgeDB and ForeverCoreBridgeDB.simItemCache
  if cache and cache.entries and context then for full in pairs(cache.entries)do total=total+1;if full:sub(1,#context+1)==context..'/'then same=same+1 end end end
  say(string.format('Item %s Schluessel=%s Treffer=%s Kontext=%s Eintraege: %d im Kontext von %d',tostring(item.id),tostring(key),entry and'JA'or'NEIN',tostring(context),same,total))
 elseif cmd=='clear' then if type(db().ahChars)=='table' then db().ahChars[charKey()]=nil end;db().ahJob=nil;say('Auktionshaus-Daten dieses Charakters geloescht');changed()
 else
  local s=store();local results=0;for _ in pairs(s.results)do results=results+1 end
  say(string.format('Auktionshaus: %d tragbare Kandidaten gemerkt, %d Ergebnisse%s. FC Scan | FC Berechnen | /fc ah top | report | item | worn | find | scans | key | diag | clear',s.count,results,s.time and s.time>0 and(' (Stand '..date('%H:%M',s.time)..')')or''))
 end
end
local old=SlashCmdList and SlashCmdList.FOREVERCORE
if old then
 SlashCmdList.FOREVERCORE=function(msg)
  local head,tail=tostring(msg or''):match('^%s*(%S+)%s*(.-)%s*$')
  if head and head:lower()=='ah' then return AH.Command(tail)end
  return old(msg)
 end
end
-- Two small buttons above the auction house window. They live on their own frame (not inside the
-- Blizzard frame, whose layout differs between clients) and follow its visibility.
local function addButtons()
 local host=_G.AuctionHouseFrame
 if not host or not CreateFrame then return false end
 if C.UI and C.UI.AttachAuctionPanel then
  local ok,attached=pcall(C.UI.AttachAuctionPanel,host)
  if ok and attached then return true end
 end
 if AH.bar then AH.bar:SetShown(host:IsShown());return true end
 local ok,err=pcall(function()
  local bar=CreateFrame('Frame','ForeverCoreAHBar',UIParent)
  bar:SetSize(250,24);bar:SetPoint('BOTTOMLEFT',host,'TOPLEFT',4,2);bar:SetFrameStrata('HIGH')
  local function button(label,x,w,handler)
   local b=CreateFrame('Button',nil,bar,'UIPanelButtonTemplate')
   b:SetSize(w,22);b:SetPoint('LEFT',bar,'LEFT',x,0);b:SetText(label);b:SetScript('OnClick',handler)
   return b
  end
  local scanButton=button('FC Scan',0,120,function()AH.Scan()end);button('FC Berechnen',124,130,function()AH.Calculate()end)
  AH.scanButton=scanButton
  -- the scan button shows the remaining wait and cannot be pressed before the server allows the scan
  local passed=1
  bar:SetScript('OnUpdate',function(_,elapsed)
   passed=passed+(elapsed or 0);if passed<1 then return end;passed=0
   AH.RefreshScanButton()
  end)
  host:HookScript('OnShow',function()bar:Show()end);host:HookScript('OnHide',function()bar:Hide()end)
  bar:SetShown(host:IsShown());AH.bar=bar;AH.RefreshScanButton()
 end)
 if not ok then say('Auktionshaus-Knoepfe konnten nicht erstellt werden ('..tostring(err)..'); nutze /fc ah scan und /fc ah calc');return false end
 return true
end
local frame=CreateFrame('Frame')
for _,event in ipairs({'AUCTION_HOUSE_SHOW','AUCTION_HOUSE_BROWSE_RESULTS_UPDATED','AUCTION_HOUSE_BROWSE_RESULTS_ADDED','REPLICATE_ITEM_LIST_UPDATE','PLAYER_LOGIN','PLAYER_ENTERING_WORLD'})do pcall(frame.RegisterEvent,frame,event)end
frame:SetScript('OnEvent',function(_,event,isInitialLogin,isReloadingUi)
 -- Observed: the full scan works at once after a complete restart of the game, but not after /reload.
 -- The wait therefore belongs to the game session: a fresh login clears it, a reload keeps it.
 if event=='PLAYER_ENTERING_WORLD'then
  AH.reloaded=isReloadingUi==true
  if isInitialLogin==true then db().ahLastScan=nil;db().ahRetryUntil=nil end
  return
 end
 if event=='AUCTION_HOUSE_SHOW'then
  harvestBrowse()
  -- the Blizzard window may be created slightly after the event: try now and again shortly
  if not addButtons() and C_Timer and C_Timer.After then C_Timer.After(.5,addButtons);C_Timer.After(2,addButtons)end
 elseif event=='REPLICATE_ITEM_LIST_UPDATE'then if AH.scanning then readReplicate()end
 elseif event=='PLAYER_LOGIN'then if C_Timer and C_Timer.After then C_Timer.After(4,function()AH.Resume(1)end)end
 else harvestBrowse()end
end)
