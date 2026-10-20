-- Tab "Rotation" (rotations from level 50; the HUD settings are there at every level): the builds on the left, the
-- rotations ForeverCore worked out for the selected build and the settings of the combat HUD in the middle, the result
-- and the priority list on the right. As in the Talente tab, everything shown comes from ForeverCoreClient.Sim.
ForeverSimUI=ForeverSimUI or{}
local UI=ForeverSimUI
local COLOR=UI.COLOR
local state={sel='live',rows={},rotRows={},prioRows={}}
UI.rotation=state

local function core()return ForeverCoreClient end
local function Sim()local c=core();return c and c.Sim or nil end
local function hud()return ForeverSimHUD end
local function say(text,color)
 if state.message then state.message:SetText(text or'');local c=color or COLOR.muted;state.message:SetTextColor(c[1],c[2],c[3],1)end
end
local function resultOf(id)local S=Sim();return S and S.Result(id)end
local function nameOf(id)
 local S=Sim();if id=='live'then return'Im Spiel'end
 local b=S.Build(id);if b then return b.name end
 for _,t in ipairs(S.TopBuilds())do if'top:'..t.tree==id then return t.name end end
 return tostring(id)
end

-- Left: the builds whose rotation can be looked at ---------------------------------------------------------------------
local function rowFrame(i)
 local r=state.rows[i];if r then return r end
 r=CreateFrame('Button',nil,state.left)
 r.box=UI.Box(r,{.06,.17,.34,.5},{.47,.63,.9,.22});r.box:SetAllPoints();r.box:EnableMouse(false)
 r.icon=UI.IconBox(r,28);r.icon:SetPoint('LEFT',r,'LEFT',6,0)
 r.name=UI.Text(r,13,COLOR.text,'body','LEFT');r.name:SetWordWrap(false)
 r.sub=UI.Text(r,11,COLOR.muted,'body','LEFT');r.sub:SetWordWrap(false)
 r.value=UI.Text(r,12,COLOR.text,'num','RIGHT')
 r:RegisterForClicks('LeftButtonUp');r:SetHighlightTexture('Interface\\Buttons\\WHITE8X8')
 local hl=r:GetHighlightTexture();if hl then hl:SetVertexColor(.4,.6,1,.12)end
 r:SetScript('OnClick',function(self)state.sel=self.id;UI.rotationRefresh()end)
 state.rows[i]=r;return r
end
local function layoutRows()
 local S=Sim();local list={}
 list[1]={id='live',name='Im Spiel',entries=state.live}
 for _,b in ipairs(S.Builds())do list[#list+1]={id=b.id,name=b.name,entries=b.entries}end
 local own=#list
 for _,t in ipairs(S.TopBuilds())do list[#list+1]={id='top:'..t.tree,name=t.name,tree=t.tree,top=true}end
 local n=#list
 local h=math.max(26,math.min(42,math.floor((state.left:GetHeight()-60-(n>own and 26 or 0))/math.max(1,n))-5))
 local y=-30;local used=0
 for i,m in ipairs(list)do
  if i==own+1 then state.topHead:ClearAllPoints();state.topHead:SetPoint('TOPLEFT',state.left,'TOPLEFT',0,y-3);state.topHead:Show();y=y-26 end
  used=used+1;local r=rowFrame(used);r.id=m.id
  r:ClearAllPoints();r:SetPoint('TOPLEFT',state.left,'TOPLEFT',0,y);r:SetPoint('TOPRIGHT',state.left,'TOPRIGHT',0,y);r:SetHeight(h);y=y-h-5
  local tree=m.tree or(m.entries and select(1,UI.talentsMainTree and UI.talentsMainTree(m.entries)))or 1
  local _,icon=UI.TreeInfo(tree);r.icon:SetIcon(icon);r.icon:SetSize(math.min(28,h-6),math.min(28,h-6))
  r.name:SetText(m.name)
  r.name:ClearAllPoints();r.sub:ClearAllPoints();r.value:ClearAllPoints()
  r.value:SetPoint('RIGHT',r,'RIGHT',-9,0);r.value:SetWidth(60)
  local res=resultOf(m.id)
  if h>=34 then
   r.name:SetPoint('TOPLEFT',r.icon,'TOPRIGHT',9,1);r.name:SetPoint('RIGHT',r.value,'LEFT',-4,0)
   r.sub:SetPoint('TOPLEFT',r.name,'BOTTOMLEFT',0,-1);r.sub:SetPoint('RIGHT',r.value,'LEFT',-4,0);r.sub:Show()
   r.sub:SetText(res and res.rotation and('Rota: '..res.rotation)or'noch nicht berechnet')
  else
   r.name:SetPoint('LEFT',r.icon,'RIGHT',9,0);r.name:SetPoint('RIGHT',r.value,'LEFT',-4,0);r.sub:Hide()
  end
  r.value:SetText(res and res.dps and UI.FormatDps(res.dps)or'')
  local on=state.sel==m.id
  UI.BoxColors(r.box,on and{.24,.43,.78,.55}or{.06,.17,.34,.5},on and{.953,.78,.357,.9}or{.47,.63,.9,.22})
  r:Show()
 end
 if n<=own then state.topHead:Hide()end
 for i=used+1,#state.rows do state.rows[i]:Hide()end
end

-- Middle: the rotations of the selected build ---------------------------------------------------------------------------------
local function rotRow(i)
 local r=state.rotRows[i];if r then return r end
 r=UI.Box(state.mid,{.055,.15,.30,.5},{.47,.63,.9,.2});r:SetHeight(30)
 r.star=r:CreateTexture(nil,'ARTWORK');r.star:SetSize(16,16);r.star:SetPoint('LEFT',r,'LEFT',9,0);r.star:SetTexture('Interface\\Icons\\INV_Misc_Note_01')
 r.name=UI.Text(r,13,COLOR.text,'body','LEFT');r.name:SetPoint('LEFT',r,'LEFT',32,0)
 r.tag=UI.Text(r,9.5,COLOR.gold,'body','LEFT')
 r.bar=UI.Bar(r,150,9);r.bar:SetPoint('RIGHT',r,'RIGHT',-180,0)
 r.value=UI.Text(r,12,COLOR.text,'num','RIGHT');r.value:SetPoint('RIGHT',r,'RIGHT',-88,0);r.value:SetWidth(70)
 r.delta=UI.Text(r,11.5,COLOR.muted,'num','RIGHT');r.delta:SetPoint('RIGHT',r,'RIGHT',-10,0);r.delta:SetWidth(70)
 state.rotRows[i]=r;return r
end
local function refreshRotations()
 local S=Sim();local res=resultOf(state.sel)
 local list=res and res.rotations or{}
 state.rotTitle:SetText('ROTATIONEN FÜR '..string.upper(nameOf(state.sel)))
 local best=0;for _,r in ipairs(list)do best=math.max(best,tonumber(r.dps)or 0)end
 local active=Sim().Rotation();local activeName=state.sel=='live'and active and active.name or nil
 local shown=math.min(#list,6)
 for i=1,shown do
  local item=list[i];local r=rotRow(i)
  r:ClearAllPoints();r:SetPoint('TOPLEFT',state.mid,'TOPLEFT',0,-112-(i-1)*34);r:SetPoint('TOPRIGHT',state.mid,'TOPRIGHT',0,-112-(i-1)*34)
  r.name:SetText(item.name or'?')
  r.tag:ClearAllPoints();r.tag:SetPoint('LEFT',r.name,'RIGHT',8,0);r.tag:SetText(item.custom and'EIGEN'or'MYTHICSIM')
  local top=item.name==(res.rotation)
  UI.Show(r.star,top);r.name:SetTextColor((top and COLOR.gold or COLOR.text)[1],(top and COLOR.gold or COLOR.text)[2],(top and COLOR.gold or COLOR.text)[3],1)
  r.bar:SetFraction(best>0 and(item.dps/best)or 0,top and COLOR.gold or{1,.54,.24})
  r.value:SetText(UI.FormatDps(item.dps))
  if best>0 and not top then local p=100*(item.dps/best-1);r.delta:SetText(UI.FormatPct(p));r.delta:SetTextColor(COLOR.bad[1],COLOR.bad[2],COLOR.bad[3],1)
  else r.delta:SetText(activeName==item.name and'aktiv'or'');r.delta:SetTextColor(COLOR.muted[1],COLOR.muted[2],COLOR.muted[3],1)end
  UI.BoxColors(r,top and{.18,.17,.12,.6}or{.055,.15,.30,.5},top and{.953,.78,.357,.7}or{.47,.63,.9,.2})
  r:Show()
 end
 for i=shown+1,#state.rotRows do state.rotRows[i]:Hide()end
 state.rotEmpty:SetText(#list==0 and'Noch keine Rotationen berechnet. „Beste Rota simmen“ vergleicht alle Rotationen der Engine für diese Skillung.'or'')
end

-- Right: result and priorities --------------------------------------------------------------------------------------------------
local function refreshResult()
 local res=resultOf(state.sel)
 if res and res.dps then
  state.dps:SetText(UI.FormatDps(res.dps,1));state.unit:SetText('DPS · '..tostring(res.rotation or'?'))
  local list=res.rotations or{};local custom=nil
  for _,r in ipairs(list)do if r.custom then custom=r end end
  local mythic;for _,r in ipairs(list)do if not r.custom then mythic=mythic or r end end
  if custom and mythic and mythic.dps>0 and res.rotation==custom.name then
   local p=100*(custom.dps/mythic.dps-1);state.delta:SetText((p>=0 and'▲ 'or'▼ ')..UI.FormatPct(p));state.vs:SetText('gegenüber der MythicSim-Rota')
  else state.delta:SetText('');state.vs:SetText(res.rotation and'beste Rotation der Engine'or'')end
 else state.dps:SetText('–');state.unit:SetText('noch nicht berechnet');state.delta:SetText('');state.vs:SetText('Beste Rota simmen drücken')end
end
local function prioRow(i)
 local r=state.prioRows[i];if r then return r end
 r=UI.Box(state.right,{.055,.15,.30,.5},{.47,.63,.9,.2});r:SetHeight(42)
 r.num=UI.Text(r,10.5,COLOR.dim,'num','CENTER');r.num:SetPoint('LEFT',r,'LEFT',2,0);r.num:SetWidth(18)
 r.icon=UI.IconBox(r,32);r.icon:SetPoint('LEFT',r,'LEFT',22,0)
 r.name=UI.Text(r,13,COLOR.text,'body','LEFT');r.name:SetPoint('TOPLEFT',r.icon,'TOPRIGHT',9,2)
 r.tag=UI.Text(r,9.5,COLOR.gold,'body','LEFT')
 r.hint=UI.Text(r,11,COLOR.muted,'body','LEFT');r.hint:SetPoint('TOPLEFT',r.name,'BOTTOMLEFT',0,-1);r.hint:SetPoint('RIGHT',r,'RIGHT',-6,0);r.hint:SetWordWrap(false)
 state.prioRows[i]=r;return r
end
local function refreshPriorities()
 local H=hud();local rows,source=H.Rows()
 state.prioTitle:SetText(source=='engine'and'PRIORITÄTEN · BESTE ROTA'or'PRIORITÄTEN · EINFACHE ROTA')
 local n=math.min(#rows,6)
 for i=1,n do
  local row=rows[i];local r=prioRow(i)
  r:ClearAllPoints();r:SetPoint('TOPLEFT',state.right,'TOPLEFT',0,-210-(i-1)*46);r:SetPoint('TOPRIGHT',state.right,'TOPRIGHT',0,-210-(i-1)*46)
  local name,icon;if FUSLive and FUSLive.spellDisplay then name,icon=FUSLive.spellDisplay(row.spellId)end
  r.num:SetText(tostring(i));r.icon:SetIcon(icon or UI.SpellIcon(row.spellId));r.name:SetText(name or('Zauber '..tostring(row.spellId)))
  local proc=H.IsProcSpell(row.spellId)
  r.tag:ClearAllPoints();r.tag:SetPoint('LEFT',r.name,'RIGHT',8,0);r.tag:SetText(proc and'PROCC'or'')
  r.hint:SetText(H.Describe(row))
  UI.BoxColors(r,proc and{.18,.17,.12,.6}or{.055,.15,.30,.5},proc and{.953,.78,.357,.6}or{.47,.63,.9,.2})
  r:Show()
 end
 for i=n+1,#state.prioRows do state.prioRows[i]:Hide()end
 state.prioEmpty:SetText(n==0 and'Für diese Klasse gibt es noch keine Rotation.'or(#rows>6 and('+ '..(#rows-6)..' weitere Zeilen')or''))
end

-- Status and refresh ------------------------------------------------------------------------------------------------------------------
local function refreshHudPanel()
 local H=hud();local cfg=H.Config()
 for _,c in ipairs(state.checks)do c:Refresh()end
 for _,s in ipairs(state.steppers)do s:Refresh()end
 state.move:SetLabel(cfg.locked and'HUD verschieben'or'HUD fixieren')
end
function UI.rotationRefresh()
 local S=Sim();if not state.page or not S then return end
 state.live=S.LiveEntries()
 local can=S.Available('rotation')
 UI.Show(state.simBox,can);UI.Show(state.left,can);UI.Show(state.lockedBox,not can)
 UI.Show(state.rotBox,can);UI.Show(state.card,can)
 if can then
  layoutRows();refreshRotations();refreshResult()
  if S.running or state.busy then state.simulate:SetLabel('Rechnet …');state.simulate:SetEnabledLook(false)
  else state.simulate:SetLabel('Beste Rota simmen');state.simulate:SetEnabledLook(true)end
  state.refine:Refresh()
 end
 refreshPriorities();refreshHudPanel()
end

local function build(page)
 state.page=page;state.rows,state.rotRows,state.prioRows={}, {}, {}
 local S=Sim()
 if not S or not hud()then
  local msg=UI.Text(page,14,COLOR.muted,'body','CENTER');msg:SetPoint('CENTER',page,'CENTER',0,0);msg:SetText('ForeverCore (ForeverCoreBridge) ist nicht geladen.');return
 end
 local lw,rw,gap=232,304,18
 state.left=CreateFrame('Frame',nil,page);state.left:SetPoint('TOPLEFT',page,'TOPLEFT',0,0);state.left:SetPoint('BOTTOMLEFT',page,'BOTTOMLEFT',0,0);state.left:SetWidth(lw)
 state.mid=CreateFrame('Frame',nil,page);state.mid:SetPoint('TOPLEFT',page,'TOPLEFT',lw+gap,0);state.mid:SetPoint('BOTTOMRIGHT',page,'BOTTOMRIGHT',-(rw+gap),0)
 state.right=CreateFrame('Frame',nil,page);state.right:SetPoint('TOPRIGHT',page,'TOPRIGHT',0,0);state.right:SetPoint('BOTTOMRIGHT',page,'BOTTOMRIGHT',0,0);state.right:SetWidth(rw)
 local midW=page:GetWidth()-lw-rw-2*gap;if not midW or midW<300 then midW=630 end
 -- left
 local h1=UI.Heading(state.left,'Skillung',1);h1:SetPoint('TOPLEFT',state.left,'TOPLEFT',0,0);h1:SetWidth(lw)
 state.topHead=CreateFrame('Frame',nil,state.left);state.topHead:SetSize(lw,22)
 local star=state.topHead:CreateTexture(nil,'ARTWORK');star:SetSize(16,16);star:SetPoint('LEFT',0,0);star:SetTexture('Interface\\Icons\\INV_Misc_Note_01')
 local th=UI.Text(state.topHead,11,COLOR.gold,'body','LEFT');th:SetPoint('LEFT',star,'RIGHT',7,0);th:SetText('MYTHICSIM TOP')
 -- middle: simulate
 state.simBox=CreateFrame('Frame',nil,state.mid);state.simBox:SetPoint('TOPLEFT',state.mid,'TOPLEFT',0,0);state.simBox:SetPoint('TOPRIGHT',state.mid,'TOPRIGHT',0,0);state.simBox:SetHeight(110)
 local h2=UI.Heading(state.simBox,'Rota simmen',2);h2:SetPoint('TOPLEFT',state.simBox,'TOPLEFT',0,0);h2:SetWidth(300)
 state.simulate=UI.Button(state.simBox,'Beste Rota simmen',{w=300,h=48,style='buttonBig',size=16,color={1,1,1},icon='Interface\\Icons\\Spell_Nature_WispSplode',iconSize=17})
 state.simulate:SetPoint('TOPLEFT',state.simBox,'TOPLEFT',0,-28)
 state.refine=UI.Check(state.simBox,'Eigene Rota verfeinern',function()return S.Store().refine==true end,function(on)S.Store().refine=on and true or false end,230)
 state.refine:SetPoint('LEFT',state.simulate,'RIGHT',24,0)
 UI.Tooltip(state.refine,{'Eigene Rota verfeinern','MythicSim probiert kleine Änderungen an der besten Rotation aus und behält, was mehr Schaden macht. Läuft im Hintergrund auf dem PC.'})
 state.message=UI.Text(state.simBox,11,COLOR.muted,'body','LEFT');state.message:SetPoint('TOPLEFT',state.simulate,'BOTTOMLEFT',2,-6);state.message:SetWidth(midW-4)
 state.simulate:SetScript('OnClick',function()
  if S.running or state.busy then return end
  local spec=S.BuildSpec(state.sel);if not spec then say('Diese Skillung ist nicht lesbar.',COLOR.bad);return end
  state.busy=true;say('')
  local ok=S.Detail(spec,function(detail,issue)
   state.busy=false
   if not detail then say(tostring(issue or'Berechnung fehlgeschlagen'),COLOR.bad)
   elseif S.Store().refine and UI.rotaTune then UI.rotaTune(spec)end
   UI.rotationRefresh()
  end)
  if not ok then state.busy=false;say('Simulieren ist gerade nicht möglich.',COLOR.bad)end
  UI.rotationRefresh()
 end)
 state.rotBox=CreateFrame('Frame',nil,state.mid);state.rotBox:SetAllPoints(state.mid)
 state.rotTitle=UI.Text(state.rotBox,11,COLOR.gold,'body','LEFT');state.rotTitle:SetPoint('TOPLEFT',state.mid,'TOPLEFT',2,-92)
 state.rotEmpty=UI.Text(state.rotBox,12,COLOR.muted,'body','LEFT');state.rotEmpty:SetPoint('TOPLEFT',state.mid,'TOPLEFT',4,-122);state.rotEmpty:SetWidth(midW-20);state.rotEmpty:SetWordWrap(true)
 -- below level 50 there is no simulation yet
 state.lockedBox=CreateFrame('Frame',nil,state.mid);state.lockedBox:SetPoint('TOPLEFT',state.mid,'TOPLEFT',0,0);state.lockedBox:SetPoint('TOPRIGHT',state.mid,'TOPRIGHT',0,0);state.lockedBox:SetHeight(110)
 local lt=UI.Text(state.lockedBox,15,COLOR.gold,'title','LEFT');lt:SetPoint('TOPLEFT',state.lockedBox,'TOPLEFT',2,-8);lt:SetText('Rotation berechnen ab Stufe 50')
 local ls=UI.Text(state.lockedBox,12.5,COLOR.muted,'body','LEFT');ls:SetPoint('TOPLEFT',lt,'BOTTOMLEFT',0,-8);ls:SetWidth(midW-10);ls:SetWordWrap(true)
 ls:SetText('Bis dahin zeigt das HUD im Kampf eine einfache Rotation deiner Klasse. Das HUD mit den Procs läuft ab Stufe 1; unten stellst du es ein.')
 -- middle: HUD settings
 local H=hud();local panel=UI.Box(state.mid);panel:SetPoint('BOTTOMLEFT',state.mid,'BOTTOMLEFT',0,0);panel:SetPoint('BOTTOMRIGHT',state.mid,'BOTTOMRIGHT',0,0);panel:SetHeight(270)
 state.hudPanel=panel
 local ph=UI.Text(panel,10.5,COLOR.gold,'body','LEFT');ph:SetPoint('TOPLEFT',panel,'TOPLEFT',14,-11);ph:SetText('HUD IM KAMPF')
 local pn=UI.Text(panel,10.5,COLOR.muted,'body','RIGHT');pn:SetPoint('TOPRIGHT',panel,'TOPRIGHT',-14,-11);pn:SetText('läuft von rechts nach links · Procc wird groß und leuchtet')
 state.checks={};state.steppers={}
 local function cfgCheck(label,key,x,y,tip)
  local c=UI.Check(panel,label,function()return H.Config()[key]==true end,function(on)H.Config()[key]=on;H.Apply()end,midW/2-30)
  c:SetPoint('TOPLEFT',panel,'TOPLEFT',x,-y);state.checks[#state.checks+1]=c
  if tip then UI.Tooltip(c,tip)end
 end
 cfgCheck('HUD anzeigen','enabled',16,40,'Das HUD erscheint nur im Kampf.')
 cfgCheck('Tasten anzeigen','showKeys',16,68,'Die Taste des Zaubers von deiner Aktionsleiste.')
 cfgCheck('Procs einschieben','procs',16,96,'Ein leuchtender Zauber springt nach vorne, wird groß und leuchtet.')
 cfgCheck('Verzögerung anzeigen','showDelay',16,124,'Zeigt, in wie vielen Sekunden der nächste Zauber bereit ist.')
 cfgCheck('Name beim Procc','showNames',midW/2,40)
 cfgCheck('Aktionsleiste hervorheben','barHighlight',midW/2,68,'Goldener Rahmen um die Taste des Zaubers, den du drücken sollst.')
 cfgCheck('Ton bei Procc','procSound',midW/2,96)
 local function stepper(label,key,min,max,step,fmt,x,y)
  local s=UI.Stepper(panel,label,function()return H.Config()[key]end,function(v)H.Config()[key]=v;H.Apply()end,min,max,step,fmt,midW/2-30)
  s:SetPoint('TOPLEFT',panel,'TOPLEFT',x,-y);state.steppers[#state.steppers+1]=s
 end
 local pct=function(v)return string.format('%d %%',math.floor(v*100+.5))end
 stepper('Größe','scale',.6,1.6,.1,pct,16,160);stepper('Deckkraft','alpha',.3,1,.1,pct,midW/2,160)
 stepper('Zauber in der Reihe','queue',1,5,1,function(v)return tostring(v)end,16,196)
 local bw=(midW-28-3*8)/4
 state.preview=UI.Button(panel,'Vorschau',{w=bw,h=38,size=12});state.preview:SetPoint('BOTTOMLEFT',panel,'BOTTOMLEFT',14,12)
 state.preview:SetScript('OnClick',function()H.Demo('normal',6)end)
 state.procTest=UI.Button(panel,'Procc zeigen',{w=bw,h=38,size=12});state.procTest:SetPoint('LEFT',state.preview,'RIGHT',8,0)
 state.procTest:SetScript('OnClick',function()H.Demo('proc',6)end)
 state.move=UI.Button(panel,'HUD verschieben',{w=bw,h=38,size=12});state.move:SetPoint('LEFT',state.procTest,'RIGHT',8,0)
 state.move:SetScript('OnClick',function()
  local cfg=H.Config()
  if not H.SetLocked(not cfg.locked)then say('Im Kampf lässt sich das HUD nicht verschieben.',COLOR.bad)end
  refreshHudPanel()
 end)
 UI.Tooltip(state.move,{'HUD verschieben','Entsperrt das HUD: mit der linken Maustaste ziehen, danach wieder fixieren.'})
 state.reset=UI.Button(panel,'Zurücksetzen',{w=bw,h=38,size=12});state.reset:SetPoint('LEFT',state.move,'RIGHT',8,0)
 state.reset:SetScript('OnClick',function()if not H.ResetPosition()then say('Im Kampf geht das nicht.',COLOR.bad)end end)
 -- right
 local h3=UI.Heading(state.right,'Ergebnis',3);h3:SetPoint('TOPLEFT',state.right,'TOPLEFT',0,0);h3:SetWidth(rw)
 state.card=CreateFrame('Frame',nil,state.right);state.card:SetSize(rw,140);state.card:SetPoint('TOPLEFT',state.right,'TOPLEFT',0,-26);UI.Style(state.card,'card','BACKGROUND')
 state.dps=UI.Text(state.card,34,COLOR.gold,'title','CENTER');state.dps:SetPoint('TOP',state.card,'TOP',0,-30);state.dps:SetWidth(rw-40)
 state.unit=UI.Text(state.card,12.5,COLOR.muted,'body','CENTER');state.unit:SetPoint('TOP',state.dps,'BOTTOM',0,-2);state.unit:SetWidth(rw-50)
 state.delta=UI.Text(state.card,15,COLOR.good,'body','CENTER');state.delta:SetPoint('TOP',state.unit,'BOTTOM',0,-3);state.delta:SetWidth(rw-50)
 state.vs=UI.Text(state.card,11,COLOR.muted,'body','CENTER');state.vs:SetPoint('TOP',state.delta,'BOTTOM',0,-1);state.vs:SetWidth(rw-50)
 state.prioTitle=UI.Text(state.right,10.5,COLOR.gold,'body','LEFT');state.prioTitle:SetPoint('TOPLEFT',state.right,'TOPLEFT',2,-188)
 state.prioEmpty=UI.Text(state.right,11,COLOR.muted,'body','LEFT');state.prioEmpty:SetPoint('BOTTOMLEFT',state.right,'BOTTOMLEFT',2,2);state.prioEmpty:SetWidth(rw)
 S.OnChange(function()if page:IsVisible()then UI.rotationRefresh()end end)
end

UI.RegisterTab({key='rotation',label='Rotation',order=2,icon='Interface\\Icons\\Spell_Nature_WispSplode',build=build,
 show=function()UI.rotationRefresh()end,refresh=function()UI.rotationRefresh()end})
