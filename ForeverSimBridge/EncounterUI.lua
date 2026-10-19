-- Standalone encounter selector; safe when ForeverDungeonQuest is not installed.
local P=_G.FUSLive
if not P or not P.encounters then return end
local M=P.encounters
local UI={};P.encounterUI=UI
local root='Interface\\AddOns\\ForeverSimBridge\\Media\\'
local frame,labels,selection={},{},{}
local function numberLevel()
 local f=P.publicNumber
 return (f and UnitLevel and f(UnitLevel('player'))) or 60
end
local function safeCombat()return InCombatLockdown and InCombatLockdown()end
local function label(parent,x,y,w,h,value,bright)
 local t=parent:CreateFontString(nil,'OVERLAY','GameFontNormal')
 t:SetPoint('TOPLEFT',x,y);t:SetSize(w,h);t:SetJustifyH('LEFT');t:SetJustifyV('TOP');t:SetWordWrap(true);t:SetText(value or '')
 if bright then t:SetTextColor(.95,.79,.48)else t:SetTextColor(.80,.85,.93)end
 return t
end
local function action(parent,x,y,w,h,title,callback)
 local f=CreateFrame('Button',nil,parent,'BackdropTemplate');f:SetPoint('TOPLEFT',x,y);f:SetSize(w,h)
 f:SetBackdrop({bgFile=root..'FQButtonBlue',edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',edgeSize=10,insets={left=3,right=3,top=3,bottom=3}})
 f:SetBackdropColor(.11,.18,.28,.96);f:SetBackdropBorderColor(.52,.47,.39,.88)
 local t=label(f,8,-math.max(6,(h-16)/2),w-16,16,title);t:SetJustifyH('CENTER');f:SetHighlightTexture(root..'FQSelection','ADD')
 f:SetScript('OnClick',function()if not safeCombat()then callback()end end)
 return f
end
local function current()
 ForeverSimBridgeDB=ForeverSimBridgeDB or {}
 return ForeverSimBridgeDB.encounter or {}
end
local function set(options)
 local ok,reason=M.Configure(options)
 if not ok then print('Forever SIM: '..tostring(reason));return end
 UI.Refresh()
end
local function cycle(values,old)
 if #values==0 then return nil end
 for index,v in ipairs(values)do if v==old then return values[(index % #values)+1]end end
 return values[1]
end
function UI.Refresh()
 if not frame or not frame.IsShown or not frame:IsShown() then return end
 local req=current();local level=numberLevel();local resolved=M.Resolve(level,req)
 if not resolved then return end
 labels.title:SetText('CHARAKTER LEVEL '..level..'  /  '..string.upper(resolved.mode or 'quest'))
 labels.profile:SetText(M.Describe(resolved))
 labels.note:SetText('Rüstung: '..tostring(resolved.armorSource or 'unbekannt')..'\nWiderstände: '..tostring(resolved.resistanceSource or 'unbekannt')..'\nZiellevel-Differenz: '..tostring(resolved.levelDifference or '?')..' · Alle neun Klassen nutzen identische Gegnerparameter.')
 labels.dungeon:SetText('Dungeon: '..tostring(req.dungeon or '(keiner)'))
 labels.boss:SetText('Boss: '..tostring(req.boss or '(keiner)'))
 labels.fdq:SetText(#M.ListDungeons()>0 and 'FDQ-Journal verbunden · Bosse/Level aus vorhandenen Daten' or 'FDQ-Dungeonjournal nicht verfügbar · generisches Dungeon-Modell')
 labels.warning:SetText('WICHTIG: Synthetische Rüstung ist ein offen gekennzeichnetes Vergleichsmodell, kein gemessener NPC-Wert. Ohne belegte Bossdaten werden keine Eigenschaften erfunden.')
end
local function build()
 if frame and frame.CreateFontString then return end
 local f=CreateFrame('Frame','ForeverSimEncounterSelector',UIParent,'BackdropTemplate');frame=f;f:SetFrameStrata('DIALOG');f:SetSize(800,605);f:SetClampedToScreen(true)
 f:SetPoint('CENTER');f:SetMovable(true);f:EnableMouse(true);f:RegisterForDrag('LeftButton');f:SetScript('OnDragStart',function(self)if not safeCombat()then self:StartMoving()end end);f:SetScript('OnDragStop',function(self)self:StopMovingOrSizing()end)
 f:SetBackdrop({bgFile=root..'FQDark',edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',edgeSize=15,insets={left=5,right=5,top=5,bottom=5}})
 f:SetBackdropColor(.025,.035,.064,.99);f:SetBackdropBorderColor(.76,.58,.34,.98)
 label(f,24,-19,620,28,'FOREVER SIM  /  ENCOUNTER-BENCHMARK',true)
 local close=CreateFrame('Button',nil,f,'UIPanelCloseButton');f.appClose=close;close:SetPoint('TOPRIGHT',-10,-12);close:SetScript('OnClick',function()f:Hide()end)
 labels.title=label(f,26,-63,700,24,'',true)
 labels.profile=label(f,26,-97,745,37,'')
 action(f,24,-157,175,38,'Questgegner',function()set({mode='quest',offset=1})end)
 action(f,214,-157,175,38,'Elite',function()set({mode='elite',offset=0})end)
 action(f,404,-157,175,38,'Dungeon',function()
  local d=current();local dirs=M.ListDungeons();local name=d.dungeon or dirs[1]
  local bosses=M.ListBosses(name);set({mode='dungeon',dungeon=name,boss=d.boss or bosses[1]})
 end)
 action(f,594,-157,175,38,'Standardziel',function()set({mode='standard'})end)
 label(f,25,-218,690,18,'QUEST-REFERENZEN  /  LEVELABSTAND',true)
 local preset={{'-1',-1},{'0',0},{'+1',1},{'+2',2},{'Elite 0',0,'elite'}}
 for i,r in ipairs(preset)do
  action(f,24+(i-1)*150,-248,136,37,r[1],function()set({mode=r[3]or'quest',offset=r[2]})end)
 end
 label(f,25,-306,700,19,'DUNGEON-BOSSE  /  KEINE EIGENE NPC-DATENBANK',true)
 labels.dungeon=label(f,26,-335,680,18,'')
 action(f,595,-329,173,30,'Dungeon wechseln',function()
  local dirs=M.ListDungeons();local d=cycle(dirs,current().dungeon)
  if d then set({mode='dungeon',dungeon=d,boss=M.ListBosses(d)[1]})end
 end)
 labels.boss=label(f,26,-374,560,18,'')
 action(f,595,-368,173,30,'Boss wechseln',function()
  local d=current();local bosses=M.ListBosses(d.dungeon)
  local b=cycle(bosses,d.boss)
  if b then set({mode='dungeon',dungeon=d.dungeon,boss=b})end
 end)
 labels.fdq=label(f,26,-411,743,21,'')
 labels.note=label(f,25,-444,742,65,'')
 labels.warning=label(f,25,-510,740,48,'')
 action(f,25,-559,355,35,'DPS / Rotation berechnen',function()if P.optimizeNow then P.optimizeNow()end end)
 action(f,395,-559,373,35,'DPS-Szenario ansehen',function()if P.scenarioStudio then P.scenarioStudio.Show('scenario')elseif P.dashboardUI then P.dashboardUI.Show('simulation')end end)
 f:Hide();-- No writes to Blizzard UISpecialFrames (taint isolation).
end
function UI.Show()
 if safeCombat()then return end
 build()
 local w,h=UIParent:GetWidth(),UIParent:GetHeight();frame:SetScale(math.max(.55,math.min(1,w*.92/800,h*.92/605)))
 frame:Show();UI.Refresh()
end
function UI.Command(msg)
 if msg=='encounter' or msg=='target' then UI.Show();return true end
 local mode=msg:match('^target%s+(%a+)$')
 if mode and (mode=='quest' or mode=='elite' or mode=='dungeon' or mode=='standard')then set({mode=mode});UI.Show();return true end
 local off=tonumber(msg:match('^target%s+([%+%-]?%d+)$'))
 if off and off>=-5 and off<=10 then set({mode='quest',offset=off});UI.Show();return true end
end
SLASH_FOREVERSIMENCOUNTER1='/fsimtarget'
SlashCmdList['FOREVERSIMENCOUNTER']=function()UI.Show()end

-- Expose only the addon-owned root for the embedded app view.
function UI.GetFrame() return frame and frame.CreateFontString and frame end
