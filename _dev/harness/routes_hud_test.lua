unpack=table.unpack
math.atan2=function(y,x)return math.atan(y,x)end
local M=dofile('_dev/harness/wowmock.lua')
dofile('_dev/harness/gameapi.lua')
local count=0
local function check(ok,msg)assert(ok,msg);count=count+1 end
local accepted,complete,objectives={},{},{}
C_QuestLog={IsOnQuest=function(q)return accepted[q]or false end,IsComplete=function()return false end,
 IsQuestFlaggedCompleted=function(q)return complete[q]or false end,
 GetQuestObjectives=function(q)return objectives[q]end,GetTitleForQuestID=function(q)return 'Quest '..q end}
local instance=false
function IsInInstance()return instance end
function GetInstanceInfo()return nil,nil,nil,nil,nil,nil,nil,999 end
local px,py,pm=0,0,0
function UnitPosition()return px,py,0,pm end
function GetPlayerFacing()return 0 end
local bags=0
function GetItemCount(id)return bags end
C_Item=C_Item or{};C_Item.GetItemCount=GetItemCount
function GetItemInfo(id)return 'Item '..id,'item:'..id,nil,nil,nil,nil,nil,nil,nil,'icon' end
function GetNumSkillLines()return 0 end
function InCombatLockdown()return false end
C_Container={GetContainerNumFreeSlots=function()return 8,0 end}
local pin,added,removed=nil,0,0
C_Map={GetBestMapForUnit=function()return 1 end,GetMapPosFromWorldPos=function()return 1,{x=.5,y=.5}end,
 SetUserWaypoint=function(v)pin=v end,ClearUserWaypoint=function()pin=nil end}
UiMapPoint={CreateFromCoordinates=function(map,x,y)return{uiMapID=map,position={x=x,y=y}}end}
local function data(steps)
 ForeverRoutesData={build='test',routes={['gnome-warlock']={revision='r1',s=steps,opts={}}}}
 ForeverRoutesCharDB={};ForeverRoutesDB={};ForeverRoutes.live=nil;ForeverRoutes.undo=nil
end
for _,file in ipairs({'Core','Tasks','ArtData','Art','Navigation','Tooltips','UI'})do dofile('ForeverRoutes/'..file..'.lua')end
local FR=ForeverRoutes
local steps={{op='a',q=1,n='First',m=0,x=100,y=0},{op='w',q=1,n='First',k='kill',c=2,tg='Wolf',m=0,x=100,y=0},{op='t',q=1,n='First',m=0,x=0,y=0},{op='note',n='Read this'}}
data(steps);FR.Show();check(FR.TaskView().step.op=='a','accept first')
accepted[1]=true;objectives[1]={{text='Wolves: 1/2',type='monster',numFulfilled=1,numRequired=2,finished=false}}
FR.Refresh();check(FR.TaskView().step.op=='w','accepted quest advances')
check(FR.frame.current.text:GetText():find('töte',1,true),'current task visible')
check(FR.frame.rows[1].text:GetText():find('1/2',1,true),'real objective progress visible')
check(not FR.CanConfirm(FR.TaskView().step),'cannot falsely confirm quest')
FR.Skip();check(FR.TaskView().step.op=='t','skip work')
FR.Back();check(FR.TaskView().step.op=='w','undo skip work')
objectives[1][1].finished=true;FR.Refresh();check(FR.TaskView().step.op=='t','finished objective advances')
complete[1]=true;FR.Refresh();check(FR.TaskView().step.op=='note','turnin advances')
check(FR.Confirm(),'manual note confirm');check(FR.TaskView().step==nil,'route ends')
FR.Back();check(FR.TaskView().step.op=='note','undo manual confirm')
FR.Config().compact=true;FR.Refresh();check(not FR.frame.nextLabel:IsShown(),'compact hides preview')
-- Arrival and navigation failure do not complete an active quest.
local st={op='w',q=2,k='kill',c=1,m=0,x=0,y=0};accepted[2]=true
objectives[2]={{text='Mob: 0/1',type='monster',numRequired=1,finished=false}}
check(FR.Navigation(st).arrived,'arrival recognized');check(not FR.Done(st),'arrival does not finish quest')
check(FR.Navigation({op='w',m=1,x=0,y=0}).distance==nil,'cross continent has no false distance')
C_Map.GetMapPosFromWorldPos=function()return 1,{x=1.1,y=.4}end
check(not FR.Waypoint(0,1,1,'test'),'invalid converted pin rejected')
C_Map.GetMapPosFromWorldPos=function()return 1,{x=.5,y=.5}end
FR.UpdateWaypoint(st,FR.Navigation(st));check(pin~=nil,'fallback map pin installed')
FR.UpdateWaypoint(nil,nil);check(pin==nil and FR.pinned==nil,'stale pin cleared')
-- TomTom only replaces waypoints when target changes.
TomTom={AddWaypoint=function()added=added+1;return added end,RemoveWaypoint=function()removed=removed+1 end}
FR.UpdateWaypoint(st,FR.Navigation(st));FR.UpdateWaypoint(st,FR.Navigation(st));check(added==1,'no TomTom churn')
FR.ClearWaypoint();check(removed==1,'TomTom waypoint removed')
TomTom=nil
-- Completed leading steps in a live plan must not make Skip remove step 1.
FR.live={{op='a',q=1},{op='note',n='live note'},{op='note',n='live second'}}
FR.CharDB().confirmed={};check(FR.Advance().n=='live note','live completed prefix skipped')
FR.Skip();check(#FR.live==2 and FR.live[1].q==1 and FR.Advance().n=='live second','live skip removes actual current index')
FR.Back();check(#FR.live==3 and FR.Advance().n=='live note','live undo inserts once at correct index')
FR.Confirm();FR.Back();check(#FR.live==3 and FR.Advance().n=='live note','live undo confirmation does not duplicate')
FR.SetLive({steps={{op='accept',quest=1},{op='work',quest=2,obj=0,at={m=0,x=0,y=0}}}})
check(FR.live[2].o==1 and FR.undo==nil,'new plan carries objective and discards undo')
instance=true;check(FR.Navigation(FR.live[2])==nil,'no navigation in dungeon');FR.Refresh();check(not FR.arrow:IsShown(),'arrow hides in dungeon')
instance=false
check(FR.Done({op='g',l=20}),'level-only grind completes at target level')
check(not FR.Done({op='g',l=20,xp=6000}),'grind waits for target xp')
-- Data-driven shopping never invents item quantities.
local shop={op='buy',items={{id=9001,count=3}}};bags=2
check(not FR.Done(shop),'shopping awaits all items');bags=3;check(FR.Done(shop),'shopping completes from bags')
check(not FR.Done({op='buy'}),'missing shopping data is not completion')
-- Tracker hooks preserve native behavior and clear recycled quest identities.
local native=0;local block=CreateFrame('Button',nil,UIParent);block.id=2;block.Header=block;block:SetScript('OnEnter',function()native=native+1 end)
QuestObjectiveTracker={usedBlocks={[2]=block}};FR.ScanQuestTracker();M.script(block,'OnEnter')
check(native==1 and ForeverRoutesQuestTooltip:IsShown(),'native mouseover preserved and extended')
QuestObjectiveTracker.usedBlocks={};FR.ScanQuestTracker();FR.HideQuestTooltip();M.script(block,'OnEnter')
check(native==2 and not ForeverRoutesQuestTooltip:IsShown(),'recycled native block drops old identity')
-- Ambiguous equal-count objectives never invent an NPC/model.
ForeverRoutesData.quests={[2]={objectives={{kind='kill',id=12,count=1},{kind='kill',id=13,count=1}}}}
check(FR.ObjectiveMeta(2,1)==nil,'ambiguous objective has no target')
-- Exercise events/timers, option window, slash commands and saved visibility.
FR.ToggleMenu();FR.ToggleMenu()
for _,cmd in ipairs({'compact','scale 1.1','lock','position','arrow','show','hide','show'})do SlashCmdList.FOREVERROUTES(cmd)end
M.Fire('QUEST_LOG_UPDATE');M.Advance(2)
check(FR.frame:IsShown()and not FR.Config().hidden,'show state preserved')
check(#M.errors==0,'UI/event errors: '..(#M.errors>0 and M.errors[1].msg or''))
local unknown={};for k in pairs(M.unknownMethods)do unknown[#unknown+1]=k end
check(#unknown==0,'unknown widget methods: '..table.concat(unknown,', '))
local realData=os.getenv('ROUTES_DATA')
if realData then
 dofile(realData);local originalKey=FR.Key;local routeCount=0
 for key,r in pairs(ForeverRoutesData.routes)do
  local base=key:gsub('%-dungeons$','')
  FR.Key=function()return base end;FR.live=nil;FR.undo=nil
  for _,idx in ipairs({1,math.max(1,math.floor(#r.s/2)),#r.s})do
   ForeverRoutesCharDB={index=idx,routeKey=key,dataRevision=r.revision,dungeons=key:find('%-dungeons$')~=nil}
   FR.Refresh()
  end
  routeCount=routeCount+1
 end
 FR.Key=originalKey;check(#M.errors==0,'real route event errors')
 io.write('PASS actual route data: '..routeCount..' variants, start/middle/end HUD refresh\n')
end
io.write('PASS '..count..' checks; no mocked UI/event errors\n')
