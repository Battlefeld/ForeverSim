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

-- every job kind the window sends needs the character snapshot ('state.sim')
for _,kind in ipairs({'talent-compare','build-detail','rota-tune','presets','weights'})do
 local ok,snap=pcall(C.Capture,kind);assert(ok and type(snap)=='table' and snap.sim and snap.sim.class=='mage','the job kind '..kind..' carries the character: '..tostring(snap))
end
-- refining the rotation -------------------------------------------------------------------------------------------------------
Sim.Store().results.live={dps=1500,rotation='fire',rotations={{name='fire',dps=1500}},priority={{spellId=1}},context=C.SimCacheContext and C.SimCacheContext(),engine=C.engineRevision}
local tuneJobs={};local order0
C.Request=function(kind,payload,cb)
 tuneJobs[#tuneJobs+1]={kind=kind,payload=payload}
 if kind=='rota-tune'then
  assert(payload.rotation=='fire' and payload.iterations,'the engine rotation is the start')
  if not payload.order then cb({dps=1500,order={0,1,2},bestOrder={1,0,2},bestDps=1520,tried=5,rotation='fire'})
  elseif payload.order[1]==1 and payload.order[2]==0 then cb({dps=1520,order=payload.order,bestOrder={1,2,0},bestDps=1530,tried=5})
  else cb({dps=1530,order=payload.order,tried=5})end
 elseif kind=='talent-compare'then
  local rows={};for i,b in ipairs(payload.builds)do rows[i]={id=b.id,dps=b.id=='tuned'and 1531 or 1500,rotation=b.rotation,priority={{spellId=2},{spellId=1}}}end
  cb({builds=rows})
 end
 return true
end
local rec,gain;local started,why=Sim.Tune({id='live',name='Im Spiel'},nil,function(r,g)rec,gain=r,g end)
assert(started~=false,'tune started: '..tostring(why))
assert(rec and rec.rotation=='eigen:fire:1,2,0','the tuned rotation is a name: '..tostring(rec and rec.rotation))
assert(math.abs(gain-100*(1531/1500-1))<1e-9,'gain over the engine rotation')
assert(C.ActiveRotation()=='eigen:fire:1,2,0','the tuned rotation becomes the active one for the live build')
assert(Sim.Rotation().priority[1].spellId==2,'the HUD follows the tuned priority list')
assert(Sim.Result('live').rotations[1].custom and Sim.Result('live').rotations[2].name=='fire','the list shows the tuned rotation first')
assert(tuneJobs[#tuneJobs].kind=='talent-compare' and #tuneJobs[#tuneJobs].payload.builds==2,'confirmed with the full count against the engine rotation')
assert(Sim.TunedBase('eigen:fire:1,2,0')=='fire' and Sim.TunedBase('fire')=='fire')
-- tuning again starts from the engine rotation, not from the tuned name
tuneJobs={};Sim.Tune({id='live'},nil,function()end);assert(tuneJobs[1].payload.rotation=='fire','the base of a tuned name is used')
-- nothing to gain
C.Request=function(kind,payload,cb)if kind=='rota-tune'then cb({dps=1500,order={0,1,2},tried=3})end;return true end
Sim.Store().results.live.rotation='fire';rec=nil;local text
Sim.Tune({id='live'},nil,function(r,g)rec,text=r,g end);assert(rec==nil and tostring(text):find('nicht verbessern',1,true),'no gain: '..tostring(text))
-- a gain that the full count does not confirm
C.Request=function(kind,payload,cb)
 if kind=='rota-tune'then cb({dps=1500,order={0,1,2},bestOrder={1,0,2},bestDps=1520,tried=3})
 else local rows={};for i,b in ipairs(payload.builds)do rows[i]={id=b.id,dps=1500}end;cb({builds=rows})end
 return true
end
Sim.Tune({id='live'},nil,function(r,g)rec,text=r,g end);assert(rec==nil and tostring(text):find('nicht bestätigt',1,true),'not confirmed: '..tostring(text))
-- before the first comparison there is nothing to tune
Sim.Store().results.live=nil;local a,b=Sim.Tune({id='live'});assert(a==false and b,'needs a result first')
-- refine is a step of the full run, and the last one
Sim.Store().refine=true;Sim.Store().presets=nil
local labels={}
C.Request=function(kind,payload,cb)
 if kind=='presets'then cb({engineRevision='e',class='mage',talents={},gear={},builds={},layout={}})
 elseif kind=='talent-compare'then local rows={};for i,bb in ipairs(payload.builds)do rows[i]={id=bb.id,dps=1500,rotation='fire',priority={{spellId=1}}}end;cb({builds=rows})
 elseif kind=='build-detail'then cb({dps=1500,rotation='fire',rotations={{name='fire',dps=1500}},priority={{spellId=1}},breakdown={},curve={}})
 elseif kind=='rota-tune'then labels[#labels+1]='tune';cb({dps=1500,order={0},tried=1})end
 return true
end
local sawStep;Sim.RunAll({},function(i,n,label)sawStep=label end,function()end)
assert(sawStep=='Eigene Rota verfeinern' and labels[1]=='tune','the refinement is the last step of the full run: '..tostring(sawStep))
Sim.Store().refine=false
assert(#MOCK.errors==0,'no errors: '..tostring(MOCK.errors[1]))
io.write('talent search ok\n')
