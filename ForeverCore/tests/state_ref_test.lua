-- The character state is sent once; later jobs refer to it by key. An unknown key makes the addon resend it.
local root=assert(arg[1]);dofile(root..'/_dev/harness/wowmock.lua');dofile(root..'/_dev/harness/gameapi.lua')
local function loadAddon(addon)
 for line in io.lines(root..'/'..addon..'/'..addon..'.toc')do
  local file=line:gsub(string.char(13),''):gsub(string.char(92),'/'):match('^%s*([^#].-%.lua)%s*$')
  if file then assert(loadfile(root..'/'..addon..'/'..file))(addon,{})end
 end
end
loadAddon('ForeverSimBridge');loadAddon('ForeverCoreBridge')
UnitLevel=function()return 20 end
MOCK.Fire('PLAYER_LOGIN');MOCK.Advance(.5,.05)
local C=ForeverCoreClient;local P=FUSLive
C.engineRevision='rev-test'
P.capture=function()return{class='mage',level=20,faction='Horde',equipped={},spells={},talents={},buffs={x=1}}end
P.normalizeSnapshot=function(s)return{class='mage',level=20,faction='Horde',equipped={}}end
C.Say=function()end
local function settle()C.pending=nil;C.queue={};C.stateKnown=nil end
C.stateRefOK=true
settle()
-- a reply the "PC" sends for whatever job is pending
local replyStatus,replyMessage='ok',nil
C_AddOns={LoadAddOn=function()
 local p=C.pending;if not p then return false end
 ForeverCore_Reply={schema=3,session=p.session or C.session,sequence=p.sequence,revision=p.revision,kind=p.kind,status=replyStatus,message=replyMessage,result={baselineDps=1,candidates={}}}
 return true
end}
local function run(label)
 assert(C.Request('rotation',{},function()end),label..': request accepted')
 MOCK.Advance(.2,.05)
 assert(C.pending,label..': job pending')
 return C.pending
end
local first=run('first')
assert(first.message:find('"state":',1,true) and first.message:find('"stateKey":',1,true),'the first job carries the full state and its key')
local sizeFirst=#first.message
MOCK.Advance(6,.1)
assert(C.pending==nil and C.stateKnown==first.stateKey,'the PC confirmed the state: '..tostring(C.stateKnown))
local second=run('second')
assert(not second.message:find('"state":',1,true) and second.message:find('"stateKey":',1,true),'the second job refers to the state by key')
assert(#second.message<sizeFirst,'the reference job is smaller')
-- the PC forgot the state: the addon resends it in full
replyStatus,replyMessage='error','STATE_UNKNOWN: Zustand nicht gespeichert'
MOCK.Advance(6,.1)
replyStatus,replyMessage='ok',nil
assert(C.stateKnown==nil,'the state is no longer assumed to be known')
MOCK.Advance(.3,.05)
local again=C.pending
assert(again and again.kind=='rotation' and again.message:find('"state":',1,true),'the job was queued again with the full state')
MOCK.Advance(6,.1)
assert(C.stateKnown~=nil,'known again after the full state was accepted')
-- a changed character state needs a new full state
C.simRevision=C.simRevision+1
P.capture=function()return{class='mage',level=21,faction='Horde',equipped={},spells={},talents={}}end
UnitLevel=function()return 21 end
local third=run('third')
assert(third.message:find('"state":',1,true),'a different state is sent in full')
-- export jobs always carry the full state (the file must stand on its own)
settle()
local gotExport
C.StoreExport=function(job,message)gotExport=message end
C.Request('item',{items={}},nil,{export=true});C.stateKnown=nil
MOCK.Advance(.3,.05)
assert(gotExport and gotExport:find('"state":',1,true),'export keeps the full state')
-- an export is not stored while the hunter quiver is unreadable: it waits and tries again
do
 local quiver='unreadable'
 local capKeep=P.capture
 P.capture=function()local snap=capKeep();snap.hunter={quiver={status=quiver}};return snap end
 C.Capture=function()return{sim={class='hunter',level=20,hunter={quiver={status=quiver}}}}end
 gotExport=nil;settle()
 C.Request('item',{items={}},nil,{export=true})
 MOCK.Advance(1,.1)
 assert(gotExport==nil,'nothing is stored while the quiver is unreadable')
 quiver='ok'
 MOCK.Advance(4,.1)
 assert(gotExport and gotExport:find('"ok"',1,true),'stored once the quiver is readable')
 P.capture=capKeep
end
-- worn items that are not readable yet: the job waits instead of failing on the PC
do
 local worn={{id=1383,name='Stone Tomahawk',itemClass=2,statsComplete=false}}
 C.Capture=function()return{sim={class='hunter',level=20,equipped=worn,hunter={quiver={status='ok'}}}}end
 gotExport=nil;settle();C.stateRefOK=false
 local seq0=C.sequence
 assert(C.Request('rotation',{},function()end))
 MOCK.Advance(1,.1)
 assert(C.sequence==seq0,'no job is sent while a worn item is unreadable')
 worn[1].statsComplete=true;worn[1].weapon={min=3,max=5,speed=2}
 MOCK.Advance(5,.1)
 assert(C.sequence>seq0,'the job goes out once the item data is there')
 settle()
end
-- nothing is painted at login: the first real job of the session is preceded by exactly one ping
do
 local kinds={};local keepSay=C.Say
 C.Say=function(t)local k=tostring(t):match('^Berechnung: (%a+)');if k then kinds[#kinds+1]=k end end
 C.Capture=function()return{sim={class='hunter',level=20,equipped={},hunter={quiver={status='ok'}}}}end
 settle();C.needPing=true;C.stateRefOK=false
 MOCK.Advance(2,.1)
 assert(#kinds==0,'no ping without a job: '..table.concat(kinds,','))
 assert(C.Request('rotation',{},function()end));MOCK.Advance(8,.1)
 assert(kinds[1]=='ping' and kinds[2]=='rotation','a ping first, then the job: '..table.concat(kinds,','))
 assert(C.Request('rotation',{},function()end));MOCK.Advance(8,.1)
 assert(#kinds==3 and kinds[3]=='rotation','later jobs need no new ping: '..table.concat(kinds,','))
 C.Say=keepSay
end
-- after /reload the addon remembers what the running ForeverCore.exe knows: no ping, no state transfer
do
 ForeverCoreBridgeDB.pixelTuned={cell=1,style='low'}
 ForeverCoreBridgeDB.stateRefOK=true;ForeverCoreBridgeDB.stateKnown='K-persisted'
 C.stateRefOK=false;C.stateKnown=nil;C.needPing=true
 MOCK.Fire('PLAYER_LOGIN')
 assert(C.stateRefOK==true and C.stateKnown=='K-persisted' and C.needPing==false,'login restores the knowledge of the PC: '..tostring(C.stateRefOK)..' '..tostring(C.stateKnown)..' '..tostring(C.needPing))
 -- a state that the PC no longer has is forgotten for good
 ForeverCoreBridgeDB.stateKnown=nil;C.stateKnown=nil
end
-- readiness for every class: hunter pet, warlock demon, quiver, ammunition, worn items
do
 local U=C.StateUnreadyReason
 assert(U({class='MAGE',equipped={}})==nil,'a mage without pet is ready')
 assert(U({class='HUNTER',hunter={quiver={status='none'},ammo={status='none'},pet={status='ok'}},petActive=true})==nil,'valid answers (none/ok) are ready')
 assert(tostring(U({hunter={quiver={status='unreadable'}}})):find('Koecher',1,true),'quiver')
 assert(tostring(U({hunter={ammo={status='unreadable'}}})):find('Munition',1,true),'ammunition')
 assert(tostring(U({petActive=true,hunter={pet={status='unreadable'}}})):find('Begleiter',1,true),'hunter pet')
 assert(U({petActive=false,hunter={pet={status='unreadable'}}})==nil,'no pet active: an unreadable pet does not matter')
 assert(tostring(U({petActive=true,petLive={status='unreadable'}})):find('Daemon',1,true),'warlock demon')
 assert(U({petActive=true,petLive={status='ok',mana=100}})==nil,'a readable demon is ready')
 local reason,ids=U({equipped={{id=5,name='Axe',itemClass=2}}})
 assert(tostring(reason):find('Axe',1,true) and ids[1]==5,'worn weapon without damage values')
 for _,class in ipairs({'WARRIOR','PALADIN','ROGUE','PRIEST','SHAMAN','MAGE','WARLOCK','DRUID'})do
  assert(U({class=class,equipped={{id=1,statsComplete=true}}})==nil,class..': nothing to wait for')
 end
end
-- an old ForeverCore.exe never gets references: the ping answer must announce support first
C.stateRefOK=false;C.pending=nil;C.queue={};C.stateKnown=nil
local old1=run('old exe 1');MOCK.Advance(6,.1)
local old2=run('old exe 2')
assert(old2.message:find('"state":',1,true),'without announced support the full state is always sent')
io.write('state reference tests passed\n')
