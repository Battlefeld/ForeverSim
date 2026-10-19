-- Pixel strip contrast: both levels must stay on the correct side of the PC's R+G+B >= 384 threshold.
local root=assert(arg[1]);dofile(root..'/_dev/harness/wowmock.lua');dofile(root..'/_dev/harness/gameapi.lua')
for _,file in ipairs({'Protocol.lua','Bridge.lua','Adapters.lua'})do assert(loadfile(root..'/ForeverCoreBridge/'..file))('ForeverCoreBridge',{})end
local C=ForeverCoreClient
MOCK.Fire('PLAYER_LOGIN');C.queue={};C.pending=nil
assert(C.PixelStyle()=='low','default must be the low contrast strip')
local regions=rawget(C.pixelFrame,'__regions') or {}
assert(#regions>=C.protocol.columns*C.protocol.rows,'pixel textures not found: '..#regions)
local seen={}
for _,r in ipairs(regions)do rawset(r,'SetColorTexture',function(self,cr,cg,cb,ca)seen[#seen+1]={cr,cg,cb,ca}end)end
assert(C.Request('ping'));MOCK.Advance(.5,.05)
assert(#seen>=C.protocol.columns*C.protocol.rows,'strip was not painted: '..#seen)
local lo,hi=1,0
for _,c in ipairs(seen)do local v=c[1];assert(c[2]==v and c[3]==v and c[4]==1,'grey with full alpha required');if v<lo then lo=v end;if v>hi then hi=v end end
assert(hi>lo,'both levels must occur');
local function sum(v)return math.floor(v*255+.5)*3 end
assert(sum(lo)<384-30 and sum(hi)>=384+30,'levels too close to the decision threshold: '..sum(lo)..'/'..sum(hi))
assert(hi-lo<=0.2,'low style should be low contrast')
-- fallbacks after timeouts, in order: frame time (0.10 -> 0.18 s), then contrast, then (below) geometry
assert(math.abs(C.FrameSeconds()-.10)<1e-9,'default frame time is 0.10 s')
C.pending.elapsed=181;MOCK.Advance(.1,.05)
assert(math.abs(C.FrameSeconds()-.18)<1e-9 and C.PixelStyle()=='low','first timeout restores the slow frame time only')
assert(C.Request('ping'));MOCK.Advance(.5,.05)
C.pending.elapsed=181;MOCK.Advance(.1,.05)
assert(C.PixelStyle()=='normal','timeout must fall back to normal contrast')
-- geometry: cell size 1..8, validated, persisted, reverted by a second timeout
local P=C.protocol
assert(C.ApplyPixelCell(3)==true and P.cell==3 and ForeverCoreBridgeDB.pixelCell==3,'cell 3 not applied')
assert(select(1,C.ApplyPixelCell(9))==false and select(1,C.ApplyPixelCell(0))==false and select(1,C.ApplyPixelCell('x'))==false,'invalid sizes must be rejected')
assert(P.cell==3,'rejected size must not change the strip')
SlashCmdList.FOREVERCORE('pixel size 5');assert(P.cell==5,'slash command: '..tostring(P.cell))
assert(C.Request('ping'));MOCK.Advance(.5,.05)
C.pending.elapsed=181;MOCK.Advance(.1,.05)   -- style already normal: now the geometry falls back
assert(P.cell==2,'second timeout must restore cell size 2: '..tostring(P.cell))
io.write('pixel style tests passed (levels '..lo..'/'..hi..')\n')
