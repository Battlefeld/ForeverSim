-- Navigation uses world yards (north, west), never percentages from another map.
local FR=ForeverRoutes
local call=FR.Call
function FR.ClearWaypoint()
 if FR.tomtom and TomTom then call(TomTom.RemoveWaypoint,TomTom,FR.tomtom)end
 FR.tomtom=nil
 if FR.ownsPin and C_Map then call(C_Map.ClearUserWaypoint)end
 FR.ownsPin=nil;FR.pinned=nil
end
local function valid(map,pos)
 return map and pos and type(pos.x)=='number'and type(pos.y)=='number'and pos.x>=0 and pos.x<=1 and pos.y>=0 and pos.y<=1
end
function FR.Waypoint(m,x,y,title)
 if not(C_Map and CreateVector2D and type(x)=='number'and type(y)=='number')then return false end
 local here=call(C_Map.GetBestMapForUnit,'player')
 local map,pos=call(C_Map.GetMapPosFromWorldPos,m,CreateVector2D(x,y),here)
 if not valid(map,pos)then map,pos=call(C_Map.GetMapPosFromWorldPos,m,CreateVector2D(x,y))end
 if not valid(map,pos)then return false end
 if TomTom and TomTom.AddWaypoint then
  FR.tomtom=call(TomTom.AddWaypoint,TomTom,map,pos.x,pos.y,{title=title,persistent=false,minimap=true,world=true})
  if FR.tomtom then return true end
 end
 if C_Map.SetUserWaypoint and UiMapPoint then
  local point=call(UiMapPoint.CreateFromCoordinates,map,pos.x,pos.y)
  if point then
   local ok=pcall(C_Map.SetUserWaypoint,point)
   if ok then FR.ownsPin=true;if C_SuperTrack then call(C_SuperTrack.SetSuperTrackedUserWaypoint,true)end;return true end
  end
 end
 return false
end
function FR.Navigation(step)
 if not step or FR.Paused(step)or call(IsInInstance)==true then return nil end
 local m,x,y,dying=FR.Target(step)
 if type(m)~='number'or type(x)~='number'or type(y)~='number'then return nil end
 local px,py,_,pm=call(UnitPosition,'player')
 local nav={m=m,x=x,y=y,dying=dying,key=FR.StepKey(step)..(dying and':die'or'')}
 if pm==m and type(px)=='number'and type(py)=='number'then
  local dx,dy=x-px,y-py
  nav.distance=math.sqrt(dx*dx+dy*dy);nav.arrived=nav.distance<=(step.radius or 12)
  local facing=call(GetPlayerFacing)
  if type(facing)=='number'and math.atan2 then nav.rotation=math.atan2(dy,dx)-facing end
 end
 return nav
end
function FR.UpdateWaypoint(step,nav)
 if not nav then if FR.pinned or FR.ownsPin or FR.tomtom then FR.ClearWaypoint()end;return end
 if FR.pinned==nav.key then return end
 FR.ClearWaypoint()
 if FR.Waypoint(nav.m,nav.x,nav.y,nav.dying and'Death Skip: hier sterben'or FR.Text(step))then FR.pinned=nav.key end
end
