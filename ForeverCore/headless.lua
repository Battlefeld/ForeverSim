-- The existing, pinned FDQ planner runs outside WoW. No simulated quest completion.
local H=FC_ROOT..'/_dev/harness'
local lib=dofile(H..'/routelib.lua');lib.lazy=true
local loadErrors={}
local oldStderr=io.stderr
io.stderr={write=function(_,s)loadErrors[#loadErrors+1]=s end}
local input=FC_INPUT
local ns=lib.Load(H,FC_ROOT,input.race,input.class,input.faction)
io.stderr=oldStderr
if #loadErrors>0 then error(table.concat(loadErrors,'\n'))end
MOCK.player.level=input.level;MOCK.player.name='ForeverCore';MOCK.mapID=input.map
local function defaults(s)
 for _,key in ipairs({'active','completed','ready','inventory','bagItems','professions','spells','buffs','dungeonRuns','observedXP','taxiNodes'})do s[key]=s[key]or{}end
 s.mode=s.mode or 'balanced';s.allowUnverified=true;s.partySize=s.partySize or 1;s.instance=s.instance or {};s.freeSlots=s.freeSlots or 0
 return s
end
local state=defaults(input);for id,value in pairs(input.completionEvidence or{})do state.completed[id]=value end
C_QuestLog.IsQuestFlaggedCompleted=function(id)return state.completed[id]==true end
C_QuestLog.GetLogIndexForQuestID=function(id)return state.active[id]and 1 or 0 end
C_QuestLog.IsComplete=function(id)return state.ready[id]==true end
C_QuestLog.GetQuestObjectives=function(id)return state.questObjectives and state.questObjectives[id]or{}end
GetItemCount=function(id)return state.inventory[id]or 0 end
if C_Item then C_Item.GetItemCount=GetItemCount end
ns.Character.Read=function()return state end
ns.Character.InstallTaxiHook=function()end
local db=input.routeDB or {};db.settings=db.settings or {};db.settings.mode=state.mode
-- Settings only, never credentials or other characters' state.
ForeverDungeonQuestDB=db;ForeverRouteDB=db
local M=ns.Model
M.Init()
local chapters={}
for _,chapter in ipairs(M.chapters or {})do
 local c={id=chapter.id,name=chapter.name,lv=chapter.lv,map=chapter.map,steps={}}
 for _,step in ipairs(chapter.steps or {})do
  local copy={}
  for _,key in ipairs({'uid','id','q','title','level','kind','protected','g','o','r','map','objectives','details','unverified','noSkip','phase','userSelected','label','text','target','routeNode','count'})do copy[key]=step[key]end
  c.steps[#c.steps+1]=copy
 end
 chapters[#chapters+1]=c
end
local displayRoute={}
for key,value in pairs(state.route or{})do if key~='plan'and key~='completedSteps'then displayRoute[key]=value end end
if state.route and state.route.plan then local p=state.route.plan;displayRoute.plan={id=p.id,name=p.name,minLevel=p.minLevel,maxLevel=p.maxLevel,nextPlan=p.nextPlan}end
local known={};for id in tostring(input.knownQuests or''):gmatch('%d+')do known[tonumber(id)]=true end
local queries,seen={},{}
local function query(id)if type(id)=='number'and not seen[id]and not known[id]and(input.completionEvidence or{})[id]==nil and #queries<250 then seen[id]=true;queries[#queries+1]=id end end
if state.route and state.route.plan then for _,block in ipairs(state.route.plan.blocks or{})do for _,node in ipairs(block.nodes or{})do query(node.id);local q=ns.DataProvider.GetQuest(node.id);for _,id in ipairs(q and q.preAll or{})do query(id)end;for _,id in ipairs(q and q.preAny or{})do query(id)end end end end
table.sort(queries)
FC_OUTPUT={completionQueries=queries,route=displayRoute,dungeonState=state.dungeonState,prep=M.prep,chapters=chapters,bi=M.bi,si=M.si,routeDB={routeProgress=db.routeProgress,completedPlans=db.completedPlans,routeRecovery=db.routeRecovery,routeCheckpoints=db.routeCheckpoints},status=state.route and state.route.status or 'Route berechnet',source='FDQ '..tostring(ns.Version and ns.Version.RouteVersion or 'unbekannt'),questCount=0}
for _ in pairs(state.completed)do FC_OUTPUT.questCount=FC_OUTPUT.questCount+1 end
if FC_OUT then
 local function encode(v,seen)
  local kind=type(v)
  if kind=='nil'then return 'null'end
  if kind=='boolean'or kind=='number'then return tostring(v)end
  if kind=='string'then return '"'..v:gsub('[%z\1-\31\\"]',function(c)local b=c:byte();if c=='\\'or c=='"'then return '\\'..c end;return string.format('\\u%04x',b)end)..'"'end
  if kind~='table'then return 'null'end
  seen=seen or{};if seen[v]then return 'null'end;seen[v]=true
  local n=#v;local count=0;local arr=n>0
  for k in pairs(v)do count=count+1;if type(k)~='number'or k<1 or k>n then arr=false end end
  if count~=n then arr=false end
  local out={}
  if arr then for i=1,n do out[#out+1]=encode(v[i],seen)end
  else for k,x in pairs(v)do if type(x)~='function'and type(x)~='userdata'then out[#out+1]=encode(tostring(k),seen)..':'..encode(x,seen)end end end
  seen[v]=nil;return(arr and '['or'{')..table.concat(out,',')..(arr and ']'or'}')
 end
 local file=assert(io.open(FC_OUT,'wb'));file:write(encode(FC_OUTPUT));file:close()
end
