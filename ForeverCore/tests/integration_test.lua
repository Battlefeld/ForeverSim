local root=assert(arg[1]);dofile(root..'/_dev/harness/wowmock.lua');dofile(root..'/_dev/harness/gameapi.lua')
local function loadAddon(addon)
 local ns={}
 for line in io.lines(root..'/'..addon..'/'..addon..'.toc')do
  local file=line:gsub('\r',''):gsub('\\','/'):match('^%s*([^#].-%.lua)%s*$')
  if file then assert(loadfile(root..'/'..addon..'/'..file))(addon,ns)end
 end
 return ns
end
loadAddon('ForeverSimBridge');loadAddon('ForeverCoreBridge')
MOCK.Fire('PLAYER_LOGIN');MOCK.Advance(.2,.05)
local C=ForeverCoreClient;ForeverCoreBridgeDB.enabled=true;C.InstallAdapters();C.revision=1
local s=C.Capture('route');assert(s.level==20 and s.class=='WARLOCK','snapshot mismatch')
-- Item jobs still carry the live character, talents included: every item comparison depends on them.
local itemSnapshot=C.Capture('item')
assert(itemSnapshot.sim and itemSnapshot.sim.level==20,'item jobs must capture live simulation data')
assert(type(itemSnapshot.sim.talents)=='table','talents must still be read for item comparisons')
assert(type(itemSnapshot.sim.unspentTalentPoints)=='number','talent point budget must be available to Engine')
assert(C.ItemCandidate({id=9001,slot='mainhand'},'item:9001').slot==14,'item slot alias broken')
assert(C.ItemCandidate({id=9001,slot='HeadSlot'}).slot==0,'equipped slot alias broken')
local called=false;FUSLive.enqueue(function()called=true end,function()end);assert(not called,'legacy combat engine executed')
local item=FUSLive.itemScore.Get(MOCK.link(9001));assert(not item or item.state=='busy' or item.state=='unmodeled','low-level item must dispatch or explain unavailability')
-- /fc sim reports a plain baseline number.
C.ApplySim({engine='Engine Go',baselineDps=100,dps=101,pct=101,candidates={}})
assert(C.lastSim and C.lastSim.dps==101,'baseline result not kept')

-- The old ForeverSim window, rotation and talent features are gone, and so are their entry points.
local P=FUSLive
for _,gone in ipairs({'app','dashboard','dashboardUI','shell','actions','rotationHUD','talentBuild','talentPlanner','leveling',
                      'analysisUI','traceUI','encounterUI','combatAudit','targetHealth','optimizeNow','tuneRotation','talentTreeLayouts','XNPresets'})do
 assert(P[gone]==nil,'removed module is still there: '..gone)
end
assert(C.RecommendTalents==nil and C.ShowResult==nil,'removed ForeverCore talent/result helpers are still there')
for _,cmd in ipairs({'FOREVERSIMDASH','FOREVERSIMTALENTPLAN'})do assert(SlashCmdList[cmd]==nil,'removed command still registered: '..cmd)end
-- /fc opens the ForeverCore overview; the former window commands answer without errors.
SlashCmdList.FOREVERCORE('')
assert(_G.ForeverCoreMainWindow and _G.ForeverCoreMainWindow:IsShown(),'/fc did not open the overview')
for _,cmd in ipairs({'gear','talents','rotation','quests','dungeons','advanced','leveling'})do SlashCmdList.FOREVERCORE(cmd)end
for _,cmd in ipairs({'','optimize','hud','leveling','audit','analysis','encounter','status','class'})do SlashCmdList.FOREVERSIMBRIDGE(cmd)end
-- /fc test runs against the mocked client without errors and stores its result.
SlashCmdList.FOREVERCORE('test');assert(ForeverCoreBridgeDB.diagnose and #ForeverCoreBridgeDB.diagnose.lines>3,'diagnose')
for _,e in ipairs(MOCK.errors)do io.stderr:write(e.msg..'\n')end
assert(#MOCK.errors==0,'addon integration errors')
io.write('addon integration tests passed\n')
