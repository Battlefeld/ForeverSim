-- The in-game look (UI.lua, UIPanels.lua, tooltip line): quiet chat, minimap status, auction house side panel,
-- dungeon window, loot roll badge. Everything only displays values; the calculation paths stay untouched.
local root=assert(arg[1]);dofile(root..'/_dev/harness/wowmock.lua');dofile(root..'/_dev/harness/gameapi.lua')
local function loadAddon(addon)
 for line in io.lines(root..'/'..addon..'/'..addon..'.toc')do
  local file=line:gsub(string.char(13),''):gsub(string.char(92),'/'):match('^%s*([^#].-%.lua)%s*$')
  if file then assert(loadfile(root..'/'..addon..'/'..file))(addon,{})end
 end
end
ForeverCoreBridgeDB=nil
loadAddon('ForeverSimBridge');loadAddon('ForeverCoreBridge')
UnitLevel=function()return 20 end
-- frames update before the login: the saved table must not be created empty there (fresh install keeps enabled=true)
MOCK.Advance(1,.1)
assert(ForeverCoreBridgeDB==nil,'nothing creates the saved table before the login')
MOCK.Fire('PLAYER_LOGIN');MOCK.Advance(.5,.05)
assert(ForeverCoreBridgeDB and ForeverCoreBridgeDB.enabled==true,'fresh install: enabled after the login')
local C=ForeverCoreClient;local UI=C.UI;local AH=C.AH;local P=FUSLive
assert(UI and C.Chat and UI.BuildMinimap,'UI loaded')

-- minimap button and status ---------------------------------------------------------------------------------
local button=_G.ForeverCoreMinimapButton
assert(button and button.dot,'minimap button with status dot')
C.queue={};C.pending=nil;C.tuning=nil
assert((UI.State())=='idle','no job yet: idle '..tostring(select(2,UI.State())))
C.Say('Verbunden · item fertig')
assert((UI.State())=='ok','answered job: ok')
C.Say('Zeitlimit: ForeverCore/Fenstermodus pruefen')
assert((UI.State())=='error','failed job: error')
C.Say('Verbunden · item fertig')
C.pending={kind='item'}
assert((UI.State())=='busy','running job: busy');C.pending=nil
SlashCmdList.FOREVERCORE('minimap aus');assert(not button:IsShown(),'minimap button can be hidden')
SlashCmdList.FOREVERCORE('minimap an');assert(button:IsShown(),'and shown again')
UI.ToggleMain();assert(_G.ForeverCoreMainWindow and _G.ForeverCoreMainWindow:IsShown(),'left click opens the overview')
UI.ToggleMain();assert(not _G.ForeverCoreMainWindow:IsShown(),'and closes it')

-- quiet chat ------------------------------------------------------------------------------------------------
local function printed()return #MOCK.prints end
local before=printed()
C.Chat('Auktionshaus gelesen: 100 Eintraege.')
assert(printed()==before,'routine messages stay out of the chat')
C.Chat('Auktionshaus-Auswertung fehlgeschlagen: x')
assert(printed()==before+1,'problems reach the chat')
local notice
UIErrorsFrame={AddMessage=function(_,t)notice=t end}
C.Chat('311 Items uebertragen. Tippe jetzt /reload: ...')
assert(printed()==before+2 and notice and notice:find('/reload',1,true),'a /reload request reaches the chat and the screen')
C.Chat('Liste',true)
assert(printed()==before+3,'forced messages reach the chat')
SlashCmdList.FOREVERCORE('chat alles')
local n=printed();C.Chat('Auktionshaus gelesen: 100 Eintraege.')
assert(printed()==n+1,'chat alles shows routine messages')
SlashCmdList.FOREVERCORE('chat ruhig')
n=printed();SlashCmdList.FOREVERCORE('ah')
assert(printed()>n,'answers to typed commands always reach the chat')
assert(C.logLines and #C.logLines>0,'everything is in the copyable log')

-- auction house side panel ----------------------------------------------------------------------------------
AuctionHouseFrame=CreateFrame('Frame','AuctionHouseFrame',UIParent);AuctionHouseFrame:SetSize(800,500);AuctionHouseFrame:Show()
C_Item=C_Item or{}
C_Item.GetItemInfoInstant=function(id)id=tonumber(tostring(id):match('(%d+)'))return id,'Armor','Cloth','INVTYPE_HEAD','icon'..tostring(id),4,1 end
local NAMES={[301]='Silk Hood',[302]='Linen Cap'}
C_Item.GetItemInfo=function(ref)
 local id=tonumber(tostring(ref):match('item:(%d+)')or ref)
 if not NAMES[id] then return nil end
 return NAMES[id],'|cff1eff00|Hitem:'..id..'::::::::20:::::::|h['..NAMES[id]..']|h|r',2,20,20,'Armor','Cloth',1,'INVTYPE_HEAD','icon'..id
end
GetItemInfo=C_Item.GetItemInfo
MOCK.Fire('AUCTION_HOUSE_SHOW');MOCK.Advance(.6,.1)
local panel=_G.ForeverCoreAuctionPanel
assert(panel and panel:IsShown(),'side panel at the auction house')
assert(AH.scanButton==panel.scan,'the scan button of the panel is the one that is refreshed')
assert(AH.bar==nil,'no extra button bar when the panel exists')
local s=AH.Store()
s.items['item:301']=12345;s.items['item:302']=500;s.count=2
s.results['item:301']={pct=6.04,delta=0.8};s.results['item:302']={pct=-1,delta=-0.1}
AH.Changed()
assert(panel.rows[1]:IsShown() and panel.rows[1].name:GetText()=='Silk Hood','best row shows the item name: '..tostring(panel.rows[1].name:GetText()))
assert(panel.rows[1].value:GetText()=='+6,0 %','gain with comma: '..tostring(panel.rows[1].value:GetText()))
assert(panel.rows[1].slotText:GetText()=='Kopf','slot label')
assert(not panel.rows[2]:IsShown(),'no row for a worse item')
AH.calculating=true;MOCK.Advance(.6,.1)
assert(tostring(panel.status:GetText()):find('Auswertung',1,true),'progress is shown: '..tostring(panel.status:GetText()))
AH.calculating=false
AuctionHouseFrame:Hide();assert(not panel:IsShown(),'the panel follows the auction house window')
AuctionHouseFrame:Show();assert(panel:IsShown(),'and comes back with it')
AuctionHouseFrame:Hide()

-- dungeon window --------------------------------------------------------------------------------------------
UI.ShowDungeon({name='Hall of Thanes',total=3,ready=3,better=1,rows={{boss='Plunder',id=301,pct=70.2,delta=8.1,chance=12.5},{boss='Plunder',id=302,pct=0}}},true)
local dw=_G.ForeverCoreDungeonWindow
assert(dw and dw:IsShown() and dw.title:GetText()=='Hall of Thanes','dungeon window with the name')
assert(dw.lines[1].boss:IsShown() and dw.lines[1].boss:GetText()=='Plunder','boss header')
assert(dw.lines[2]:IsShown() and tostring(dw.lines[2].value:GetText()):find('+70',1,true),'upgrade row: '..tostring(dw.lines[2].value:GetText()))
assert(not dw.lines[3]:IsShown() and not dw.lines[3].boss:IsShown(),'items without gain are left out')
UI.ShowDungeon(nil);assert(not dw:IsShown(),'leaving the dungeon closes the window')
-- the dungeon report fills the window (automatic list: no chat lines)
do
 local api=_G.ForeverSimDungeonAPI
 local keep={ctx=api.InstanceContext,src=api.Sources};local keepResult=C.ItemResult;local keepBlocked=AH.CannotCalculate
 api.InstanceContext=function()return{name='Ragefire Chasm',items={301}}end
 api.Sources=function()return{{dungeon='Ragefire Chasm',boss='Taragaman',chance=10}}end
 C.ItemResult=function()return{state='ok',pct=5,delta=1}end
 AH.CannotCalculate=function()return nil end
 n=printed()
 C.DungeonReport.Report(false,1,true)
 assert(printed()==n,'the automatic list does not write into the chat')
 assert(dw:IsShown() and dw.title:GetText()=='Ragefire Chasm','the automatic list opens the window when something is better')
 api.InstanceContext=keep.ctx;api.Sources=keep.src;C.ItemResult=keepResult;AH.CannotCalculate=keepBlocked
 dw:Hide()
end

-- loot roll badge -------------------------------------------------------------------------------------------
do
 local keepResult=C.ItemResult
 GetLootRollItemLink=function()return '|cff1eff00|Hitem:301::::::::20:::::::|h[Silk Hood]|h|r' end
 local asked
 C.ItemResult=function(link,preview)asked={link=link,preview=preview};return{state='ok',pct=12.3,delta=1.5}end
 MOCK.Fire('START_LOOT_ROLL',7);MOCK.Advance(.5,.05)
 assert(asked and asked.link:find('Hitem:301',1,true) and not asked.preview,'outside a dungeon the full link is used')
 IsInInstance=function()return true,'party' end
 MOCK.Fire('START_LOOT_ROLL',8);MOCK.Advance(.5,.05)
 assert(asked.link=='item:301' and asked.preview==true,'in a dungeon the drop is looked up like the dungeon list')
 IsInInstance=function()return false,'none' end
 C.ItemResult=keepResult
 MOCK.Fire('CANCEL_LOOT_ROLL',7);MOCK.Fire('CANCEL_LOOT_ROLL',8)
end

-- a job without an answer: the player is told that ForeverCore.exe probably does not run ----------------------
do
 C.queue={}
 C.pending={kind='item',elapsed=0,part=0,frames=1,message='',id=0,sequence=999,revision='x',timeout=600,noPaint=true}
 n=printed()
 MOCK.Advance(1,.1)
 assert(printed()==n and (UI.State())~='error','no warning while the answer can still come')
 C.pending.elapsed=30
 MOCK.Advance(1,.1)
 local state,text=UI.State()
 assert(state=='error' and text:find('ForeverCore.exe',1,true),'overdue job: the status names ForeverCore.exe: '..tostring(text))
 assert(printed()==n+1 and MOCK.prints[#MOCK.prints]:find('Starten.cmd',1,true),'one chat line tells what to do')
 MOCK.Advance(2,.1)
 assert(printed()==n+1,'only once per job')
 C.pending={kind='item',elapsed=30,resumed=true,timeout=600,noPaint=true,part=0,frames=1,message='',id=0}
 assert((UI.State())~='error','an auction house job may compute longer')
 C.pending=nil
end

-- tooltip: one line, details with Shift ---------------------------------------------------------------------
do
 local IS=P.itemScore
 local keepGet=IS.Get
 IS.Get=function()return{state='ok',pct=10.7,delta=1.5,status='upgrade',result={warnings={'Kein Daemon aktiv'}},replaces='Alter Helm'}end
 local link='|cff1eff00|Hitem:301::::::::20:::::::|h[Silk Hood]|h|r'
 GameTooltip.GetItem=function()return 'Silk Hood',link end
 GameTooltip:SetOwner(UIParent)
 MOCK.script(GameTooltip,'OnTooltipSetItem')
 local lines=GameTooltip.__lines
 local text=table.concat(lines,' | ')
 assert(text:find('+10,7 % DPS',1,true) and text:find('FCArrowUp',1,true),'one line with arrow and gain: '..text)
 assert(not text:find('Kein Daemon',1,true) and text:find('Shift: Details',1,true),'warnings only with Shift: '..text)
 IsShiftKeyDown=function()return true end
 GameTooltip:SetOwner(UIParent);MOCK.script(GameTooltip,'OnTooltipSetItem')
 text=table.concat(GameTooltip.__lines,' | ')
 assert(text:find('Kein Daemon',1,true) and text:find('ersetzt: Alter Helm',1,true) and not text:find('Shift: Details',1,true),'details with Shift: '..text)
 IsShiftKeyDown=function()return false end
 IS.Get=keepGet;GameTooltip.GetItem=nil
end
for _,e in ipairs(MOCK.errors)do error('script error: '..tostring(e.kind)..' '..tostring(e.msg))end
io.write('ui tests passed\n')
