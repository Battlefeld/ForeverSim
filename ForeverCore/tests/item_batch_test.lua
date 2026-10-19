-- Item batching: several item requests become ONE job; unwearable items are sorted out beforehand.
local root=assert(arg[1]);dofile(root..'/_dev/harness/wowmock.lua');dofile(root..'/_dev/harness/gameapi.lua')
local function loadAddon(addon)
 local ns={}
 for line in io.lines(root..'/'..addon..'/'..addon..'.toc')do
  local file=line:gsub('\r',''):gsub('\\','/'):match('^%s*([^#].-%.lua)%s*$')
  if file then assert(loadfile(root..'/'..addon..'/'..file))(addon,ns)end
 end
end
loadAddon('ForeverSimBridge');loadAddon('ForeverCoreBridge')
UnitLevel=function()return 20 end
MOCK.Fire('PLAYER_LOGIN');MOCK.Advance(.5,.05)
local C=ForeverCoreClient;local P=FUSLive
C.engineRevision='rev-test'
local items={}
for id=101,110 do items[id]={id=id,slot='head',name='Helm '..id,minLevel=1,stats={},statsComplete=true} end
items[103].minLevel=30
P.readItem=function(link)return items[tonumber(tostring(link):match('item:(%d+)'))]end
P.capture=function()return{class='mage',level=20,faction='Horde',equipped={},spells={},talents={}}end
P.normalizeSnapshot=function(s)return{class='mage',level=20,faction='Horde',equipped={}}end
local calls={}
C.Request=function(kind,payload,cb)calls[#calls+1]={kind=kind,payload=payload,cb=cb};return true end
-- 1. three requests inside the window -> one job with the two wearable candidates
local e1,e2,e3=C.ItemResult('item:101'),C.ItemResult('item:102'),C.ItemResult('item:103')
assert(e1.state=='busy' and e2.state=='busy','wearable items are pending: '..tostring(e1.state))
assert(e3.state=='blocked' and tostring(e3.reason):find('Level',1,true),'unwearable item must be blocked locally: '..tostring(e3.state)..' '..tostring(e3.reason))
assert(#calls==0,'nothing may be sent before the collection window ends')
MOCK.Advance(.6,.05)
assert(#calls==1 and calls[1].kind=='item' and #calls[1].payload.items==2,'expected one job with 2 candidates, got '..#calls..' jobs')
calls[1].cb({baselineDps=100,candidates={{pct=103,dps=103},{pct=99,dps=99}}})
assert(e1.state=='ok' and math.abs(e1.pct-3)<1e-9 and e1.status=='upgrade','first result: '..tostring(e1.state)..' '..tostring(e1.pct))
assert(e2.state=='ok' and math.abs(e2.pct+1)<1e-9 and e2.status=='downgrade','second result')
assert(math.abs(e1.delta-3)<1e-9,'delta from baseline')
-- 2. a failing batch must not poison the items: every item is asked on its own
C.simRevision=C.simRevision+1;calls={}
local a,b=C.ItemResult('item:104'),C.ItemResult('item:105');MOCK.Advance(.6,.05)
assert(#calls==1 and #calls[1].payload.items==2,'second batch')
calls[1].cb(nil,'Ruestung nicht tragbar')
assert(#calls==3 and #calls[2].payload.items==1 and #calls[3].payload.items==1,'fallback must issue single jobs: '..#calls)
calls[2].cb({baselineDps=100,candidateDps=101,percent=1,delta=1});calls[3].cb(nil,'Item benoetigt Level 13')
assert(a.state=='ok' and b.state=='unmodeled','single results: '..tostring(a.state)..'/'..tostring(b.state))
-- 3. transient capture errors are retried, not answered with single jobs and not kept
C.simRevision=C.simRevision+1;calls={}
local c,d=C.ItemResult('item:106'),C.ItemResult('item:107');MOCK.Advance(.6,.05)
calls[1].cb(nil,'Munition konnte im Spiel nicht gelesen werden')
assert(#calls==1,'transient errors must not start single jobs')
assert(C.ItemResult('item:106')~=c,'a retried item is requested again later')
-- 4. a changed state drops collected requests
C.simRevision=C.simRevision+1;calls={}
C.ItemResult('item:108');C.simRevision=C.simRevision+1;MOCK.Advance(.6,.05)
assert(#calls==0,'requests of an outdated state must not be sent')
-- 5. many items are split into jobs of at most 24
C.simRevision=C.simRevision+1;calls={}
for id=1000,1029 do items[id]={id=id,slot='head',name='X'..id,minLevel=1,stats={},statsComplete=true} end
for id=1000,1029 do C.ItemResult('item:'..id)end
MOCK.Advance(.6,.05)
local total=0;for _,call in ipairs(calls)do assert(#call.payload.items<=24,'job too large');total=total+#call.payload.items end
assert(total==30,'all items must be sent: '..total)
-- 6. lean candidates: no snapshot first; the PC asks for it ('need') only for unknown items
C.simRevision=C.simRevision+1;calls={}
local u,v=C.ItemResult('item:109'),C.ItemResult('item:110');MOCK.Advance(.6,.05)
assert(#calls==1 and #calls[1].payload.items==2,'lean batch')
for _,it in ipairs(calls[1].payload.items)do assert(it.snapshot==nil and it.spec and it.metadata,'first send must be lean') end
calls[1].cb({baselineDps=100,candidates={{pct=102,dps=102},{need=true,pct=0,dps=0}}})
assert(u.state=='ok' and math.abs(u.pct-2)<1e-9,'known item is done')
assert(v.state=='busy' and #calls==2 and #calls[2].payload.items==1 and calls[2].payload.items[1].snapshot~=nil,'unknown item is resent with its snapshot')
calls[2].cb({baselineDps=100,candidateDps=105,percent=5,delta=5})
assert(v.state=='ok' and math.abs(v.pct-5)<1e-9,'resent item result')
-- dungeon preview: the level requirement does not block; normal hovering still does
C.simRevision=C.simRevision+1;calls={}
local normal=C.ItemResult('item:103')
assert(normal.state=='blocked' and tostring(normal.reason):find('Level',1,true),'a normal hover still respects the level requirement')
local preview=C.ItemResult('item:103',true)
assert(preview.state=='busy','a dungeon preview is computed although the level is not reached: '..tostring(preview.state))
MOCK.Advance(.6,.05)
assert(#calls==1 and calls[1].payload.items[1].ignoreLevel==true,'the PC is told to ignore the level for this candidate')
assert(C.ItemResult('item:103').state=='blocked','the preview does not leak into normal hovering')
-- batches ask for per-item answers: an item the PC cannot compute only marks itself, no single jobs follow
do
 for id=111,112 do items[id]={id=id,slot='head',name='Helm '..id,minLevel=1,stats={},statsComplete=true} end
 C.simRevision=C.simRevision+1;calls={}
 local a,b=C.ItemResult('item:111'),C.ItemResult('item:112');MOCK.Advance(.6,.05)
 assert(#calls==1 and calls[1].payload.partial==true and #calls[1].payload.items==2,'batch is sent as partial')
 calls[1].cb({baselineDps=100,candidates={{pct=103,dps=103},{error='Item 112: Basis-Waffenschaden fehlt',pct=0,dps=0}}})
 assert(a.state=='ok' and math.abs(a.pct-3)<1e-9,'the good item is computed')
 assert(b.state=='unmodeled' and tostring(b.reason):find('Waffenschaden',1,true),'the bad item carries its own reason: '..tostring(b.reason))
 assert(#calls==1,'no single follow-up jobs for the good items')
end
-- an item whose data the client has not loaded is not sent; a failed item is not asked again at once
do
 items[130]={id=130,slot='mainhand',name='Stone Dagger',minLevel=1,stats={},statsComplete=false,itemClass=2,weaponClass=2,itemSubclass=15,weaponSubclass=15}
 C.simRevision=C.simRevision+1;calls={};C.failedItems={}
 local e=C.ItemResult('item:130');MOCK.Advance(.6,.05)
 assert(#calls==1 and calls[1].payload.items[1].snapshot==nil,'the lean candidate goes first')
 calls[1].cb({baselineDps=100,candidates={{need=true,pct=0,dps=0}}})
 assert(e.state=='unmodeled' and tostring(e.reason):find('nicht geladen',1,true),'incomplete data: not sent in full, marked: '..tostring(e.state)..' '..tostring(e.reason))
 assert(#calls==1,'no resend with a snapshot that the PC would only refuse')
 -- the failure is remembered across a state change
 C.simRevision=C.simRevision+1
 local again=C.ItemResult('item:130')
 assert(again.state=='unmodeled' and #calls==1,'not asked again right away')
end
io.write('item batch tests passed ('..#calls..' jobs for 30 items)\n')
