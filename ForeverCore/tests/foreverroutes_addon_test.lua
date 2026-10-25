-- ForeverRoutes addon (ForeverRoutes/): the route of the race and class, followed from the quest log, skip and back,
-- the deathskip arrow, the window and the live plan from the bridge.
local root=assert(arg[1]);dofile(root..'/_dev/harness/wowmock.lua');dofile(root..'/_dev/harness/gameapi.lua')
ForeverRoutesData={routes={['dwarf-warrior']={race='Dwarf',class='Warrior',target=20,hours=14,basis='plan',s={
 {op='a',q=179,n='Dwarven Outfitters',m=0,x=-6240,y=330,l=1},
 {op='w',q=179,n='Dwarven Outfitters',o=1,k='item',c=8,tg='Ragged Young Wolf',m=0,x=-6100,y=400,l=2},
 {op='t',q=179,n='Dwarven Outfitters',m=0,x=-6240,y=330,l=2},
 {op='t',q=218,n='The Stolen Journal',m=0,x=-5600,y=-480,l=3,v='d',gy='Dun Morogh',dm=0,dx=-6420,dy=820},
 {op='g',c=30,tg='Frostmane Novice',m=0,x=-6500,y=340,l=4},
}}}}
for _,file in ipairs({'Core.lua','UI.lua'})do assert(loadfile(root..'/ForeverRoutes/'..file))('ForeverRoutes',{})end
local FR=ForeverRoutes
UnitRace=function()return'Zwerg','Dwarf'end;UnitClass=function()return'Krieger','WARRIOR'end;UnitFactionGroup=function()return'Alliance'end
local level,taken,done,objs=1,{},{},{}
UnitLevel=function()return level end
C_QuestLog.IsOnQuest=function(q)return taken[q]==true end
C_QuestLog.IsQuestFlaggedCompleted=function(q)return done[q]==true end
C_QuestLog.IsComplete=function()return false end
C_QuestLog.GetQuestObjectives=function(q)return objs[q]end
C_QuestLog.GetTitleForQuestID=function(q)if q==179 then return'Zwergische Ausrüstung'end end
assert(FR.Key()=='dwarf-warrior','key '..tostring(FR.Key()))
UnitRace=function()return'Untoter','Scourge'end;assert(FR.Key()=='undead-warrior','undead key')
UnitRace=function()return'Himmelsgeborener','Skyborne'end;UnitFactionGroup=function()return'Horde'end;assert(FR.Key()=='skyborne-h-warrior','skyborne key')
UnitRace=function()return'Zwerg','Dwarf'end;UnitFactionGroup=function()return'Alliance'end
-- the window on login, the first step with the localized quest name and the arrow on it
local pinned
C_Map.GetMapPosFromWorldPos=function(m,v)return 1426,CreateVector2D(.3,.7)end
C_Map.SetUserWaypoint=function(p)pinned=p end;UiMapPoint={CreateFromCoordinates=function(map,x,y)return{map=map,x=x,y=y}end}
MOCK.Fire('PLAYER_LOGIN')
assert(_G.ForeverRoutesFrame and _G.ForeverRoutesFrame:IsShown(),'window not shown')
assert(FR.index==1 and FR.Text(FR.Steps()[1])=='Annehmen: Zwergische Ausrüstung','first step')
assert(pinned and pinned.map==1426,'arrow not set')
-- taking the quest moves on; the objective counts by kind and count
taken[179]=true;objs[179]={{type='item',numFulfilled=3,numRequired=8,finished=false}};MOCK.Fire('QUEST_ACCEPTED',179)
assert(FR.index==2,'accept not followed: '..FR.index)
assert(FR.Text(FR.Steps()[2])=='Zwergische Ausrüstung: sammle 8 von Ragged Young Wolf','work text '..FR.Text(FR.Steps()[2]))
objs[179]={{type='item',numFulfilled=8,numRequired=8,finished=true}};MOCK.Fire('QUEST_LOG_UPDATE');assert(FR.index==3,'objective not followed')
taken[179]=nil;done[179]=true;MOCK.Fire('QUEST_TURNED_IN',179);assert(FR.index==4,'turn-in not followed')
-- a deathskip: the arrow first leads to the place to die, after the death to the step
pinned=nil;C_Map.GetMapPosFromWorldPos=function(m,v)return 1426,CreateVector2D(v.x==-6420 and .1 or .9,.5)end;FR.pinned=nil;FR.Refresh()
assert(pinned and pinned.x==.1,'arrow must lead to the place to die')
assert(FR.Hint(FR.Steps()[4]):find('Death Skip',1,true),'deathskip hint')
MOCK.Fire('PLAYER_DEAD');MOCK.Fire('PLAYER_ALIVE');assert(pinned.x==.9,'after the death the arrow must lead to the step')
-- skip and back
FR.Skip();assert(FR.index==5,'skip');FR.Back();FR.Refresh();assert(FR.index==4,'back')
-- grinding is done at the level
done[218]=true;level=4;MOCK.Fire('PLAYER_LEVEL_UP');assert(FR.index==6 and FR.Text(FR.Steps()[6])=='Route geschafft','end of route')
assert(ForeverRoutesCharDB.index==6,'progress not kept')
-- the live plan from the bridge takes over
FR.SetLive({steps={{op='work',quest=790,name='Sarkoth: kill 10',at={m=1,x=-500,y=-4200},level=5},{op='turnin',quest=790,name='Sarkoth',via='deathskip: Razor Hill',viaAt={m=1,x=-10,y=-20}}}})
local s,i=FR.Advance();assert(i==1 and s.q==790 and s.op=='w','live step')
assert(FR.live[2].v=='d'and FR.live[2].gy=='Razor Hill'and FR.live[2].dx==-10,'live deathskip')
FR.SetLive(nil);assert(not FR.live,'live plan not cleared')
-- slash command toggles the window
SlashCmdList.FOREVERROUTES('');assert(not _G.ForeverRoutesFrame:IsShown(),'/fr must hide');SlashCmdList.FOREVERROUTES('');assert(_G.ForeverRoutesFrame:IsShown(),'/fr must show')
-- no route for this character: said in the window
UnitClass=function()return'Hexer','WARLOCK'end;FR.Refresh()
for _,e in ipairs(MOCK.errors)do error(e.kind..': '..tostring(e.msg))end
io.write('foreverroutes addon test ok\n')
