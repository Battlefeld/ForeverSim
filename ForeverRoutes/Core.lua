-- ForeverRoutes: the leveling route of this race and class (Data/Routes.lua, made by ForeverRoutes' export-addon),
-- followed step by step from what the quest log says. No ForeverCore needed: the route is in the addon. When the
-- ForeverCore bridge plans live, its steps take the place of the stored ones (FR.SetLive).
local FR={}
ForeverRoutes=FR
local function call(fn,...)if type(fn)~='function'then return nil end;local r={pcall(fn,...)};if not r[1]then return nil end;return select(2,unpack(r))end

-- The route's key: race and class as the route files name them; the Skyborne by side.
local RACE={Scourge='undead',Undead='undead',NightElf='nightelf',Human='human',Dwarf='dwarf',Gnome='gnome',Orc='orc',Troll='troll',Tauren='tauren'}
function FR.Key()
 local _,race=call(UnitRace,'player');local _,class=call(UnitClass,'player')
 if not race or not class then return nil end
 local r=RACE[race]
 if not r and tostring(race):find('Skyborne')then
  local side=call(UnitFactionGroup,'player');r=(side=='Horde')and'skyborne-h'or'skyborne-a'
 end
 if not r then r=tostring(race):lower()end
 return r..'-'..tostring(class):lower()
end

function FR.Route()
 local key=FR.Key();local data=ForeverRoutesData and ForeverRoutesData.routes
 return key and data and data[key],key
end

local function charDB()
 ForeverRoutesCharDB=ForeverRoutesCharDB or{}
 local c=ForeverRoutesCharDB;c.skipped=c.skipped or{};c.index=c.index or 1
 return c
end

-- Quest state from the game.
local function completed(q)
 if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then return call(C_QuestLog.IsQuestFlaggedCompleted,q)==true end
 return call(IsQuestFlaggedCompleted,q)==true
end
local function onQuest(q)
 if C_QuestLog and C_QuestLog.IsOnQuest then return call(C_QuestLog.IsOnQuest,q)==true end
 return false
end
local function questDone(q)
 return C_QuestLog and C_QuestLog.IsComplete and call(C_QuestLog.IsComplete,q)==true
end
local TYPE={kill='monster',item='item',object='object',event='event',talk='monster'}
-- An objective step is done when the game says its objective is finished: the game's objective of the same kind and
-- count (the route numbers objectives its own way), or every objective when none matches.
local function objectiveDone(step)
 if questDone(step.q)then return true end
 local list=C_QuestLog and call(C_QuestLog.GetQuestObjectives,step.q)
 if type(list)~='table'or #list==0 then return false end
 local want=TYPE[step.k]
 for _,o in ipairs(list)do
  if(not want or o.type==want)and(not step.c or tonumber(o.numRequired)==step.c)then return o.finished==true end
 end
 for _,o in ipairs(list)do if not o.finished then return false end end
 return true
end

-- Whether a step is done: taken, handed in, objective finished, level reached.
function FR.Done(step)
 if not step then return true end
 if step.op=='a'then return onQuest(step.q)or completed(step.q)end
 if step.op=='t'then return completed(step.q)end
 if step.op=='w'then return completed(step.q)or(onQuest(step.q)and objectiveDone(step))end
 if step.op=='g'then return(call(UnitLevel,'player')or 0)>=(step.l or 0)end
 if step.op=='d'then
  -- a dungeon run with the group: done once the character has been inside and is out again
  local db=charDB();db.ran=db.ran or{}
  if call(IsInInstance)then db.ran[step.n or'?']=true;return false end
  return db.ran[step.n or'?']==true
 end
 return false
end

-- The steps to show: the live plan when there is one, else the stored route.
function FR.Steps()
 if FR.live then return FR.live,true end
 local r=FR.Route();return r and r.s or{},false
end

-- Moves past what is done or skipped. Returns the current step.
function FR.Advance()
 local steps,live=FR.Steps();local c=charDB()
 local i=live and 1 or c.index
 while steps[i]and(FR.Done(steps[i])or(not live and c.skipped[i]))do i=i+1 end
 if not live then c.index=i end
 FR.index=i
 return steps[i],i
end

function FR.Skip()
 local steps,live=FR.Steps();local c=charDB()
 if live then table.remove(FR.live,1)else c.skipped[c.index]=true;c.index=c.index+1 end
 return FR.Advance()
end
function FR.Back()
 local c=charDB();if FR.live then return FR.Advance()end
 local i=math.max(1,c.index-1);c.skipped[i]=nil;c.index=i
 return FR.Steps()[i],i
end
function FR.Reset()
 ForeverRoutesCharDB={};return FR.Advance()
end

-- The live plan from the ForeverCore bridge (its route-next result): steps in its own form, turned into ours.
local OP={accept='a',turnin='t',work='w',grind='g'}
function FR.SetLive(result)
 if type(result)~='table'or type(result.steps)~='table'then FR.live=nil;return end
 local out={}
 for _,s in ipairs(result.steps)do
  local at=type(s.at)=='table'and s.at or{}
  local via=type(s.via)=='string'and s.via or''
  out[#out+1]={op=OP[s.op]or s.op,q=s.quest,n=s.name,m=at.m,x=at.x,y=at.y,l=s.level,
   v=(via:find('^deathskip')and'd')or(via=='hearth'and'h')or nil,gy=via:match('^deathskip: (.+)$'),
   dm=s.viaAt and s.viaAt.m,dx=s.viaAt and s.viaAt.x,dy=s.viaAt and s.viaAt.y,live=true}
 end
 FR.live=out
end

-- Wording.
local function questName(step)
 local t=C_QuestLog and call(C_QuestLog.GetTitleForQuestID,step.q)
 return(type(t)=='string'and t~='')and t or step.n or('Quest '..tostring(step.q))
end
function FR.Text(step)
 if not step then return'Route geschafft'end
 local n=questName(step)
 if step.op=='a'then return'Annehmen: '..n end
 if step.op=='t'then return'Abgeben: '..n end
 if step.op=='g'then return string.format('Grinden bis Level %d%s',step.l or 0,step.tg and(': '..step.tg)or'')end
 if step.op=='d'then return'Dungeon mit Gruppe: '..(step.n or'?')..' (alle Quests im Log erledigen)'end
 if step.op=='w'then
  local c,tg=step.c or 1,step.tg
  if step.k=='kill'then return string.format('%s: töte %d × %s',n,c,tg or'?')end
  if step.k=='item'then return string.format('%s: sammle %d%s',n,c,tg and(' von '..tg)or'')end
  if step.k=='object'then return string.format('%s: benutze %s',n,tg or'das Objekt')end
  if step.k=='talk'then return string.format('%s: sprich mit %s',n,tg or'?')end
  return n..': Ziel erledigen'
 end
 return tostring(step.op)
end
-- What to do first to get there: a deathskip or the hearthstone.
function FR.Hint(step)
 if not step then return nil end
 if step.v=='d'then return'Death Skip: hier sterben, beim Geistheiler wiederbeleben'..(step.gy and(' ('..step.gy..')')or'')end
 if step.v=='h'then return'Ruhestein benutzen'end
 return nil
end

-- Where the arrow points: the place to die before a deathskip (until the character has died for this step), else the
-- step.
function FR.Target(step)
 if not step then return nil end
 local died=charDB().died
 if step.v=='d'and step.dx and not call(UnitIsDeadOrGhost,'player')and died~=FR.index then return step.dm,step.dx,step.dy,true end
 return step.m,step.x,step.y,false
end
-- The character died: the deathskip of the current step is done.
function FR.Died()charDB().died=FR.index end
