-- Route while playing (ForeverCoreBridge/Route.lua): what is read from the game, the job, the window, the waypoint
-- and the automatic replanning after quest events.
local root=assert(arg[1]);dofile(root..'/_dev/harness/wowmock.lua');dofile(root..'/_dev/harness/gameapi.lua')
for _,file in ipairs({'Protocol.lua','Bridge.lua','Adapters.lua','Route.lua'})do assert(loadfile(root..'/ForeverCoreBridge/'..file))('ForeverCoreBridge',{})end
local C=ForeverCoreClient;local R=C.Route
-- a level 12 orc in Durotar with two quests in the log, one finished
UnitPosition=function(u)if u=='player'then return -607.3,-4251.5,0,1 end end
UnitLevel=function()return 12 end;UnitXP=function()return 3400 end
UnitClass=function()return'Hexenmeister','WARLOCK'end;UnitRace=function()return'Orc','Orc'end
C_QuestLog=C_QuestLog or{}
C_QuestLog.GetAllCompletedQuestIDs=function()return{788,789,4641}end
local progress=3
C_QuestLog.GetQuestObjectives=function(id)if id==790 then return{{type='monster',numFulfilled=progress,numRequired=10,finished=false}}end;return{{type='item',numFulfilled=6,numRequired=6,finished=true}}end
GetNumQuestLogEntries=function()return 3 end
GetQuestLogTitle=function(i)
 if i==1 then return'Durotar',nil,nil,true end
 if i==2 then return'Sarkoth',3,nil,false,nil,nil,nil,790 end
 return'Vile Familiars',4,nil,false,nil,1,nil,792
end
GetItemCooldown=function(id)if id==6948 then return GetTime()-600,3600 end;return 0,0 end
local s=R.Capture()
assert(s.race=='Orc'and s.class=='WARLOCK'and s.faction~=nil,'identity')
assert(s.live.level==12 and s.live.xp==3400,'level/xp')
assert(s.live.pos.m==1 and s.live.pos.x==-607.3 and s.live.pos.y==-4251.5,'position')
assert(#s.live.completed==3,'completed quests')
assert(#s.live.active==2 and s.live.active[1].id==790 and s.live.active[1].objectives[1].have==3 and s.live.active[1].objectives[1].type=='monster','log progress')
assert(s.live.active[2].ready==true,'finished quest must be ready')
assert(math.abs(s.live.hearthIn-3000)<1,'hearthstone cooldown')
-- the wand, the professions and the options switched on in ForeverRoutes go along
GetItemCount=function(id)return id==11287 and 1 or 0 end;ForeverRoutes={HasProfessions=function()return true end}
ForeverRoutesCharDB={opts={[79976]=true,[1503]=false}}
local s2=R.Capture();assert(s2.live.wand==true and s2.live.prof==true,'wand and professions')
assert(s2.options and #s2.options==1 and s2.options[1]==79976,'options switched on')
ForeverRoutes=nil;ForeverRoutesCharDB=nil;assert(R.Capture().options==nil and R.Capture().live.prof==nil,'without ForeverRoutes nothing about them')
-- in an instance there is no position, the PC refuses to plan
UnitPosition=function(u)if u=='player'then return 10,10,0,33 end end;assert(R.Capture().live.pos==nil,'instance position sent')
UnitPosition=function(u)if u=='player'then return -607.3,-4251.5,0,1 end end
assert(C.Capture('route-next').live.level==12,'Capture must route route-next to Route.lua')
-- wording
assert(R.Text({op='work',name='Sarkoth: kill 10 × Mottled Boar'})=='Sarkoth: toete 10 × Mottled Boar','work text')
assert(R.Text({op='accept',name='Sarkoth'})=='Annehmen: Sarkoth'and R.Text({op='grind',name='12 × Boar'})=='Grinden: 12 × Boar','texts')
-- one request: the job, the reply, the window and the waypoint
MOCK.Fire('PLAYER_LOGIN');C.queue={};C.needPing=false
local pinned
C_Map=C_Map or{};C_Map.GetBestMapForUnit=function()return 1411 end
C_Map.GetMapPosFromWorldPos=function(m,v,ui)return ui or 1411,CreateVector2D(.45,.62)end
C_Map.SetUserWaypoint=function(p)pinned=p end;UiMapPoint={CreateFromCoordinates=function(map,x,y)return{map=map,x=x,y=y}end}
assert(R.Request(true),'route-next not queued');assert(not R.Request(false),'second route-next queued')
MOCK.Advance(.3,.05);local p=C.pending;assert(p and p.kind=='route-next','route-next not sent')
assert(p.message:find('"pos":{"m":1',1,true)and p.message:find('"horizon":3600',1,true),'live state or horizon missing in the job')
assert(not p.message:find('"sim"',1,true),'SIM snapshot sent with the route')
C_AddOns.LoadAddOn=function()ForeverCore_Reply={schema=3,session=C.session,sequence=p.sequence,revision=p.revision,kind='route-next',status='ok',result={level=12,toLevel=13,seconds=3700,
 steps={{op='work',quest=790,name='Sarkoth: kill 10 × Mottled Boar',time=300,at={m=1,x=-500,y=-4200}},{op='turnin',quest=790,name='Sarkoth',time=420}}}};return true end
MOCK.Advance(2.1,.05);assert(not C.pending,'reply not taken')
assert(R.last and R.last.toLevel==13,'route not stored')
assert(_G.ForeverCoreRouteFrame and _G.ForeverCoreRouteFrame:IsShown(),'window not shown')
assert(pinned and pinned.map==1411 and pinned.x==.45,'waypoint not set on the first step')
-- automatic replanning only when switched on, after a quest change, once per burst
C.queue={};ForeverCoreBridgeDB.routeNext=nil
MOCK.Fire('QUEST_TURNED_IN',790);MOCK.Advance(20,.5);assert(#C.queue==0 and not(C.pending and C.pending.kind=='route-next'),'replanned while switched off')
ForeverCoreBridgeDB.routeNext=true
MOCK.Fire('QUEST_ACCEPTED',791);MOCK.Fire('QUEST_LOG_UPDATE');MOCK.Fire('QUEST_LOG_UPDATE')
MOCK.Advance(20,.5)
local n=0;for _,job in ipairs(C.queue)do if job.kind=='route-next'then n=n+1 end end;if C.pending and C.pending.kind=='route-next'then n=n+1 end
assert(n==1,'a burst of quest events must give exactly one route request, got '..n)
-- objective progress counts, an unchanged log does not
C.queue={};C.pending=nil;R.scheduled=false
MOCK.Fire('QUEST_LOG_UPDATE');MOCK.Advance(20,.5);assert(#C.queue==0 and not C.pending,'unchanged quest log replanned')
progress=4;MOCK.Fire('QUEST_LOG_UPDATE');MOCK.Advance(20,.5);assert(#C.queue==1 or(C.pending and C.pending.kind=='route-next'),'objective progress did not replan')
-- flight masters are remembered per character by the NPC id of the flight master
UnitGUID=function(u)if u=='npc'then return'Creature-0-1-1-1-3310-0000'end;return'Player-1-0000001'end
MOCK.Fire('TAXIMAP_OPENED');assert(R.Capture().live.flightMasters[1]==3310,'flight master not remembered')
for _,e in ipairs(MOCK.errors)do error(e.kind..': '..tostring(e.msg))end
io.write('route next test ok\n')
