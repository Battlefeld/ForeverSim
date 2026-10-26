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
assert(FR.Hint({op='a',v='t'})=='Teleportieren: Mondlichtung','teleport hint')
FR.SetLive({steps={{op='accept',quest=5,name='X',at={m=1,x=1,y=1},via='teleport'}}});assert(FR.live[1].v=='t','live teleport');FR.SetLive(nil)
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
-- "Solo mit Dungeon" when chosen; back to "Solo ohne Dungeon"
ForeverRoutesData.routes['dwarf-warrior-dungeons']={race='Dwarf',class='Warrior',target=40,s={{op='d',n='The Deadmines',m=0,x=-11073,y=1529,l=20}}}
UnitClass=function()return'Krieger','WARRIOR'end
SlashCmdList.FOREVERROUTES('dungeon');local r,k=FR.Route();assert(k=='dwarf-warrior-dungeons'and FR.Steps()[1].op=='d','route with dungeons not chosen')
SlashCmdList.FOREVERROUTES('solo');r,k=FR.Route();assert(k=='dwarf-warrior','solo route not back')
-- a dungeon step: done once the character was inside and is out again
local dstep={op='d',n='The Deadmines',m=0,x=-11073,y=1529,l=20}
assert(FR.Text(dstep)=='Dungeon laufen: The Deadmines (Gruppe suchen, alle Quests im Log erledigen)','dungeon text')
assert(FR.Text({op='d',n='Ragefire Chasm',qi={'Returning the Lost Satchel'}})=='Dungeon laufen: Ragefire Chasm (Gruppe suchen, alle Quests im Log erledigen) – im Dungeon annehmen: Returning the Lost Satchel','quests taken inside')
assert(not FR.Done(dstep),'dungeon not run yet');IsInInstance=function()return true,'party'end
assert(not FR.Done(dstep),'still inside');IsInInstance=function()return false,'none'end;assert(FR.Done(dstep),'run not followed')
-- a second run of a dungeon: the route pauses inside and goes on outside, the arrow stays put
pinned=nil;FR.pinned=nil;IsInInstance=function()return true,'party'end;FR.Refresh()
assert(FR.Paused(FR.Steps()[FR.index])and _G.ForeverRoutesFrame and pinned==nil,'route must pause inside a dungeon')
local cleared=false;C_Map.ClearUserWaypoint=function()cleared=true end;FR.pinned='x';FR.Refresh();assert(cleared and FR.pinned==nil,'arrow must go away inside a dungeon')
IsInInstance=function()return false,'none'end;FR.Refresh();assert(not FR.Paused(FR.Steps()[FR.index]),'route must go on outside')
-- the arrow follows a new live plan; a second live deathskip still leads to its place to die
pinned=nil;FR.pinned=nil
C_Map.GetMapPosFromWorldPos=function(m,v)return 1411,CreateVector2D((v.x+1000)/10000,.5)end
FR.SetLive({steps={{op='turnin',quest=1,name='A',at={m=1,x=100,y=0},via='deathskip: X',viaAt={m=1,x=200,y=0}}}});FR.Refresh()
assert(pinned and math.abs(pinned.x-.12)<1e-6,'live arrow must lead to the first place to die')
MOCK.Fire('PLAYER_DEAD');MOCK.Fire('PLAYER_ALIVE');assert(math.abs(pinned.x-.11)<1e-6,'after the death the arrow must lead to the step')
FR.SetLive({steps={{op='turnin',quest=2,name='B',at={m=1,x=300,y=0},via='deathskip: Y',viaAt={m=1,x=400,y=0}}}});FR.Refresh()
assert(math.abs(pinned.x-.14)<1e-6,'a second live deathskip must lead to its place to die, got '..pinned.x)
FR.SetLive({steps={{op='accept',quest=3,name='C',at={m=1,x=500,y=0}}}});FR.Refresh()
assert(math.abs(pinned.x-.15)<1e-6,'the arrow must follow a new live plan')
FR.SetLive(nil)
-- a dungeon step is done in its own dungeon only
local rfc={op='d',n='Ragefire Chasm',ii=389,m=1,x=1815,y=-4418,l=13}
GetInstanceInfo=function()return'Wailing Caverns','party',1,'',5,0,false,43 end;IsInInstance=function()return true,'party'end
assert(not FR.Done(rfc)and FR.Paused(rfc),'another dungeon must not finish the run, the route pauses there')
GetInstanceInfo=function()return'Ragefire Chasm','party',1,'',5,0,false,389 end
assert(not FR.Done(rfc)and not FR.Paused(rfc),'inside its own dungeon the run goes on')
IsInInstance=function()return false,'none'end;assert(FR.Done(rfc),'out of its dungeon the run is done')
-- a live dungeon step takes its instance and the quests taken inside from the stored route
ForeverRoutesData.routes['dwarf-warrior-dungeons'].s[2]={op='d',n='Ragefire Chasm',ii=389,qi={'Returning the Lost Satchel'},m=1,x=1815,y=-4418,l=13}
ForeverRoutesCharDB.dungeons=true
FR.SetLive({steps={{op='dungeon',name='Ragefire Chasm (dungeon run)',at={m=1,x=1815,y=-4418},level=13}}})
assert(FR.live[1].n=='Ragefire Chasm'and FR.live[1].ii==389 and FR.live[1].qi[1]=='Returning the Lost Satchel','live dungeon step without its instance')
FR.SetLive(nil);ForeverRoutesCharDB.dungeons=nil
-- two alike objectives: the one naming the step's target counts
objs[500]={{type='monster',text='Kobold Vermin slain: 10/10',numFulfilled=10,numRequired=10,finished=true},{type='monster',text='Kobold Worker slain: 3/10',numFulfilled=3,numRequired=10,finished=false}}
taken[500]=true
assert(not FR.Done({op='w',q=500,o=2,k='kill',c=10,tg='Kobold Worker'}),'the other objective must not finish the step')
assert(FR.Done({op='w',q=500,o=1,k='kill',c=10,tg='Kobold Vermin'}),'its own objective finishes the step')
taken[500]=nil
-- reset keeps the choice of the route with dungeons
ForeverRoutesCharDB.dungeons=true;FR.Reset();assert(ForeverRoutesCharDB.dungeons==true,'reset must keep the route with dungeons')
ForeverRoutesCharDB.dungeons=nil
-- slash command toggles the window
SlashCmdList.FOREVERROUTES('');assert(not _G.ForeverRoutesFrame:IsShown(),'/fr must hide');SlashCmdList.FOREVERROUTES('');assert(_G.ForeverRoutesFrame:IsShown(),'/fr must show')
-- options: off the route is as it is; on, their steps go in after theirs, the route goes on from its first open step
local base=ForeverRoutesData.routes['dwarf-warrior']
base.o={{id=79976,n='Gemütlicher Schlafsack',tier='recommended',min=83,l=18,s={
 {af=0,op='a',q=79008,n='... and that note you found',m=0,x=-10581,y=1710,l=14},
 {af=3,op='t',q=79008,n='... and that note you found',m=1,x=-3379,y=-2075,l=15}}},
 {id=1919,n='Report to Jennea',tier='optional',min=2,l=16,s={{af=5,op='a',q=1919,n='Report to Jennea',m=0,x=1,y=1,l=16}}}}
local n0=#FR.Steps();assert(n0==5 and FR.OptionsOn()==0,'options must be off at first')
local o,on=FR.SetOption(1);assert(o.id==79976 and on,'option 1 not on')
local st=FR.Steps();assert(#st==7 and st[1].q==79008 and st[2].q==179 and st[5].q==79008 and st[5].op=='t','option steps not in place')
assert(FR.Hint(st[1])=='Option: Gemütlicher Schlafsack','option hint '..tostring(FR.Hint(st[1])))
assert(FR.Hint(st[5]):find('Death Skip',1,true)==nil and FR.Hint(base.s[4]):find('Death Skip',1,true),'travel hints stay')
SlashCmdList.FOREVERROUTES('option 1919');assert(#FR.Steps()==8 and FR.Steps()[8].q==1919 and FR.OptionsOn()==2,'option by id')
assert(ForeverRoutesCharDB.index>=1 and next(ForeverRoutesCharDB.skipped)==nil,'switching starts over from the first open step')
local said={};local p0=print;print=function(t)said[#said+1]=t end;SlashCmdList.FOREVERROUTES('optionen');print=p0
assert(said[1]=='1. Gemütlicher Schlafsack (empfohlen, +83 Min, fertig mit Level 18): an','options list '..tostring(said[1]))
FR.Reset();assert(FR.OptionsOn()==2,'reset must keep the options')
FR.SetOption(1,false);FR.SetOption(2,false);assert(#FR.Steps()==5 and FR.OptionsOn()==0,'options off again')
assert(FR.SetOption(9)==nil,'no such option')
base.o=nil
-- a caster's wand: done once it is in the bags or worn
local zs={op='z',it=11287,m=0,x=1,y=1,l=4};local count=0
GetItemCount=function(id)return id==11287 and count or 0 end;IsEquippedItem=function()return false end
assert(not FR.Done(zs)and FR.Text(zs):find("Novice's Practice Wand",1,true)and FR.Text(zs):find('ab Level 5',1,true),'wand step')
count=1;assert(FR.Done(zs),'wand in the bags');assert(not FR.Text({op='z',it=11287,l=5}):find('ab Level 5',1,true),'from level 5 no note')
-- the professions and the hourly camp
local lines={};GetNumSkillLines=function()return #lines end;GetSkillLineInfo=function(i)return lines[i]end
local ps={op='p',cl=10,m=0,x=1,y=1,l=3};assert(not FR.Done(ps)and FR.Text(ps):find('Lederverarbeitung',1,true),'professions step')
lines={'Kürschnerei','Lederverarbeitung'};assert(FR.Done(ps),'professions learned')
local now=100000;time=function()return now end;local gt=500;GetTime=function()return gt end
local bags={};GetItemCount=function(id)return bags[id]or 0 end
local auras={};UnitBuff=function(u,i)local a=auras[i];if a then return a.n,nil,0,nil,3600,a.e,nil,nil,nil,a.id end end;UnitDebuff=function()end
ForeverRoutesCharDB.campLevel=10;ForeverRoutesCharDB.camp=nil;level=9;assert(FR.CampStatus()==nil,'no camp below its level')
level=10;assert(FR.CampStatus():find('Lager aufschlagen',1,true)and FR.Hint({op='a'}):find('Lager aufschlagen',1,true),'camp due')
local _,beside=FR.CampStatus();assert(beside and beside:find('0/5 Leichtes Leder',1,true),'farm leather beside the route')
-- the buff: an hour, nothing to say until 10 minutes before its end
auras[1]={n='Well Rested Shelter',e=gt+3000};assert(FR.CampStatus()==nil and select(2,FR.CampStatus())==nil,'quiet with the buff on')
auras[1].e=gt+540;local h,b=FR.CampStatus();assert(h==nil and b:find('Leder farmen',1,true),'10 min before: farm leather')
bags[2318]=5;h,b=FR.CampStatus();assert(h==nil and b==nil,'10 min before with leather: quiet')
bags[2318]=0;bags[279978]=1;h,b=FR.CampStatus();assert(b==nil,'a tent in the bags')
auras[1].e=gt+240;h=FR.CampStatus();assert(h=='Lager-Buff endet in 4 Min – Zelt: bereit, Lagerfeuer: fehlt','5 min before: '..tostring(h))
bags[279981]=1;h=FR.CampStatus();assert(h:find('Lagerfeuer: bereit',1,true),'fire kit ready')
auras[1]={n='Unbekannt',id=1229451,e=gt+100};h=FR.CampStatus();assert(h:find('endet in 2 Min',1,true),'the cooldown aura by its id')
auras[1]=nil;now=now+3600;h=FR.CampStatus();assert(h:find('Lager aufschlagen',1,true),'run out: make camp')
SlashCmdList.FOREVERROUTES('lager');assert(FR.CampStatus()==nil,'camp done (no buff seen: the time since /fr lager)')
ForeverRoutesCharDB.campLevel=nil;assert(FR.Text({op='z',it=1,cl=10,l=4}):find('Verzauberkunst verlernen',1,true),'casters unlearn Enchanting')
-- no route for this character: said in the window
UnitClass=function()return'Hexer','WARLOCK'end;FR.Refresh()
for _,e in ipairs(MOCK.errors)do error(e.kind..': '..tostring(e.msg))end
io.write('foreverroutes addon test ok\n')
