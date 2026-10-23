-- Tab "Talente" (from level 60): saved builds and the engine's top builds on the left, the three talent trees in the
-- middle, the result of a simulation on the right. Everything shown comes from ForeverCoreClient.Sim (saved data and
-- answers of ForeverCore.exe); the only calculation here is formatting.
ForeverSimUI=ForeverSimUI or{}
local UI=ForeverSimUI
local COLOR=UI.COLOR
local TREE_TINT={{.43,.31,.86},{.9,.4,.12},{.18,.58,.9}}
local PALETTE={{1,.54,.24},{1,.81,.35},{.91,.27,.18},{1,.42,.63},{.29,.35,.47}}
local state={sel='live',nodes={},rows={},lines={}}
UI.talents=state

local function core()return ForeverCoreClient end
local function Sim()local c=core();return c and c.Sim or nil end
-- numbers the way the mock-ups show them: 1.842,6 and +12,3 %
local function group(n)
 local s=tostring(math.floor(math.abs(n)));local out=s:reverse():gsub('(%d%d%d)','%1.'):reverse():gsub('^%.','')
 return(n<0 and'-'or'')..out
end
function UI.FormatDps(x,decimals)
 x=tonumber(x);if not x then return'-'end
 if decimals then
  local scale=10^decimals;local rounded=math.floor(math.abs(x)*scale+.5)
  return(x<0 and'-'or'')..group(math.floor(rounded/scale))..','..string.format('%0'..decimals..'d',rounded%scale)
 end
 return group(x+.5)
end
function UI.FormatPct(p)
 p=tonumber(p)or 0
 local s=string.format('%.1f',math.abs(p)):gsub('%.',',')
 return(p>=0 and'+'or'-')..s..' %'
end
local function treeInfo(i)
 local name,icon
 if GetTalentTabInfo then local ok,n,tex=pcall(GetTalentTabInfo,i);if ok then name,icon=n,tex end end
 local S=Sim();local model=S and S.Model();local tree=model and model.talentTrees and model.talentTrees[i]
 if not name or name==''then name=tree and tree.name or('Baum '..i)end
 if not icon and tree and tree.talents and tree.talents[1]then icon=UI.SpellIcon(tree.talents[1].spellId)end
 return name,icon
end
UI.TreeInfo=treeInfo
local function mainTree(entries)
 local S=Sim();local pts=S.Points(entries);local best,bi=0,1
 for i=1,3 do if(pts[i]or 0)>best then best,bi=pts[i],i end end
 return bi,pts
end
UI.talentsMainTree=mainTree
local function pointsText(entries)
 local pts=Sim().Points(entries);return string.format('%d / %d / %d',pts[1]or 0,pts[2]or 0,pts[3]or 0)
end
local function say(text,color)
 if state.message then state.message:SetText(text or'');local c=color or COLOR.muted;state.message:SetTextColor(c[1],c[2],c[3],1)end
end

-- the entries of the build that is selected (nil while the character cannot be read)
local function selectedEntries()
 local S=Sim();local id=state.sel
 if id=='live'then return state.live end
 local b=S.Build(id);if b then return b.entries,true end
 local kind,tree=tostring(id):match('^(%a+):(%d+)$')
 if kind then for _,t in ipairs(S.TopBuilds())do if t.tree==tonumber(tree)then return t.entries end end end
end
local function resultOf(id)local S=Sim();return S and S.Result(id)end

-- Left column ---------------------------------------------------------------------------------------------------
local function rowModel()
 local S=Sim();local out={own={},top={}}
 out.own[1]={id='live',name='Im Spiel',entries=state.live}
 for _,b in ipairs(S.Builds())do out.own[#out.own+1]={id=b.id,name=b.name,entries=b.entries,saved=true}end
 for _,t in ipairs(S.TopBuilds())do out.top[#out.top+1]={id='top:'..t.tree,name=t.name,entries=t.entries,tree=t.tree,top=true}end
 return out
end
local function rowFrame(i)
 local r=state.rows[i];if r then return r end
 r=CreateFrame('Button',nil,state.left)
 r.box=UI.Box(r,{.06,.17,.34,.5},{.47,.63,.9,.22});r.box:SetAllPoints();r.box:EnableMouse(false)
 r.icon=UI.IconBox(r,30);r.icon:SetPoint('LEFT',r,'LEFT',6,0)
 r.name=UI.Text(r,13,COLOR.text,'body','LEFT');r.name:SetWordWrap(false)
 r.sub=UI.Text(r,11,COLOR.muted,'body','LEFT');r.sub:SetWordWrap(false)
 r.value=UI.Text(r,12,COLOR.text,'num','RIGHT')
 r:RegisterForClicks('LeftButtonUp');r:SetHighlightTexture('Interface\\Buttons\\WHITE8X8')
 local hl=r:GetHighlightTexture();if hl then hl:SetVertexColor(.4,.6,1,.12)end
 r:SetScript('OnClick',function(self)
  if IsShiftKeyDown and IsShiftKeyDown()and self.entries then
   UI.Prompt('Skillung zum Teilen',Sim().Export(self.entries),nil,{readOnly=true,note='Den Text kopieren (Strg+C) und bei einem anderen Spieler unter "Import" einfügen.'});return
  end
  state.sel=self.id;UI.talentsRefresh()
 end)
 UI.Tooltip(r,function(self)
  local t={self.fullName or self.name:GetText()or''}
  if self.stale then t[#t+1]='Ergebnis veraltet: Ausrüstung, Talente oder Engine haben sich geändert.'end
  if self.entries then t[#t+1]='Umschalt+Klick: Text zum Teilen'end
  return t
 end)
 state.rows[i]=r;return r
end
local function layoutRows()
 local S=Sim();local model=rowModel();local n=#model.own+#model.top
 local avail=state.left:GetHeight()-24-34-22-(#model.top>0 and 24 or 0)-50
 local h=math.max(26,math.min(44,math.floor(avail/math.max(1,n))-6))
 local y=-56;local used=0
 local liveRes=resultOf('live')
 local function place(m)
  used=used+1;local r=rowFrame(used);r.id=m.id;r.entries=m.entries
  r:ClearAllPoints();r:SetPoint('TOPLEFT',state.left,'TOPLEFT',0,y);r:SetPoint('TOPRIGHT',state.left,'TOPRIGHT',0,y);r:SetHeight(h);y=y-h-6
  local tree=m.tree or(m.entries and mainTree(m.entries))or 1
  local _,icon=treeInfo(tree);r.icon:SetIcon(icon);r.icon:SetSize(math.min(30,h-6),math.min(30,h-6))
  r.name:SetText(m.name);r.fullName=m.name
  r.name:ClearAllPoints();r.sub:ClearAllPoints();r.value:ClearAllPoints()
  r.value:SetPoint('RIGHT',r,'RIGHT',-9,0);r.value:SetWidth(64)
  if h>=36 then
   r.name:SetPoint('TOPLEFT',r.icon,'TOPRIGHT',9,1);r.name:SetPoint('RIGHT',r.value,'LEFT',-4,0)
   r.sub:SetPoint('TOPLEFT',r.name,'BOTTOMLEFT',0,-1);r.sub:SetPoint('RIGHT',r.value,'LEFT',-4,0);r.sub:Show()
  else
   r.name:SetPoint('LEFT',r.icon,'RIGHT',9,0);r.name:SetPoint('RIGHT',r.value,'LEFT',-4,0);r.sub:Hide()
  end
  r.sub:SetText(m.entries and pointsText(m.entries)or'')
  local res=resultOf(m.id)
  r.stale=res and S.IsStale(res)or false
  if res and res.dps then
   if m.id=='live'or m.top then r.value:SetText(UI.FormatDps(res.dps));r.value:SetTextColor(COLOR.text[1],COLOR.text[2],COLOR.text[3],1)
   elseif liveRes and liveRes.dps and liveRes.dps>0 then
    local p=100*(res.dps/liveRes.dps-1);local c=p>0.05 and COLOR.good or(p<-0.05 and COLOR.bad or COLOR.muted)
    r.value:SetText(UI.FormatPct(p));r.value:SetTextColor(c[1],c[2],c[3],1)
   else r.value:SetText(UI.FormatDps(res.dps));r.value:SetTextColor(COLOR.text[1],COLOR.text[2],COLOR.text[3],1)end
   r.value:SetAlpha(r.stale and .5 or 1)
  elseif res and res.error then r.value:SetText('Fehler');r.value:SetTextColor(COLOR.bad[1],COLOR.bad[2],COLOR.bad[3],1);r.value:SetAlpha(1)
  else r.value:SetText('');r.value:SetAlpha(1)end
  local on=state.sel==m.id
  UI.BoxColors(r.box,on and{.24,.43,.78,.55}or{.06,.17,.34,.5},on and{.953,.78,.357,.9}or{.47,.63,.9,.22})
  r:Show()
 end
 -- group headings
 for _,m in ipairs(model.own)do place(m)end
 if #model.top>0 then
  state.topHead:ClearAllPoints();state.topHead:SetPoint('TOPLEFT',state.left,'TOPLEFT',0,y-4);state.topHead:Show();y=y-24
  for _,m in ipairs(model.top)do place(m)end
 else state.topHead:Hide()end
 for i=used+1,#state.rows do state.rows[i]:Hide()end
 -- slots: how many of the ten saved builds are used
 local count=#S.Builds()
 state.slotText:SetText(count..' / '..S.MAX_BUILDS)
 for i,p in ipairs(state.pips)do
  local on=i<=count;p:SetColorTexture(on and COLOR.gold[1]or .47,on and COLOR.gold[2]or .63,on and COLOR.gold[3]or .9,on and 1 or .2)
 end
end

-- Middle column: the three trees ------------------------------------------------------------------------------------
local NODE=34
local function nodeButton(parent)
 local b=CreateFrame('Button',nil,parent,'BackdropTemplate');b:SetSize(NODE,NODE)
 if b.SetBackdrop then b:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=2});b:SetBackdropColor(.03,.05,.1,1)end
 b.icon=b:CreateTexture(nil,'ARTWORK');b.icon:SetPoint('TOPLEFT',2,-2);b.icon:SetPoint('BOTTOMRIGHT',-2,2);b.icon:SetTexCoord(.07,.93,.07,.93)
 b.rank=UI.Text(b,10,COLOR.muted,'num','CENTER');b.rank:SetPoint('BOTTOMRIGHT',b,'BOTTOMRIGHT',9,-8);b.rank:SetWidth(30)
 b.rankBg=b:CreateTexture(nil,'OVERLAY',nil,-1);b.rankBg:SetColorTexture(0,0,0,.85);b.rankBg:SetPoint('TOPLEFT',b.rank,'TOPLEFT',2,-1);b.rankBg:SetPoint('BOTTOMRIGHT',b.rank,'BOTTOMRIGHT',-2,1)
 b:RegisterForClicks('LeftButtonUp','RightButtonUp')
 return b
end
local function paintNode(b,rank,max,locked)
 local c
 if rank>=max then c=COLOR.gold elseif rank>0 then c=COLOR.good else c={.23,.28,.38}end
 if b.SetBackdropBorderColor then b:SetBackdropBorderColor(c[1],c[2],c[3],1)end
 b.icon:SetDesaturated(rank==0);b.icon:SetAlpha(rank>0 and 1 or(locked and .22 or .4))
 b.rank:SetText(rank..'/'..max);b.rank:SetTextColor(c[1],c[2],c[3],1)
end
local function buildTrees()
 local S=Sim();local model=S.Model();if not model then return end
 if state.builtFor==S.Class()then return end
 for _,t in ipairs(state.treeFrames or{})do t:Hide()end
 state.treeFrames={};state.nodes={}
 local W=(state.mid:GetWidth()-18)/3
 for ti,tree in ipairs(model.talentTrees or{})do
  local p=UI.Box(state.mid,{.02,.04,.09,.92},{.79,.6,.24,.55});p:SetSize(W,338);p:SetPoint('TOPLEFT',state.mid,'TOPLEFT',(ti-1)*(W+9),-48)
  local tint=TREE_TINT[ti]or TREE_TINT[1]
  p.top=p:CreateTexture(nil,'BACKGROUND');p.top:SetPoint('TOPLEFT',1,-1);p.top:SetPoint('TOPRIGHT',-1,-1);p.top:SetHeight(120);p.top:SetColorTexture(tint[1],tint[2],tint[3],.2)
  p.head=p:CreateTexture(nil,'BORDER');p.head:SetPoint('TOPLEFT',1,-1);p.head:SetPoint('TOPRIGHT',-1,-1);p.head:SetHeight(30);p.head:SetColorTexture(tint[1],tint[2],tint[3],.28)
  p.icon=p:CreateTexture(nil,'ARTWORK');p.icon:SetSize(18,18);p.icon:SetPoint('TOPLEFT',9,-7);p.icon:SetTexCoord(.07,.93,.07,.93)
  p.name=UI.Text(p,14,{math.min(1,tint[1]+.3),math.min(1,tint[2]+.3),math.min(1,tint[3]+.3)},'title','LEFT');p.name:SetPoint('LEFT',p.icon,'RIGHT',7,0)
  p.points=UI.Text(p,13,COLOR.text,'num','RIGHT');p.points:SetPoint('TOPRIGHT',p,'TOPRIGHT',-10,-9)
  state.treeFrames[ti]=p;state.nodes[ti]={}
  for _,node in ipairs(tree.talents or{})do
   local r,c=tonumber(node.row)or 0,tonumber(node.column)or 0
   local b=nodeButton(p);b:SetPoint('TOPLEFT',p,'TOPLEFT',16+2+c*46,-(40+2+r*42))
   b.t,b.r,b.c,b.max,b.node=ti,r,c,tonumber(node.maxRank)or 1,node
   b.icon:SetTexture(UI.SpellIcon(node.spellId))
   b:SetScript('OnClick',function(self,button)UI.talentsClickNode(self,button=='RightButton'and-1 or 1)end)
   b:SetScript('OnEnter',function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self,'ANCHOR_RIGHT')
    local shown=false
    if self.node.spellId and GameTooltip.SetSpellByID then shown=pcall(GameTooltip.SetSpellByID,GameTooltip,self.node.spellId)end
    if not shown then GameTooltip:SetText(tostring(self.node.name or''),1,1,1)end
    GameTooltip:AddLine('Rang '..(self.currentRank or 0)..'/'..self.max,.95,.78,.36)
    if state.editable then GameTooltip:AddLine('Linksklick: Punkt vergeben · Rechtsklick: Punkt entfernen',.6,.8,1,true)
    else GameTooltip:AddLine('Nur ansehen: "Neu" oder "Kopieren" legt eine eigene Skillung an.',.6,.6,.6,true)end
    if self.problem then GameTooltip:AddLine(self.problem,1,.45,.4,true)end
    GameTooltip:Show()
   end)
   b:SetScript('OnLeave',function()if GameTooltip then GameTooltip:Hide()end end)
   state.nodes[ti][r*10+c]=b
  end
 end
 state.builtFor=S.Class()
end
-- prerequisite arrows (vertical, with a bend when the talent needed stands in another column)
local function drawLines()
 local S=Sim();local layout=S.Layout();local n=0
 local function seg(p,x,y,w,h,c)
  n=n+1;local t=state.lines[n]
  if not t then t=p:CreateTexture(nil,'ARTWORK',nil,-2);state.lines[n]=t end
  t:SetParent(p);t:ClearAllPoints();t:SetPoint('TOPLEFT',p,'TOPLEFT',x,-y);t:SetSize(math.max(1,w),math.max(1,h));t:SetColorTexture(c[1],c[2],c[3],c[4]or .8);t:Show()
 end
 for key,l in pairs(layout)do
  local b=state.nodes[l.tree]and state.nodes[l.tree][l.row*10+l.col]
  local pre=state.nodes[l.tree]and state.nodes[l.tree][l.preRow and(l.preRow*10+l.preCol)or-1]
  if b and pre then
   local p=state.treeFrames[l.tree]
   local met=(pre.currentRank or 0)>=pre.max
   local c=met and{.953,.78,.357,.9}or{.4,.45,.58,.55}
   local px,py=16+2+pre.c*46,40+2+pre.r*42;local bx,by=16+2+b.c*46,40+2+b.r*42
   if pre.c==b.c then seg(p,bx+NODE/2-1,py+NODE,3,by-py-NODE,c)
   else
    seg(p,math.min(px,bx)+NODE/2,py+NODE/2-1,math.abs(px-bx),3,c)
    seg(p,bx+NODE/2-1,py+NODE/2,3,by-py-NODE/2,c)
   end
  end
 end
 for i=n+1,#state.lines do state.lines[i]:Hide()end
end
local function refreshTrees()
 local S=Sim();buildTrees();if not state.treeFrames then return end
 local entries,editable=selectedEntries();state.editable=editable==true
 local ranks={};for _,e in ipairs(entries or{})do ranks[e.t*1000+e.r*10+e.c]=e.n end
 local pts=S.Points(entries)
 local layout=S.Layout()
 for ti,p in ipairs(state.treeFrames)do
  local name,icon=treeInfo(ti);p.name:SetText(name);p.icon:SetTexture(icon);p.points:SetText(tostring(pts[ti]or 0))
  for key,b in pairs(state.nodes[ti])do
   local rank=ranks[ti*1000+key]or 0;b.currentRank=rank;b.problem=nil
   local locked=false
   if entries and rank==0 then local _,why=S.Change(entries,ti,b.r,b.c,1);if why then locked=true;b.problem=why end end
   paintNode(b,rank,b.max,locked and not state.editable or(locked and rank==0))
  end
 end
 drawLines()
 local total=0;for i=1,3 do total=total+(pts[i]or 0)end
 state.points:SetText('Punkte '..total..' / 51')
end
function UI.talentsClickNode(b,delta)
 local S=Sim();if not state.editable then return end
 local b0=S.Build(state.sel);if not b0 then return end
 local out,why=S.Change(b0.entries,b.t,b.r,b.c,delta)
 if not out then say(why,COLOR.bad);return end
 S.UpdateBuild(b0.id,out);say('')
end

-- Right column ------------------------------------------------------------------------------------------------------
local function spellName(id,label)
 if label and label~=''then return label end
 if id then
  if C_Spell and C_Spell.GetSpellName then local ok,n=pcall(C_Spell.GetSpellName,id);if ok and n then return n end end
  if GetSpellInfo then local ok,n=pcall(GetSpellInfo,id);if ok and type(n)=='string'then return n end end
  return'Zauber '..id
 end
 return'Sonstiges'
end
local function manaPercent(mana)
 local pool
 if UnitPowerMax then local ok,v=pcall(UnitPowerMax,'player',0);if ok and type(v)=='number'and v>0 then pool=v end end
 if not pool then return nil end
 return math.max(0,math.min(100,100+100*mana/pool))
end
local function refreshResult()
 local S=Sim();local res=resultOf(state.sel);local live=resultOf('live')
 local stale=res and S.IsStale(res)
 if res and res.dps then
  state.dps:SetText(UI.FormatDps(res.dps,1));state.dps:SetAlpha(stale and .55 or 1)
  local name=treeInfo(select(1,(function()local e=selectedEntries();return mainTree(e or{})end)()))
  state.unit:SetText('DPS · '..tostring(name)..(res.rotation and(' · '..UI.RotationLabel(res.rotation))or''))
  if state.sel~='live'and live and live.dps and live.dps>0 and not tostring(state.sel):find('^top:')then
   local p=100*(res.dps/live.dps-1);local c=p>0.05 and COLOR.good or(p<-0.05 and COLOR.bad or COLOR.muted)
   state.delta:SetText((p>=0 and'▲ 'or'▼ ')..UI.FormatPct(p));state.delta:SetTextColor(c[1],c[2],c[3],1)
   state.vs:SetText('gegenüber deinen Talenten')
  elseif tostring(state.sel):find('^top:')then state.delta:SetText('');state.vs:SetText('mit der Ausrüstung der Vorlage')
  else state.delta:SetText('');state.vs:SetText(stale and'veraltet · Simulieren drücken'or'deine aktuellen Talente')end
 else
  state.dps:SetText('–');state.dps:SetAlpha(1);state.unit:SetText(res and res.error or'noch nicht berechnet');state.delta:SetText('');state.vs:SetText('Simulieren drücken')
 end
 -- charts
 local detail=res and res.detail
 local dpsValues,manaValues={}, {}
 for _,pt in ipairs(detail and detail.curve or{})do
  dpsValues[#dpsValues+1]=pt.dps
  if pt.mana then local m=manaPercent(pt.mana);if m then manaValues[#manaValues+1]=m end end
 end
 state.chartDps:SetData(dpsValues,nil,COLOR.fire);state.chartMana:SetData(manaValues,100,COLOR.blue)
 state.dpsEnd:SetText(#dpsValues>0 and UI.FormatDps(dpsValues[#dpsValues])or'–')
 state.manaEnd:SetText(#manaValues>0 and(math.floor(manaValues[#manaValues]+.5)..' % am Ende')or'keine Daten')
 -- damage shares
 local shares=detail and detail.breakdown or{}
 local x=0;local W=state.breakBar:GetWidth()-4
 for i=1,5 do
  local seg=state.breakSeg[i];local row=state.breakRows[i];local s=shares[i]
  if s and s.pct and s.pct>0 then
   local c=PALETTE[i];seg:ClearAllPoints();seg:SetPoint('LEFT',state.breakBar,'LEFT',2+x,0);local w=math.max(1,W*s.pct/100);seg:SetSize(w,10);seg:SetColorTexture(c[1],c[2],c[3],1);seg:Show();x=x+w
   row.icon:SetTexture(s.spellId and UI.SpellIcon(s.spellId)or'Interface\\Icons\\INV_Misc_QuestionMark');row.name:SetText(s.rest and'Sonstiges'or spellName(s.spellId,s.label))
   row.pct:SetText(string.format('%d %%',math.floor(s.pct+.5)));row.swatch:SetColorTexture(c[1],c[2],c[3],1);row.frame:Show()
  else seg:Hide();row.frame:Hide()end
 end
 state.breakTitle:SetText(#shares>0 and'Schaden nach Zauber'or'Schaden nach Zauber · noch keine Daten')
end
local function refreshSpecs()
 local S=Sim();local live=resultOf('live');local bestTree,bestDps
 local maxDps=live and live.dps or 0
 local rows={}
 for tree=1,3 do
  local res=resultOf('spec:'..tree);rows[tree]=res
  if res and res.dps then
   maxDps=math.max(maxDps,res.dps)
   if not bestDps or res.dps>bestDps then bestTree,bestDps=tree,res.dps end
  end
 end
 local liveTree=state.live and mainTree(state.live)or nil
 for tree=1,3 do
  local row=state.specRows[tree];local res=rows[tree]
  local name,icon=treeInfo(tree)
  row.icon:SetIcon(icon);row.name:SetText(name)
  if res and res.dps and maxDps>0 then
   row.bar:SetFraction(res.dps/maxDps,tree==bestTree and PALETTE[1]or(TREE_TINT[tree]and{TREE_TINT[tree][1],TREE_TINT[tree][2],TREE_TINT[tree][3]}or PALETTE[2]))
   row.value:SetText(UI.FormatDps(res.dps)..(tree==liveTree and' ●'or''))
  else row.bar:SetFraction(0);row.value:SetText(res and res.error and'Fehler'or'–')end
  UI.Show(row.frame,true)
 end
 state.specBest=nil
 if bestTree and live and live.dps and live.dps>0 and bestDps>live.dps*1.001 and bestTree~=liveTree then
  local p=100*(bestDps/live.dps-1);local name=treeInfo(bestTree)
  state.specBest=bestTree
  state.specNote:SetText('Zu '..tostring(name)..' '..UI.FormatPct(p));state.specNote:SetTextColor(COLOR.good[1],COLOR.good[2],COLOR.good[3],1)
  state.apply:Show()
 elseif bestTree and live then state.specNote:SetText('Deine Skillung passt am besten');state.specNote:SetTextColor(COLOR.muted[1],COLOR.muted[2],COLOR.muted[3],1);state.apply:Hide()
 else state.specNote:SetText('Simulieren zeigt den besten Spec');state.specNote:SetTextColor(COLOR.muted[1],COLOR.muted[2],COLOR.muted[3],1);state.apply:Hide()end
end
local function refreshStatus()
 local S=Sim()
 if S.running and S.progress then
  state.simulate:SetLabel('Rechnet … '..S.progress.step..'/'..S.progress.total);state.simulate:SetEnabledLook(false)
  state.progress:SetText(tostring(S.progress.label or''))
 else
  state.simulate:SetLabel('Simulieren');state.simulate:SetEnabledLook(not S.Searching());state.progress:SetText('')
 end
 -- results of another state: say so once
 local stale=false;for _,id in ipairs({'live'})do local r=resultOf(id);if r and S.IsStale(r)then stale=true end end
 state.stale:SetText(stale and'veraltet · Simulieren drücken'or'');
 if S.Searching()then
  local sr=S.search;state.bis:SetLabel('Abbrechen · '..tostring(sr.label or''));state.bis:SetEnabledLook(true)
  state.progress:SetText(sr.sims..' Skillungen gemessen')
 else
  state.bis:SetLabel('Beste Skillung finden');state.bis:SetEnabledLook(#S.TopBuilds()>0 and not S.running)
 end
end

function UI.talentsRefresh()
 local S=Sim();if not state.page or not S then return end
 state.live=S.LiveEntries()
 layoutRows();refreshTrees();refreshResult();refreshSpecs();refreshStatus()
 -- row actions
 local saved=S.Build(state.sel)
 UI.Show(state.rename,saved~=nil);UI.Show(state.delete,saved~=nil)
 state.copy:SetEnabledLook(S.CanAddBuild() and selectedEntries()~=nil)
 state.new:SetEnabledLook(S.CanAddBuild() and state.live~=nil)
 state.dd:SetItems((function()local t={};for i=1,3 do local n,ic=treeInfo(i);t[#t+1]={key=i,text=n,icon=ic}end;return t end)())
 if not state.target then state.target=(state.live and mainTree(state.live))or 1 end
 local n,ic=treeInfo(state.target);state.dd:SetValue(state.target,'Ziel: '..tostring(n),ic)
end

-- Page --------------------------------------------------------------------------------------------------------------
local function build(page)
 state.page=page
 state.rows,state.lines,state.nodes,state.builtFor={}, {}, {},nil
 local S=Sim()
 if not S then
  local msg=UI.Text(page,14,COLOR.muted,'body','CENTER');msg:SetPoint('CENTER',page,'CENTER',0,0);msg:SetText('ForeverCore (ForeverCoreBridge) ist nicht geladen.');return
 end
 local lw,rw,gap=232,304,18
 state.left=CreateFrame('Frame',nil,page);state.left:SetPoint('TOPLEFT',page,'TOPLEFT',0,0);state.left:SetPoint('BOTTOMLEFT',page,'BOTTOMLEFT',0,0);state.left:SetWidth(lw)
 state.mid=CreateFrame('Frame',nil,page);state.mid:SetPoint('TOPLEFT',page,'TOPLEFT',lw+gap,0);state.mid:SetPoint('BOTTOMRIGHT',page,'BOTTOMRIGHT',-(rw+gap),0)
 state.right=CreateFrame('Frame',nil,page);state.right:SetPoint('TOPRIGHT',page,'TOPRIGHT',0,0);state.right:SetPoint('BOTTOMRIGHT',page,'BOTTOMRIGHT',0,0);state.right:SetWidth(rw)
 -- left: builds
 local h1=UI.Heading(state.left,'Skillung',1);h1:SetPoint('TOPLEFT',state.left,'TOPLEFT',0,0);h1:SetWidth(lw)
 state.slotText=UI.Text(state.left,11,COLOR.muted,'body','RIGHT');state.slotText:SetPoint('TOPRIGHT',state.left,'TOPRIGHT',0,-5)
 state.pips={}
 for i=1,S.MAX_BUILDS do
  local p=state.left:CreateTexture(nil,'ARTWORK');local w=(lw-(S.MAX_BUILDS-1)*3)/S.MAX_BUILDS;p:SetSize(w,5);p:SetPoint('TOPLEFT',state.left,'TOPLEFT',(i-1)*(w+3),-30);state.pips[i]=p
 end
 state.topHead=CreateFrame('Frame',nil,state.left);state.topHead:SetSize(lw,22)
 local star=state.topHead:CreateTexture(nil,'ARTWORK');star:SetSize(16,16);star:SetPoint('LEFT',0,0);star:SetTexture('Interface\\Icons\\INV_Misc_Note_01')
 local th=UI.Text(state.topHead,11,COLOR.gold,'body','LEFT');th:SetPoint('LEFT',star,'RIGHT',7,0);th:SetText('MYTHICSIM TOP')
 state.message=UI.Text(state.left,11,COLOR.muted,'body','LEFT');state.message:SetPoint('BOTTOMLEFT',state.left,'BOTTOMLEFT',2,50);state.message:SetWidth(lw);state.message:SetWordWrap(true)
 local bw=(lw-8)/2
 state.new=UI.Button(state.left,'+ Neu',{w=bw,h=40,tooltip='Neue Skillung aus deinen jetzigen Talenten'})
 state.new:SetPoint('BOTTOMLEFT',state.left,'BOTTOMLEFT',0,0)
 state.new:SetScript('OnClick',function()
  if not state.live then say('Dein Charakter ist gerade nicht lesbar.',COLOR.bad);return end
  local b,why=S.AddBuild('Neue Skillung',state.live,'own');if b then state.sel=b.id;say('');UI.talentsRefresh()else say(why,COLOR.bad)end
 end)
 state.import=UI.Button(state.left,'Import',{w=bw,h=40,tooltip='Eine geteilte Skillung einfügen'})
 state.import:SetPoint('BOTTOMRIGHT',state.left,'BOTTOMRIGHT',0,0)
 state.import:SetScript('OnClick',function()
  UI.Prompt('Skillung importieren','',function(text)
   local entries,why=S.Import(text);if not entries then say(why,COLOR.bad);return end
   local b,why2=S.AddBuild('Import',entries,'import');if b then state.sel=b.id;say('Skillung importiert.',COLOR.good);UI.talentsRefresh()else say(why2,COLOR.bad)end
  end,{okText='Importieren',note='Den Text einer geteilten Skillung hier einfügen (Strg+V).'})
 end)
 local small={w=bw-4,h=30,size=11.5}
 state.copy=UI.Button(state.left,'Kopieren',small);state.copy:SetPoint('BOTTOMLEFT',state.left,'BOTTOMLEFT',0,46)
 state.rename=UI.Button(state.left,'Umbenennen',small);state.rename:SetPoint('BOTTOMRIGHT',state.left,'BOTTOMRIGHT',0,46)
 state.delete=UI.Button(state.left,'Löschen',small);state.delete:SetPoint('BOTTOMRIGHT',state.left,'BOTTOMRIGHT',0,80)
 state.message:ClearAllPoints();state.message:SetPoint('BOTTOMLEFT',state.left,'BOTTOMLEFT',2,112)
 state.copy:SetScript('OnClick',function()
  local entries=selectedEntries();if not entries then return end
  local name=state.sel=='live'and'Kopie von Im Spiel'or nil
  if not name then local b=S.Build(state.sel);name=b and('Kopie von '..b.name)or nil end
  if not name then for _,t in ipairs(S.TopBuilds())do if'top:'..t.tree==state.sel then name=t.name end end end
  local b,why=S.AddBuild(name or'Kopie',entries,'copy');if b then state.sel=b.id;say('');UI.talentsRefresh()else say(why,COLOR.bad)end
 end)
 state.rename:SetScript('OnClick',function()
  local b=S.Build(state.sel);if not b then return end
  UI.Prompt('Skillung umbenennen',b.name,function(text)if S.RenameBuild(b.id,text)then say('')else say('Der Name darf nicht leer sein.',COLOR.bad)end end,{okText='Umbenennen'})
 end)
 state.delete:SetScript('OnClick',function()
  local b=S.Build(state.sel);if not b then return end
  UI.Prompt('Skillung "'..b.name..'" löschen?','',function()S.DeleteBuild(b.id);state.sel='live';UI.talentsRefresh()end,{okText='Löschen',note='Die Skillung und ihre Ergebnisse werden entfernt.'})
 end)
 -- middle: toolbar and trees
 state.dd=UI.Dropdown(state.mid,200,{onSelect=function(key)state.target=key;UI.talentsRefresh()end});state.dd:SetPoint('TOPLEFT',state.mid,'TOPLEFT',0,0)
 state.bis=UI.Button(state.mid,'Beste Skillung finden',{w=250,h=40,style='buttonActive',color=COLOR.gold,icon='Interface\\Icons\\INV_Misc_Spyglass_03',iconSize=16,tooltip=function()
  return{'Beste Skillung finden','MythicSim startet bei der besten Vorlage des gewählten Baums und verschiebt Punkte, solange der Schaden steigt. Läuft im Hintergrund auf dem PC; ein Klick bricht ab.'}
 end})
 state.bis:SetPoint('LEFT',state.dd,'RIGHT',12,0)
 state.bis:SetScript('OnClick',function()
  if S.Searching()then S.CancelSearch();return end
  say('')
  local ok,why=S.FindBest({tree=state.target},function()UI.talentsRefresh()end,function(build,info)
   if build then
    state.sel=build.id
    if type(info)=='number'then say('Gefunden: '..UI.FormatPct(info)..' gegenüber deinen Talenten. Gespeichert als „'..build.name..'“.',info>0 and COLOR.good or COLOR.muted)
    else say('Gefunden und gespeichert als „'..build.name..'“. '..tostring(info or''),COLOR.good)end
   else say(tostring(info or'Keine bessere Skillung gefunden.'),COLOR.muted)end
   UI.talentsRefresh()
  end)
  if not ok then say(tostring(why or'Die Suche startet gerade nicht.'),COLOR.bad)end
  UI.talentsRefresh()
 end)
 state.points=UI.Text(state.mid,12,COLOR.muted,'body','RIGHT');state.points:SetPoint('TOPRIGHT',state.mid,'TOPRIGHT',0,-14)
 state.stale=UI.Text(state.mid,11,COLOR.gold,'body','RIGHT');state.stale:SetPoint('TOPRIGHT',state.mid,'TOPRIGHT',0,-32)
 -- charts under the trees
 local cw=(state.mid:GetWidth()-12)/2
 local function chartBlock(x,title)
  local t=UI.Text(state.mid,11.5,COLOR.muted,'body','LEFT');t:SetPoint('TOPLEFT',state.mid,'TOPLEFT',x+2,-398);t:SetText(title)
  local v=UI.Text(state.mid,11.5,COLOR.text,'num','RIGHT');v:SetPoint('TOPRIGHT',state.mid,'TOPLEFT',x+cw-4,-398)
  local c=UI.Chart(state.mid,cw,100);c:SetPoint('TOPLEFT',state.mid,'TOPLEFT',x,-416)
  return c,v
 end
 state.chartDps,state.dpsEnd=chartBlock(0,'DPS über Zeit');state.chartMana,state.manaEnd=chartBlock(cw+12,'Mana')
 -- right: simulate and result
 local h2=UI.Heading(state.right,'Simulieren',2);h2:SetPoint('TOPLEFT',state.right,'TOPLEFT',0,0);h2:SetWidth(rw)
 state.simulate=UI.Button(state.right,'Simulieren',{w=rw,h=48,style='buttonBig',size=16,color={1,1,1},icon='Interface\\Icons\\Spell_Nature_WispSplode',iconSize=17})
 state.simulate:SetPoint('TOPLEFT',state.right,'TOPLEFT',0,-26)
 state.simulate:SetScript('OnClick',function()
  if S.running then return end
  say('')
  local ok=S.RunAll({selected=state.sel},function()UI.talentsRefresh()end,function(done,issue)
   if not done then say(tostring(issue or'Berechnung fehlgeschlagen'),COLOR.bad)end
   UI.talentsRefresh()
  end)
  if not ok then say('Simulieren ist gerade nicht möglich.',COLOR.bad)end
  UI.talentsRefresh()
 end)
 state.progress=UI.Text(state.right,11,COLOR.muted,'body','CENTER');state.progress:SetPoint('TOP',state.simulate,'BOTTOM',0,-2);state.progress:SetWidth(rw)
 local h3=UI.Heading(state.right,'Ergebnis',3);h3:SetPoint('TOPLEFT',state.right,'TOPLEFT',0,-96);h3:SetWidth(rw)
 local card=CreateFrame('Frame',nil,state.right);card:SetSize(rw,140);card:SetPoint('TOPLEFT',state.right,'TOPLEFT',0,-122);UI.Style(card,'card','BACKGROUND')
 state.dps=UI.Text(card,34,COLOR.gold,'title','CENTER');state.dps:SetPoint('TOP',card,'TOP',0,-30);state.dps:SetWidth(rw-40)
 state.unit=UI.Text(card,12.5,COLOR.muted,'body','CENTER');state.unit:SetPoint('TOP',state.dps,'BOTTOM',0,-2);state.unit:SetWidth(rw-50)
 state.delta=UI.Text(card,15,COLOR.good,'body','CENTER');state.delta:SetPoint('TOP',state.unit,'BOTTOM',0,-3);state.delta:SetWidth(rw-50)
 state.vs=UI.Text(card,11,COLOR.muted,'body','CENTER');state.vs:SetPoint('TOP',state.delta,'BOTTOM',0,-1);state.vs:SetWidth(rw-50)
 -- best spec for the worn gear
 local spec=UI.Box(state.right);spec:SetSize(rw,150);spec:SetPoint('TOPLEFT',state.right,'TOPLEFT',0,-270)
 local sh=UI.Text(spec,10.5,COLOR.gold,'body','LEFT');sh:SetPoint('TOPLEFT',spec,'TOPLEFT',12,-9);sh:SetText('BESTER SPEC FÜR DEIN GEAR')
 state.specRows={}
 for i=1,3 do
  local f=CreateFrame('Frame',nil,spec);f:SetPoint('TOPLEFT',spec,'TOPLEFT',12,-26-(i-1)*27);f:SetPoint('TOPRIGHT',spec,'TOPRIGHT',-12,-26-(i-1)*27);f:SetHeight(24)
  local r={frame=f}
  r.icon=UI.IconBox(f,22);r.icon:SetPoint('LEFT',f,'LEFT',0,0)
  r.name=UI.Text(f,11,COLOR.muted,'body','LEFT');r.name:SetPoint('LEFT',r.icon,'RIGHT',7,0);r.name:SetWidth(52);r.name:SetWordWrap(false)
  r.bar=UI.Bar(f,120,12);r.bar:SetPoint('LEFT',r.name,'RIGHT',4,0)
  r.value=UI.Text(f,12,COLOR.text,'num','RIGHT');r.value:SetPoint('RIGHT',f,'RIGHT',0,0)
  state.specRows[i]=r
 end
 local note=CreateFrame('Frame',nil,spec);note:SetPoint('BOTTOMLEFT',spec,'BOTTOMLEFT',6,6);note:SetPoint('BOTTOMRIGHT',spec,'BOTTOMRIGHT',-6,6);note:SetHeight(40);UI.Style(note,'note','BACKGROUND')
 state.specNote=UI.Text(note,12,COLOR.good,'body','LEFT');state.specNote:SetPoint('LEFT',note,'LEFT',14,0);state.specNote:SetWidth(150)
 state.apply=UI.Button(note,'Übernehmen',{w=104,h=32,style='buttonActive',color=COLOR.gold,size=11.5});state.apply:SetPoint('RIGHT',note,'RIGHT',-6,0)
 state.apply:SetScript('OnClick',function()
  local tree=state.specBest;if not tree then return end
  for _,t in ipairs(S.TopBuilds())do
   if t.tree==tree then
    local b,why=S.AddBuild(t.name,t.entries,'preset')
    if b then state.sel=b.id;say('"'..t.name..'" ist gespeichert. Umskillen musst du selbst beim Talentlehrer.',COLOR.good);UI.talentsRefresh()else say(why,COLOR.bad)end
    return
   end
  end
 end)
 -- where the damage comes from
 local brk=UI.Box(state.right);brk:SetSize(rw,140);brk:SetPoint('TOPLEFT',state.right,'TOPLEFT',0,-428)
 state.breakTitle=UI.Text(brk,10.5,COLOR.gold,'body','LEFT');state.breakTitle:SetPoint('TOPLEFT',brk,'TOPLEFT',12,-9)
 state.breakBar=UI.Box(brk,{.01,.03,.06,1},{.47,.63,.9,.25});state.breakBar:SetSize(rw-24,14);state.breakBar:SetPoint('TOPLEFT',brk,'TOPLEFT',12,-26)
 state.breakSeg={};state.breakRows={}
 for i=1,5 do
  state.breakSeg[i]=state.breakBar:CreateTexture(nil,'ARTWORK')
  local f=CreateFrame('Frame',nil,brk);f:SetPoint('TOPLEFT',brk,'TOPLEFT',12,-48-(i-1)*17);f:SetPoint('TOPRIGHT',brk,'TOPRIGHT',-12,-48-(i-1)*17);f:SetHeight(16)
  local r={frame=f}
  r.swatch=f:CreateTexture(nil,'ARTWORK');r.swatch:SetSize(5,13);r.swatch:SetPoint('LEFT',0,0)
  r.icon=f:CreateTexture(nil,'ARTWORK');r.icon:SetSize(14,14);r.icon:SetPoint('LEFT',9,0);r.icon:SetTexCoord(.07,.93,.07,.93)
  r.name=UI.Text(f,11.5,COLOR.text,'body','LEFT');r.name:SetPoint('LEFT',r.icon,'RIGHT',6,0);r.name:SetWidth(150);r.name:SetWordWrap(false)
  r.pct=UI.Text(f,11.5,COLOR.text,'num','RIGHT');r.pct:SetPoint('RIGHT',f,'RIGHT',0,0)
  state.breakRows[i]=r
 end
 S.OnChange(function()if page:IsVisible()then UI.talentsRefresh()end end)
end

UI.RegisterTab({key='talents',label='Talente',order=1,icon='Interface\\Icons\\INV_Misc_Book_09',build=function(page)
 local S=Sim()
 if S and not S.Available('talents')then
  UI.LockedNotice(page,'Ab Stufe 60 verfügbar','Skillungen vergleichen und die beste finden gibt es mit allen 51 Talentpunkten. Du bist Stufe '..tostring(S.Level())..'.')
  state.locked=true;return
 end
 build(page)
end,show=function(page)
 local S=Sim()
 if state.locked and S and S.Available('talents')then state.locked=false;for _,c in ipairs({page:GetChildren()})do c:Hide()end;build(page)end
 if S and state.left then
  S.LoadPresets(function()UI.talentsRefresh()end)
  UI.talentsRefresh()
 end
end,refresh=function()UI.talentsRefresh()end})
