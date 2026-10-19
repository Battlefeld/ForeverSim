local root=assert(arg[1]);dofile(root..'/_dev/harness/wowmock.lua');dofile(root..'/_dev/harness/gameapi.lua')
for _,file in ipairs({'Protocol.lua','Bridge.lua','Adapters.lua','AnalysisAdapters.lua'})do assert(loadfile(root..'/ForeverCoreBridge/'..file))('ForeverCoreBridge',{})end
local C=ForeverCoreClient
assert(C.crc('123456789')==3421780262,'CRC32 mismatch')
assert(#C.frame(1,0,1,'ä中')==256,'frame length')
local test=C.json({text='"\n\0',quest=783,done=true});assert(test:find('\\u0000',1,true),'NUL not escaped')
local marker={};local old=issecretvalue;issecretvalue=function(v)return v==marker end
assert(C.clean({safe=4,secret=marker}).secret==nil,'secret serialized');issecretvalue=old
MOCK.Fire('PLAYER_LOGIN');assert(C.pixelFrame,'pixels not made');assert(ForeverCoreBridgeDB.enabled==true,'fresh install not enabled')
assert(C.protocol.columns==512 and C.protocol.rows==4 and C.protocol.cell>=1 and C.protocol.cell<=3,'transport must use thin strip')
assert(not C.pixelFrame:IsShown(),'idle pixel strip must stay hidden')
assert(C.queue[1] and C.queue[1].kind=='ping','automatic startup ping missing')
C.queue={};ForeverCoreBridgeDB.enabled=false
C.Capture=function()error('ping must not capture character or quest data')end
assert(C.Request('ping'));MOCK.Advance(.3,.05);assert(C.pending and C.pending.kind=='ping','request missing')
assert(C.pending.frames==1,'ping must fit one frame')
assert(C.pixelFrame:IsShown(),'pixel strip must be visible during transmission')
local p=C.pending
C_AddOns.LoadAddOn=function()ForeverCore_Reply={schema=3,session='wrong',sequence=p.sequence,revision=p.revision,kind='ping',status='ok'};return true end
MOCK.Advance(2.1,.05);assert(C.pending,'wrong session accepted')
C_AddOns.LoadAddOn=function()ForeverCore_Reply={schema=3,session=C.session,sequence=p.sequence,revision=p.revision,kind='ping',status='ok',result={version='test'}};return true end
MOCK.Advance(2.1,.05);assert(not C.pending,'correct reply refused')
assert(not C.pixelFrame:IsShown(),'pixel strip must hide immediately after reply')
C.Capture=function()return{sim={class='WARRIOR',level=10},knownQuests='route-only-marker'}end
local accepted=false;C.Request('sim',{},function(result)accepted=result~=nil end);MOCK.Advance(.2,.05);local pending=C.pending;assert(not pending.message:find('route-only-marker',1,true),'quest database sent to SIM');C.MarkChanged()
C_AddOns.LoadAddOn=function()ForeverCore_Reply={schema=3,session=C.session,sequence=pending.sequence,revision=pending.revision,kind='sim',status='ok',result={dps=1}};return true end
MOCK.Advance(2.1,.05);assert(accepted,'quest progress incorrectly discarded SIM result')
local receivedIssue
C.Request('sim',{},function(_,issue)receivedIssue=issue end);MOCK.Advance(.2,.05)
pending=C.pending;C.MarkChanged()
C_AddOns.LoadAddOn=function()ForeverCore_Reply={schema=3,session=C.session,sequence=pending.sequence,revision=pending.revision,kind='sim',status='error',message='Munition konnte im Spiel nicht gelesen werden'};return true end
MOCK.Advance(2.1,.05)
assert(receivedIssue=='Munition konnte im Spiel nicht gelesen werden','real error hidden by stale revision')
-- Only actual SIM-relevant character changes may invalidate a running result.
local invalidated=false
C.Request('sim',{},function(result)invalidated=result~=nil end);MOCK.Advance(.2,.05)
pending=C.pending;C.simRevision=C.simRevision+1
C_AddOns.LoadAddOn=function()ForeverCore_Reply={schema=3,session=C.session,sequence=pending.sequence,revision=pending.revision,kind='sim',status='ok',result={dps=1}};return true end
MOCK.Advance(2.1,.05)
assert(not invalidated,'outdated SIM result accepted after character change')

-- All everyday features must be reachable from one /fc command.
local oldLive=FUSLive
local opened={}
FUSLive={app={Open=function(section)opened[#opened+1]=section end}}
for _,case in ipairs({{'','overview'},{'gear','gear'},{'talents','talents'},
                       {'rotation','rotation'},{'quests','quests'},{'dungeons','dungeons'}})do
 SlashCmdList.FOREVERCORE(case[1])
 assert(opened[#opened]==case[2],'/fc '..case[1]..' did not open '..case[2])
end
FUSLive=oldLive
assert(#MOCK.errors==0,MOCK.errors[1]and MOCK.errors[1].msg or'')
print=io.write;print('bridge tests passed\n')
