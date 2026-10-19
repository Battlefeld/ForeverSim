-- Every page of the ForeverSim window and every /fsim command still opens without a Lua error after the
-- legacy modules (scenario studio, stat weights, insights, release workspace, route bridge, dungeon pre-calculation,
-- notes) were removed. Rotation, talents, trace, audit, benchmark and dungeons stay.
local root=assert(arg[1]);dofile(root..'/_dev/harness/wowmock.lua');dofile(root..'/_dev/harness/gameapi.lua')
local function loadAddon(addon)
 for line in io.lines(root..'/'..addon..'/'..addon..'.toc')do
  local file=line:gsub(string.char(13),''):gsub(string.char(92),'/'):match('^%s*([^#].-%.lua)%s*$')
  if file then
   local f=io.open(root..'/'..addon..'/'..file,'r');assert(f,'the toc names a file that does not exist: '..addon..'/'..file);f:close()
   assert(loadfile(root..'/'..addon..'/'..file))(addon,{})
  end
 end
end
loadAddon('ForeverSimBridge');loadAddon('ForeverCoreBridge')
UnitLevel=function()return 20 end
MOCK.Fire('PLAYER_LOGIN');MOCK.Advance(1,.1)
local P=FUSLive
for _,gone in ipairs({'scenarioStudio','statWeightsUI','statWeights60','insightsUI','releaseWorkspace','routeBridge','dungeonPrecalc'})do
 assert(P[gone]==nil,'removed module is gone: '..gone)
end
assert(P.app and P.app.Open,'the window is there')
local routes={{'overview'},{'talents'},{'rotation'},{'gear'},{'gear','weights'},{'gear','plan'},{'dungeons'},{'benchmark'},{'benchmark','encounter'},
 {'benchmark','leveling'},{'analysis'},{'analysis','trace'},{'analysis','audit'},{'analysis','scenario'},{'diagnostics'},{'diagnostics','spells'}}
for _,r in ipairs(routes)do
 local before=#MOCK.errors
 local ok,err=pcall(P.app.Open,r[1],r[2])
 assert(r[1]=='overview' or r[1]=='talents' or r[1]=='rotation' or (P.shell.active and P.shell.active:IsShown()),'the page is really built: '..r[1])
 assert(ok,'route '..r[1]..'/'..tostring(r[2])..': '..tostring(err))
 MOCK.Advance(.2,.1)
 assert(#MOCK.errors==before,'route '..r[1]..'/'..tostring(r[2])..' raised: '..tostring(MOCK.errors[#MOCK.errors]and MOCK.errors[#MOCK.errors].msg))
end
for _,cmd in ipairs({'','talents','analysis','audit','gear','dungeon','encounter','help','weights','scenario'})do
 local before=#MOCK.errors
 local ok,err=pcall(SlashCmdList.FOREVERSIMDASH,cmd)
 assert(ok,'/fsim '..cmd..': '..tostring(err))
 MOCK.Advance(.2,.1)
 assert(#MOCK.errors==before,'/fsim '..cmd..' raised: '..tostring(MOCK.errors[#MOCK.errors]and MOCK.errors[#MOCK.errors].msg))
end
for _,e in ipairs(MOCK.errors)do error('script error: '..tostring(e.kind)..' '..tostring(e.msg))end
io.write('window routes tests passed\n')
