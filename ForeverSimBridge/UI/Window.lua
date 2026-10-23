-- The ForeverSim window: curved frame, race banner, class medallion, the ForeverCore crystal and three tabs
-- (Talente, Rotation, Beute). It only displays what ForeverCore.exe computed (ForeverCoreClient.Sim keeps it);
-- every tab file registers itself with UI.RegisterTab.
ForeverSimUI=ForeverSimUI or{}
local UI=ForeverSimUI
local COLOR=UI.COLOR
UI.W,UI.H=1290,800
local tabs={}
function UI.RegisterTab(def)
 for i,t in ipairs(tabs)do if t.key==def.key then tabs[i]=def;return end end
 tabs[#tabs+1]=def;table.sort(tabs,function(a,b)return(a.order or 99)<(b.order or 99)end)
end
function UI.Tabs()return tabs end

local function core()return ForeverCoreClient end
local function sim()local c=core();return c and c.Sim or nil end
local function db()ForeverSimBridgeDB=ForeverSimBridgeDB or{};return ForeverSimBridgeDB end

-- Race -> banner. The Forever client's own race tokens: an unknown one falls back to its faction's city.
local BANNER={orc='orc_troll',troll='orc_troll',scourge='undead',undead='undead',tauren='tauren',human='human',dwarf='dwarf_gnome',gnome='dwarf_gnome',nightelf='nightelf'}
function UI.BannerKey()
 local ok,name,token=pcall(UnitRace,'player')
 local t=ok and type(token)=='string'and token or''
 t=t:lower():gsub('[^%a]','')
 local key=BANNER[t]
 if not key and(t:find('sky',1,true)or(ok and type(name)=='string'and name:lower():find('sky',1,true)))then key='skyborn'end
 if not key then
  local okf,faction=pcall(UnitFactionGroup,'player')
  key=(okf and faction=='Horde')and'orc_troll'or'human'
 end
 return'banner_'..key
end
function UI.ClassKey()
 local ok,_,token=pcall(UnitClass,'player')
 if ok and type(token)=='string'then return'class_'..token:lower()end
 return'class_warrior'
end
local function headerText()
 local okn,name=pcall(UnitName,'player');local okr,race=pcall(UnitRace,'player');local okc,class=pcall(UnitClass,'player');local okl,level=pcall(UnitLevel,'player')
 return okn and name or'?',(okr and race or'?')..' · '..(okc and class or'?'),'Stufe '..tostring(okl and level or'?')
end
-- Is ForeverCore.exe reachable right now?
function UI.Connected()
 local c=core();local u=c and c.UI
 if not(u and u.State)then return false,'ForeverCore nicht geladen'end
 local state,text=u.State()
 -- blue only after ForeverCore.exe has answered in this session; a queued job alone proves nothing
 return u.lastOk~=nil and(state=='ok'or state=='busy'),text
end

local frame
local function scaleToScreen()
 if not frame then return end
 local sh,sw=UIParent:GetHeight()or 768,UIParent:GetWidth()or 1365
 local s=math.min(1,(sh*.94)/(UI.H+70),(sw*.96)/(UI.W+60))
 frame:SetScale(math.max(.45,s))
end
UI.FitScale=scaleToScreen
local function place()
 local p=db().window
 frame:ClearAllPoints()
 if type(p)=='table'and tonumber(p.x)and tonumber(p.y)then frame:SetPoint('CENTER',UIParent,'CENTER',p.x,p.y)
 else frame:SetPoint('CENTER',UIParent,'CENTER',0,24)end
end
local function selectTab(key)
 local found=false;for _,t in ipairs(tabs)do if t.key==key then found=true;break end end
 if not found then key=tabs[1]and tabs[1].key end
 for _,t in ipairs(tabs)do
  local on=t.key==key
  if t.button then
   t.button:SetStyle(on and'tabOn'or'tab');t.button.label:SetTextColor(on and COLOR.gold[1]or COLOR.text[1],on and COLOR.gold[2]or COLOR.text[2],on and COLOR.gold[3]or COLOR.text[3],1)
  end
  if t.frame then
   if on then t.frame:Show()else t.frame:Hide()end
  end
 end
 UI.activeTab=key;db().tab=key
 for _,t in ipairs(tabs)do if t.key==key and t.show then pcall(t.show,t.frame)end end
end
UI.SelectTab=selectTab
function UI.UpdateCrystal()
 if not frame then return end
 local on,text=UI.Connected()
 UI.SetArt(frame.crystal.tex,on and'crystal_on'or'crystal_off');UI.SetArt(frame.crystal.glow,on and'crystal_on'or'crystal_off')
 frame.crystal.connected=on;frame.crystal.status=text
end
function UI.RefreshHeader()
 if not frame then return end
 local name,sub,level=headerText()
 frame.name:SetText(name);frame.sub:SetText(sub);frame.level:SetText(level)
 UI.SetArt(frame.banner,UI.BannerKey());UI.SetArt(frame.classIcon,UI.ClassKey())
end
function UI.Refresh()
 if not frame then return end
 UI.RefreshHeader();UI.UpdateCrystal()
 for _,t in ipairs(tabs)do if t.refresh and t.frame and t.frame:IsShown()then pcall(t.refresh,t.frame)end end
end

local function build()
 local f=CreateFrame('Frame','ForeverSimWindow',UIParent)
 f:SetSize(UI.W,UI.H);f:SetFrameStrata('HIGH');f:SetToplevel(true);f:EnableMouse(true);f:SetMovable(true);f:SetClampedToScreen(false)
 f:RegisterForDrag('LeftButton')
 f:SetScript('OnDragStart',function(self)self:StartMoving()end)
 f:SetScript('OnDragStop',function(self)
  self:StopMovingOrSizing()
  local x,y=self:GetCenter();local ux,uy=UIParent:GetCenter()
  local s=self:GetEffectiveScale()/(UIParent:GetEffectiveScale()or 1)
  if x and ux then local own=self:GetScale();if not own or own<=0 then own=1 end;db().window={x=(x*s-ux)/own,y=(y*s-uy)/own};self:ClearAllPoints();self:SetPoint('CENTER',UIParent,'CENTER',db().window.x,db().window.y)end
 end)
 -- the frame, drawn once at its fixed size in power-of-two tiles
 for key,e in pairs(ForeverSimArt or{})do
  if type(key)=='string'and key:match('^frame_%d%d$')then
   local t=f:CreateTexture(nil,'BACKGROUND',nil,0);UI.SetArt(t,key);t:SetSize(e.w,e.h);t:SetPoint('TOPLEFT',f,'TOPLEFT',e.x,-e.y)
  end
 end
 -- race banner standing on the curve
 f.banner=f:CreateTexture(nil,'ARTWORK',nil,3);f.banner:SetSize(819,205);f.banner:SetPoint('TOPLEFT',f,'TOPLEFT',239,14)
 -- class medallion in the left corner
 local med=CreateFrame('Frame',nil,f);med:SetSize(156,153);med:SetPoint('TOPLEFT',f,'TOPLEFT',-8,-20);med:SetFrameLevel(f:GetFrameLevel()+3);med:EnableMouse(false)
 f.classIcon=med:CreateTexture(nil,'ARTWORK',nil,1);f.classIcon:SetSize(78,78);f.classIcon:SetPoint('TOPLEFT',med,'TOPLEFT',39,-37)
 f.medal=UI.ArtTexture(med,'ARTWORK','portrait_round',2,156,153);f.medal:SetPoint('TOPLEFT',med,'TOPLEFT',0,0)
 f.name=UI.Text(f,21,COLOR.gold,'title','LEFT');f.name:SetPoint('TOPLEFT',f,'TOPLEFT',160,-104)
 f.sub=UI.Text(f,13,COLOR.muted,'body','LEFT');f.sub:SetPoint('TOPLEFT',f.name,'BOTTOMLEFT',0,-3)
 local pill=UI.Box(f,{.04,.13,.28,.7},{.47,.63,.9,.4});pill:SetSize(70,18);pill:SetPoint('TOPLEFT',f.sub,'BOTTOMLEFT',0,-6)
 f.level=UI.Text(pill,11,{.81,.89,1},'body','CENTER');f.level:SetAllPoints()
 -- crystal in the right corner: blue = ForeverCore.exe answers, grey = it does not; a click closes the window
 local cr=CreateFrame('Button','ForeverSimCrystal',f);cr:SetSize(176,176);cr:SetPoint('TOPRIGHT',f,'TOPRIGHT',18,-8);cr:SetFrameLevel(f:GetFrameLevel()+4)
 cr.tex=cr:CreateTexture(nil,'ARTWORK');cr.tex:SetAllPoints()
 cr.glow=cr:CreateTexture(nil,'OVERLAY');cr.glow:SetAllPoints();cr.glow:SetBlendMode('ADD');cr.glow:SetAlpha(0)
 cr:RegisterForClicks('LeftButtonUp')
 cr:SetScript('OnClick',function()f:Hide()end)
 cr:SetScript('OnEnter',function(self)
  self.glow:SetAlpha(.35)
  if GameTooltip then
   GameTooltip:SetOwner(self,'ANCHOR_LEFT');GameTooltip:SetText('ForeverSim',1,.82,0)
   GameTooltip:AddLine(self.connected and'ForeverCore.exe ist verbunden'or'ForeverCore.exe antwortet nicht',self.connected and .3 or 1,self.connected and 1 or .45,self.connected and .4 or .4)
   if self.status and not self.connected then GameTooltip:AddLine(tostring(self.status),.8,.8,.8,true)end
   GameTooltip:AddLine('Klicken zum Schließen',.6,.8,1);GameTooltip:Show()
  end
 end)
 cr:SetScript('OnLeave',function(self)self.glow:SetAlpha(0);if GameTooltip then GameTooltip:Hide()end end)
 f.crystal=cr
 -- where the tab pages go
 f.content=CreateFrame('Frame',nil,f);f.content:SetPoint('TOPLEFT',f,'TOPLEFT',44,-190);f.content:SetPoint('BOTTOMRIGHT',f,'BOTTOMRIGHT',-44,40)
 -- the tab buttons hang under the window
 local x=62
 for _,t in ipairs(tabs)do
  local b=UI.Button(f,t.label,{w=176,h=50,styles={'tab','tabOn'},kind='title',size=15,icon=t.icon,iconSize=17})
  b:SetPoint('TOPLEFT',f,'TOPLEFT',x,-794);x=x+184
  b:SetScript('OnClick',function()selectTab(t.key)end)
  t.button=b
  local page=CreateFrame('Frame',nil,f.content);page:SetAllPoints();page:Hide();t.frame=page
  local ok,err=pcall(t.build,page,t)
  if not ok then
   local msg=UI.Text(page,13,COLOR.bad,'body','CENTER');msg:SetPoint('CENTER',page,'CENTER',0,0);msg:SetWidth(700);msg:SetText('Dieser Reiter konnte nicht aufgebaut werden: '..tostring(err))
  end
 end
 f:SetScript('OnShow',function()scaleToScreen();UI.Refresh();if not UI.activeTab then selectTab(db().tab or(tabs[1]and tabs[1].key))else selectTab(UI.activeTab)end end)
 f:SetScript('OnUpdate',function(self,elapsed)
  self.tick=(self.tick or 0)+(elapsed or 0);if self.tick<.5 then return end;self.tick=0
  UI.UpdateCrystal()
 end)
 f:RegisterEvent('PLAYER_LEVEL_UP');f:RegisterEvent('UI_SCALE_CHANGED');f:RegisterEvent('DISPLAY_SIZE_CHANGED')
 f:SetScript('OnEvent',function(self,event)
  if event=='PLAYER_LEVEL_UP'then UI.RefreshHeader()end
  scaleToScreen();if self:IsShown()then UI.Refresh()end
 end)
 if UISpecialFrames then table.insert(UISpecialFrames,'ForeverSimWindow')end
 frame=f;place();scaleToScreen();UI.RefreshHeader();UI.UpdateCrystal();f:Hide()
 return f
end
function UI.Window()if not frame then build()end;return frame end
function UI.Open(tabKey)
 local f=UI.Window();if tabKey then UI.activeTab=tabKey end
 if f:IsShown()then selectTab(UI.activeTab)else f:Show()end
end
function UI.Close()if frame then frame:Hide()end end
function UI.Toggle()
 local f=UI.Window()
 if f:IsShown()then f:Hide()else f:Show()end
end
function UI.IsOpen()return frame~=nil and frame:IsShown()end

-- a notice that fills a tab while its feature is not available yet ("Ab Stufe 60 verfügbar")
function UI.LockedNotice(page,text,sub)
 local n=CreateFrame('Frame',nil,page);n:SetAllPoints()
 local a=UI.Text(n,22,COLOR.gold,'title','CENTER');a:SetPoint('CENTER',n,'CENTER',0,18);a:SetText(text)
 local b=UI.Text(n,14,COLOR.muted,'body','CENTER');b:SetPoint('TOP',a,'BOTTOM',0,-10);b:SetWidth(640);b:SetText(sub or'')
 return n
end
UI.Sim=sim
