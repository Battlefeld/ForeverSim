-- How ForeverCore looks in the game: a minimap button with the connection status, a small overview window and
-- a quiet chat. Everything here only DISPLAYS what the other files compute; no calculation starts here.
--   Chat: by default only what needs the player (errors, "/reload") and answers to typed /fc commands go into the
--   chat window. Everything else is in the status (minimap button), the windows and /fc log.
--   /fc chat alles | ruhig   switches between all messages and the quiet chat (default: ruhig)
--   /fc minimap an | aus     shows or hides the minimap button
-- Taint rules as in ForeverSimBridge: only own frames, nothing is attached to or changed on Blizzard frames.
local C=ForeverCoreClient
local UI={};C.UI=UI
UI.MEDIA='Interface\\AddOns\\ForeverCoreBridge\\Media\\'
UI.ICON='Interface\\Icons\\Ability_DualWield'
-- Reading never creates the saved table: Bridge.lua creates it at PLAYER_LOGIN with enabled=true, and an empty table
-- made earlier (OnUpdate runs before the login) would switch the automatic strip tuning off on a fresh install.
local EMPTY={}
local function db()return ForeverCoreBridgeDB or EMPTY end
local function dbw()ForeverCoreBridgeDB=ForeverCoreBridgeDB or{enabled=true};return ForeverCoreBridgeDB end
local function now()return GetTime and GetTime()or 0 end
UI.GREEN={.25,1,.25};UI.RED={1,.35,.3};UI.GOLD={1,.82,0};UI.GREY={.62,.62,.62};UI.ORANGE={1,.62,.25}

-- Chat --------------------------------------------------------------------------------------------------------
-- Messages the player has to see even in the quiet chat: something failed, or he has to do something.
local IMPORTANT={'/reload','fehlgeschlagen','nicht lesbar','abgebrochen','Keine Antwort','verworfen','Zeitlimit','Fehler','nicht erstellt','nicht geladen','verbraucht','pausiert'}
function UI.Important(text)
 text=tostring(text or'')
 for _,word in ipairs(IMPORTANT)do if text:find(word,1,true)then return true end end
 return false
end
function UI.ChatMode()return db().chat=='alles' and 'alles' or 'ruhig' end
-- force: the player asked for this text (a typed /fc command), it always goes into the chat.
function C.Chat(text,force)
 text=tostring(text or'')
 if C.Say then C.Say(text)end -- status, minimap tooltip and the copyable log
 UI.lastMessage=text
 for _,fn in ipairs(UI.listeners)do pcall(fn,text)end
 local show=force or UI.inCommand or UI.ChatMode()=='alles' or UI.Important(text)
 if show and DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then DEFAULT_CHAT_FRAME:AddMessage('|cff66ccffForeverCore:|r '..text)end
 -- something to do: also in the middle of the screen, where the error messages of the game appear
 if text:find('/reload',1,true) and UIErrorsFrame and UIErrorsFrame.AddMessage then pcall(UIErrorsFrame.AddMessage,UIErrorsFrame,'ForeverCore: /reload tippen',1,.82,0) end
end
UI.listeners={}
function UI.OnMessage(fn)UI.listeners[#UI.listeners+1]=fn end

-- Status ------------------------------------------------------------------------------------------------------
-- ok (last job answered), busy (a job is running), error (the last job failed), off (pixel strip off), idle.
local ERRORS={'fehlgeschlagen','Zeitlimit','nicht lesbar','verbraucht','Berechnung fehlgeschlagen','nicht verfuegbar','abgebrochen','Keine Antwort'}
local say=C.Say
if type(say)=='function' then
 C.Say=function(text,...)
  local t=tostring(text or'')
  if t:find('Verbunden',1,true) or t:find('fertig',1,true) then UI.lastOk=now();UI.lastError=nil
  else for _,word in ipairs(ERRORS)do if t:find(word,1,true)then UI.lastError=t;UI.lastErrorAt=now();break end end end
  local r=say(text,...)
  if UI.Refresh then UI.Refresh()end
  return r
 end
end
-- A job without an answer: after a while the most likely reason is that ForeverCore.exe is not running. Hover and
-- ping jobs answer within seconds; simulations take longer; an auction house job computes hundreds of items.
local function patience(p)
 if p.resumed then return 120 end
 if p.kind=='item' or p.kind=='ping' then return 25 end
 return 90
end
-- seconds the running job waits already, when that is longer than it should take; nil otherwise
function UI.Overdue()
 local p=C.pending
 if type(p)~='table' or type(p.elapsed)~='number' or p.tuning then return nil end
 if p.elapsed>=patience(p) then return math.floor(p.elapsed)end
end
function UI.State()
 local d=db()
 if d.enabled==false then return 'off','Pausiert (/fc on)' end
 local overdue=UI.Overdue()
 if overdue then return 'error',string.format('Keine Antwort von ForeverCore.exe seit %d s - laeuft sie? (Starten.cmd)',overdue)end
 local AH=C.AH
 if C.pending or #(C.queue or{})>0 or(AH and(AH.calculating or AH.scanning or AH.reading))then return 'busy',tostring(C.status or'rechnet ...') end
 if UI.lastError and now()-(UI.lastErrorAt or 0)<300 then return 'error',UI.lastError end
 if d.pixelOff then return 'off','Pixelstreifen aus: nur Auktionshaus ueber /reload' end
 local data=C.dataStatus
 if UI.lastOk and type(data)=='table' then
  if data.status=='checking' then return 'busy',data.message or'Daten werden geprueft' end
  if data.status=='warning' or data.status=='error' then return 'warning',data.message or'Datenpruefung ausstehend' end
  if data.status=='ready' then return 'ok','Bereit · Daten automatisch geprueft' end
 end
 if UI.lastOk then return 'ok','Bereit' end
 return 'idle','Wartet auf die erste Berechnung (ForeverCore.exe starten)'
end
local STATE_COLOR={ok=UI.GREEN,busy=UI.GOLD,error=UI.RED,warning=UI.ORANGE,off=UI.GREY,idle=UI.GREY}
function UI.StateColor(state)return STATE_COLOR[state]or UI.GREY end

-- Shared look: a dark tooltip-style window with a gold title, movable, position remembered -----------------------
function UI.Window(name,title,width,height)
 local f=CreateFrame('Frame',name,UIParent,BackdropTemplateMixin and 'BackdropTemplate' or nil)
 f:SetSize(width,height);f:SetFrameStrata('MEDIUM');f:SetClampedToScreen(true);f:SetMovable(true);f:EnableMouse(true)
 f:RegisterForDrag('LeftButton')
 f:SetScript('OnDragStart',function(self)self:StartMoving()end)
 f:SetScript('OnDragStop',function(self)
  self:StopMovingOrSizing()
  local point,_,relPoint,x,y=self:GetPoint(1)
  local w=dbw();w.windows=w.windows or{};w.windows[name]={point,relPoint,x,y}
 end)
 if f.SetBackdrop then
  f:SetBackdrop({bgFile='Interface\\Tooltips\\UI-Tooltip-Background',edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',tile=true,tileSize=16,edgeSize=16,insets={left=4,right=4,top=4,bottom=4}})
  f:SetBackdropColor(.04,.04,.06,.94);f:SetBackdropBorderColor(.55,.5,.35,1)
 end
 f.title=f:CreateFontString(nil,'OVERLAY','GameFontNormal');f.title:SetPoint('TOPLEFT',12,-10);f.title:SetText(title or'ForeverCore')
 local close=CreateFrame('Button',nil,f,'UIPanelCloseButton');close:SetSize(24,24);close:SetPoint('TOPRIGHT',-2,-2)
 close:SetScript('OnClick',function()f:Hide()end);f.close=close
 local saved=db().windows and db().windows[name]
 if type(saved)=='table' and saved[1] then f:SetPoint(saved[1],UIParent,saved[2]or saved[1],tonumber(saved[3])or 0,tonumber(saved[4])or 0)end
 if UISpecialFrames then table.insert(UISpecialFrames,name)end
 return f
end
-- A row with item icon, name (quality colour from the link), a value on the right; hover shows the item tooltip,
-- shift-click puts the link into the chat. onClick(row) is optional.
function UI.ItemRow(parent,width)
 local r=CreateFrame('Button',nil,parent)
 r:SetSize(width,18)
 r.icon=r:CreateTexture(nil,'ARTWORK');r.icon:SetSize(16,16);r.icon:SetPoint('LEFT',0,0)
 r.value=r:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');r.value:SetPoint('RIGHT',-2,0);r.value:SetJustifyH('RIGHT')
 r.name=r:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');r.name:SetPoint('LEFT',r.icon,'RIGHT',4,0);r.name:SetPoint('RIGHT',r.value,'LEFT',-6,0)
 r.name:SetJustifyH('LEFT');if r.name.SetWordWrap then r.name:SetWordWrap(false)end
 local hl=r:CreateTexture(nil,'HIGHLIGHT');hl:SetAllPoints();hl:SetColorTexture(1,1,1,.08)
 r:SetScript('OnEnter',function(self)
  if self.link and GameTooltip then GameTooltip:SetOwner(self,'ANCHOR_RIGHT');pcall(GameTooltip.SetHyperlink,GameTooltip,self.link);GameTooltip:Show()end
 end)
 r:SetScript('OnLeave',function()if GameTooltip then GameTooltip:Hide()end end)
 r:SetScript('OnClick',function(self)
  if IsShiftKeyDown and IsShiftKeyDown() and self.link and ChatEdit_InsertLink then ChatEdit_InsertLink(self.link);return end
  if self.onClick then self.onClick(self)end
 end)
 return r
end
-- Fills a row from an item id or link: icon, name (quality colour), falls back to "Item 123" until the client has it.
function UI.FillItem(row,ref)
 local info=(C_Item and C_Item.GetItemInfo)or GetItemInfo
 local inst=(C_Item and C_Item.GetItemInfoInstant)or GetItemInfoInstant
 local name,link,quality,icon
 if type(info)=='function' then local ok,n,l,q,_,_,_,_,_,_,tex=pcall(info,ref);if ok then name,link,quality,icon=n,l,q,tex end end
 if not icon and type(inst)=='function' then local ok,_,_,_,_,tex=pcall(inst,ref);if ok then icon=tex end end
 row.link=link or(type(ref)=='string' and ref:find('|H',1,true) and ref)or nil
 row.icon:SetTexture(icon or'Interface\\Icons\\INV_Misc_QuestionMark')
 local color=quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
 row.name:SetText(name or('Item '..tostring(tostring(ref):match('item:(%d+)')or ref)))
 if color then row.name:SetTextColor(color.r,color.g,color.b)else row.name:SetTextColor(1,1,1)end
 return name~=nil
end
-- "+10,7 %" with a comma, coloured
function UI.Percent(pct)
 pct=tonumber(pct)or 0
 local text=(pct>=0 and'+'or'-')..(string.format(math.abs(pct)<10 and'%.1f'or'%.0f',math.abs(pct)):gsub('%.',','))..' %'
 local c=pct>0.005 and UI.GREEN or(pct<-0.005 and UI.RED or UI.GREY)
 return text,c
end

-- Minimap button --------------------------------------------------------------------------------------------
local function placeMinimap(b)
 local angle=math.rad(tonumber(db().minimapAngle)or 205)
 local radius=((Minimap and Minimap.GetWidth and Minimap:GetWidth()or 140)/2)+10
 b:ClearAllPoints();b:SetPoint('CENTER',Minimap,'CENTER',math.cos(angle)*radius,math.sin(angle)*radius)
end
local function minimapTooltip(b)
 if not GameTooltip then return end
 local state,text=UI.State();local c=UI.StateColor(state)
 GameTooltip:SetOwner(b,'ANCHOR_LEFT')
 GameTooltip:SetText('ForeverCore',1,.82,0)
 GameTooltip:AddLine(text,c[1],c[2],c[3],true)
 if UI.lastOk then
  local ago=math.floor((now()-UI.lastOk)/60)
  GameTooltip:AddLine(ago<1 and'Letzte Antwort von ForeverCore.exe: gerade eben' or string.format('Letzte Antwort von ForeverCore.exe: vor %d min',ago),.8,.8,.8)
 else
  GameTooltip:AddLine('ForeverCore.exe hat in dieser Sitzung noch nicht geantwortet',.8,.8,.8)
 end
 local AH=C.AH
 if AH and AH.Store then
  local ok,s=pcall(AH.Store)
  if ok and s and s.count and s.count>0 then
   local n=0;for _,r in pairs(s.results or{})do if r.pct and r.pct>0.005 then n=n+1 end end
   GameTooltip:AddLine(string.format('Auktionshaus: %d Items gemerkt, %d Verbesserungen',s.count,n),.8,.8,.8)
  end
 end
 GameTooltip:AddLine(' ')
 GameTooltip:AddLine(ForeverSimUI and'Linksklick: ForeverSim-Fenster'or'Linksklick: Uebersicht',.6,.8,1)
 GameTooltip:AddLine('Rechtsklick: Uebersicht und Einstellungen',.6,.8,1)
 GameTooltip:AddLine('Umschalt + Rechtsklick: Protokoll (kopierbar)',.6,.8,1)
 GameTooltip:AddLine('Ziehen: verschieben',.6,.8,1)
 GameTooltip:Show()
end
function UI.BuildMinimap()
 if UI.minimap or not Minimap or not CreateFrame then return UI.minimap end
 local b=CreateFrame('Button','ForeverCoreMinimapButton',Minimap)
 b:SetSize(31,31);b:SetFrameStrata('MEDIUM');b:SetFrameLevel(8)
 b:RegisterForClicks('LeftButtonUp','RightButtonUp');b:RegisterForDrag('LeftButton')
 b:SetHighlightTexture('Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight')
 local overlay=b:CreateTexture(nil,'OVERLAY');overlay:SetSize(53,53);overlay:SetTexture('Interface\\Minimap\\MiniMap-TrackingBorder');overlay:SetPoint('TOPLEFT')
 local bg=b:CreateTexture(nil,'BACKGROUND');bg:SetSize(20,20);bg:SetTexture('Interface\\Minimap\\UI-Minimap-Background');bg:SetPoint('TOPLEFT',7,-5)
 local icon=b:CreateTexture(nil,'ARTWORK');icon:SetSize(17,17);icon:SetTexture(UI.ICON);icon:SetPoint('TOPLEFT',7,-6);icon:SetTexCoord(.08,.92,.08,.92)
 -- the ForeverCore crystal (blue: connected, grey: not) when the ForeverSim art is installed
 if ForeverSimArt and ForeverSimArt.crystal_on then icon:SetSize(22,22);icon:SetPoint('TOPLEFT',5,-4);icon:SetTexCoord(0,1,0,1);b.crystal=icon end
 b.dot=b:CreateTexture(nil,'OVERLAY');b.dot:SetSize(10,10);b.dot:SetTexture(UI.MEDIA..'FCDot');b.dot:SetPoint('BOTTOMRIGHT',-5,6)
 b:SetScript('OnClick',function(_,button)
  if button=='RightButton' then
   if IsShiftKeyDown and IsShiftKeyDown() then if C.ShowLog then C.ShowLog()end else UI.ToggleMain()end
   return
  end
  if ForeverSimUI and ForeverSimUI.Toggle then ForeverSimUI.Toggle() else UI.ToggleMain() end
 end)
 b:SetScript('OnEnter',minimapTooltip)
 b:SetScript('OnLeave',function()if GameTooltip then GameTooltip:Hide()end end)
 b:SetScript('OnDragStart',function(self)
  self:SetScript('OnUpdate',function(me)
   local mx,my=Minimap:GetCenter();local px,py=GetCursorPosition();local s=Minimap:GetEffectiveScale()
   if mx and px then dbw().minimapAngle=math.deg(math.atan2(py/s-my,px/s-mx));placeMinimap(me)end
  end)
 end)
 b:SetScript('OnDragStop',function(self)self:SetScript('OnUpdate',nil)end)
 placeMinimap(b)
 UI.minimap=b
 if db().minimapHidden then b:Hide()end
 UI.Refresh()
 return b
end
-- Colours the status dot and the overview text; called on every status message and twice a second.
function UI.Refresh()
 local state,text=UI.State();local c=UI.StateColor(state)
 if UI.minimap and UI.minimap.dot then UI.minimap.dot:SetVertexColor(c[1],c[2],c[3])end
 if UI.minimap and UI.minimap.crystal and ForeverSimArt then
  local e=ForeverSimArt[(state=='ok'or state=='busy'or state=='warning')and UI.lastOk and'crystal_on'or'crystal_off']
  if e and UI.minimap.crystalKey~=e.file then UI.minimap.crystalKey=e.file;UI.minimap.crystal:SetTexture(ForeverSimArt.dir..e.file)end
 end
 local m=UI.main
 if m and m.IsShown and m:IsShown() then
  m.dot:SetVertexColor(c[1],c[2],c[3]);m.state:SetText(text)
 end
end

-- Overview window -----------------------------------------------------------------------------------------
local function check(parent,label,y,get,set)
 local cb=CreateFrame('CheckButton',nil,parent,'UICheckButtonTemplate')
 cb:SetSize(22,22);cb:SetPoint('TOPLEFT',10,y)
 local text=cb.Text or cb.text or cb:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
 text:ClearAllPoints();text:SetPoint('LEFT',cb,'RIGHT',2,1);text:SetFontObject('GameFontHighlightSmall');text:SetText(label)
 cb:SetScript('OnShow',function(self)self:SetChecked(get())end)
 cb:SetScript('OnClick',function(self)set(self:GetChecked()==true)end)
 cb:SetChecked(get())
 return cb
end
function UI.BuildMain()
 if UI.main then return UI.main end
 local f=UI.Window('ForeverCoreMainWindow','ForeverCore',280,214)
 if not(db().windows and db().windows.ForeverCoreMainWindow)then f:SetPoint('TOPRIGHT',UIParent,'TOPRIGHT',-200,-220)end
 f.dot=f:CreateTexture(nil,'ARTWORK');f.dot:SetSize(10,10);f.dot:SetTexture(UI.MEDIA..'FCDot');f.dot:SetPoint('TOPLEFT',14,-34)
 f.state=f:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');f.state:SetPoint('TOPLEFT',30,-32);f.state:SetWidth(236);f.state:SetJustifyH('LEFT')
 if f.state.SetWordWrap then f.state:SetWordWrap(true)end
 local function button(label,x,y,w,fn)
  local b=CreateFrame('Button',nil,f,'UIPanelButtonTemplate');b:SetSize(w,22);b:SetPoint('TOPLEFT',x,y);b:SetText(label);b:SetScript('OnClick',fn);return b
 end
 button('Dungeon-Liste',10,-62,128,function()if C.DungeonReport then C.DungeonReport.Report(false,1,false,true)end end)
 button('Auktionshaus',142,-62,128,function()if UI.ShowAuctionList then UI.ShowAuctionList(true)end end)
 button('Protokoll',10,-88,128,function()if C.ShowLog then C.ShowLog()end end)
 button('Verbindung',142,-88,128,function()if C.window then C.window:Show();C.Say(C.status)end end)
 check(f,'Alle Meldungen im Chat',-118,function()return UI.ChatMode()=='alles' end,function(on)dbw().chat=on and'alles'or nil end)
 check(f,'Dungeon-Liste beim Betreten zeigen',-140,function()return db().dungeonReportAuto~=false end,function(on)dbw().dungeonReportAuto=on end)
 check(f,'Upgrade-Pfeile auf Items',-162,function()return db().arrows~=false end,function(on)dbw().arrows=on;if UI.RefreshMarks then UI.RefreshMarks()end end)
 check(f,'Tooltip immer ausfuehrlich (sonst Shift)',-184,function()return db().tooltipDetails==true end,function(on)dbw().tooltipDetails=on or nil end)
 f:SetScript('OnShow',function()UI.Refresh()end)
 f:Hide()
 UI.main=f
 return f
end
function UI.ToggleMain()
 local f=UI.BuildMain()
 if f:IsShown()then f:Hide()else f:Show();UI.Refresh()end
end

-- Slash commands: everything typed after /fc counts as asked for, its answers go into the chat ---------------------
local old=SlashCmdList and SlashCmdList.FOREVERCORE
if old then
 SlashCmdList.FOREVERCORE=function(msg)
  local head,tail=tostring(msg or''):lower():match('^%s*(%S*)%s*(.-)%s*$')
  if head=='chat' and(tail=='alles' or tail=='ruhig')then
   dbw().chat=tail=='alles' and'alles'or nil
   C.Chat(tail=='alles' and'Chat: alle Meldungen' or'Chat: nur Fehler, Hinweise und Antworten auf /fc-Befehle (alles weitere in /fc log)',true);return
  end
  if head=='minimap' and(tail=='an' or tail=='aus')then
   dbw().minimapHidden=tail=='aus' or nil
   local b=UI.BuildMinimap();if b then b:SetShown(tail=='an')end;return
  end
  UI.inCommand=true
  local ok,err=pcall(old,msg)
  UI.inCommand=false
  if not ok and DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage('|cff66ccffForeverCore:|r Fehler: '..tostring(err))end
 end
end

if CreateFrame then
 local f=CreateFrame('Frame')
 f:RegisterEvent('PLAYER_LOGIN')
 f:SetScript('OnEvent',function()pcall(UI.BuildMinimap)end)
 local passed=0
 f:SetScript('OnUpdate',function(_,dt)
  passed=passed+(dt or 0);if passed<.5 then return end;passed=0
  -- once per job: say it in the chat when the PC does not answer (the job keeps waiting until its time limit)
  local p=C.pending
  if p and UI.warned~=p and UI.Overdue() then
   UI.warned=p
   C.Chat('Keine Antwort von ForeverCore.exe - laeuft sie? Starten.cmd im ForeverCore-Ordner starten; der Auftrag wartet weiter.')
  end
  UI.Refresh()
 end)
 if IsLoggedIn and IsLoggedIn()then pcall(UI.BuildMinimap)end
end

