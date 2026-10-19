-- Dungeon loot report: the drops of the dungeon you are in, by boss, with drop chance and the DPS gain
-- the simulation computed for your character.
--   /fc dungeon              list (waits up to 12 s for values that are still being computed)
--   /fc dungeon alle         list every wearable drop, not only the upgrades
--   /fc dungeon auto on|off  print the list by itself a few seconds after entering a dungeon (default: on)
-- Loot, bosses and chances come from the catalog of ForeverSimBridge (ForeverSimDungeonAPI); the values come
-- from the same cache as every item tooltip, so nothing is computed twice.
local C=ForeverCoreClient
local D={};C.DungeonReport=D
local function db()ForeverCoreBridgeDB=ForeverCoreBridgeDB or{};return ForeverCoreBridgeDB end
-- loud: the list was asked for with /fc dungeon, so it goes into the chat; the automatic list and the window
-- button only fill the window (C.Chat in UI.lua decides, problems always reach the chat).
local function say(text,loud)
 if C.Chat then return C.Chat(text,loud)end
 if C.Say then C.Say(text)end
 if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then DEFAULT_CHAT_FRAME:AddMessage('|cff66ccffForeverCore:|r '..tostring(text))end
end
-- Shows the list in the dungeon window (UI), when there is one. open: bring the window up.
local function toWindow(list,open)
 D.last=list
 if C.UI and C.UI.ShowDungeon then pcall(C.UI.ShowDungeon,list,open)end
end
local function linkOf(id)
 local fn=(C_Item and C_Item.GetItemInfo)or GetItemInfo
 if type(fn)~='function' then return nil end
 local ok,_,link=pcall(fn,id)
 if ok and type(link)=='string' then return link end
end
local function itemFacts(id)
 local inst=(C_Item and C_Item.GetItemInfoInstant)or GetItemInfoInstant
 local info=(C_Item and C_Item.GetItemInfo)or GetItemInfo
 local facts={}
 if type(inst)=='function'then
  local ok,iid,typ,sub,loc,_,classID,subID=pcall(inst,id)
  if ok and iid then facts.known=true;facts.type=typ;facts.sub=sub;facts.loc=loc;facts.classID=classID;facts.subID=subID end
 end
 if type(info)=='function'then local ok,name=pcall(info,id);if ok and type(name)=='string'then facts.name=name end end
 return facts
end
-- Recipes, patterns, bags and other non-equipment: nothing to calculate, nothing to wait for
local NOT_EQUIPMENT={[''] =true,INVTYPE_NON_EQUIP=true,INVTYPE_NON_EQUIP_IGNORE=true,INVTYPE_BAG=true,INVTYPE_TABARD=true,INVTYPE_BODY=true,INVTYPE_AMMO=true,INVTYPE_QUIVER=true}
local function notEquipment(facts)return facts.known and (facts.loc==nil or NOT_EQUIPMENT[facts.loc]==true)end
local function base(name)return(tostring(name or''):lower():gsub(':.*$',''):gsub('^%s+',''):gsub('%s+$',''))end
-- The drops of the current instance grouped by boss: { {boss=, items={ {id=, chance=} ... }} ... }
local function collect(ctx)
 local api=_G.ForeverSimDungeonAPI
 local byBoss,order={},{}
 local mine=base(ctx.name)
 for _,id in ipairs(ctx.items or{})do
  local sources=(api and api.Sources and api.Sources(id))or{}
  local chosen={}
  for _,s in ipairs(sources)do
   local theirs=base(s.dungeon)
   if theirs~='' and(mine:find(theirs,1,true) or theirs:find(mine,1,true))then chosen[#chosen+1]=s end
  end
  if #chosen==0 then chosen=sources end -- names that do not match: better to show than to hide
  for _,s in ipairs(chosen)do
   local boss=s.boss or s.dungeon or '?'
   if not byBoss[boss]then byBoss[boss]={boss=boss,items={}};order[#order+1]=boss end
   byBoss[boss].items[#byBoss[boss].items+1]={id=id,chance=s.chance}
  end
 end
 local out={};for _,name in ipairs(order)do out[#out+1]=byBoss[name]end
 return out
end
-- attempt counts the waiting rounds (every 4 s) while values are still being computed.
-- quiet: the automatic list after entering; window: asked for with the button of the overview window.
function D.Report(showAll,attempt,quiet,window)
 attempt=attempt or 1
 local loud=not quiet and not window
 local outer=say
 local say=function(text)return outer(text,loud)end
 local api=_G.ForeverSimDungeonAPI
 local ctx=api and api.InstanceContext and api.InstanceContext()
 if not ctx then
  if not quiet then outer('Kein bekannter Dungeon: die Liste gibt es im Dungeon.',true)end
  if quiet then toWindow(nil,false)end -- left the dungeon: the window closes
  return false
 end
 if not C.ItemResult then say('Berechnung nicht verfuegbar');return false end
 local blocked=C.AH and C.AH.CannotCalculate and C.AH.CannotCalculate()
 if blocked then if not quiet then outer(blocked,true)end;return false end
 local groups=collect(ctx)
 local pending,ready,total=0,0,0
 local rows={}
 local why={}        -- how many drops are in which state, to see where things stand
 local unread={}     -- ids the client could not read yet
 local unreadFacts={}
 local function count(key)why[key]=(why[key]or 0)+1 end
 for _,g in ipairs(groups)do
  for _,it in ipairs(g.items)do
   total=total+1
   local e=C.ItemResult('item:'..it.id,true)
   if e then
    count(e.state..(e.state=='blocked'and e.reason and(': '..(tostring(e.reason):gsub('%d+','N')))or''))
   else
    local facts=itemFacts(it.id)
    if notEquipment(facts)then count('keine Ausruestung')
    elseif facts.known and facts.name then count('Slot nicht unterstuetzt')
    else count('Daten nicht geladen') end
   end
   if e==nil then unread[#unread+1]=it.id end
   if e==nil then
    -- the client has no readable data for this item: why?
    local facts=itemFacts(it.id)
    if notEquipment(facts)then
     -- not a piece of equipment: nothing to wait for
    elseif facts.known and facts.name then
     -- equipment the model has no slot for: nothing to wait for
    else
     pending=pending+1
     if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID,it.id)end
    end
    unreadFacts[#unreadFacts+1]={id=it.id,facts=facts}
   elseif e.state=='busy'then
    pending=pending+1
   elseif e.state=='ok'then ready=ready+1;rows[#rows+1]={boss=g.boss,id=it.id,chance=it.chance,pct=e.pct or 0,delta=e.delta or 0}
   end
  end
 end
 -- The automatic list (quiet) waits in the background for up to about 50 s and prints once, when the values are
 -- there; a list asked for by hand waits 12 s and then shows what it has.
 local maxAttempts=quiet and 12 or 4
 if pending>0 and attempt<maxAttempts and C_Timer and C_Timer.After then
  if attempt==1 then say(string.format('%s: %d Drops, %d davon werden berechnet; die Liste erscheint von selbst.',tostring(ctx.name),total,pending))end
  toWindow({name=ctx.name,total=total,ready=ready,pending=pending,rows=rows,busy=true},window or not quiet)
  C_Timer.After(4,function()D.Report(showAll,attempt+1,quiet,window)end)
  return true
 end
 table.sort(rows,function(a,b)if a.boss~=b.boss then return a.boss<b.boss end;return a.pct>b.pct end)
 local better=0;for _,r in ipairs(rows)do if r.pct>0.005 then better=better+1 end end
 say(string.format('%s: %d Drops im Katalog, %d fuer dich berechnet, %d verbessern deinen Schaden%s.',tostring(ctx.name),total,ready,better,
  pending>0 and string.format(' (%d noch offen)',pending)or''))
 local shown,lastBoss=0,nil
 for _,r in ipairs(rows)do
  if showAll or r.pct>0.005 then
   if shown>=30 and not showAll then say('... weitere mit /fc dungeon alle');break end
   if r.boss~=lastBoss then say('|cffffd200'..tostring(r.boss)..'|r');lastBoss=r.boss end
   local chance=r.chance and(' - Drop '..(tostring(r.chance):gsub('%.',','))..' %')or''
   say(string.format('  %+.2f %% (%+.2f DPS)  %s%s',r.pct,r.delta,linkOf(r.id)or('Item '..r.id),chance))
   shown=shown+1
  end
 end
 if better==0 and ready>0 then say('Kein Drop dieses Dungeons verbessert deinen Schaden.')end
 toWindow({name=ctx.name,total=total,ready=ready,pending=pending,rows=rows,better=better},window or not quiet or better>0)
 -- breakdown: this is what tells why drops are missing from the list
 local parts={};for k,n in pairs(why)do parts[#parts+1]=k..' '..n end;table.sort(parts)
 say('Stand der '..total..' Drops: '..table.concat(parts,', ')..'.')
 if #unread>0 then
  local known,seen={},{}
  for _,u in ipairs(unreadFacts)do
   if #known>=5 then break end
   if not seen[u.id]then
    seen[u.id]=true
    local fa=u.facts
    known[#known+1]=string.format('%d %s [%s / %s / Slot %s]',u.id,tostring(fa.name or'Name nicht geladen'),tostring(fa.type or'?'),tostring(fa.sub or'?'),tostring(fa.loc==''and'keiner'or fa.loc or'?'))
   end
  end
  say('Nicht lesbar, Beispiele: '..table.concat(known,'; '))
 end
 return true
end
local old=SlashCmdList and SlashCmdList.FOREVERCORE
if old then
 SlashCmdList.FOREVERCORE=function(msg)
  local head,tail=tostring(msg or''):match('^%s*(%S+)%s*(.-)%s*$')
  if head and head:lower()=='dungeon'then
   tail=tostring(tail):lower()
   if tail=='auto on' or tail=='auto off'then db().dungeonReportAuto=(tail=='auto on');say('Dungeon-Liste beim Betreten: '..(tail=='auto on'and'AN'or'AUS'));return end
   return D.Report(tail=='alle'or tail=='all')
  end
  return old(msg)
 end
end
if CreateFrame then
 local f=CreateFrame('Frame')
 pcall(f.RegisterEvent,f,'PLAYER_ENTERING_WORLD')
 f:SetScript('OnEvent',function()
  if db().dungeonReportAuto==false then return end
  -- a few seconds after the entry: the catalog needs the instance data, the values need a moment
  if C_Timer and C_Timer.After then C_Timer.After(4,function()D.Report(false,1,true)end)end
 end)
end
