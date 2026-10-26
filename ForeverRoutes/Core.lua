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

local function charDB()
 ForeverRoutesCharDB=ForeverRoutesCharDB or{}
 local c=ForeverRoutesCharDB;c.skipped=c.skipped or{};c.index=c.index or 1
 return c
end

-- The route of this character: "Solo mit Dungeon" (with dungeon runs) when chosen and there is one, else "Solo ohne
-- Dungeon".
function FR.Route()
 local key=FR.Key();local data=ForeverRoutesData and ForeverRoutesData.routes
 if not key or not data then return nil,key end
 local c=charDB()
 if(c.dungeons or c.group)and data[key..'-dungeons']then return data[key..'-dungeons'],key..'-dungeons'end
 return data[key],key
end

-- With or without dungeons: the other route starts over from its first step that is not done yet.
function FR.SetDungeons(on)
 local c=charDB();c.dungeons=on and true or nil;c.group=nil;c.index=1;c.skipped={};FR.pinned=nil
 return FR.Advance()
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
-- count (the route numbers objectives its own way), the one naming the step's target first when two are alike, or
-- every objective when none matches.
local function objectiveDone(step)
 if questDone(step.q)then return true end
 local list=C_QuestLog and call(C_QuestLog.GetQuestObjectives,step.q)
 if type(list)~='table'or #list==0 then return false end
 local want=TYPE[step.k]
 local alike={}
 for _,o in ipairs(list)do
  if(not want or o.type==want)and(not step.c or tonumber(o.numRequired)==step.c)then alike[#alike+1]=o end
 end
 if #alike>1 and type(step.tg)=='string'and step.tg~=''then
  for _,o in ipairs(alike)do
   if type(o.text)=='string'and o.text:lower():find(step.tg:lower(),1,true)then return o.finished==true end
  end
 end
 if alike[1]then return alike[1].finished==true end
 for _,o in ipairs(list)do if not o.finished then return false end end
 return true
end

-- The instance the character is in (its map id), nil outside.
local function instanceID()
 if call(IsInInstance)~=true then return nil end
 local r={call(GetInstanceInfo)}
 return r[8]or 0
end
-- Whether the character is inside the dungeon of a dungeon step (any dungeon when the step does not name one).
local function inDungeonOf(step)
 local id=instanceID()
 return id~=nil and(not step.ii or step.ii==id)
end

-- A step's identity, the same for the same step in the stored route and in a new live plan.
function FR.StepKey(step)
 if not step then return''end
 return table.concat({tostring(step.op),tostring(step.q or''),tostring(step.o or''),tostring(step.n or''),tostring(step.x or''),tostring(step.y or'')},':')
end

-- Whether a step is done: taken, handed in, objective finished, level reached.
function FR.Done(step)
 if not step then return true end
 if step.op=='a'then return onQuest(step.q)or completed(step.q)end
 if step.op=='t'then return completed(step.q)end
 if step.op=='w'then return completed(step.q)or(onQuest(step.q)and objectiveDone(step))end
 if step.op=='g'then return(call(UnitLevel,'player')or 0)>=(step.l or 0)end
 if step.op=='z'then return(call(GetItemCount,step.it)or 0)>0 or call(IsEquippedItem,step.it)==true end
 if step.op=='p'then return FR.HasProfessions()end
 if step.op=='d'then
  -- a dungeon run: done once the character has been inside that dungeon and is out again
  local db=charDB();db.ran=db.ran or{}
  if inDungeonOf(step)then db.ran[step.n or'?']=true;return false end
  return db.ran[step.n or'?']==true
 end
 return false
end

-- Skinning and Leatherworking learned (by the skill lines, English or German).
local SKILL={skin={Skinning=true,['Kürschnerei']=true},leather={Leatherworking=true,Lederverarbeitung=true}}
function FR.HasProfessions()
 local n=call(GetNumSkillLines)or 0;local skin,leather=false,false
 for i=1,n do
  local name=call(GetSkillLineInfo,i)
  if SKILL.skin[name]then skin=true end
  if SKILL.leather[name]then leather=true end
 end
 return skin and leather
end

-- The camp, coupled to the camp buff (an hour; all camp objects share that cooldown). The buff is found among the
-- character's auras by its name (CAMP_AURAS); without it the time since the last camp (/fr lager) stands in.
-- 10 minutes before it runs out: is there leather for another tent? If not, "farm leather" beside the route.
-- 5 minutes before: the buff ends soon, with what the camp still lacks. Run out: make camp.
FR.CAMP_AURAS={'Camp','Lager','Zelt','Tent'}
FR.LIGHT_LEATHER=2318;FR.TENT_LEATHER=5            -- a Camp Tent: 5 Light Leather (two tents per craft)
FR.TENT_NAMES={'Camp Tent','Lagerzelt'}
FR.FIRE={{4470,1},{4471,1}}                        -- Basic Campfire: Simple Wood, Flint and Tinder (as in Classic)
local function campAura()
 local now=call(GetTime)or 0
 for _,fn in ipairs({UnitBuff,UnitDebuff})do
  for i=1,40 do
   local name,_,_,_,duration,expires=call(fn,'player',i)
   if not name then break end
   for _,k in ipairs(FR.CAMP_AURAS)do
    if tostring(name):find(k,1,true)and(duration or 0)>0 and expires then return expires-now end
   end
  end
 end
 return nil
end
-- Seconds the camp buff has left (0: none or run out); nil before the camps start.
function FR.CampLeft()
 local c=charDB()
 if not c.campLevel or(call(UnitLevel,'player')or 0)<c.campLevel then return nil end
 local left=campAura()
 if left then return math.max(0,left)end
 return math.max(0,3600-((call(time)or 0)-(c.camp or -1e9)))
end
-- What a camp needs that the bags lack: tent (or leather for one), fire.
function FR.CampMaterials()
 local tents=0
 for _,n in ipairs(FR.TENT_NAMES)do tents=tents+(call(GetItemCount,n)or 0)end
 local leather=call(GetItemCount,FR.LIGHT_LEATHER)or 0
 local fire=true
 for _,r in ipairs(FR.FIRE)do if(call(GetItemCount,r[1])or 0)<r[2]then fire=false end end
 return{tent=tents>0 or leather>=FR.TENT_LEATHER,leather=leather,fire=fire}
end
-- The camp's word for the window: a hint for the route line and a task beside the route (nil when nothing).
function FR.CampStatus()
 local left=FR.CampLeft();if not left then return nil,nil end
 local m=FR.CampMaterials()
 local farm=not m.tent and string.format('Nebenbei: Leder farmen – Wildtiere kürschnern (%d/%d Leichtes Leder für ein Lagerzelt)',m.leather,FR.TENT_LEATHER)or nil
 if left<=0 then
  return'Lager aufschlagen: Lagerfeuer, Lagerzelt, 1 Minute rasten (/fr lager)',farm
 end
 if left<=300 then
  return string.format('Lager-Buff endet in %d Min – Zelt: %s, Lagerfeuer: %s',math.ceil(left/60),m.tent and'bereit'or'fehlt',m.fire and'bereit'or'fehlt'),farm
 end
 if left<=600 then return nil,farm end
 return nil,nil
end
function FR.Camped()local c=charDB();c.camp=call(time)or 0 end

-- Paused: the character is inside a dungeon the route does not run now (a second run). Nothing is
-- blocked: the route waits and goes on from its first open step once the character is out (steps done meanwhile,
-- levels reached meanwhile, are passed by themselves).
function FR.Paused(step)
 return instanceID()~=nil and not(step and step.op=='d'and inDungeonOf(step))
end

-- Options (route.o): goals the route leaves out that can be switched on, each with its steps and for each the step
-- of the route it comes after (af, 0 before the first). On, its steps go in there; the route's grind steps are then
-- done earlier by themselves (a grind step is done at its level).
function FR.Options()
 local r=FR.Route();return r and r.o or{}
end
local function optionOn(o)local c=charDB();return c.opts and c.opts[o.id]==true end
-- How many options are switched on.
function FR.OptionsOn()
 local n=0;for _,o in ipairs(FR.Options())do if optionOn(o)then n=n+1 end end;return n
end
-- An option by its number in the list or its id; nil when there is none.
function FR.Option(n)
 n=tonumber(n);if not n then return nil end
 local list=FR.Options()
 if list[n]then return list[n]end
 for _,o in ipairs(list)do if o.id==n then return o end end
 return nil
end
-- Switches an option on or off (nil: the other way); the route goes on from its first step not done yet.
function FR.SetOption(n,on)
 local o=FR.Option(n);if not o then return nil end
 local c=charDB();c.opts=c.opts or{}
 if on==nil then on=not optionOn(o)end
 c.opts[o.id]=on and true or nil;c.index=1;c.skipped={};FR.pinned=nil
 FR.Advance()
 return o,on
end
-- The stored route with the options switched on in it (kept until the route or the options change).
local merged
local function withOptions(r,key)
 local on={}
 for _,o in ipairs(r.o or{})do if optionOn(o)then on[#on+1]=o end end
 if #on==0 then return r.s or{}end
 local ids={};for _,o in ipairs(on)do ids[#ids+1]=o.id end
 local tag=key..':'..table.concat(ids,',')
 if merged and merged.tag==tag then return merged.s end
 local at={}
 for _,o in ipairs(on)do
  for _,st in ipairs(o.s or{})do
   st.opt=o.n;local a=st.af or 0;at[a]=at[a]or{};local l=at[a];l[#l+1]=st
  end
 end
 local out={}
 for i=0,#(r.s or{})do
  if i>0 then out[#out+1]=r.s[i]end
  for _,st in ipairs(at[i]or{})do out[#out+1]=st end
 end
 merged={tag=tag,s=out}
 return out
end

-- The steps to show: the live plan when there is one, else the stored route (with the options switched on).
function FR.Steps()
 if FR.live then return FR.live,true end
 local r,key=FR.Route();return r and withOptions(r,key)or{},false
end

-- Moves past what is done or skipped. Returns the current step.
function FR.Advance()
 local steps,live=FR.Steps();local c=charDB()
 local i=live and 1 or c.index
 while steps[i]and(FR.Done(steps[i])or(not live and c.skipped[i]))do
  if(steps[i].op=='p'or steps[i].op=='z')and steps[i].cl then c.campLevel=steps[i].cl end -- the professions: camps from then on
  i=i+1
 end
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
 local c=charDB()
 ForeverRoutesCharDB={dungeons=c.dungeons,opts=c.opts};return FR.Advance()
end

-- The live plan from the ForeverCore bridge (its route-next result): steps in its own form, turned into ours.
local OP={accept='a',turnin='t',work='w',grind='g',dungeon='d'}
-- A live dungeon step names the dungeon only: its instance and the quests taken inside come from the stored routes.
local function storedDungeon(name)
 local data=ForeverRoutesData and ForeverRoutesData.routes
 local r=FR.Route()
 for _,route in ipairs({r or{},data and data[(FR.Key()or'')..'-dungeons']or{}})do
  for _,st in ipairs(route.s or{})do if st.op=='d'and st.n==name then return st end end
 end
 return nil
end
function FR.SetLive(result)
 if type(result)~='table'or type(result.steps)~='table'then FR.live=nil;return end
 local out={}
 for _,s in ipairs(result.steps)do
  local at=type(s.at)=='table'and s.at or{}
  local via=type(s.via)=='string'and s.via or''
  local name=type(s.name)=='string'and s.name:gsub(' %(dungeon run%)$','')or s.name
  out[#out+1]={op=OP[s.op]or s.op,q=s.quest,n=name,m=at.m,x=at.x,y=at.y,l=s.level,
   v=(via:find('^deathskip')and'd')or(via=='hearth'and'h')or(via=='teleport'and't')or nil,gy=via:match('^deathskip: (.+)$'),
   dm=s.viaAt and s.viaAt.m,dx=s.viaAt and s.viaAt.x,dy=s.viaAt and s.viaAt.y,live=true}
  local st=out[#out]
  if st.op=='d'then local known=storedDungeon(st.n);if known then st.ii,st.qi=known.ii,known.qi end end
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
 if step.op=='p'then return'Berufe: Kürschnern, Kochkunst und Lederverarbeitung lernen – Wildtiere kürschnern, Lederverarbeitung mit dem Leder auf 20 (Lagerzelt)'end
 if step.op=='z'then
  local t="Zauberstäbe: Verzauberkunst lernen, Novice's Practice Wand herstellen (Einfaches Holz, Mote of Magic vom Händler), mit Übungszauberstäben auf 10, Geringe Magische Essenz im Auktionshaus, Geringen Zauberstab herstellen"
  if(step.l or 0)<5 then t=t..' – den Übungszauberstab tragen, ab Level 5 den Geringen'end
  if step.cl then t=t..'. Danach Verzauberkunst verlernen; Kürschnern, Kochkunst und Lederverarbeitung lernen (Lagerzelt)'end
  return t
 end
 if step.op=='g'then return string.format('Grinden bis Level %d%s',step.l or 0,step.tg and(': '..step.tg)or'')end
 if step.op=='d'then
  local t='Dungeon laufen: '..(step.n or'?')..' (Gruppe suchen, alle Quests im Log erledigen)'
  if type(step.qi)=='table'and #step.qi>0 then t=t..' – im Dungeon annehmen: '..table.concat(step.qi,', ')end
  return t
 end
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
-- What to do first to get there: a deathskip, the hearthstone or a druid's teleport to Moonglade.
function FR.Hint(step)
 if not step then return nil end
 local h=FR.TravelHint(step)
 if step.opt then h='Option: '..step.opt..(h and(' · '..h)or'')end
 local camp=FR.CampStatus()
 if camp then h=(h and(h..' · ')or'')..camp end
 return h
end
function FR.TravelHint(step)
 if step.v=='d'then return'Death Skip: hier sterben, beim Geistheiler wiederbeleben'..(step.gy and(' ('..step.gy..')')or'')end
 if step.v=='h'then return'Ruhestein benutzen'end
 if step.v=='t'then return'Teleportieren: Mondlichtung'end
 return nil
end

-- Where the arrow points: the place to die before a deathskip (until the character has died for this step), else the
-- step.
function FR.Target(step)
 if not step then return nil end
 local died=charDB().died
 if step.v=='d'and step.dx and not call(UnitIsDeadOrGhost,'player')and died~=FR.StepKey(step)then return step.dm,step.dx,step.dy,true end
 return step.m,step.x,step.y,false
end
-- The character died: the deathskip of the current step is done.
function FR.Died()
 local steps=FR.Steps()
 charDB().died=FR.StepKey(steps[FR.index or 1])
end
