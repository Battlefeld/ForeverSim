-- The ForeverCore windows: auction house side panel, dungeon window, a badge under the loot roll window and
-- upgrade arrows on item icons. They read what AuctionExport.lua, DungeonReport.lua and Adapters.lua already
-- computed; nothing here starts a calculation except the buttons the player presses (FC Scan / FC Berechnen).
-- Only own frames; Blizzard frames are only used as anchors (and their scripts hooked, never replaced).
local C=ForeverCoreClient
local UI=C.UI
-- Reading never creates the saved table: Bridge.lua creates it at PLAYER_LOGIN with enabled=true, and an empty table
-- made earlier (OnUpdate runs before the login) would switch the automatic strip tuning off on a fresh install.
local EMPTY={}
local function db()return ForeverCoreBridgeDB or EMPTY end
local function dbw()ForeverCoreBridgeDB=ForeverCoreBridgeDB or{enabled=true};return ForeverCoreBridgeDB end
local function inCombat()return InCombatLockdown and InCombatLockdown()==true end
local function idOf(ref)return tonumber(tostring(ref or''):match('item:(%d+)'))end
local ARROW_UP=UI.MEDIA..'FCArrowUp'

-- Auction house side panel --------------------------------------------------------------------------------
local MAX_ROWS=20
local panel
local function searchAuction(name)
 if not name then return false end
 local host=_G.AuctionHouseFrame
 local bar=type(host)=='table' and type(host.SearchBar)=='table' and host.SearchBar or nil
 if bar and type(bar.SearchBox)=='table' and bar.SearchBox.SetText then
  bar.SearchBox:SetText(name)
  if bar.StartSearch then pcall(bar.StartSearch,bar)
  elseif bar.SearchButton and bar.SearchButton.Click then pcall(bar.SearchButton.Click,bar.SearchButton)end
  return true
 end
 if _G.BrowseName and _G.BrowseName.SetText then
  _G.BrowseName:SetText(name)
  if _G.AuctionFrameBrowse_Search then pcall(_G.AuctionFrameBrowse_Search)end
  return true
 end
 return false
end
local function progressText()
 local AH=C.AH;local d=db()
 if AH.scanning or AH.reading then return 'Auktionshaus wird gelesen ...',UI.GOLD end
 if AH.calculating then return 'Auswertung laeuft ...',UI.GOLD end
 if type(d.ahJob)=='table' then
  if C.pending and C.pending.resumed then return 'ForeverCore.exe rechnet ...',UI.GOLD end
  return 'Bereit: jetzt /reload tippen',UI.GOLD
 end
 return nil
end
local function buildPanel()
 if panel then return panel end
 local f=UI.Window('ForeverCoreAuctionPanel','ForeverCore',272,460)
 f:SetFrameStrata('HIGH')
 f.info=f:CreateFontString(nil,'OVERLAY','GameFontDisableSmall');f.info:SetPoint('TOPLEFT',12,-28);f.info:SetWidth(248);f.info:SetJustifyH('LEFT')
 local function button(label,x,w,fn)
  local b=CreateFrame('Button',nil,f,'UIPanelButtonTemplate');b:SetSize(w,22);b:SetPoint('TOPLEFT',x,-44);b:SetText(label);b:SetScript('OnClick',fn);return b
 end
 f.scan=button('Scannen',10,124,function()C.AH.Scan()end)
 f.calc=button('Berechnen',138,124,function()C.AH.Calculate()end)
 f.status=f:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');f.status:SetPoint('TOPLEFT',12,-72);f.status:SetWidth(248);f.status:SetJustifyH('LEFT')
 if f.status.SetWordWrap then f.status:SetWordWrap(true)end
 f.header=f:CreateFontString(nil,'OVERLAY','GameFontNormalSmall');f.header:SetPoint('TOPLEFT',12,-104);f.header:SetText('Beste Verbesserung je Platz')
 f.rows={}
 for i=1,MAX_ROWS do
  local slot=f:CreateFontString(nil,'OVERLAY','GameFontDisableSmall');slot:SetPoint('TOPLEFT',12,-104-i*16);slot:SetWidth(64);slot:SetJustifyH('LEFT')
  if slot.SetWordWrap then slot:SetWordWrap(false)end
  local r=UI.ItemRow(f,186);r:SetHeight(16);r:SetPoint('TOPLEFT',76,-102-i*16);r.slotText=slot
  r.onClick=function(row)if row.itemName then searchAuction(row.itemName)end end
  r:Hide();slot:Hide();f.rows[i]=r
 end
 f.empty=f:CreateFontString(nil,'OVERLAY','GameFontDisableSmall');f.empty:SetPoint('TOPLEFT',12,-124);f.empty:SetWidth(248);f.empty:SetJustifyH('LEFT')
 f.empty:SetText('Noch keine Ergebnisse: erst Scannen, dann Berechnen.')
 f.hint=f:CreateFontString(nil,'OVERLAY','GameFontDisableSmall');f.hint:SetPoint('BOTTOMLEFT',12,36);f.hint:SetWidth(248);f.hint:SetJustifyH('LEFT')
 f.hint:SetText('Klick: im Auktionshaus suchen · Shift-Klick: Link')
 local report=CreateFrame('Button',nil,f,'UIPanelButtonTemplate');report:SetSize(124,22);report:SetPoint('BOTTOMLEFT',10,10);report:SetText('Bericht im Chat')
 report:SetScript('OnClick',function()C.AH.Report()end)
 local all=CreateFrame('Button',nil,f,'UIPanelButtonTemplate');all:SetSize(124,22);all:SetPoint('BOTTOMLEFT',138,10);all:SetText('Liste im Chat')
 all:SetScript('OnClick',function()C.AH.Top(1,nil,true)end)
 f:Hide()
 panel=f
 return f
end
-- Rows of the best upgrade per slot (AH.TopRows), names coloured by quality.
function UI.RefreshAuction()
 local f=panel;if not(f and f:IsShown())then return end
 local AH=C.AH
 local ok,s=pcall(AH.Store);if not ok then return end
 local chosen,total,distinct,missing=AH.TopRows(1)
 f.info:SetText(string.format('%d Items gemerkt%s',s.count or 0,(s.time and s.time>0 and date)and(' · Stand '..date('%d.%m. %H:%M',s.time))or''))
 f.header:SetText(total>0 and string.format('Beste Verbesserung je Platz (%d gesamt)',total)or'Beste Verbesserung je Platz')
 local shown=0
 for i,row in ipairs(chosen)do
  if i>MAX_ROWS then break end
  local r=f.rows[i];shown=i
  local link=AH.LinkOf(row.key)
  UI.FillItem(r,link or row.key)
  r.itemName=link and link:match('%[(.-)%]')
  local text,c=UI.Percent(row.pct)
  r.value:SetText(text);r.value:SetTextColor(c[1],c[2],c[3])
  r.slotText:SetText(row.twice and(row.slot..' 2x')or row.slot);r.slotText:Show();r:Show()
 end
 for i=shown+1,MAX_ROWS do f.rows[i]:Hide();f.rows[i].slotText:Hide()end
 f.empty:SetShown(shown==0)
 f.missing=missing>0
end
local function refreshStatus()
 local f=panel;if not(f and f:IsShown())then return end
 local text,c=progressText()
 if not text then text=C.AH.lastMessage or'';c=UI.GREY end
 if #text>150 then text=text:sub(1,147)..'...' end
 f.status:SetText(text);f.status:SetTextColor(c[1],c[2],c[3])
 if C.AH.RefreshScanButton then C.AH.RefreshScanButton()end
end
-- Attaches the panel to the right edge of the auction house window. Returns true when it is there.
function UI.AttachAuctionPanel(host)
 host=host or _G.AuctionHouseFrame
 if not host then return false end
 local f=buildPanel()
 C.AH.scanButton=f.scan
 if not f.attached then
  f.attached=true
  f:SetMovable(false);f:SetScript('OnDragStart',nil);f:SetScript('OnDragStop',nil)
  host:HookScript('OnShow',function()if f.attached then f:Show()end end)
  host:HookScript('OnHide',function()if f.attached then f:Hide()end end)
 end
 f:ClearAllPoints();f:SetPoint('TOPLEFT',host,'TOPRIGHT',2,0)
 local h=host.GetHeight and host:GetHeight();if type(h)=='number' and h>200 then f:SetHeight(h)end
 f:SetShown(host:IsShown())
 UI.RefreshAuction();refreshStatus()
 return true
end
-- Without the auction house: the same list as a free window (scanning needs the auction house).
function UI.ShowAuctionList()
 local host=_G.AuctionHouseFrame
 if host and host.IsShown and host:IsShown() then return UI.AttachAuctionPanel(host)end
 local f=buildPanel()
 if f.attached or f:GetNumPoints()==0 then f:ClearAllPoints();f:SetPoint('CENTER',UIParent,'CENTER',260,0)end
 f.attached=false
 f:Show();UI.RefreshAuction();refreshStatus()
 return true
end

-- Dungeon window ------------------------------------------------------------------------------------------
local dungeon
local DUNGEON_ROWS=22
local function buildDungeon()
 if dungeon then return dungeon end
 local f=UI.Window('ForeverCoreDungeonWindow','Dungeon',270,120)
 if not(db().windows and db().windows.ForeverCoreDungeonWindow)then f:SetPoint('TOPRIGHT',UIParent,'TOPRIGHT',-24,-250)end
 f.info=f:CreateFontString(nil,'OVERLAY','GameFontDisableSmall');f.info:SetPoint('TOPLEFT',12,-28);f.info:SetWidth(246);f.info:SetJustifyH('LEFT')
 f.lines={}
 for i=1,DUNGEON_ROWS do
  local r=UI.ItemRow(f,246);r:SetHeight(16);r:SetPoint('TOPLEFT',12,-30-i*16)
  r.boss=f:CreateFontString(nil,'OVERLAY','GameFontNormalSmall');r.boss:SetPoint('TOPLEFT',12,-32-i*16);r.boss:SetWidth(246);r.boss:SetJustifyH('LEFT')
  r:Hide();r.boss:Hide();f.lines[i]=r
 end
 f:Hide()
 dungeon=f
 return f
end
-- list: {name, total, ready, pending, better, busy, rows={ {boss, id, chance, pct, delta} }} or nil (left the dungeon)
function UI.ShowDungeon(list,open)
 if not list then if dungeon then dungeon:Hide()end;return end
 local f=buildDungeon()
 f.title:SetText(tostring(list.name or'Dungeon'))
 if list.busy then f.info:SetText(string.format('%d Drops · %d werden berechnet ...',list.total or 0,list.pending or 0))
 else f.info:SetText(string.format('%d Drops · %d berechnet · %d verbessern deinen Schaden',list.total or 0,list.ready or 0,list.better or 0))end
 local rows={}
 for _,r in ipairs(list.rows or{})do if (r.pct or 0)>0.005 then rows[#rows+1]=r end end
 table.sort(rows,function(a,b)if a.boss~=b.boss then return tostring(a.boss)<tostring(b.boss)end;return a.pct>b.pct end)
 local line,lastBoss=0,nil
 local function next()line=line+1;return f.lines[line]end
 for _,r in ipairs(rows)do
  if line>=DUNGEON_ROWS-1 then break end
  if r.boss~=lastBoss then
   local h=next();h:Hide();h.boss:SetText(tostring(r.boss));h.boss:Show();lastBoss=r.boss
  end
  local it=next();it.boss:Hide()
  UI.FillItem(it,r.id)
  local text,c=UI.Percent(r.pct)
  local chance=r.chance and('  |cff9d9d9d'..(tostring(r.chance):gsub('%.',','))..'%|r')or''
  it.value:SetText(text..chance);it.value:SetTextColor(c[1],c[2],c[3])
  it:Show()
 end
 if line==0 and not list.busy then
  local h=next();h:Hide();h.boss:SetText('|cff9d9d9dKein Drop verbessert deinen Schaden.|r');h.boss:Show()
 end
 for i=line+1,DUNGEON_ROWS do f.lines[i]:Hide();f.lines[i].boss:Hide()end
 f:SetHeight(46+math.max(1,line)*16+12)
 if open then f:Show()end
end

-- Loot roll badge -----------------------------------------------------------------------------------------
-- Under Blizzard's roll window: the value the dungeon list or a hover already computed. In a dungeon the drop is
-- looked up like in the dungeon list (level requirement ignored); nothing is computed in combat.
local badges={}
local function rollEntry(link)
 local id=idOf(link);if not id or not C.ItemResult then return nil end
 local inInstance=IsInInstance and select(1,IsInInstance())
 local ok,e=pcall(C.ItemResult,inInstance and('item:'..id)or link,inInstance and true or nil)
 return ok and e or nil
end
local function badge(rollID)
 local b=badges[rollID]
 if b then return b end
 b=CreateFrame('Frame',nil,UIParent,BackdropTemplateMixin and 'BackdropTemplate' or nil)
 b:SetSize(220,22);b:SetFrameStrata('DIALOG');b:EnableMouse(false)
 if b.SetBackdrop then
  b:SetBackdrop({bgFile='Interface\\Tooltips\\UI-Tooltip-Background',edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',tile=true,tileSize=16,edgeSize=12,insets={left=3,right=3,top=3,bottom=3}})
  b:SetBackdropColor(.04,.04,.06,.94);b:SetBackdropBorderColor(.55,.5,.35,1)
 end
 b.arrow=b:CreateTexture(nil,'OVERLAY');b.arrow:SetSize(14,14);b.arrow:SetPoint('LEFT',6,0);b.arrow:SetTexture(ARROW_UP)
 b.text=b:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');b.text:SetPoint('LEFT',24,0);b.text:SetPoint('RIGHT',-6,0);b.text:SetJustifyH('LEFT')
 badges[rollID]=b
 return b
end
local function showRoll(rollID,tries)
 tries=tries or 1
 local link=GetLootRollItemLink and GetLootRollItemLink(rollID)
 if not link then return end
 local e=(not inCombat())and rollEntry(link)or nil
 local IS=FUSLive and FUSLive.itemScore
 local frame,index=nil,nil;if IS and IS.RollFrame then frame,index=IS.RollFrame(rollID)end
 local b=badge(rollID);b:ClearAllPoints()
 if frame then b:SetPoint('TOPLEFT',frame,'BOTTOMLEFT',4,-2)else b:SetPoint('TOP',UIParent,'TOP',0,-260)end
 b.arrow:Hide()
 if not e or e.state=='busy' then
  b.text:SetText('|cff9d9d9dForeverCore rechnet ...|r');b:Show()
  if tries<10 and C_Timer and C_Timer.After then C_Timer.After(2,function()if badges[rollID]and badges[rollID]:IsShown()then showRoll(rollID,tries+1)end end)end
  return
 end
 if e.state=='ok' and type(e.pct)=='number' then
  local text,c=UI.Percent(e.pct)
  if e.pct>0.005 then
   b.arrow:Show()
   b.text:SetText(string.format('|cff40ff40%s DPS|r  |cff9d9d9d(%+.1f DPS)|r',text,tonumber(e.delta)or 0))
   if IS and IS.GoldBorder and IS.RollNeedButton then local need=IS.RollNeedButton(frame,index);if need then IS.ClearMarks('roll'..rollID);IS.GoldBorder('roll'..rollID,need,3)end end
  else
   b.text:SetText(string.format('|cff%02x%02x%02x%s DPS|r  kein Gewinn',c[1]*255,c[2]*255,c[3]*255,text))
  end
 elseif e.state=='blocked' then b.text:SetText('|cff9d9d9d'..tostring(e.reason or'nicht anlegbar')..'|r')
 elseif e.state=='none' or e.state=='irrelevant' then b.text:SetText('|cff9d9d9dKein Schadensgewinn|r')
 else b.text:SetText('|cffffa040Nicht berechenbar (Spezialeffekt)|r')end
 b:Show()
end
UI.ShowRoll=showRoll
local function hideRoll(rollID)
 local b=badges[rollID];if b then b:Hide()end
 local IS=FUSLive and FUSLive.itemScore;if IS and IS.ClearMarks then IS.ClearMarks('roll'..tostring(rollID))end
end

-- Upgrade arrows on item icons ----------------------------------------------------------------------------
-- Auction house list and loot window. Only values that already exist are shown (no new calculations).
local arrows,free={}, {}
local function arrowOn(anchor,group)
 local a=table.remove(free)
 if not a then
  a=CreateFrame('Frame',nil,UIParent);a:SetSize(14,14);a:SetFrameStrata('DIALOG');a:EnableMouse(false)
  a.tex=a:CreateTexture(nil,'OVERLAY');a.tex:SetAllPoints();a.tex:SetTexture(ARROW_UP)
 end
 a.group=group;a.anchor=anchor
 a:ClearAllPoints();a:SetPoint('TOPLEFT',anchor,'TOPLEFT',1,-1);a:Show()
 arrows[#arrows+1]=a
 return a
end
local function clearArrows(group)
 local kept={}
 for _,a in ipairs(arrows)do if a.group==group then a:Hide();a.anchor=nil;free[#free+1]=a else kept[#kept+1]=a end end
 arrows=kept
end
function UI.ArrowsEnabled()return db().arrows~=false end
-- best stored auction result per item id (any variant), rebuilt when the results change
local bestById,bestStamp=nil,nil
local function auctionBest(id)
 if not bestById then
  bestById={}
  local ok,s=pcall(C.AH.Store)
  if ok and s then for key,r in pairs(s.results or{})do local i=idOf(key);if i and r.pct and r.pct>(bestById[i]or 0.005)then bestById[i]=r.pct end end end
 end
 return bestById[id]
end
local function cachedUpgrade(link)
 local IS=FUSLive and FUSLive.itemScore
 if not(IS and IS.Peek)then return false end
 local id=idOf(link)
 for _,key in ipairs({link,id and('item:'..id..'#preview')or nil})do
  local e=key and IS.Peek(key)
  if e and e.state=='ok' and type(e.pct)=='number' then return e.pct>0.005 end
 end
 return id and auctionBest(id)~=nil or false
end
-- the browse list of the auction house window; its layout differs between clients, so every step is checked
local function field(t,key)if type(t)=='table' then local v=t[key];if type(v)=='table' then return v end end end
local function auctionRows(fn)
 local box=field(field(field(_G.AuctionHouseFrame,'BrowseResultsFrame'),'ItemList'),'ScrollBox')
 if box and type(box.ForEachFrame)=='function' then pcall(box.ForEachFrame,box,fn)end
end
local function refreshAuctionArrows()
 clearArrows('ah')
 if not UI.ArrowsEnabled() or inCombat() then return end
 auctionRows(function(row)
  local data=row.rowData or(row.GetElementData and row:GetElementData())
  local id=data and data.itemKey and data.itemKey.itemID
  if id and row.IsVisible and row:IsVisible() and auctionBest(id) then arrowOn(row,'ah')end
 end)
end
local function refreshLootArrows()
 clearArrows('loot')
 if not UI.ArrowsEnabled() or inCombat() or not GetLootSlotLink then return end
 for i=1,8 do
  local button=_G['LootButton'..i]
  if button and button.IsVisible and button:IsVisible() and button.slot then
   local ok,link=pcall(GetLootSlotLink,button.slot)
   if ok and link and cachedUpgrade(link)then arrowOn(button,'loot')end
  end
 end
end
function UI.RefreshMarks()
 bestById=nil
 refreshAuctionArrows();refreshLootArrows()
 local IS=FUSLive and FUSLive.itemScore;if IS and IS.RefreshBags then pcall(IS.RefreshBags)end
end

-- Events --------------------------------------------------------------------------------------------------
if C.AH and C.AH.OnChanged then C.AH.OnChanged(function()bestById=nil;UI.RefreshAuction()end)end
if CreateFrame then
 local f=CreateFrame('Frame')
 for _,e in ipairs({'START_LOOT_ROLL','CANCEL_LOOT_ROLL','LOOT_OPENED','LOOT_SLOT_CLEARED','LOOT_CLOSED','GET_ITEM_INFO_RECEIVED','AUCTION_HOUSE_CLOSED'})do pcall(f.RegisterEvent,f,e)end
 f:SetScript('OnEvent',function(_,e,arg)
  if e=='START_LOOT_ROLL' then if C_Timer and C_Timer.After then C_Timer.After(.2,function()showRoll(arg,1)end)else showRoll(arg,1)end
  elseif e=='CANCEL_LOOT_ROLL' then hideRoll(arg)
  elseif e=='LOOT_OPENED' or e=='LOOT_SLOT_CLEARED' then if C_Timer and C_Timer.After then C_Timer.After(.1,refreshLootArrows)else refreshLootArrows()end
  elseif e=='LOOT_CLOSED' then clearArrows('loot')
  elseif e=='AUCTION_HOUSE_CLOSED' then clearArrows('ah')
  elseif e=='GET_ITEM_INFO_RECEIVED' then if panel and panel:IsShown() and panel.missing then UI.RefreshAuction()end end
 end)
 -- the auction house list scrolls and changes without an event this addon gets: look twice a second
 local passed=0
 f:SetScript('OnUpdate',function(_,dt)
  passed=passed+(dt or 0);if passed<.5 then return end;passed=0
  refreshStatus()
  local host=_G.AuctionHouseFrame
  if host and host.IsShown and host:IsShown() then refreshAuctionArrows()end
 end)
end
