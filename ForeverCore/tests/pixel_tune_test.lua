-- Automatic pixel strip tuning: least noticeable variant first, stop at the first one the PC reads.
local root=assert(arg[1]);dofile(root..'/_dev/harness/wowmock.lua');dofile(root..'/_dev/harness/gameapi.lua')
local function fresh()
 for _,file in ipairs({'Protocol.lua','Bridge.lua','Adapters.lua','AnalysisAdapters.lua'})do assert(loadfile(root..'/ForeverCoreBridge/'..file))('ForeverCoreBridge',{})end
 ForeverCoreBridgeDB=nil;MOCK.Fire('PLAYER_LOGIN')
 return ForeverCoreClient
end
local C=fresh();local P=C.protocol
-- 1. first probe: smallest cell, low contrast
assert(C.tuning==1 and P.cell==1 and C.PixelStyle()=='low','first probe must be the least noticeable variant')
MOCK.Advance(.3,.05);assert(C.pending and C.pending.kind=='ping' and C.pending.tuning and C.pending.timeout==20,'probe must be a short ping')
local function timeout() C.pending.elapsed=C.pending.timeout+1;MOCK.Advance(.2,.05) end
-- 2. every timeout moves on to the next variant
timeout();MOCK.Advance(.3,.05);assert(C.tuning==2 and P.cell==2 and C.PixelStyle()=='low','second variant')
timeout();MOCK.Advance(.3,.05);assert(C.tuning==3 and P.cell==2 and C.PixelStyle()=='normal','third variant')
timeout();MOCK.Advance(.3,.05);assert(C.tuning==4 and P.cell==3 and C.PixelStyle()=='normal','fourth variant')
-- 3. nothing worked: defaults, no stored result
timeout();MOCK.Advance(.3,.05)
assert(C.tuning==nil and P.cell==2 and C.PixelStyle()=='low' and not ForeverCoreBridgeDB.pixelTuned,'failed tuning must restore defaults and store nothing')
-- 4. success on the first variant is stored
C.pending=nil;C.queue={}
ForeverCoreBridgeDB.pixelTuned=nil;SlashCmdList.FOREVERCORE('pixel auto');MOCK.Advance(.3,.05)
assert(C.tuning==1 and C.pending and C.pending.tuning,'pixel auto must restart tuning')
local cb=C.pending.callback;C.pending=nil;cb({engineRevision='rev-test'})
local t=ForeverCoreBridgeDB.pixelTuned
assert(t and t.cell==1 and t.style=='low' and C.tuning==nil,'successful variant not stored')
assert(C.engineRevision=='rev-test' and ForeverCoreBridgeDB.lastEngineRevision=='rev-test','ping result must still be processed')
-- 5. manual choices end tuning for good
SlashCmdList.FOREVERCORE('pixel size 4');assert(ForeverCoreBridgeDB.pixelTuned.manual==true and P.cell==4,'manual size')
io.write('pixel tune tests passed\n')
