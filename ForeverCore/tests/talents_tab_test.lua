-- The "Talente" tab of the ForeverSim window: builds list, trees, editing, simulating, specs, prompts.
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
local C=ForeverCoreClient;local Sim=C.Sim;local UI=assert(ForeverSimUI)
C.queue={};C.pending=nil;C.Say=function()end
ForeverCoreBridgeDB.sim=nil
local model=Sim.Model();local fire=model.talentTrees[2].talents
-- the character plays a few fire talents
local liveTalents={{entries={}},{entries={{classKey=fire[1].key,rank=1}}},{entries={}}}
FUSLive.capture=function()return{class='mage',level=60,talents=liveTalents}end
local jobs={}
C.Request=function(kind,payload,cb,opts)jobs[#jobs+1]={kind=kind,payload=payload,cb=cb};return true end

-- formatting ----------------------------------------------------------------------------------------------------
assert(UI.FormatDps(1842.6)=='1.843' and UI.FormatDps(999)=='999' and UI.FormatDps(1234567)=='1.234.567','dps: '..UI.FormatDps(1842.6))
assert(UI.FormatDps(1842.64,1)=='1.842,6','dps with a decimal: '..UI.FormatDps(1842.64,1))
assert(UI.FormatPct(12.34)=='+12,3 %' and UI.FormatPct(-3.04)=='-3,0 %' and UI.FormatPct(0)=='+0,0 %')

-- the tab is locked below level 60 (a fresh window shows a notice) ---------------------------------------------------
local win=UI.Window()
UI.Open('talents')
assert(win:IsShown() and #MOCK.errors==0,'window opens with the talents tab: '..tostring(MOCK.errors[1]))
local S=UI.talents
assert(S.left and S.mid and S.right and not S.locked,'built at level 60')
assert(#S.rows>=1 and S.rows[1].id=='live' and S.rows[1]:IsShown(),'the first row is the build in game')
assert(S.nodes[2] and next(S.nodes[2]),'the fire tree has nodes')
assert(S.points:GetText()=='Punkte 1 / 51','points: '..tostring(S.points:GetText()))
assert(S.apply and not S.apply:IsShown(),'no apply button without a better spec')
-- presets were requested when the tab was shown
local pj;for _,j in ipairs(jobs)do if j.kind=='presets'then pj=j end end
assert(pj,'presets job sent')
pj.cb({engineRevision='eng-1',class='mage',talents={
 {name='Arcane DPS',talentsString='a',valid=true,tree=1,entries={{tree=1,row=0,col=1,rank=5}}},
 {name='Fire DPS',talentsString='f',valid=true,tree=2,entries={{tree=2,row=0,col=0,rank=2}}},
 {name='Frost DPS',talentsString='z',valid=true,tree=3,entries={}},
},gear={{name='Pre-BiS',items={}}},builds={},layout={}})
local shown=0;for _,r in ipairs(S.rows)do if r:IsShown()then shown=shown+1 end end
assert(shown==4,'live + three top builds: '..shown)
assert(S.topHead:IsShown(),'MythicSim top heading')

-- selecting a top build shows it read-only ---------------------------------------------------------------------------
local topRow;for _,r in ipairs(S.rows)do if r:IsShown() and r.id=='top:2'then topRow=r end end
assert(topRow,'top:2 row')
topRow.__scripts.OnClick(topRow)
assert(S.sel=='top:2' and not S.editable)
local node;for _,b in pairs(S.nodes[2])do if b.r==fire[1].row and b.c==fire[1].column then node=b end end
assert(node and node.currentRank==2,'the top build has 2 points in the first fire talent')
node.__scripts.OnClick(node,'LeftButton');assert(Sim.Builds()[1]==nil,'a read-only build is not edited')

-- copy -> own build, editable ---------------------------------------------------------------------------------------
S.copy.__scripts.OnClick(S.copy)
local copy=Sim.Builds()[1];assert(copy and S.sel==copy.id,'copy created and selected: '..tostring(S.sel))
assert(S.editable and S.slotText:GetText()=="1 / 10")
node.__scripts.OnClick(node,'LeftButton')
assert(Sim.Build(copy.id).entries,'build still there')
local function rankOf(id,t,r,c)for _,e in ipairs(Sim.Build(id).entries)do if e.t==t and e.r==r and e.c==c then return e.n end end return 0 end
local before=rankOf(copy.id,2,fire[1].row,fire[1].column)
node.__scripts.OnClick(node,'RightButton')
assert(rankOf(copy.id,2,fire[1].row,fire[1].column)==before-1,'right click removes a point')
node.__scripts.OnClick(node,'LeftButton')
assert(rankOf(copy.id,2,fire[1].row,fire[1].column)==before,'left click adds a point')
-- a rule violation is shown, not applied
local locked;for _,b in pairs(S.nodes[2])do if b.r>=3 and b.currentRank==0 then locked=b break end end
if locked then
 local n0=#Sim.Build(copy.id).entries
 locked.__scripts.OnClick(locked,'LeftButton')
 assert(#Sim.Build(copy.id).entries==n0 and S.message:GetText()~='','a talent that cannot be taken says why: '..tostring(S.message:GetText()))
end

-- rename, delete, import, share --------------------------------------------------------------------------------------
S.rename.__scripts.OnClick(S.rename)
local pr=assert(UI.Prompt('x','',nil))   -- the shared prompt window
pr:Hide()
S.rename.__scripts.OnClick(S.rename)
-- find the live prompt via its edit box: set the new name and press OK
local function prompt()for _,f in ipairs(MOCK.frames)do if f.edit and f.ok then return f end end end
local p=assert(prompt(),'prompt window exists');assert(p:IsShown() and p.edit:GetText()==copy.name,'rename prompt starts with the old name')
p.edit:SetText('Mein Feuer');p.ok.__scripts.OnClick(p.ok)
assert(Sim.Build(copy.id).name=='Mein Feuer' and not p:IsShown(),'renamed')
local text=Sim.Export(Sim.Build(copy.id).entries)
S.import.__scripts.OnClick(S.import)
p.edit:SetText('kaputt');p.ok.__scripts.OnClick(p.ok)
assert(#Sim.Builds()==1 and S.message:GetText()~='','a broken import is refused with a message')
S.import.__scripts.OnClick(S.import)
p.edit:SetText(text);p.ok.__scripts.OnClick(p.ok)
assert(#Sim.Builds()==2 and Sim.Builds()[2].source=='import','import adds a build')
S.sel=Sim.Builds()[2].id;UI.talentsRefresh()
S.delete.__scripts.OnClick(S.delete);assert(p:IsShown());p.ok.__scripts.OnClick(p.ok)
assert(#Sim.Builds()==1 and S.sel=='live','delete returns to the build in game')

-- simulate -----------------------------------------------------------------------------------------------------------
jobs={}
S.simulate.__scripts.OnClick(S.simulate)
assert(Sim.running and #jobs>=1,'the first step is sent')
-- answer every step the way ForeverCore does
local function answer(j)
 if j.kind=='presets'then j.cb({engineRevision='eng-1',class='mage',talents={},gear={},builds={},layout={}})
 elseif j.kind=='talent-compare'then
  local rows={};for i,b in ipairs(j.payload.builds)do rows[i]={id=b.id,dps=b.id=='live'and 1500.5 or 1000+100*i,rotation='fire',points={0,0,0}}end
  j.cb({builds=rows})
 elseif j.kind=='build-detail'then
  j.cb({dps=1500.5,rotation='fire',rotations={},spec='mage',duration=180,priority={{spellId=133}},
   breakdown={{spellId=133,label='Feuerball',pct=59},{spellId=116,pct=25},{rest=true,pct=16}},
   curve={{t=15,dps=1400,mana=-300},{t=60,dps=1480,mana=-800},{t=180,dps=1500,mana=-2500}}})
 end
end
local guard=0
while Sim.running and guard<20 do
 guard=guard+1
 local j=table.remove(jobs,1);if not j then break end
 answer(j)
end
assert(not Sim.running,'all steps done: '..guard)
assert(S.simulate and S.dps:GetText()=='1.500,5','result card: '..tostring(S.dps:GetText()))
assert(S.breakRows[1].frame:IsShown() and S.breakRows[3].name:GetText()=='Sonstiges','damage shares listed incl. rest: '..tostring(S.breakRows[3].name:GetText()))
assert(#MOCK.errors==0,'no errors: '..tostring(MOCK.errors[1]))

-- unreadable character --------------------------------------------------------------------------------------------------
FUSLive.capture=function()error('boom')end
UI.talentsRefresh();assert(#MOCK.errors==0,'an unreadable character does not break the tab: '..tostring(MOCK.errors[1]))
FUSLive.capture=function()return{class='mage',level=60,talents=liveTalents}end

-- levels below 60: a notice instead of the tab -------------------------------------------------------------------------------
level=55
local def;for _,t in ipairs(UI.Tabs())do if t.key=='talents'then def=t end end
local page=CreateFrame('Frame',nil,UIParent);local before=UI.talents.left
for k in pairs(UI.talents)do UI.talents[k]=nil end
def.build(page)
assert(UI.talents.locked and not UI.talents.left,'below level 60 only the notice is built')
assert(#MOCK.errors==0,'no errors: '..tostring(MOCK.errors[1]))
level=60;def.show(page)
assert(UI.talents.left and not UI.talents.locked,'reaching level 60 builds the tab')

for tag,n in pairs(MOCK.unknownMethods)do error('unknown widget method '..tag..' x'..n)end
io.write('talents tab ok\n')
