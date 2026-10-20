-- The "Rotation" tab of the ForeverSim window: builds, rotations of the selected build, priorities, HUD settings.
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
IsPlayerSpell=function()return true end
local C=ForeverCoreClient;local Sim=C.Sim;local UI=assert(ForeverSimUI);local HUD=assert(ForeverSimHUD)
C.queue={};C.pending=nil;C.Say=function()end
ForeverCoreBridgeDB.sim=nil;ForeverSimBridgeDB.hud=nil
local model=Sim.Model();local fire=model.talentTrees[2].talents
FUSLive.capture=function()return{class='mage',level=60,talents={{entries={}},{entries={{classKey=fire[1].key,rank=1}}},{entries={}}}}end
local jobs={}
C.Request=function(kind,payload,cb)jobs[#jobs+1]={kind=kind,payload=payload,cb=cb};return true end

UI.Window();UI.Open('rotation')
local S=UI.rotation
assert(S.left and S.mid and S.right and #MOCK.errors==0,'built: '..tostring(MOCK.errors[1]))
assert(S.rows[1].id=='live' and S.rows[1]:IsShown(),'the build in game is listed')
assert(S.dps:GetText()=='–','nothing calculated yet')
-- priorities: the simple list for a mage without a simulation
assert(S.prioTitle:GetText():find('EINFACHE',1,true) and S.prioRows[1] and S.prioRows[1]:IsShown(),'basic priority list: '..tostring(S.prioTitle:GetText()))
-- simulate
S.simulate.__scripts.OnClick(S.simulate)
assert(#jobs==1 and jobs[1].kind=='build-detail' and S.busy,'build-detail job sent')
Sim.Store().rotation=nil
jobs[1].cb({dps=1871.4,rotation='fire',rotations={{name='fire',dps=1871.4},{name='fire_lowrank',dps=1811},{name='frostfire',dps=1702}},spec='mage',duration=180,
 priority={{spellId=133},{spellId=2948,condition={['not']={val={auraIsActive={auraId={spellId=2948},sourceUnit={type='CurrentTarget'}}}}}},{spellId=116}},breakdown={},curve={}})
assert(not S.busy and S.dps:GetText()=='1.871,4','result: '..tostring(S.dps:GetText()))
assert(S.rotRows[1]:IsShown() and S.rotRows[3]:IsShown() and not(S.rotRows[4]and S.rotRows[4]:IsShown()),'three rotations listed')
assert(S.rotRows[1].delta:GetText()=='aktiv','the best rotation is the active one: '..tostring(S.rotRows[1].delta:GetText()))
assert(S.rotRows[2].delta:GetText()=='-3,2 %','difference to the best: '..tostring(S.rotRows[2].delta:GetText()))
assert(S.prioTitle:GetText():find('BESTE',1,true),'the simulated priority list is shown')
assert(S.prioRows[2].hint:GetText()=='Erneuern, wenn der Effekt fehlt' and S.prioRows[3].hint:GetText()=='sonst immer','priority hints: '..tostring(S.prioRows[2].hint:GetText()))
assert(Sim.Rotation() and Sim.Rotation().name=='fire','the active rotation is stored')
-- a failing job is reported
S.simulate.__scripts.OnClick(S.simulate);jobs[#jobs].cb(nil,'Keine Antwort')
assert(S.message:GetText()=='Keine Antwort' and not S.busy,'error shown')
-- refine hook
local tuned;UI.rotaTune=function(spec)tuned=spec end
S.refine.__scripts.OnClick(S.refine);assert(Sim.Store().refine==true)
S.simulate.__scripts.OnClick(S.simulate);jobs[#jobs].cb({dps=1800,rotation='fire',rotations={},priority={}})
assert(tuned and tuned.id=='live','"Eigene Rota verfeinern" calls the tuner after the comparison')
UI.rotaTune=nil
-- saved builds are selectable
local b=Sim.AddBuild('Feuer PvE',Sim.LiveEntries(),'own');MOCK.Advance(.1,.05)
local row;for _,r in ipairs(S.rows)do if r:IsShown() and r.id==b.id then row=r end end
assert(row,'saved build listed');row.__scripts.OnClick(row);assert(S.sel==b.id and S.rotTitle:GetText():find('FEUER PVE',1,true),'selection: '..tostring(S.rotTitle:GetText()))
assert(S.rotEmpty:GetText()~='','no rotations yet for this build')

-- HUD settings -------------------------------------------------------------------------------------------------------
local cfg=HUD.Config()
local function check(label)for _,c in ipairs(S.checks)do if c.text:GetText()==label then return c end end;error('no check '..label)end
check('Tasten anzeigen').__scripts.OnClick(check('Tasten anzeigen'));assert(cfg.showKeys==false,'setting stored')
check('Procs einschieben').__scripts.OnClick(check('Procs einschieben'));assert(cfg.procs==false)
check('Verzögerung anzeigen').__scripts.OnClick(check('Verzögerung anzeigen'));assert(cfg.showDelay==false)
local stepper=S.steppers[3];assert(stepper.text:GetText()=='Zauber in der Reihe')
local q=cfg.queue;stepper.plus.__scripts.OnClick(stepper.plus);assert(cfg.queue==math.min(5,q+1),'queue +1')
for i=1,10 do stepper.plus.__scripts.OnClick(stepper.plus)end;assert(cfg.queue==5,'limited to 5')
for i=1,10 do stepper.minus.__scripts.OnClick(stepper.minus)end;assert(cfg.queue==1,'limited to 1')
local sc=S.steppers[1];local before=cfg.scale;sc.plus.__scripts.OnClick(sc.plus);assert(cfg.scale>before and HUD.frame:GetScale()>before-.001,'size applies to the HUD')
S.procTest.__scripts.OnClick(S.procTest);MOCK.Advance(.7,.05);assert(HUD.frame:IsShown(),'the proc demo shows the HUD')
MOCK.Advance(8,.1)
S.move.__scripts.OnClick(S.move);assert(cfg.locked==false and S.move.label:GetText()=='HUD fixieren','unlocked')
S.move.__scripts.OnClick(S.move);assert(cfg.locked==true)
S.reset.__scripts.OnClick(S.reset)

-- below level 50 only the HUD part is there ----------------------------------------------------------------------------
level=30;UI.rotationRefresh()
assert(not S.simBox:IsShown() and S.lockedBox:IsShown() and S.hudPanel:IsShown() and not S.left:IsShown(),'level 30: notice and HUD settings only')
assert(S.prioRows[1]:IsShown(),'the simple rotation is still listed')
level=60;UI.rotationRefresh();assert(S.simBox:IsShown() and not S.lockedBox:IsShown())
assert(#MOCK.errors==0,'no errors: '..tostring(MOCK.errors[1]))
for tag,n in pairs(MOCK.unknownMethods)do error('unknown widget method '..tag..' x'..n)end
io.write('rotation tab ok\n')
