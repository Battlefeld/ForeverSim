-- ForeverCoreBridge/Sim.lua: saved builds, presets, comparisons and the active rotation (no windows involved).
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
local C=ForeverCoreClient;local Sim=C.Sim;local P=FUSLive
assert(Sim,'Sim.lua is not loaded')
C.queue={};C.pending=nil;C.Say=function()end
ForeverCoreBridgeDB.sim=nil

-- gates ---------------------------------------------------------------------------------------------------------
assert(Sim.Class()=='mage')
assert(Sim.Available('hud') and Sim.Available('talents'),'level 60 offers everything')
level=55;assert(Sim.Available('rotation') and Sim.Available('loot') and not Sim.Available('talents'),'level 55: no talents tab')
level=49;assert(Sim.Available('hud') and not Sim.Available('rotation') and not Sim.Available('loot'),'level 49: HUD only')
level=1;assert(Sim.Available('hud'),'HUD from level 1')
level=60

-- the character's own talents, mapped to places in the tree ---------------------------------------------------------
local model=Sim.Model();assert(model and #model.talentTrees==3,'mage model')
local fire=model.talentTrees[2].talents
P.capture=function()return{class='mage',level=60,talents={{entries={}},{entries={{classKey=fire[1].key,rank=2},{classKey=fire[2].key,rank=3},{classKey='unknown-key',rank=1},{classKey=fire[3].key,rank=0}}},{entries={}}}}end
local live=assert(Sim.LiveEntries())
assert(#live==2,'unknown keys and rank 0 are left out: '..#live)
assert(live[1].t==2 and live[1].r==fire[1].row and live[1].c==fire[1].column and live[1].n==2)
local pts,total=Sim.Points(live);assert(pts[2]==5 and pts[1]==0 and total==5)
local payload=Sim.Payload(live);assert(payload[1][1]==2 and payload[1][4]==2 and #payload[1]==4,'compact form [tree,row,col,rank]')
assert(Sim.Signature(live)==Sim.Signature({live[2],live[1]}),'signature does not depend on order')
P.capture=function()error('boom')end
local none,why=Sim.LiveEntries();assert(none==nil and why,'an unreadable character is reported')

-- saved builds: at most ten ---------------------------------------------------------------------------------------
assert(Sim.CanAddBuild() and #Sim.Builds()==0)
local first=assert(Sim.AddBuild('  Feuer PvE  ',live,'own'));assert(first.name=='Feuer PvE' and first.id=='b1')
first.entries[1].n=99;assert(live[1].n==2,'the build holds a copy')
assert(Sim.AddBuild('',live).name=='Skillung 2','an empty name gets a default')
for i=3,10 do assert(Sim.AddBuild('B'..i,live))end
local refused,reason=Sim.AddBuild('elf',live);assert(refused==nil and reason:find('10',1,true),'the eleventh build is refused')
assert(not Sim.CanAddBuild())
assert(Sim.RenameBuild('b2','Eis')and Sim.Build('b2').name=='Eis' and not Sim.RenameBuild('b2','  ') and not Sim.RenameBuild('nope','x'))
Sim.Store().results.b3={dps=1}
assert(Sim.DeleteBuild('b3') and not Sim.Build('b3') and Sim.Store().results.b3==nil,'deleting a build drops its result')
assert(Sim.CanAddBuild() and not Sim.DeleteBuild('b3'))
Sim.Store().results.b4={dps=1};assert(Sim.UpdateBuild('b4',live) and Sim.Store().results.b4==nil,'a changed build loses its old result')

-- another character has its own data -----------------------------------------------------------------------------
local oldGuid=UnitGUID;UnitGUID=function()return'Player-2-9'end
assert(#Sim.Builds()==0,'a second character starts empty');UnitGUID=oldGuid;assert(#Sim.Builds()==9)

-- presets and the top builds -------------------------------------------------------------------------------------
local sent
C.Request=function(kind,payload,cb,opts)sent={kind=kind,payload=payload,cb=cb,opts=opts};return true end
local got,issue;assert(Sim.LoadPresets(function(p,i)got,issue=p,i end))
assert(sent.kind=='presets' and sent.payload.class=='mage')
sent.cb({engineRevision='eng-1',class='mage',talents={
 {name='Frost 14/0/37',talentsString='f',valid=false,tree=3,error='49 statt 51 Punkte'},
 {name='Arcane DPS',talentsString='a',valid=true,tree=1,spec='mage',entries={{tree=1,row=0,col=1,rank=5}}},
 {name='Fire DPS',talentsString='fi',valid=true,tree=2,spec='mage',entries={{tree=2,row=0,col=0,rank=2}}},
 {name='Fire 0/35/16',talentsString='fi2',valid=true,tree=2,entries={}},
},gear={{name='Phase 1',items={}},{name='Pre-BiS',items={}}},builds={}})
assert(got and got.engine=='eng-1' and Sim.Presets()==got)
local top=Sim.TopBuilds()
assert(#top==2,'one build per tree; an invalid preset is not offered: '..#top)
assert(top[1].tree==1 and top[1].name=='Arcane DPS' and top[2].name=='Fire DPS' and top[2].gearPreset=='Pre-BiS','the best-of-all gear set is the "BiS" one')
assert(top[2].entries[1].t==2 and top[2].entries[1].n==2,'preset entries map to build entries')
C.engineRevision='eng-1'
sent=nil;assert(Sim.LoadPresets(function()end) and sent==nil,'presets of this engine are not asked again')
sent=nil;Sim.LoadPresets(function()end,true);assert(sent and sent.kind=='presets','force asks again')
-- the engine pairs builds itself
sent.cb({engineRevision='eng-1',class='mage',talents={{name='Fire DPS',talentsString='fi',valid=true,tree=2,entries={}}},gear={{name='Weird',items={}},{name='Raid',items={}}},builds={{name='Fire',talents='Fire DPS',gear='Raid'}}})
top=Sim.TopBuilds();assert(#top==1 and top[1].name=='Fire' and top[1].gearPreset=='Raid','paired builds win')
local failed;sent=nil;Sim.LoadPresets(function(p,i)failed=i end,true);sent.cb(nil,'Zeitlimit');assert(failed=='Zeitlimit')

-- comparing builds -----------------------------------------------------------------------------------------------
C.SimCacheContext=function()return'ctx-1'end
Sim.Store().presets=nil;for _=1,9 do Sim.DeleteBuild(Sim.Builds()[1].id)end
local own=Sim.AddBuild('Feuer',live,'own')
sent=nil;assert(Sim.CompareOwn(function(rows,i)issue=i;got=rows end))
assert(sent.kind=='talent-compare' and sent.opts.timeout==300 and sent.payload.priority==true)
local b=sent.payload.builds;assert(#b==2 and b[1].id=='live' and b[1].talents==nil,'the live build is not overridden')
assert(b[2].id==own.id and #b[2].talents==2 and b[2].talents[1][1]==2)
sent.cb({builds={
 {id='live',name='Im Spiel',dps=1641.2,rotation='frost',rotations={{name='frost',dps=1641.2},{name='fire',dps=1500}},points={0,5,0},spec='mage',priority={{spellId=116}}},
 {id=own.id,name='Feuer',dps=1842.6,rotation='fire',priority={{spellId=133}}},
}})
assert(#got==2 and issue==nil)
local rec=Sim.Result('live');assert(rec.dps==1641.2 and rec.rotation=='frost' and rec.context=='ctx-1' and rec.priority[1].spellId==116)
assert(Sim.Result(own.id).priority==nil,'only the live build keeps its priority list')
assert(not Sim.IsStale(rec),'same state: not stale')
C.SimCacheContext=function()return'ctx-2'end;assert(Sim.IsStale(rec),'another state: stale')
C.SimCacheContext=function()return'ctx-1'end;C.engineRevision='eng-2';assert(Sim.IsStale(rec),'another engine: stale');C.engineRevision='eng-1'
assert(Sim.IsStale(nil),'no result counts as stale')
assert(C.ActiveRotation()=='frost' and Sim.Rotation().priority[1].spellId==116 and Sim.Rotation().dps==1641.2,'the live build sets the active rotation')
-- an error row is stored and does not touch the rotation
sent=nil;Sim.Compare({{id='live',name='Im Spiel'}},nil);sent.cb({builds={{id='live',error='Rotation fehlt'}}})
assert(Sim.Result('live').error=='Rotation fehlt' and Sim.Result('live').dps==nil and C.ActiveRotation()=='frost')
-- no answer
sent=nil;local failure;Sim.CompareOwn(function(r,i)failure=i end);sent.cb(nil,'Zeitlimit');assert(failure=='Zeitlimit')
-- a job that cannot be queued
C.Request=function()return false end
local refusedMsg;assert(Sim.CompareOwn(function(r,i)refusedMsg=i end)==false and refusedMsg)
-- empty list needs no job
local emptyCalled;assert(Sim.Compare({},function(rows)emptyCalled=rows end)and #emptyCalled==0)

-- top and spec comparisons name their builds -----------------------------------------------------------------------
Sim.Store().presets={engine='eng-1',class='mage',talents={{name='Arcane DPS',talentsString='a',valid=true,tree=1,entries={}},{name='Fire DPS',talentsString='fi',valid=true,tree=2,spec='mage',entries={}}},gear={{name='Pre-BiS',items={}}},builds={}}
C.Request=function(kind,payload,cb,opts)sent={kind=kind,payload=payload,cb=cb,opts=opts};return true end
Sim.CompareTop();b=sent.payload.builds
assert(#b==2 and b[1].id=='top:1' and b[1].talentsString=='a' and b[1].gearPreset=='Pre-BiS' and sent.payload.priority==false)
Sim.CompareSpecs();b=sent.payload.builds
assert(#b==3 and b[1].id=='live' and b[2].id=='spec:1' and b[2].gearPreset==nil,'specs are compared with the gear worn now')

-- the rotation reaches every other job ---------------------------------------------------------------------------
loadAddon('ForeverCoreBridge')   -- fresh Request (the stubs above replaced it)
C=ForeverCoreClient;Sim=C.Sim;C.queue={};C.pending=nil
Sim.Store().rotation={name='fire'}
assert(C.Request('item',{items={}}) and C.queue[#C.queue].payload.rotation=='fire' and C.queue[#C.queue].payload.rotationSoft==true,'item jobs carry the active rotation')
assert(C.Request('sim',{rotation='frost'}) and C.queue[#C.queue].payload.rotation=='frost','an explicit rotation is kept')
assert(C.Request('ping',{}) and C.queue[#C.queue].payload.rotation==nil,'a ping has no rotation')
Sim.Store().rotation=nil
assert(C.Request('weights',{}) and C.queue[#C.queue].payload.rotation==nil,'no active rotation: nothing added')

assert(#MOCK.errors==0,MOCK.errors[1]and MOCK.errors[1].msg or'')
print=io.write;print('sim service tests passed\n')
