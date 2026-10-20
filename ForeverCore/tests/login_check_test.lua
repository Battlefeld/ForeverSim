-- The check after the login: when a new calculation is due and what happens.
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
local bags={}
C_Container.GetContainerNumSlots=function(bag)return bag==0 and 8 or 0 end
C_Container.GetContainerItemID=function(bag,slot)return bag==0 and bags[slot]or nil end
IsEquippableItem=function(id)return id<5000 end
local combat=false;InCombatLockdown=function()return combat end
MOCK.Fire('PLAYER_LOGIN');MOCK.Advance(.5,.05)
local C=ForeverCoreClient;C.SimCharacterContext=function()return C.SimCacheContext()end;local Sim=C.Sim;local UI=assert(ForeverSimUI)
C.queue={};C.pending=nil;C.Say=function()end
ForeverCoreBridgeDB.sim=nil
C.engineRevision='eng-1'
local ctx='ctx-1';C.SimCacheContext=function()return ctx end
local build='1.60.1.70338';local realBuildInfo=GetBuildInfo;GetBuildInfo=function()return'1.60.1',build:match('(%d+)$')end

-- bags: only equippable items count
bags={101,102,9999}
local seen=Sim.ScanBags();assert(seen[101] and seen[102] and not seen[9999],'junk is not counted')
-- the first time
local r=Sim.RecalcReasons();assert(#r==1 and r[1]=='Erste Berechnung')
level=30;assert(#Sim.RecalcReasons()==0,'below level 50 there is nothing to calculate');level=60
-- a finished run is remembered
local jobs={}
C.Request=function(kind,payload,cb)jobs[#jobs+1]={kind=kind,payload=payload,cb=cb};return true end
local function answerAll()
 local guard=0
 while #jobs>0 and guard<50 do guard=guard+1
  local j=table.remove(jobs,1)
  if j.kind=='presets'then j.cb({engineRevision='eng-1',class='mage',talents={},gear={},builds={},layout={}})
  elseif j.kind=='talent-compare'then local rows={};for i,b in ipairs(j.payload.builds)do rows[i]={id=b.id,dps=1500,rotation='fire',priority={{spellId=1}}}end;j.cb({builds=rows})
  elseif j.kind=='build-detail'then j.cb({dps=1500,rotation='fire',rotations={{name='fire',dps=1500}},priority={{spellId=1}},breakdown={},curve={}})
  else j.cb(nil,'unbekannt')end
 end
end
assert(Sim.RunAll({selected='live'}));answerAll()
local last=Sim.Store().lastRun;assert(last and last.engine=='eng-1' and last.level==60 and last.seen[101],'the run is remembered with the items')
assert(#Sim.RecalcReasons()==0,'nothing changed: nothing is due')
-- each reason on its own
C.engineRevision='eng-2';r=Sim.RecalcReasons();assert(#r==1 and r[1]=='Neue Engine-Version','engine: '..table.concat(r,','));C.engineRevision='eng-1'
build='1.60.2.70500';r=Sim.RecalcReasons();assert(#r==1 and r[1]=='Neuer Spielpatch','patch: '..table.concat(r,','));build='1.60.1.70338'
level=61;r=Sim.RecalcReasons();assert(r[1]=='Neue Stufe');level=60
ctx='ctx-2';r=Sim.RecalcReasons();assert(#r==1 and r[1]:find('Ausrüstung',1,true),'gear: '..table.concat(r,','));ctx='ctx-1'
bags={101,102,103,104,105};r=Sim.RecalcReasons();assert(#r==1 and r[1]=='3 neue Items','items: '..table.concat(r,','))
bags={101,102,103};r=Sim.RecalcReasons();assert(r[1]=='1 neues Item')
bags={101};assert(#Sim.RecalcReasons()==0,'fewer items are no reason')
-- several reasons at once
C.engineRevision='eng-2';build='1.60.2.70500';bags={101,102,777};r=Sim.RecalcReasons();assert(#r==3,'three reasons: '..table.concat(r,','))
-- setting
assert(Sim.AutoLogin()==true);Sim.AutoLogin(false);assert(Sim.AutoLogin()==false);Sim.AutoLogin(true)

-- the check after the login ---------------------------------------------------------------------------------------------------
UI.Window()
local connected=false
UI.Connected=function()return connected end
local state=UI.loginCheck;state.done=false;state.waited=0
local function simJobs()local n=0;for _,j in ipairs(jobs)do if j.kind=='presets'or j.kind=='talent-compare'or j.kind=='build-detail'then n=n+1 end end;return n end
-- not connected yet: nothing happens
MOCK.Fire('PLAYER_LOGIN');MOCK.Advance(20,.5)
assert(simJobs()==0 and not state.done,'waits for ForeverCore.exe')
connected=true;combat=true;MOCK.Advance(6,.5);assert(simJobs()==0,'not during a fight');combat=false
MOCK.Advance(3,.5)
assert(state.done and simJobs()>=1,'the calculation started')
local notice=_G.ForeverSimLoginNotice;assert(notice and notice:IsShown() and notice.title:GetText()=='ForeverSim rechnet neu','a notice says so')
assert(notice.reason:GetText():find('Neue Engine-Version',1,true) and notice.reason:GetText():find('Neuer Spielpatch',1,true),'it names the reasons: '..notice.reason:GetText())
assert(notice.status:GetText():find('Schritt',1,true),'progress: '..notice.status:GetText())
answerAll()
assert(notice.title:GetText()=='ForeverSim ist auf dem neuesten Stand' and not Sim.running,'done')
MOCK.Advance(9,.5);assert(not notice:IsShown(),'the notice goes away by itself')
assert(#Sim.RecalcReasons()==0,'afterwards nothing is due')
-- only once per login
bags={101,500,501};state.tick=0;MOCK.Advance(10,.5);assert(simJobs()==0,'no second calculation in the same session')
-- switched off
state.done=false;Sim.AutoLogin(false);UI.RunLoginCheck();assert(simJobs()==0 and state.done,'off: nothing');Sim.AutoLogin(true)
-- a failed run says so
state.done=false;UI.RunLoginCheck();local j;for i,x in ipairs(jobs)do if x.kind=='presets'or x.kind=='talent-compare'then j=table.remove(jobs,i)break end end;assert(j,'started again');j.cb(nil,'Keine Antwort')
assert(notice:IsShown() and notice.title:GetText()=='ForeverSim konnte nicht fertig rechnen' and notice.reason:GetText()=='Keine Antwort','failure shown')
-- the connection never comes: give up quietly
state.done=false;state.waited=0;connected=false;MOCK.Fire('PLAYER_LOGIN');jobs={};MOCK.Advance(200,1)
assert(state.done and simJobs()==0,'no connection: no calculation and no noise')
assert(#MOCK.errors==0,'no errors: '..tostring(MOCK.errors[1]))
for tag,n in pairs(MOCK.unknownMethods)do error('unknown widget method '..tag..' x'..n)end
io.write('login check ok\n')
