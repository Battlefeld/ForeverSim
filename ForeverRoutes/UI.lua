-- The window (current step, what comes next) and the arrow: a TomTom waypoint when TomTom is there, else the game's
-- own map pin. Plain on purpose; the look comes later.
local FR=ForeverRoutes
local function call(fn,...)if type(fn)~='function'then return nil end;local r={pcall(fn,...)};if not r[1]then return nil end;return select(2,unpack(r))end
local ROWS=5

function FR.Waypoint(m,x,y,title)
 if not m or not x or not C_Map or not C_Map.GetMapPosFromWorldPos or not CreateVector2D then return false end
 local here=call(C_Map.GetBestMapForUnit,'player')
 local map,pos=call(C_Map.GetMapPosFromWorldPos,m,CreateVector2D(x,y),here)
 if not pos or pos.x<0 or pos.x>1 or pos.y<0 or pos.y>1 then map,pos=call(C_Map.GetMapPosFromWorldPos,m,CreateVector2D(x,y))end
 if not map or not pos then return false end
 if TomTom and TomTom.AddWaypoint then
  if FR.tomtom and TomTom.RemoveWaypoint then call(TomTom.RemoveWaypoint,TomTom,FR.tomtom)end
  FR.tomtom=call(TomTom.AddWaypoint,TomTom,map,pos.x,pos.y,{title=title,persistent=false,minimap=true,world=true})
  return FR.tomtom~=nil
 end
 if C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
  call(C_Map.SetUserWaypoint,UiMapPoint.CreateFromCoordinates(map,pos.x,pos.y))
  if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then call(C_SuperTrack.SetSuperTrackedUserWaypoint,true)end
  return true
 end
 return false
end

-- Takes the arrow away (inside a dungeon it has nothing to show).
function FR.ClearWaypoint()
 if FR.tomtom and TomTom and TomTom.RemoveWaypoint then call(TomTom.RemoveWaypoint,TomTom,FR.tomtom)end
 FR.tomtom=nil
 if FR.pinned and C_Map and C_Map.ClearUserWaypoint then call(C_Map.ClearUserWaypoint)end
 FR.pinned=nil
end

local frame,header,hint,lines
local function makeFrame()
 if frame then return frame end
 frame=CreateFrame('Frame','ForeverRoutesFrame',UIParent,'BackdropTemplate')
 frame:SetSize(400,74+ROWS*18);frame:SetPoint('RIGHT',UIParent,'RIGHT',-40,120)
 if frame.SetBackdrop then frame:SetBackdrop({bgFile='Interface\\Tooltips\\UI-Tooltip-Background'});frame:SetBackdropColor(.03,.04,.07,.88)end
 frame:SetMovable(true);frame:EnableMouse(true);frame:RegisterForDrag('LeftButton')
 frame:SetScript('OnDragStart',frame.StartMoving);frame:SetScript('OnDragStop',frame.StopMovingOrSizing)
 header=frame:CreateFontString(nil,'OVERLAY','GameFontNormal');header:SetPoint('TOPLEFT',10,-8);header:SetWidth(300);header:SetJustifyH('LEFT')
 hint=frame:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');hint:SetPoint('TOPLEFT',10,-26);hint:SetWidth(380);hint:SetJustifyH('LEFT')
 lines={}
 for i=1,ROWS do
  local l=frame:CreateFontString(nil,'OVERLAY',i==1 and'GameFontHighlight'or'GameFontDisableSmall')
  l:SetPoint('TOPLEFT',10,-46-(i-1)*18);l:SetWidth(380);l:SetJustifyH('LEFT');lines[i]=l
 end
 local skip=CreateFrame('Button',nil,frame,'UIPanelButtonTemplate');skip:SetSize(84,20);skip:SetPoint('TOPRIGHT',-26,-5);skip:SetText('Überspringen')
 skip:SetScript('OnClick',function()FR.Skip();FR.Refresh()end)
 local back=CreateFrame('Button',nil,frame,'UIPanelButtonTemplate');back:SetSize(60,20);back:SetPoint('RIGHT',skip,'LEFT',-4,0);back:SetText('Zurück')
 back:SetScript('OnClick',function()FR.Back();FR.Refresh()end)
 local close=CreateFrame('Button',nil,frame,'UIPanelCloseButton');close:SetPoint('TOPRIGHT',2,2)
 close:SetScript('OnClick',function()frame:Hide();ForeverRoutesDB=ForeverRoutesDB or{};ForeverRoutesDB.hidden=true end)
 return frame
end

-- Moves the arrow to the current step (also with the window hidden); inside a dungeon there is none.
local function arrow(step)
 if call(IsInInstance)==true then FR.ClearWaypoint();return end
 local m,x,y,dying=FR.Target(step)
 if not m then return end
 local key=FR.StepKey(step)..(dying and':die'or'')
 if FR.pinned~=key then
  FR.pinned=key
  FR.Waypoint(m,x,y,dying and'Death Skip: hier sterben'or FR.Text(step))
 end
end

-- Redraws the window and moves the arrow to the current step.
function FR.Refresh()
 local step,i=FR.Advance()
 local steps,live=FR.Steps()
 local route,key=FR.Route()
 if FR.Paused(step)then FR.ClearWaypoint()else arrow(step)end
 if not frame then return step end
 if not live and not route then
  header:SetText('ForeverRoutes');hint:SetText('Keine Route für '..tostring(key));for k=1,ROWS do lines[k]:SetText('')end
  return nil
 end
 if FR.Paused(step)then
  header:SetText('ForeverRoutes · Route pausiert (Dungeon)')
  hint:SetText('Geht nach dem Dungeon beim nächsten offenen Schritt weiter')
  for k=1,ROWS do local s=steps[i+k-1];lines[k]:SetText(s and FR.Text(s)or'')end
  return step
 end
 header:SetText(live and'ForeverRoutes · live geplant'or string.format('ForeverRoutes · %s · Schritt %d/%d',tostring(key):find('%-dungeons$')and'Solo mit Dungeon'or'Solo ohne Dungeon',i,#steps))
 hint:SetText(FR.Hint(step)or'')
 for k=1,ROWS do
  local s=steps[i+k-1]
  lines[k]:SetText(s and FR.Text(s)or(k==1 and FR.Text(nil)or''))
 end
 return step
end

function FR.Show()makeFrame():Show();ForeverRoutesDB=ForeverRoutesDB or{};ForeverRoutesDB.hidden=nil;FR.Refresh()end

local events=CreateFrame('Frame')
for _,e in ipairs({'PLAYER_LOGIN','PLAYER_ENTERING_WORLD','QUEST_ACCEPTED','QUEST_TURNED_IN','QUEST_REMOVED','QUEST_LOG_UPDATE','PLAYER_LEVEL_UP','PLAYER_DEAD','PLAYER_UNGHOST','PLAYER_ALIVE'})do pcall(events.RegisterEvent,events,e)end
events:SetScript('OnEvent',function(_,event)
 if event=='PLAYER_LOGIN'then
  if not(ForeverRoutesDB and ForeverRoutesDB.hidden)then FR.Show()end
  return
 end
 if event=='PLAYER_DEAD'then FR.Died()end
 FR.Refresh()
end)

SLASH_FOREVERROUTES1='/fr'
SlashCmdList.FOREVERROUTES=function(msg)
 msg=strtrim(tostring(msg or'')):lower()
 if msg=='skip'then FR.Skip()elseif msg=='back'or msg=='zurueck'then FR.Back()elseif msg=='reset'then FR.Reset()
 elseif msg=='dungeon'or msg=='dungeons'or msg=='mit'or msg=='gruppe'then FR.SetDungeons(true)
 elseif msg=='solo'or msg=='ohne'then FR.SetDungeons(false)
 elseif msg==''and frame and frame:IsShown()then frame:Hide();ForeverRoutesDB=ForeverRoutesDB or{};ForeverRoutesDB.hidden=true;return end
 FR.Show()
end
