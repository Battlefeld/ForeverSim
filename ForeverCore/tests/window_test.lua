-- The ForeverSim window (ForeverSimBridge/UI): frame, header, crystal and tabs, without any tab content.
local root=assert(arg[1]);dofile(root..'/_dev/harness/wowmock.lua');dofile(root..'/_dev/harness/gameapi.lua')
local function loadAddon(addon)
 for line in io.lines(root..'/'..addon..'/'..addon..'.toc')do
  local file=line:gsub(string.char(13),''):gsub(string.char(92),'/'):match('^%s*([^#].-%.lua)%s*$')
  if file then assert(loadfile(root..'/'..addon..'/'..file))(addon,{})end
 end
end
loadAddon('ForeverSimBridge');loadAddon('ForeverCoreBridge')
local race,class,level='Troll','MAGE',60
UnitRace=function()return race=='Skyborn'and'Skyborn'or race,race end
UnitClass=function()return class:sub(1,1)..class:sub(2):lower(),class,8 end
UnitLevel=function()return level end
MOCK.Fire('PLAYER_LOGIN');MOCK.Advance(.5,.05)
local UI=assert(ForeverSimUI,'window module not loaded')
local A=assert(ForeverSimArt,'art data not loaded')

-- art data ---------------------------------------------------------------------------------------------------------
for _,key in ipairs({'banner_orc_troll','banner_undead','banner_tauren','banner_human','banner_dwarf_gnome','banner_nightelf','banner_skyborn','crystal_on','crystal_off','portrait_round','badge','glow','rays','checkbox','dropdown','button_normal','button_glow','button_active','panel_wide_small','notification_panel','panel_square_medium'})do
 assert(A[key],'missing art '..key)
end
for _,c in ipairs({'warrior','paladin','hunter','rogue','priest','shaman','mage','warlock','druid'})do assert(A['class_'..c],'missing class icon '..c)end
local tiles=0;for k in pairs(A)do if type(k)=='string'and k:match('^frame_%d%d$')then tiles=tiles+1 end end
assert(tiles==9,'the window frame has nine tiles: '..tiles)
for key,e in pairs(A)do
 if type(e)=='table'then
  local f=io.open(root..'/ForeverSimBridge/Media/UI/'..e.file,'rb');assert(f,'texture file missing: '..e.file)
  local head=f:read(18);f:close()
  assert(#head==18 and head:byte(3)==2 or head:byte(3)==10,'not a TGA: '..e.file)
  local w,h=head:byte(13)+head:byte(14)*256,head:byte(15)+head:byte(16)*256
  assert(w==e.tw and h==e.th,e.file..': canvas '..w..'x'..h..' vs '..e.tw..'x'..e.th)
  local p=1;while p<w do p=p*2 end;assert(p==w,e.file..': width not a power of two');p=1;while p<h do p=p*2 end;assert(p==h,e.file..': height not a power of two')
  assert(head:byte(17)==32,e.file..': not 32 bit')
 end
end

-- race and class pick the banner and the medallion ------------------------------------------------------------------
local cases={Orc='banner_orc_troll',Troll='banner_orc_troll',Scourge='banner_undead',Tauren='banner_tauren',Human='banner_human',Dwarf='banner_dwarf_gnome',Gnome='banner_dwarf_gnome',NightElf='banner_nightelf',Skyborn='banner_skyborn'}
for token,want in pairs(cases)do race=token;assert(UI.BannerKey()==want,token..' -> '..UI.BannerKey())end
race='SomethingNew';UnitFactionGroup=function()return'Horde'end;assert(UI.BannerKey()=='banner_orc_troll','unknown race: faction banner (Horde)')
UnitFactionGroup=function()return'Alliance'end;assert(UI.BannerKey()=='banner_human','unknown race: faction banner (Alliance)')
race='Troll'
for _,c in ipairs({'WARRIOR','DRUID','SHAMAN'})do class=c;assert(UI.ClassKey()=='class_'..c:lower())end
class='MAGE'

-- the window with one stub tab ------------------------------------------------------------------------------------
local shown={}
UI.RegisterTab({key='one',label='Eins',order=1,build=function(page)local t=page:CreateTexture();t:SetAllPoints();shown.one=page end,show=function()shown.oneShown=true end})
UI.RegisterTab({key='two',label='Zwei',order=2,build=function(page)error('broken tab')end})
UI.RegisterTab({key='three',label='Drei',order=3,build=function(page)shown.three=page end})
local f=UI.Window();assert(f and f==UI.Window(),'one window')
assert(f:GetWidth()==1290 and f:GetHeight()==800)
assert(not f:IsShown(),'closed at the start')
local count=0;for _,r in ipairs(f.__regions)do if r.__texture and tostring(r.__texture):find('frame_',1,true)then count=count+1 end end
assert(count==9,'nine frame tiles drawn: '..count)
assert(f.banner.__texture:find('banner_orc_troll',1,true),'banner follows the race')
assert(f.classIcon.__texture:find('class_mage',1,true),'icon follows the class')
assert(f.name:GetText()=='Test' and f.sub:GetText():find('Troll',1,true) and f.level:GetText()=='Stufe 60','header text: '..tostring(f.sub:GetText()))
-- crystal: grey without a connection, blue with one
local C=ForeverCoreClient
C.UI.lastOk=nil
UI.UpdateCrystal();assert(f.crystal.tex.__texture:find('crystal_off',1,true) and f.crystal.connected==false,'never answered (a job is only queued): grey crystal')
local realState=C.UI.State
C.UI.lastOk=1
C.UI.State=function()return'ok','Bereit'end
UI.UpdateCrystal();assert(f.crystal.tex.__texture:find('crystal_on',1,true) and f.crystal.connected==true,'connected: blue crystal')
C.UI.State=function()return'error','Keine Antwort'end
UI.UpdateCrystal();assert(f.crystal.tex.__texture:find('crystal_off',1,true) and f.crystal.connected==false,'error: grey crystal')
C.UI.State=function()return'busy','rechnet'end
UI.UpdateCrystal();assert(f.crystal.connected==true,'busy counts as connected')
C.UI.State=realState
-- open, tabs, close with the crystal ------------------------------------------------------------------------------
UI.Toggle();assert(f:IsShown(),'opened');assert(shown.one:IsShown() and shown.oneShown,'the first tab is shown')
assert(shown.two==nil and #MOCK.errors==0,'a broken tab does not break the window')
UI.SelectTab('three');assert(shown.three:IsShown() and not shown.one:IsShown(),'tab switch')
assert(ForeverSimBridgeDB.tab=='three','the tab is remembered')
UI.Toggle();assert(not f:IsShown());UI.Open('one');assert(f:IsShown() and shown.one:IsShown(),'Open selects a tab')
f.crystal.__scripts.OnClick(f.crystal);assert(not f:IsShown(),'a click on the crystal closes the window')
-- the window fits the screen
UIParent.__h,UIParent.__w=768,1365;UI.FitScale();assert(f:GetScale()<1 and f:GetScale()>=.45,'scaled down on a small screen: '..f:GetScale())
UIParent.__h,UIParent.__w=2000,3000;UI.FitScale();assert(f:GetScale()==1,'never scaled up')
-- a locked page
local page=CreateFrame('Frame');local n=UI.LockedNotice(page,'Ab Stufe 60 verfügbar','Du bist Stufe 52.');assert(n)
-- the minimap button: crystal, left click = window, right click = overview
local mm=C.UI.minimap;assert(mm and mm.crystal,'minimap button shows the crystal')
C.UI.lastOk=nil;C.UI.Refresh();assert(mm.crystal.__texture:find('crystal_off',1,true),'minimap crystal grey without an answer')
C.UI.lastOk=1;realState=C.UI.State;C.UI.State=function()return'ok','Bereit'end;C.UI.Refresh();assert(mm.crystal.__texture:find('crystal_on',1,true),'minimap crystal blue');C.UI.State=realState
f:Hide();mm.__scripts.OnClick(mm,'LeftButton');assert(f:IsShown(),'left click opens the ForeverSim window');mm.__scripts.OnClick(mm,'LeftButton');assert(not f:IsShown())
mm.__scripts.OnClick(mm,'RightButton');assert(C.UI.main and C.UI.main:IsShown(),'right click opens the overview');C.UI.main:Hide()
-- /fus opens the window
SlashCmdList.FOREVERSIMBRIDGE('');assert(f:IsShown(),'/fus opens the window');SlashCmdList.FOREVERSIMBRIDGE('fenster');assert(not f:IsShown())
-- position is remembered
f:Show();f:GetCenter();f.__scripts.OnDragStop(f);assert(ForeverSimBridgeDB.window,'position saved')
assert(#MOCK.errors==0,MOCK.errors[1]and MOCK.errors[1].msg or'')
local unknown={};for k in pairs(MOCK.unknownMethods)do unknown[#unknown+1]=k end;table.sort(unknown)
assert(#unknown==0,'unknown widget methods: '..table.concat(unknown,', '))
print=io.write;print('window tests passed\n')
