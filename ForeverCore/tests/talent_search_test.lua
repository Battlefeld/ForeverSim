-- The search for the best talents (ForeverCoreBridge/SimSearch.lua) against a stand-in for the engine whose damage
-- depends on known talents, so the result of the search is known.
local root=assert(arg[1]);dofile(root..'/_dev/harness/wowmock.lua');dofile(root..'/_dev/harness/gameapi.lua')
local function loadAddon(addon)
 for line in io.lines(root..'/'..addon..'/'..addon..'.toc')do
  local file=line:gsub(string.char(13),''):gsub(string.char(92),'/'):match('^%s*([^#].-%.lua)%s*$')
  if file then assert(loadfile(root..'/'..addon..'/'..file))(addon,{})end
 end
end
loadAddon('ForeverSimBridge');loadAddon('ForeverCoreBridge')
UnitClass=function(u)if u=='player'then return'Mage','MAGE',8 end end
local level=60;UnitLevel=function()return level end
MOCK.Fire('PLAYER_LOGIN');MOCK.Advance(.5,.05)
local C=ForeverCoreClient;local Sim=C.Sim
C.queue={};C.pending=nil;C.Say=function()end
ForeverCoreBridgeDB.sim=nil
local model=Sim.Model();local fire=model.talentTrees[2].talents
assert(Sim.Layout and Sim.Search==nil and Sim.FindBest,'search module loaded')
-- presets with a start build: five points in the first fire talents
local row0={};for _,n in ipairs(fire)do if n.row==0 then row0[#row0+1]=n end end
table.sort(row0,function(a,b)return a.column<b.column end)
assert(#row0>=2,'the first row has several talents')
local start={{tree=2,row=0,col=row0[1].column,rank=math.min(row0[1].maxRank,2)}}
local startE=Sim.PresetEntries({entries=start})
local want=row0[2]
Sim.Store().presets={engine=C.engineRevision,class='mage',talents={{name='Fire DPS',valid=true,tree=2,entries=start,talentsString='x'}},gear={},builds={},layout={}}
local jobs=0;local screened=0
-- the stand-in: every point in the wanted talent is worth 50, any other point 5
local function dpsOf(b)
 local d=1000
 for _,e in ipairs(b.talents or{})do d=d+(e[1]==2 and e[2]==0 and e[3]==want.column and 50 or 5)*e[4]end
 return d
end
FUSLive.capture=function()return{class='mage',level=60,talents={{entries={}},{entries={{classKey=fire[1].key,rank=1}}},{entries={}}}}end
C.Request=function(kind,payload,cb)
 assert(kind=='talent-compare','only builds are measured: '..kind)
 jobs=jobs+1;assert(#payload.builds<=12,'the engine takes at most 12 builds');if payload.screenOnly then screened=screened+1 end
 local rows={}
 for i,b in ipairs(payload.builds)do rows[i]={id=b.id,dps=dpsOf(b),rotation='fire'}end
 cb({builds=rows});return true
end
local seen,finished,info,built
local ok=Sim.FindBest({tree=2},function(s)seen=s.label end,function(b,i)finished=true;built=b;info=i end)
assert(ok==true or ok==nil or ok,'started')
assert(finished,'the stand-in answers at once, so the search is done')
assert(built and built.source=='search' and built.searchTree==2,'the found build is saved')
local _,total=Sim.Points(built.entries);assert(total==select(2,Sim.Points(startE)),'the number of points stays the same: '..total)
local rank=Sim.Rank(built.entries,2,0,want.column)
assert(rank>=math.min(want.maxRank,2) and rank==want.maxRank or rank>Sim.Rank(startE,2,0,want.column),'points moved to the talent that is worth more: rank '..rank)
assert(Sim.Valid(built.entries),'the build found is legal')
assert(screened>=3 and jobs>screened-1,'quick measurements were used: '..screened..'/'..jobs)
assert(Sim.Result(built.id) and Sim.Result('live'),'the found build was measured next to the character: '..tostring(Sim.Result(built.id)))
assert(not Sim.Searching(),'the search is over')
assert(type(info)=='number' or info==nil,'gain reported')
-- a second search replaces the first result of the same tree
local n=#Sim.Builds();Sim.FindBest({tree=2},nil,function(b)finished=b end)
assert(#Sim.Builds()==n,'the earlier result of this tree is replaced, not added again')
-- a start build that is already the best
want={column=row0[1].column,maxRank=row0[1].maxRank}
Sim.Store().presets.talents[1].entries={{tree=2,row=0,col=row0[1].column,rank=row0[1].maxRank}}
local note;Sim.FindBest({tree=2},nil,function(b,i)built=b;note=i end)
assert(built==nil and tostring(note):find('beste',1,true),'nothing better: '..tostring(note))
-- no preset for the tree
local ok2,why=Sim.FindBest({tree=3});assert(ok2==false and why,'no start build: '..tostring(why))
-- cancel in the middle (answers come later)
local pending={}
C.Request=function(kind,payload,cb)pending[#pending+1]={payload=payload,cb=cb};return true end
Sim.Store().presets.talents[1].entries=start
built=nil;note=nil;local called
Sim.FindBest({tree=2},nil,function(b,i)called=true;built=b;note=i end)
assert(Sim.Searching() and #pending==1,'waiting for the first answer')
assert(not Sim.FindBest({tree=2}),'only one search at a time')
assert(not Sim.RunAll({}),'no simulation run while the search runs')
Sim.CancelSearch()
local j=table.remove(pending,1);local rows={};for i,b in ipairs(j.payload.builds)do rows[i]={id=b.id,dps=1000,rotation='fire'}end;j.cb({builds=rows})
assert(called and built==nil and tostring(note):find('abgebrochen',1,true) and not Sim.Searching(),'cancelled: '..tostring(note))
-- an engine that does not answer
Sim.FindBest({tree=2},nil,function(b,i)built=b;note=i end);j=table.remove(pending,1);j.cb(nil,'Keine Antwort')
assert(note=='Keine Antwort' and not Sim.Searching(),'engine error is passed on')
-- all ten places used: a clear message
C.Request=function(kind,payload,cb)local rows={};for i,b in ipairs(payload.builds)do rows[i]={id=b.id,dps=dpsOf(b),rotation='fire'}end;cb({builds=rows});return true end
want=row0[2];for i=#Sim.Builds(),1,-1 do Sim.DeleteBuild(Sim.Builds()[i].id)end
for i=1,10 do Sim.AddBuild('B'..i,startE,'own')end
Sim.FindBest({tree=2},nil,function(b,i)built=b;note=i end)
assert(built==nil and tostring(note):find('belegt',1,true),'full: '..tostring(note))
assert(#MOCK.errors==0,'no errors: '..tostring(MOCK.errors[1]))
io.write('talent search ok\n')
