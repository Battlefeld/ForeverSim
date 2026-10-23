-- After the login: if the engine, the game patch, the gear, the level or the items in the bags changed since the last
-- calculation, everything is calculated again in the background (a small notice says why). Only once per login; during the
-- session a new calculation starts only when the player presses the button.
ForeverSimUI=ForeverSimUI or{}
local UI=ForeverSimUI
local COLOR=UI.COLOR
local function Sim()local c=ForeverCoreClient;return c and c.Sim or nil end
local state={waited=0,done=false}
UI.loginCheck=state
local popup
local function build()
 local f=CreateFrame('Frame','ForeverSimLoginNotice',UIParent);f:SetSize(480,170);f:SetPoint('TOP',UIParent,'TOP',0,-140);f:SetFrameStrata('HIGH')
 f:Hide()   -- no mouse on the frame itself: it must never swallow clicks in the world
 UI.Style(f,'panel','BACKGROUND')
 f.icon=f:CreateTexture(nil,'ARTWORK');f.icon:SetSize(34,34);f.icon:SetPoint('TOPLEFT',f,'TOPLEFT',32,-36);UI.SetArt(f.icon,'crystal_on')
 f.title=UI.Text(f,16,COLOR.gold,'title','LEFT');f.title:SetPoint('TOPLEFT',f.icon,'TOPRIGHT',10,2)
 f.reason=UI.Text(f,12,COLOR.text,'body','LEFT');f.reason:SetPoint('TOPLEFT',f.icon,'BOTTOMLEFT',0,-10);f.reason:SetWidth(410);f.reason:SetWordWrap(true)
 f.status=UI.Text(f,12,COLOR.muted,'body','LEFT');f.status:SetPoint('BOTTOMLEFT',f,'BOTTOMLEFT',32,26)
 f.close=UI.Button(f,'Ausblenden',{w=120,h=34,size=12});f.close:SetPoint('BOTTOMRIGHT',f,'BOTTOMRIGHT',-26,16)
 f.close:SetScript('OnClick',function()f:Hide()end)
 f:SetScript('OnUpdate',function(self,dt)
  if self.hideAt and GetTime()>=self.hideAt then self.hideAt=nil;self:Hide()end
 end)
 return f
end
function UI.LoginNotice(title,reason,status,hideAfter)
 popup=popup or build()
 popup.title:SetText(title or'');popup.reason:SetText(reason or'');popup.status:SetText(status or'')
 popup.hideAt=hideAfter and(GetTime()+hideAfter)or nil
 popup:Show()
end
local function readableReasons(list)return table.concat(list,' · ')end

-- Starts the calculation when it is due. Returns true when it did.
function UI.RunLoginCheck()
 local S=Sim();if not S or state.done then return false end
 state.done=true
 if not S.AutoLogin()then return false end
 local reasons=S.RecalcReasons();if #reasons==0 then return false end
 state.reasons=reasons
 UI.LoginNotice('ForeverSim rechnet neu',readableReasons(reasons),'Startet …')
 local ok=S.RunAll({selected='live'},function(step,total,label)
  UI.LoginNotice('ForeverSim rechnet neu',readableReasons(reasons),'Schritt '..step..' von '..total..' · '..tostring(label or''))
 end,function(done,issue)
  if done then UI.LoginNotice('ForeverSim ist auf dem neuesten Stand',readableReasons(reasons),'Fertig. Du kannst jetzt weiterspielen.',8)
  else UI.LoginNotice('ForeverSim konnte nicht fertig rechnen',tostring(issue or'Keine Antwort von ForeverCore.exe'),'Im Fenster unter „Simulieren“ erneut versuchen.',15)end
  if UI.talentsRefresh then UI.talentsRefresh()end
  if UI.rotationRefresh then UI.rotationRefresh()end
 end)
 if not ok then popup:Hide();state.done=false end
 return ok
end

-- Waits for the connection to ForeverCore.exe (it answers a little after the login), then checks once.
local driver=CreateFrame('Frame')
local started=false
driver:RegisterEvent('PLAYER_LOGIN')
driver:SetScript('OnEvent',function()started=true;state.waited=0;state.done=false end)
driver:SetScript('OnUpdate',function(_,dt)
 if not started or state.done then return end
 state.waited=state.waited+dt
 state.tick=(state.tick or 0)+dt;if state.tick<2 then return end;state.tick=0
 if state.waited>180 then state.done=true;return end            -- ForeverCore.exe is not running: nothing to do this time
 if state.waited<6 then return end
 if UI.HUDInCombat and UI.HUDInCombat()then return end
 if ForeverSimHUD and ForeverSimHUD.InCombat and ForeverSimHUD.InCombat()then return end
 local on=UI.Connected and UI.Connected()
 if on then UI.RunLoginCheck()
 elseif not state.pinged and state.waited>=10 then
  -- nothing has answered yet in this session: a ping tells whether ForeverCore.exe is there
  state.pinged=true;local c=ForeverCoreClient;if c and c.Request then pcall(c.Request,'ping',{},function()end)end
 end
end)
