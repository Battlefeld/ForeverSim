-- ForeverCoreBridge/Loot.lua: candidates from the dungeon catalog, bags and top gear; values, best items, farming places.
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
local C=ForeverCoreClient;local Sim=C.Sim;local Loot=assert(C.Loot,'loot module loaded')
C.queue={};C.pending=nil;C.Say=function()end
ForeverCoreBridgeDB.sim=nil
-- items the stand-in knows nothing about: the catalog's own slot text decides
C_Item.GetItemInfoInstant=function()return nil end;GetItemInfoInstant=C_Item.GetItemInfoInstant
local worn={[5]=1111,[15]=2222}
GetInventoryItemID=function(u,slot)return worn[slot]end
GetInventoryItemLink=function(u,slot)return worn[slot]and('|cff0070dd|Hitem:'..worn[slot]..':2564:0:0|h[Getragen '..worn[slot]..']|h|r')end

-- slot/pool resolution -------------------------------------------------------------------------------------------------------
assert(Loot.PoolOf(5,'Back, Cloth')=='back' and Loot.PoolOf(5,'Main Hand, Sword')=='mainhand' and Loot.PoolOf(5,'Finger')=='finger' and Loot.PoolOf(5,'Recipe, Tailoring')==nil,'catalog slot texts')
C_Item.GetItemInfoInstant=function(id)return id,'Armor','Cloth','INVTYPE_ROBE'end;GetItemInfoInstant=C_Item.GetItemInfoInstant
assert(Loot.PoolOf(5,'whatever')=='chest','the client\'s equip location wins');
C_Item.GetItemInfoInstant=function()return nil end;GetItemInfoInstant=C_Item.GetItemInfoInstant
assert(Loot.EnchantOf('|cff|Hitem:1111:2564:0:0|h[x]|h|r')==2564 and Loot.EnchantOf('|Hitem:1111::0|h')==0 and Loot.EnchantOf(nil)==0,'enchant of a link')
assert(#Loot.SLOTS==17 and Loot.Slot('finger2').pool=='finger')

-- candidates ----------------------------------------------------------------------------------------------------------------------
local cands=Loot.Candidates()
assert(#cands>200,'the dungeon catalog gives many candidates: '..#cands)
for _,c in ipairs(cands)do assert(c.pool and #c.sources>=1)end
local sample;for _,c in ipairs(cands)do if c.sources[1].kind=='dungeon'and c.sources[1].chance then sample=c break end end
assert(sample and sample.sources[1].boss and sample.sources[1].dungeon,'a drop knows its boss and dungeon')
-- bags and the top gear join in
local before=#cands
Sim.ScanBags=function()return{[7001]=true}end
C_Item.GetItemInfoInstant=function(id)if id==7001 then return id,'Armor','Cloth','INVTYPE_FINGER'end end;GetItemInfoInstant=C_Item.GetItemInfoInstant
Sim.Store().presets={gear={{name='Pre-BiS',items={{slot=4,id=8001},{slot=10,id=8002}}},{name='Phase 3',items={{slot=0,id=8003}}}},talents={},builds={},layout={}}
Loot.Reset();cands=Loot.Candidates()
local function find(id)for _,c in ipairs(cands)do if c.id==id then return c end end end
assert(find(7001) and find(7001).owned and find(7001).pool=='finger','a bag item')
assert(find(8001) and find(8001).star and find(8001).pool=='chest' and find(8002).pool=='finger','items of the BiS set are stars; slot index decides the pool')
assert(not find(8003),'only the BiS set is used when there is one')
-- filters
Loot.SetFilter('dungeon',false);cands=Loot.Candidates();assert(#cands==3,'without dungeons: bag + two star items: '..#cands);Loot.SetFilter('dungeon',true)
Loot.SetFilter('onlyStar',true);cands=Loot.Candidates();assert(#cands==2,'only the star list: '..#cands);Loot.SetFilter('onlyStar',false)
Loot.SetFilter('star',false);Loot.SetFilter('bag',false);cands=Loot.Candidates();assert(#cands==before,'dungeons only: '..#cands..' vs '..before);Loot.SetFilter('star',true);Loot.SetFilter('bag',true)

-- values -----------------------------------------------------------------------------------------------------------------------------
-- the stand-in for the item pipeline: a few items are better than what is worn, one is busy at first
local values={[8001]=3.9,[8002]=1.1,[7001]=0.4}
local busyFirst={[8001]=true}
local calls=0
C.ItemResult=function(link,preview)
 calls=calls+1
 local id=tonumber(link:match('item:(%d+)'))
 if busyFirst[id]then busyFirst[id]=nil;return{state='busy'}end
 if id==9999 then return nil end
 local v=values[id]
 if v==nil then v=((id%7)-4)*0.3 end
 return{state='ok',pct=v,delta=v*10}
end
Loot.Reset();cands=Loot.Candidates()
local p=Loot.Poll(10000)
assert(p.total==#cands and p.busy==1 and p.ready==#cands-1,'one item still busy: '..p.busy..'/'..p.ready)
p=Loot.Poll(10000);assert(p.busy==0 and p.ready==#cands,'all valued')
-- a poll asks for a limited number at once
Loot.Reset();calls=0;busyFirst={};Loot.Poll(30);assert(calls<=30,'budget per poll: '..calls)
-- running to the end
Loot.Reset();local doneP;local running=Loot.Run(function(pp)doneP=pp end)
assert(running)
local guard=0;while Loot.running and guard<400 do guard=guard+1;MOCK.Advance(3,1)end
assert(doneP and doneP.busy==0 and doneP.ready+doneP.failed+doneP.blocked+doneP.unread==doneP.total,'the run finished: '..guard)
assert(Loot.LastRun() and Loot.LastRun().total==doneP.total,'the run is remembered')
assert(not Loot.Run or Loot.running==false)

-- best items ----------------------------------------------------------------------------------------------------------------------
Loot.Reset();Loot.Poll(10000)
local pre=Loot.PreBis()
assert(#pre==17,'a row per slot')
local function row(key)for _,r in ipairs(pre)do if r.slot==key then return r end end end
assert(row('chest').best and row('chest').best.id==8001 and math.abs(row('chest').best.pct-3.9)<1e-9,'the best chest item')
assert(row('chest').worn and row('chest').worn.id==1111,'what is worn now')
assert(row('finger1').best and row('finger1').best.pct>=row('finger2').best.pct,'two rings: the two best ones, best first')
assert(row('finger1').best.id~=row('finger2').best.id,'not the same ring twice')
assert(row('neck').best==nil or row('neck').best.pct>Loot.THRESHOLD,'a slot without a real upgrade has no best item')
local total,n=Loot.Total(pre);assert(n>5 and total>3.9,'total and number of upgrades: '..total..'/'..n)
local alt=Loot.Alternatives('chest',8001,3);assert(#alt<=3 and alt[1].id~=8001 and alt[1].pct>=(alt[2]and alt[2].pct or -99),'alternatives')
-- an item that is worn already is not offered again
worn[11]=8002;pre=Loot.PreBis();local f1,f2;for _,r in ipairs(pre)do if r.slot=='finger1'then f1=r elseif r.slot=='finger2'then f2=r end end
assert(not(f2.best and f2.best.id==8002) and not(f1.best and f1.best.id==8002),'the ring worn in the other slot is no upgrade');worn[11]=nil
-- where to farm
local farm=Loot.Farm(Loot.PreBis(),3)
assert(#farm>=1 and farm[1].perRun>0 and farm[1].upgrades>=1 and farm[1].dungeon,'a dungeon with upgrades: '..#farm)
for i=2,#farm do assert(farm[i-1].perRun>=farm[i].perRun,'sorted by gain per run')end

-- stat weights ---------------------------------------------------------------------------------------------------------------------------
local sent;C.Request=function(kind,payload,cb)sent={kind=kind,cb=cb};return true end
local got;Loot.LoadWeights(function(w)got=w end)
assert(sent.kind=='weights')
sent.cb({rows={{key='StatSpellDamage',perPoint=1.0},{key='StatCritRating',perPoint=0.5},{key='StatIntellect',perPoint=0.25},{key='StatHitRating',perPoint=-0.1}}})
assert(got and #got.rows==4 and got.rows[1].key=='StatSpellDamage' and got.rows[1].weight==1 and got.rows[2].weight==.5 and got.rows[4].weight==0,'weights relative to the best: '..tostring(got and got.rows[4].weight))
assert(got.rows[1].label=='Zauberschaden')
sent=nil;Loot.LoadWeights(function(w)got=w end);assert(sent==nil,'cached for the same character state')
sent=nil;Loot.LoadWeights(nil,true);assert(sent,'forced reload')
assert(#MOCK.errors==0,'no errors: '..tostring(MOCK.errors[1]))
io.write('loot ok\n')
