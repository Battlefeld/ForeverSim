-- Regression: noisy events must not cause an endless request/discard loop.
local root=assert(arg[1]);dofile(root..'/_dev/harness/wowmock.lua');dofile(root..'/_dev/harness/gameapi.lua')
for _,file in ipairs({'Protocol.lua','Bridge.lua','Adapters.lua','AnalysisAdapters.lua'})do assert(loadfile(root..'/ForeverCoreBridge/'..file))('ForeverCoreBridge',{})end
local C=ForeverCoreClient
MOCK.Fire('PLAYER_LOGIN')
C.queue={};C.pending=nil
local count={}
local orig=C.Request
C.Request=function(kind,...)count[kind]=(count[kind] or 0)+1;return orig(kind,...)end
-- Without a route addon the simulator must stay completely quiet, whatever the game does.
for t=1,240 do
 MOCK.Fire('QUEST_LOG_UPDATE');MOCK.Fire('BAG_UPDATE_DELAYED');MOCK.Fire('PET_UI_UPDATE')
 MOCK.Advance(.5,.05)
end
local quiet=0;for _,n in pairs(count)do quiet=quiet+n end
assert(quiet==0,'automatic requests without a route addon: '..quiet)
-- With a route addon present (it exports _G.ForeverCoreFDQ) events produce a bounded number of route jobs.
_G.ForeverCoreFDQ={}
C.queue={};C.pending=nil;for k in pairs(count)do count[k]=nil end
-- 2 minutes of game time: quest log / bag / pet events every half second.
for t=1,240 do
 MOCK.Fire('QUEST_LOG_UPDATE');MOCK.Fire('BAG_UPDATE_DELAYED');MOCK.Fire('PET_UI_UPDATE')
 MOCK.Advance(.5,.05)
end
local total=0;for _,n in pairs(count)do total=total+n end
assert(total>=1,'refresh starved by constant events')
assert(total<=25,'request storm: '..total..' auto requests in 120s')
-- /fc off must stop everything
SlashCmdList.FOREVERCORE('off');C.queue={};C.pending=nil
for k in pairs(count)do count[k]=0 end
for t=1,40 do MOCK.Fire('QUEST_LOG_UPDATE');MOCK.Advance(.5,.05)end
local after=0;for _,n in pairs(count)do after=after+n end
assert(after==0,'requests issued while disabled: '..after)
io.write('request storm tests passed ('..total..' requests in 120s)\n')
