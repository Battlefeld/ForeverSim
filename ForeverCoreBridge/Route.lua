-- Route while playing. The game's view of the character (level, XP, position, quest log with progress, finished
-- quests, known flight masters, hearthstone) goes to ForeverCore (job route-next); ForeverRoutes plans the next hour
-- from exactly there and the window shows it, with a waypoint on the first step. Every quest event plans again,
-- so the route follows the character instead of a fixed guide.
-- Off until switched on: /fc route an (automatic), /fc route (once and open the window).
local C=ForeverCoreClient
local R={}
C.Route=R
local EMPTY={}
local function db()return ForeverCoreBridgeDB or EMPTY end
local function call(fn,...)if type(fn)~='function'then return nil end;local r={pcall(fn,...)};if not r[1]then return nil end;return select(2,unpack(r))end
local function charKey()return tostring(call(UnitGUID,'player')or'?')end
local function npcID(guid)
 if type(guid)~='string'then return nil end
 local kind,_,_,_,_,id=strsplit('-',guid);if kind~='Creature'then return nil end
 return tonumber(id)
end
local function charDB(field)
 local d=ForeverCoreBridgeDB;if not d then return{}end
 d[field]=d[field]or{};local k=charKey();d[field][k]=d[field][k]or{};return d[field][k]
end

-- The world position in ForeverRoutes' terms (cmangos: x along north, y along west, continent 0/1).
-- UnitPosition returns exactly these two first; instances and other maps are not planned.
function R.Position()
 local a,b,_,instance=call(UnitPosition,'player')
 if type(a)~='number'or type(b)~='number'or(instance~=0 and instance~=1)then return nil end
 return{m=instance,x=a,y=b}
end

local function completedIDs()
 local out={}
 local all=C_QuestLog and call(C_QuestLog.GetAllCompletedQuestIDs)
 if type(all)=='table'then for _,id in ipairs(all)do if type(id)=='number'then out[#out+1]=id end end;return out end
 local map=call(GetQuestsCompleted)
 if type(map)=='table'then for id,done in pairs(map)do if done and type(id)=='number'then out[#out+1]=id end end end
 table.sort(out);return out
end

local function objectives(id)
 local list=C_QuestLog and call(C_QuestLog.GetQuestObjectives,id)
 local out={}
 for _,o in ipairs(type(list)=='table'and list or{})do
  out[#out+1]={type=tostring(o.type or''),have=tonumber(o.numFulfilled)or 0,need=tonumber(o.numRequired)or 0,done=o.finished==true or nil}
 end
 return out
end

local function questLog()
 local out={}
 local n=call(GetNumQuestLogEntries)or 0
 for i=1,n do
  local _,_,_,isHeader,_,isComplete,_,id=call(GetQuestLogTitle,i)
  if not isHeader and type(id)=='number'and id>0 then
   out[#out+1]={id=id,ready=(isComplete==1 or isComplete==true)or nil,objectives=objectives(id)}
  end
 end
 return out
end

local function hearthIn()
 local get=GetItemCooldown or(C_Container and C_Container.GetItemCooldown)
 local start,duration=call(get,6948)
 if type(start)~='number'or type(duration)~='number'or start<=0 then return 0 end
 return math.max(0,start+duration-(GetTime and GetTime()or 0))
end

local function flightMasters()
 local out={};for id in pairs(charDB('routeFlight'))do out[#out+1]=id end;table.sort(out);return out
end

-- The hearthstone's place: the position where the player last agreed to bind (CONFIRM_BINDER), once the
-- hearthstone names a new place; as long as it names that place.
local function bind()
 local b=charDB('routeBind');local name=call(GetBindLocation)
 if b.candidate and name~=b.oldName then b.pos,b.name,b.candidate,b.oldName=b.candidate,name,nil,nil end
 if b.pos and b.name==name then return b.pos end
 return nil
end

-- What route-next sends: small on purpose (finished quests are the bulk, a few KB).
function R.Capture()
 if InCombatLockdown and InCombatLockdown()then error('Route nur ausserhalb des Kampfes')end
 local _,class=call(UnitClass,'player');local _,race=call(UnitRace,'player')
 local live={level=call(UnitLevel,'player'),xp=call(UnitXP,'player')or 0,pos=R.Position(),completed=completedIDs(),active=questLog(),bind=bind(),hearthIn=hearthIn(),flightMasters=flightMasters()}
 if not class or not race or not live.level then error('Charakter nicht lesbar')end
 -- "Solo mit Dungeon" when the player chose it in the ForeverRoutes addon (/fr dungeon)
 local db=type(ForeverRoutesCharDB)=='table'and ForeverRoutesCharDB or{}
 local dungeons=(db.dungeons==true or db.group==true)or nil
 return{race=race,class=class,faction=call(UnitFactionGroup,'player'),dungeons=dungeons,live=live}
end

-- Wording of a step.
local VERB={kill='toete',item='sammle',object='benutze'}
function R.Text(step)
 local name=tostring(step.name or'')
 if step.op=='accept'then return'Annehmen: '..name end
 if step.op=='turnin'then return'Abgeben: '..name end
 if step.op=='grind'then return'Grinden: '..name end
 return(name:gsub(': (%a+) (%d+) ',function(kind,n)return': '..(VERB[kind]or kind)..' '..n..' 'end))
end

-- Waypoint on the first step: TomTom when installed, else the game's own map pin.
function R.Waypoint(step)
 local at=step and step.at
 if type(at)~='table'or not C_Map or not C_Map.GetMapPosFromWorldPos or not CreateVector2D then return false end
 local here=call(C_Map.GetBestMapForUnit,'player')
 local map,pos=call(C_Map.GetMapPosFromWorldPos,at.m,CreateVector2D(at.x,at.y),here)
 if not pos or pos.x<0 or pos.x>1 or pos.y<0 or pos.y>1 then map,pos=call(C_Map.GetMapPosFromWorldPos,at.m,CreateVector2D(at.x,at.y))end
 if not map or not pos then return false end
 local title=R.Text(step)
 if TomTom and TomTom.AddWaypoint then
  if R.tomtom and TomTom.RemoveWaypoint then call(TomTom.RemoveWaypoint,TomTom,R.tomtom)end
  R.tomtom=call(TomTom.AddWaypoint,TomTom,map,pos.x,pos.y,{title=title,persistent=false,minimap=true,world=true})
  return R.tomtom~=nil
 end
 if C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
  call(C_Map.SetUserWaypoint,UiMapPoint.CreateFromCoordinates(map,pos.x,pos.y))
  if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then call(C_SuperTrack.SetSuperTrackedUserWaypoint,true)end
  return true
 end
 return false
end

-- Window --------------------------------------------------------------------------------------------------
local ROWS=8
local frame,lines,status
local function minutes(s)return string.format('%d min',math.floor((tonumber(s)or 0)/60+.5))end
local function makeFrame()
 if frame then return frame end
 frame=CreateFrame('Frame','ForeverCoreRouteFrame',UIParent,'BackdropTemplate')
 frame:SetSize(380,64+ROWS*18);frame:SetPoint('RIGHT',UIParent,'RIGHT',-40,80)
 if frame.SetBackdrop then frame:SetBackdrop({bgFile='Interface\\Tooltips\\UI-Tooltip-Background'});frame:SetBackdropColor(.025,.04,.08,.9)end
 frame:SetMovable(true);frame:EnableMouse(true);frame:RegisterForDrag('LeftButton')
 frame:SetScript('OnDragStart',frame.StartMoving);frame:SetScript('OnDragStop',frame.StopMovingOrSizing)
 local title=frame:CreateFontString(nil,'OVERLAY','GameFontNormal');title:SetPoint('TOPLEFT',10,-8);title:SetText('ForeverRoutes · naechste Stunde')
 status=frame:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');status:SetPoint('TOPLEFT',10,-26);status:SetWidth(360);status:SetJustifyH('LEFT')
 lines={}
 for i=1,ROWS do
  local l=frame:CreateFontString(nil,'OVERLAY',i==1 and'GameFontHighlight'or'GameFontHighlightSmall')
  l:SetPoint('TOPLEFT',10,-44-(i-1)*18);l:SetWidth(360);l:SetJustifyH('LEFT');lines[i]=l
 end
 local close=CreateFrame('Button',nil,frame,'UIPanelCloseButton');close:SetPoint('TOPRIGHT',2,2)
 local again=CreateFrame('Button',nil,frame,'UIPanelButtonTemplate');again:SetSize(90,20);again:SetPoint('TOPRIGHT',-28,-5);again:SetText('Neu planen')
 again:SetScript('OnClick',function()R.Request(true)end)
 frame:Hide()
 return frame
end
function R.Show()makeFrame():Show();R.Draw()end
function R.Draw()
 if not frame then return end
 local r=R.last
 if R.issue then status:SetText('|cffff6060'..R.issue..'|r')
 elseif not r then status:SetText(R.waiting and'Route wird berechnet ...'or'Noch keine Route')
 else
  local note=r.profileNote or(#(r.notes or{})>0 and r.notes[1])or nil
  status:SetText(string.format('Level %d -> %d in %s%s',tonumber(r.level)or 0,tonumber(r.toLevel)or 0,minutes(r.seconds),note and(' · '..note)or''))
 end
 local steps=r and r.steps or{}
 for i=1,ROWS do
  local s=steps[i]
  lines[i]:SetText(s and string.format('%s  |cff9999aa%s|r',R.Text(s),minutes(s.time))or'')
 end
end

-- Requests ------------------------------------------------------------------------------------------------
local function queued()
 if C.pending and C.pending.kind=='route-next'then return true end
 for _,job in ipairs(C.queue or{})do if job.kind=='route-next'then return true end end
 return false
end
function R.Apply(result,issue)
 R.waiting=false
 if issue then R.issue=issue else R.issue=nil;R.last=result;R.at=GetTime and GetTime()or 0;R.Waypoint(result and result.steps and result.steps[1])end
 R.Draw()
 -- the ForeverRoutes addon shows the live plan in place of its stored route, and goes back to that when planning fails
 local FR=ForeverRoutes
 if FR and FR.SetLive then
  FR.SetLive(not issue and result or nil)
  if FR.Refresh then pcall(FR.Refresh)end
 end
end
function R.Request(show)
 if show then R.Show()end
 if queued()then return false end
 R.waiting=true;R.Draw()
 return C.Request('route-next',{horizon=3600},R.Apply)
end
function R.Enabled()return db().routeNext==true end

-- Plans again after what changes the route: quests taken, finished, turned in or dropped, objective progress,
-- a level, a new flight master. Waits a little so a burst of events gives one request.
local DELAY,MIN_GAP=3,15
local function progressKey()
 local parts={}
 for _,q in ipairs(questLog())do
  parts[#parts+1]=q.id..(q.ready and'!'or'')
  for _,o in ipairs(q.objectives)do parts[#parts+1]=o.have end
 end
 return table.concat(parts,',')
end
local function schedule(delay)
 if not R.Enabled()or R.scheduled then return end
 R.scheduled=true
 local wait=math.max(delay or DELAY,MIN_GAP-((GetTime and GetTime()or 0)-(R.requestedAt or-1e9)))
 C_Timer.After(wait,function()R.scheduled=false;R.requestedAt=GetTime and GetTime()or 0;R.Request(false)end)
end
R.schedule=schedule
local events=CreateFrame('Frame')
for _,e in ipairs({'PLAYER_ENTERING_WORLD','QUEST_ACCEPTED','QUEST_TURNED_IN','QUEST_REMOVED','QUEST_LOG_UPDATE','PLAYER_LEVEL_UP','TAXIMAP_OPENED','CONFIRM_BINDER'})do pcall(events.RegisterEvent,events,e)end
events:SetScript('OnEvent',function(_,event)
 if event=='TAXIMAP_OPENED'then
  local id=npcID(call(UnitGUID,'npc'))
  if id and ForeverCoreBridgeDB then local known=charDB('routeFlight');if not known[id]then known[id]=true;schedule()end end
  return
 end
 if event=='CONFIRM_BINDER'then
  local b=charDB('routeBind');b.candidate=R.Position();b.oldName=call(GetBindLocation)
  return
 end
 if event=='QUEST_LOG_UPDATE'then
  local key=progressKey();if key==R.progress then return end;R.progress=key
 end
 schedule()
end)

-- Bridge integration: route-next captures its own small state instead of the SIM snapshot.
local baseCapture=C.Capture
C.Capture=function(kind,...)
 if kind=='route-next'then return R.Capture()end
 return baseCapture(kind,...)
end
