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
local talentSnapshot=C.Capture('talent-build')
assert(talentSnapshot.sim and talentSnapshot.sim.level==20,'talent-build must capture live simulation data')
assert(type(talentSnapshot.sim.spellRankFamilies)=='table','spell rank families must accompany the HUD request')
assert(type(talentSnapshot.sim.unspentTalentPoints)=='number','talent point budget must be available to MythicSim')
assert(C.ItemCandidate({id=9001,slot='mainhand'},'item:9001').slot==14,'item slot alias broken')
-- Native Core results update the normal dashboard/HUD without calling the Lua SIM.
local compile=FUSLive.compile;FUSLive.compile=function()error('local compiler used for Core result')end
-- The synthetic rotation must name a spell actually learned in the mock spellbook.
local knownSpell=talentSnapshot.sim.spells and talentSnapshot.sim.spells[1]
assert(knownSpell and knownSpell.id,'mock spellbook required for external HUD mapping')
C.ApplySim({engine='MythicSim Go',baselineDps=100,dps=101,pct=101,priority={{spellId=knownSpell.id}},candidates={}})
assert(FUSLive.app.state.rotation.result.dps==101,'Core DPS not in dashboard')
assert(FUSLive.lastRotation.engine=='MythicSim Go'and #FUSLive.lastRotation.choice.policies==1,'Core priority not in HUD')
FUSLive.compile=compile

assert(C.ItemCandidate({id=9001,slot='HeadSlot'}).slot==0,'equipped slot alias broken')
local called=false;FUSLive.enqueue(function()called=true end,function()end);assert(not called,'legacy combat engine executed')
local item=FUSLive.itemScore.Get(MOCK.link(9001));assert(not item or item.state=='busy' or item.state=='unmodeled','low-level item must dispatch or explain unavailability')

-- New UI entry points must dispatch to external jobs and consume their results.
local request=C.Request;local shown=C.ShowResult;local dispatched={}
C.Request=function(kind,payload,done)
 dispatched[kind]=payload
 if kind=='weights'then local rows={};for _,key in ipairs({'StatSpellDamage','StatSpellHitRating','StatSpellCritRating','StatSpellHasteRating','StatIntellect','StatAgility','StatStrength','StatAttackPower'})do rows[#rows+1]={key=key,perPoint=1}end;done({base=500,rows=rows,class='warlock',level=60})
 elseif kind=='item'then assert(payload.items[1].metadata,'item requirements missing');done({baselineDps=500,candidateDps=510,delta=10,percent=2})
 elseif kind=='talents'then done({base=500,cand=500,pct=0,comparison='MythicSim'})
 elseif kind=='analysis'then done({dps=500,actions={{actor='Test',damage=60000,casts=80,id={spellId=133}}}})
 else error('unexpected analysis job '..tostring(kind))end;return true
end
C.ShowResult=function(r)assert(r.actions,'analysis result missing')end
FUSLive.dashboard.RunWeights();assert(FUSLive.dashboard.state.weights.base==500,'dashboard weights not connected')
FUSLive.dashboard.CompareTalents();assert(dispatched.talents and FUSLive.dashboard.state.talentCompare.pct==0,'talents UI not connected')
FUSLive.dashboard.CheckGear();assert(not FUSLive.dashboard.state.gear.busy and FUSLive.dashboard.state.gear.done==FUSLive.dashboard.state.gear.total,'gear search did not finish')
FUSLive.dashboard.RunTrace();assert(dispatched.analysis and not FUSLive.dashboard.state.traceBusy,'analysis UI not connected')
C.Request=request;C.ShowResult=shown

-- One actual window and one talent planner, irrespective of the legacy command used.
SlashCmdList.FOREVERCORE('')
assert(FUSLive.dashboard.state.page=='overview','/fc did not open unified overview')
SlashCmdList.FOREVERCORE('gear')
assert(FUSLive.dashboard.state.page=='more' and FUSLive.app.state.ui.tab=='gear','/fc gear did not show real item comparison')
SlashCmdList.FOREVERCORE('talents')
assert(FUSLive.dashboard.state.page=='talents','/fc talents did not open shared talent tree')
SlashCmdList.FOREVERSIMTALENTPLAN()
assert(FUSLive.dashboard.state.page=='talents','legacy talents opened duplicate planner')
SlashCmdList.FOREVERCORE('quests')
assert(FUSLive.dashboard.state.page=='quests','/fc quests did not open unified quest tab')
-- /fc test runs against the mocked client without errors and stores its result.
SlashCmdList.FOREVERCORE('test');assert(ForeverCoreBridgeDB.diagnose and #ForeverCoreBridgeDB.diagnose.lines>3,'diagnose')
for _,e in ipairs(MOCK.errors)do io.stderr:write(e.msg..'\n')end
assert(#MOCK.errors==0,'addon integration errors')
io.write('addon integration tests passed\n')
