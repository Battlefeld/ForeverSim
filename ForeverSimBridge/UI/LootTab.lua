-- Tab "Beute" (from level 50): your Pre-BiS on a paper doll (the best item for every slot from the sources the addon knows),
-- the sources and the stat weights on the left, and for the selected slot what is worn now, the alternatives and where to
-- farm on the right. A second view checks the enchants. Everything comes from ForeverCoreClient.Loot.
ForeverSimUI=ForeverSimUI or{}
local UI=ForeverSimUI
local COLOR=UI.COLOR
local state={sel='chest',view='gear',slots={},weightRows={},altRows={},farmRows={},enchRows={}}
UI.loot=state
local SKULL='Interface\\Icons\\INV_Misc_Bone_HumanSkull_01'
local BAG='Interface\\Icons\\INV_Misc_Bag_08'
local STAR='Interface\\Icons\\INV_Misc_Note_01'
local UNKNOWN='Interface\\Icons\\INV_Misc_QuestionMark'

local function core()return ForeverCoreClient end
local function Loot()local c=core();return c and c.Loot or nil end
local function Sim()local c=core();return c and c.Sim or nil end
local QUALITY={[0]={.62,.62,.62},[1]={1,1,1},[2]={.12,1,0},[3]={0,.44,.87},[4]={.64,.21,.93},[5]={1,.5,0}}
local function itemInfo(id)
 local name,quality,icon
 local f=(C_Item and C_Item.GetItemInfo)or GetItemInfo
 if f and id then
  local ok,n,_,q,_,_,_,_,_,_,ic=pcall(f,id)
  if ok and type(n)=='string'then name,quality,icon=n,q,ic end
  if not name and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID,id)end
 end
 if not icon and id then
  local g=(C_Item and C_Item.GetItemIconByID)or GetItemIcon
  if g then local ok,ic=pcall(g,id);if ok and ic then icon=ic end end
 end
 return name or(id and('Item '..id)or'?'),QUALITY[tonumber(quality)or 1]or QUALITY[1],icon or UNKNOWN
end
UI.LootItemInfo=itemInfo
local function pct(p)return UI.FormatPct and UI.FormatPct(p)or tostring(p)end
local function say(text,color)
 if state.message then state.message:SetText(text or'');local c=color or COLOR.muted;state.message:SetTextColor(c[1],c[2],c[3],1)end
end
local function sourceIcon(c)
 if not c then return nil end
 for _,s in ipairs(c.sources)do if s.kind=='dungeon'then return SKULL end end
 if c.owned then return BAG end
 if c.star then return STAR end
end
local function sourceText(src)
 if src.kind=='dungeon'then
  local chance=src.chance and(' · '..(tostring(src.chance):gsub('%.',','))..' %')or''
  return'Dungeon · '..tostring(src.boss or src.dungeon)..chance
 elseif src.kind=='bag'then return'In deinen Taschen'
 elseif src.kind=='star'then return'★ MythicSim '..tostring(src.set or'')end
 return''
end

-- Slots on the paper doll -------------------------------------------------------------------------------------------------
local function slotWidget(def)
 local b=CreateFrame('Button',nil,state.mid);b:SetSize(210,58)
 b.def=def
 b.icon=UI.IconBox(b,46);b.icon:SetPoint('LEFT',b,'LEFT',def.side=='R'and 164 or 0,0)
 b.mark=b:CreateTexture(nil,'OVERLAY');b.mark:SetSize(16,16);b.mark:SetPoint('TOPRIGHT',b.icon,'TOPRIGHT',5,5);b.mark:SetTexCoord(.07,.93,.07,.93)
 b.star=b:CreateTexture(nil,'OVERLAY');b.star:SetSize(14,14);b.star:SetPoint('TOPLEFT',b.icon,'TOPLEFT',-5,5);b.star:SetTexture(STAR);b.star:SetTexCoord(.07,.93,.07,.93)
 b.gain=UI.Text(b,11,COLOR.good,'num','CENTER');b.gain:SetPoint('TOP',b.icon,'BOTTOM',0,-1);b.gain:SetWidth(52)
 local right=def.side=='R'
 b.label=UI.Text(b,9.5,COLOR.dim,'body',right and'RIGHT'or'LEFT');b.name=UI.Text(b,12,COLOR.text,'body',right and'RIGHT'or'LEFT');b.name:SetWordWrap(true)
 if right then
  b.label:SetPoint('TOPRIGHT',b.icon,'TOPLEFT',-8,-2);b.label:SetWidth(150)
  b.name:SetPoint('TOPRIGHT',b.label,'BOTTOMRIGHT',0,-2);b.name:SetWidth(150)
 else
  b.label:SetPoint('TOPLEFT',b.icon,'TOPRIGHT',8,-2);b.label:SetWidth(150)
  b.name:SetPoint('TOPLEFT',b.label,'BOTTOMLEFT',0,-2);b.name:SetWidth(150)
 end
 b:RegisterForClicks('LeftButtonUp')
 b:SetScript('OnClick',function(self)state.sel=self.def.key;UI.lootRefresh()end)
 b:SetScript('OnEnter',function(self)
  if not GameTooltip then return end
  local id=self.itemId;GameTooltip:SetOwner(self,'ANCHOR_RIGHT')
  local shown=false
  if id and GameTooltip.SetHyperlink then shown=pcall(GameTooltip.SetHyperlink,GameTooltip,'item:'..id)end
  if not shown then GameTooltip:SetText(self.def.label,1,.82,0)end
  GameTooltip:Show()
 end)
 b:SetScript('OnLeave',function()if GameTooltip then GameTooltip:Hide()end end)
 return b
end
local function layoutSlots()
 local L,R,B={}, {}, {}
 for _,def in ipairs(Loot().SLOTS)do if def.side=='L'then L[#L+1]=def elseif def.side=='R'then R[#R+1]=def else B[#B+1]=def end end
 local top=44
 for i,def in ipairs(L)do local w=state.slots[def.key];w:ClearAllPoints();w:SetPoint('TOPLEFT',state.mid,'TOPLEFT',0,-(top+(i-1)*62))end
 for i,def in ipairs(R)do local w=state.slots[def.key];w:ClearAllPoints();w:SetPoint('TOPRIGHT',state.mid,'TOPRIGHT',0,-(top+(i-1)*62))end
 local midW=state.mid:GetWidth();if not midW or midW<300 then midW=630 end
 for i,def in ipairs(B)do local w=state.slots[def.key];w:ClearAllPoints();w:SetPoint('TOPLEFT',state.mid,'TOPLEFT',midW/2-(#B*150)/2+(i-1)*150-30,-(top+7*62+14))end
end
local function paintSlot(w,row)
 local def=w.def
 w.label:SetText(string.upper(def.label))
 local best=row.best
 local border=COLOR.gold2
 if best then
  local name,qc,icon=itemInfo(best.id)
  border=qc
  w.itemId=best.id;w.icon:SetIcon(icon);w.icon:SetAlpha(1)
  w.name:SetText(name);w.name:SetTextColor(qc[1],qc[2],qc[3],1)
  w.gain:SetText(pct(best.pct));w.gain:SetTextColor(COLOR.good[1],COLOR.good[2],COLOR.good[3],1)
  local si=sourceIcon(best.c);if si then w.mark:SetTexture(si);w.mark:Show()else w.mark:Hide()end
  UI.Show(w.star,best.c.star==true)
 else
  local worn=row.worn
  w.itemId=worn and worn.id or nil
  if worn then
   local name,_,icon=itemInfo(worn.id);w.icon:SetIcon(icon);w.name:SetText(worn.name or name)
  else w.icon:SetIcon(nil);w.name:SetText('leer')end
  w.icon:SetAlpha(.55);w.name:SetTextColor(COLOR.muted[1],COLOR.muted[2],COLOR.muted[3],1)
  w.gain:SetText(worn and'schon bestes'or'');w.gain:SetTextColor(COLOR.muted[1],COLOR.muted[2],COLOR.muted[3],1)
  w.mark:Hide();w.star:Hide()
 end
 local on=state.sel==def.key
 w.icon:SetBorder(on and COLOR.gold or border)
end

-- Refresh -------------------------------------------------------------------------------------------------------------------------
local function refreshWeights()
 local L=Loot();local w=L.Weights()
 for i=1,5 do
  local r=state.weightRows[i];local row=w and w.rows and w.rows[i]
  if row then
   r.name:SetText(row.label or row.key);r.bar:SetFraction(row.weight or 0,COLOR.blue);r.value:SetText(string.format('%.2f',row.weight or 0):gsub('%.',','));r.frame:Show()
  else r.frame:Hide()end
 end
 state.weightsNote:SetText(w and''or'Werden beim Öffnen berechnet')
end
local function refreshSide(prebis)
 local L=Loot()
 local row;for _,r in ipairs(prebis)do if r.slot==state.sel then row=r end end
 row=row or prebis[1]
 local def=L.Slot(row.slot)
 state.detailTitle:SetText(string.upper(def.label))
 local shown=row.best
 if shown then
  local name,qc=itemInfo(shown.id)
  state.itemName:SetText(name);state.itemName:SetTextColor(qc[1],qc[2],qc[3],1)
  local worn=row.worn
  state.itemWorn:SetText(worn and('Getragen: '..tostring(worn.name or('Item '..worn.id)))or'Nichts angelegt')
  state.itemGain:SetText('▲ '..pct(shown.pct)..' DPS')
  local lines={}
  for i,src in ipairs(shown.c.sources)do if i<=3 then lines[#lines+1]=sourceText(src)end end
  state.itemSources:SetText(table.concat(lines,'\n'))
 else
  local worn=row.worn
  state.itemName:SetText(worn and tostring(worn.name or('Item '..worn.id))or'Leer');state.itemName:SetTextColor(COLOR.muted[1],COLOR.muted[2],COLOR.muted[3],1)
  state.itemWorn:SetText('Dafür kennt ForeverSim kein besseres Item.');state.itemGain:SetText('');state.itemSources:SetText('')
 end
 local alts=L.Alternatives(row.slot,shown and shown.id,3)
 for i=1,3 do
  local r=state.altRows[i];local a=alts[i]
  if a then
   local name,qc,icon=itemInfo(a.id);r.icon:SetIcon(icon);r.icon:SetBorder(qc);r.name:SetText(name);r.name:SetTextColor(qc[1],qc[2],qc[3],1)
   local src=a.c.sources[1];r.sub:SetText(src and sourceText(src)or'');r.value:SetText(pct(a.pct))
   local c=a.pct>0 and COLOR.good or COLOR.muted;r.value:SetTextColor(c[1],c[2],c[3],1);r.frame:Show()
  else r.frame:Hide()end
 end
 state.altEmpty:SetText(#alts==0 and'keine'or'')
 local farm=L.Farm(prebis,3)
 for i=1,3 do
  local r=state.farmRows[i];local f=farm[i]
  if f then
   r.name:SetText(f.dungeon);r.sub:SetText(f.upgrades..(f.upgrades==1 and' Upgrade'or' Upgrades'));r.value:SetText(pct(f.perRun)..' /Lauf');r.frame:Show()
  else r.frame:Hide()end
 end
 state.farmEmpty:SetText(#farm==0 and'Noch keine Upgrades gefunden.'or'')
end
local ENCHANTABLE={head=true,shoulder=true,back=true,chest=true,wrist=true,hands=true,legs=true,feet=true,mainhand=true,offhand=true,ranged=true}
local function refreshEnchants()
 local L=Loot();local n=0;local missing=0
 for _,def in ipairs(L.SLOTS)do
  if ENCHANTABLE[def.key]then
   n=n+1;local r=state.enchRows[n]
   local worn=L.Worn(def.key)
   r.label:SetText(def.label)
   if worn then
    local name,qc,icon=itemInfo(worn.id);r.icon:SetIcon(icon);r.icon:SetBorder(qc);r.name:SetText(worn.name or name)
    local e=L.EnchantOf(worn.link)
    if e>0 then r.status:SetText('verzaubert');r.status:SetTextColor(COLOR.good[1],COLOR.good[2],COLOR.good[3],1)
    else r.status:SetText('keine Verzauberung');r.status:SetTextColor(1,.62,.25,1);missing=missing+1 end
   else r.icon:SetIcon(nil);r.name:SetText('leer');r.status:SetText('');r.status:SetTextColor(COLOR.muted[1],COLOR.muted[2],COLOR.muted[3],1)end
   r.frame:Show()
  end
 end
 for i=n+1,#state.enchRows do state.enchRows[i].frame:Hide()end
 state.enchSummary:SetText(missing==0 and'Alle Verzauberbaren Plätze sind verzaubert.'or(missing..(missing==1 and' Platz ist'or' Plätze sind')..' noch nicht verzaubert.'))
end
function UI.lootRefresh()
 local L,S=Loot(),Sim();if not state.page or not L or not S then return end
 local gear=state.view=='gear'
 UI.Show(state.gearBox,gear);UI.Show(state.enchBox,not gear)
 state.viewGear:SetStyle(gear and'tabOn'or'tab');state.viewEnch:SetStyle(gear and'tab'or'tabOn')
 for _,c in ipairs(state.checks)do c:Refresh()end
 local p=L.progress or{total=#L.Candidates(),ready=0,busy=0}
 local last=L.LastRun()
 if L.running then
  state.run:SetLabel('Rechnet …');state.run:SetEnabledLook(false)
  state.runInfo:SetText(string.format('%s Items · %s fertig · läuft im Hintergrund',UI.FormatDps(p.total),UI.FormatDps(p.ready)))
 else
  state.run:SetLabel('Alle Items simmen');state.run:SetEnabledLook(S.Available('loot'))
  local when
  if last and last.at and last.at>0 then local f=date or(os and os.date);local ok,t=pcall(f,'%d.%m. %H:%M',last.at);when=ok and t end
  state.runInfo:SetText(string.format('%s Items · Stufe 50–60%s',UI.FormatDps(#L.Candidates()),when and(' · '..when)or' · noch nicht berechnet'))
 end
 refreshWeights()
 local prebis=L.PreBis()
 if gear then
  for _,row in ipairs(prebis)do local w=state.slots[row.slot];if w then paintSlot(w,row)end end
  local total,n=L.Total(prebis)
  if n>0 then state.total:SetText(pct(total));state.totalNote:SetText('wenn alles da ist · '..n..(n==1 and' Upgrade'or' Upgrades')..' (Summe der Einzelwerte)')
  else state.total:SetText('–');state.totalNote:SetText(p.ready>0 and'Kein Item verbessert deinen Schaden.'or'Alle Items simmen drücken')end
 else refreshEnchants()end
 refreshSide(prebis)
end

-- Page --------------------------------------------------------------------------------------------------------------------------------
local function build(page)
 state.page=page;state.slots,state.weightRows,state.altRows,state.farmRows,state.enchRows={}, {}, {}, {}, {}
 local L,S=Loot(),Sim()
 if not L or not S then
  local msg=UI.Text(page,14,COLOR.muted,'body','CENTER');msg:SetPoint('CENTER',page,'CENTER',0,0);msg:SetText('ForeverCore (ForeverCoreBridge) ist nicht geladen.');return
 end
 local lw,rw,gap=232,304,18
 state.left=CreateFrame('Frame',nil,page);state.left:SetPoint('TOPLEFT',page,'TOPLEFT',0,0);state.left:SetPoint('BOTTOMLEFT',page,'BOTTOMLEFT',0,0);state.left:SetWidth(lw)
 state.mid=CreateFrame('Frame',nil,page);state.mid:SetPoint('TOPLEFT',page,'TOPLEFT',lw+gap,0);state.mid:SetPoint('BOTTOMRIGHT',page,'BOTTOMRIGHT',-(rw+gap),0)
 state.right=CreateFrame('Frame',nil,page);state.right:SetPoint('TOPRIGHT',page,'TOPRIGHT',0,0);state.right:SetPoint('BOTTOMRIGHT',page,'BOTTOMRIGHT',0,0);state.right:SetWidth(rw)
 local midW=page:GetWidth()-lw-rw-2*gap;if not midW or midW<300 then midW=630 end
 -- left: sources
 local h1=UI.Heading(state.left,'Quellen',1);h1:SetPoint('TOPLEFT',state.left,'TOPLEFT',0,0);h1:SetWidth(lw)
 state.checks={}
 local function check(label,key,y,tip)
  local c=UI.Check(state.left,label,function()return L.Filter()[key]==true end,function(on)L.SetFilter(key,on);UI.lootRefresh()end,lw)
  c:SetPoint('TOPLEFT',state.left,'TOPLEFT',2,-y);state.checks[#state.checks+1]=c
  if tip then UI.Tooltip(c,tip)end
 end
 check('Dungeon-Beute','dungeon',30,'Alle tragbaren Drops der Dungeons ab Stufe 50, mit Boss und Drop-Chance.')
 check('Items in deinen Taschen','bag',56)
 check('MythicSim-Liste ★','star',82,'Die Ausrüstung, die MythicSim für deine Klasse als Top-Set mitbringt.')
 check('Nur MythicSim-Liste ★','onlyStar',108)
 state.noSources=UI.Text(state.left,10.5,COLOR.dim,'body','LEFT');state.noSources:SetPoint('TOPLEFT',state.left,'TOPLEFT',2,-136);state.noSources:SetWidth(lw);state.noSources:SetWordWrap(true)
 state.noSources:SetText('Quest, Handwerk, Ruf, Auktion und Raid folgen, sobald es dafür eine Datenquelle gibt.')
 local h2=UI.Heading(state.left,'Simmen',2);h2:SetPoint('TOPLEFT',state.left,'TOPLEFT',0,-190);h2:SetWidth(lw)
 state.run=UI.Button(state.left,'Alle Items simmen',{w=lw,h=48,style='buttonBig',size=15,color={1,1,1},icon='Interface\\Icons\\Spell_Nature_WispSplode',iconSize=17})
 state.run:SetPoint('TOPLEFT',state.left,'TOPLEFT',0,-216)
 state.run:SetScript('OnClick',function()
  if L.running then return end
  say('');local ok=L.Run(function()UI.lootRefresh()end);if not ok then say('Läuft schon.',COLOR.bad)end
  L.LoadWeights(function()UI.lootRefresh()end,true);UI.lootRefresh()
 end)
 state.runInfo=UI.Text(state.left,10.5,COLOR.muted,'body','CENTER');state.runInfo:SetPoint('TOP',state.run,'BOTTOM',0,-4);state.runInfo:SetWidth(lw)
 state.message=UI.Text(state.left,11,COLOR.muted,'body','LEFT');state.message:SetPoint('TOPLEFT',state.run,'BOTTOMLEFT',2,-22);state.message:SetWidth(lw)
 local wh=UI.Text(state.left,10.5,COLOR.gold,'body','LEFT');wh:SetPoint('TOPLEFT',state.left,'TOPLEFT',2,-318);wh:SetText('STAT-GEWICHTE')
 for i=1,5 do
  local f=CreateFrame('Frame',nil,state.left);f:SetSize(lw,24);f:SetPoint('TOPLEFT',state.left,'TOPLEFT',0,-340-(i-1)*26)
  local r={frame=f}
  r.name=UI.Text(f,11.5,COLOR.text,'body','LEFT');r.name:SetPoint('LEFT',f,'LEFT',2,0);r.name:SetWidth(96);r.name:SetWordWrap(false)
  r.bar=UI.Bar(f,76,9);r.bar:SetPoint('LEFT',f,'LEFT',102,0)
  r.value=UI.Text(f,11,COLOR.text,'num','RIGHT');r.value:SetPoint('RIGHT',f,'RIGHT',0,0)
  state.weightRows[i]=r
 end
 state.weightsNote=UI.Text(state.left,10.5,COLOR.dim,'body','LEFT');state.weightsNote:SetPoint('TOPLEFT',state.left,'TOPLEFT',2,-342)
 -- middle: two views
 state.viewGear=UI.Button(state.mid,'Ausrüstung',{w=170,h=40,styles={'tab','tabOn'},size=12.5});state.viewGear:SetPoint('TOPRIGHT',state.mid,'TOP',-4,0)
 state.viewEnch=UI.Button(state.mid,'Verzauberungen & Buffs',{w=210,h=40,styles={'tab','tabOn'},size=12.5});state.viewEnch:SetPoint('TOPLEFT',state.mid,'TOP',4,0)
 state.viewGear:SetScript('OnClick',function()state.view='gear';UI.lootRefresh()end)
 state.viewEnch:SetScript('OnClick',function()state.view='ench';UI.lootRefresh()end)
 state.gearBox=CreateFrame('Frame',nil,state.mid);state.gearBox:SetAllPoints(state.mid)
 for _,def in ipairs(L.SLOTS)do state.slots[def.key]=slotWidget(def)end
 layoutSlots()
 local h3=UI.Heading(state.gearBox,'Dein Pre-BiS',3);h3:SetPoint('TOP',state.mid,'TOP',-60,-48);h3:SetWidth(200)
 state.total=UI.Text(state.gearBox,30,COLOR.good,'title','CENTER');state.total:SetPoint('TOP',state.mid,'TOP',0,-300);state.total:SetWidth(240)
 state.totalNote=UI.Text(state.gearBox,11,COLOR.muted,'body','CENTER');state.totalNote:SetPoint('TOP',state.total,'BOTTOM',0,-2);state.totalNote:SetWidth(240)
 state.legend=UI.Text(state.gearBox,10.5,COLOR.muted,'body','CENTER');state.legend:SetPoint('BOTTOM',state.mid,'BOTTOM',0,0);state.legend:SetWidth(midW)
 state.legend:SetText('Totenkopf = Dungeon · Tasche = schon bei dir · Notiz = MythicSim-Liste · ★ am Item = trägt MythicSim Top')
 -- second view: enchants
 state.enchBox=CreateFrame('Frame',nil,state.mid);state.enchBox:SetAllPoints(state.mid)
 local eh=UI.Heading(state.enchBox,'Verzauberungen deiner Ausrüstung');eh:SetPoint('TOPLEFT',state.mid,'TOPLEFT',0,-52);eh:SetWidth(midW)
 for i=1,11 do
  local f=UI.Box(state.enchBox,{.055,.15,.30,.5},{.47,.63,.9,.2});f:SetHeight(34)
  local col=(i<=6)and 0 or 1;local rowIndex=(i<=6)and i-1 or i-7
  f:SetPoint('TOPLEFT',state.mid,'TOPLEFT',col*(midW/2+4),-82-rowIndex*40);f:SetWidth(midW/2-4)
  local r={frame=f}
  r.icon=UI.IconBox(f,26);r.icon:SetPoint('LEFT',f,'LEFT',5,0)
  r.label=UI.Text(f,9.5,COLOR.dim,'body','LEFT');r.label:SetPoint('TOPLEFT',r.icon,'TOPRIGHT',8,2)
  r.name=UI.Text(f,11.5,COLOR.text,'body','LEFT');r.name:SetPoint('TOPLEFT',r.label,'BOTTOMLEFT',0,-1);r.name:SetWidth(150);r.name:SetWordWrap(false)
  r.status=UI.Text(f,11,COLOR.muted,'body','RIGHT');r.status:SetPoint('RIGHT',f,'RIGHT',-8,0)
  state.enchRows[i]=r
 end
 state.enchSummary=UI.Text(state.enchBox,12,COLOR.text,'body','LEFT');state.enchSummary:SetPoint('TOPLEFT',state.mid,'TOPLEFT',2,-330);state.enchSummary:SetWidth(midW)
 local en=UI.Text(state.enchBox,11,COLOR.muted,'body','LEFT');en:SetPoint('TOPLEFT',state.enchSummary,'BOTTOMLEFT',0,-10);en:SetWidth(midW);en:SetWordWrap(true)
 en:SetText('Was eine Verzauberung oder ein Buff an Schaden bringt, zeigt ForeverSim hier, sobald MythicSim dafür Werte liefert. Bis dahin siehst du, welche Plätze noch keine Verzauberung tragen.')
 -- right: the selected slot
 state.detailTitle=UI.Text(state.right,10.5,COLOR.gold,'body','LEFT');state.detailTitle:SetPoint('TOPLEFT',state.right,'TOPLEFT',2,-2)
 local card=UI.Box(state.right,{.02,.05,.1,.95},{.79,.6,.24,.85});card:SetSize(rw,170);card:SetPoint('TOPLEFT',state.right,'TOPLEFT',0,-24)
 state.itemName=UI.Text(card,14,COLOR.text,'title','LEFT');state.itemName:SetPoint('TOPLEFT',card,'TOPLEFT',12,-12);state.itemName:SetWidth(rw-24);state.itemName:SetWordWrap(false)
 state.itemWorn=UI.Text(card,11.5,COLOR.muted,'body','LEFT');state.itemWorn:SetPoint('TOPLEFT',state.itemName,'BOTTOMLEFT',0,-6);state.itemWorn:SetWidth(rw-24);state.itemWorn:SetWordWrap(true)
 state.itemGain=UI.Text(card,15,COLOR.good,'num','LEFT');state.itemGain:SetPoint('TOPLEFT',card,'TOPLEFT',12,-76)
 state.itemSources=UI.Text(card,11.5,COLOR.text,'body','LEFT');state.itemSources:SetPoint('TOPLEFT',state.itemGain,'BOTTOMLEFT',0,-8);state.itemSources:SetWidth(rw-24);state.itemSources:SetWordWrap(true)
 local ah=UI.Text(state.right,10.5,COLOR.gold,'body','LEFT');ah:SetPoint('TOPLEFT',state.right,'TOPLEFT',2,-206);ah:SetText('ALTERNATIVEN')
 local function listRow(parent,y,store,i)
  local f=UI.Box(parent,{.055,.15,.30,.5},{.47,.63,.9,.2});f:SetHeight(40);f:SetPoint('TOPLEFT',parent,'TOPLEFT',0,y);f:SetPoint('TOPRIGHT',parent,'TOPRIGHT',0,y)
  local r={frame=f}
  r.icon=UI.IconBox(f,28);r.icon:SetPoint('LEFT',f,'LEFT',6,0)
  r.name=UI.Text(f,12,COLOR.text,'body','LEFT');r.name:SetPoint('TOPLEFT',r.icon,'TOPRIGHT',8,2);r.name:SetPoint('RIGHT',f,'RIGHT',-64,0);r.name:SetWordWrap(false)
  r.sub=UI.Text(f,10.5,COLOR.muted,'body','LEFT');r.sub:SetPoint('TOPLEFT',r.name,'BOTTOMLEFT',0,-1);r.sub:SetPoint('RIGHT',f,'RIGHT',-64,0);r.sub:SetWordWrap(false)
  r.value=UI.Text(f,11.5,COLOR.good,'num','RIGHT');r.value:SetPoint('RIGHT',f,'RIGHT',-8,0)
  store[i]=r;return r
 end
 for i=1,3 do listRow(state.right,-228-(i-1)*44,state.altRows,i)end
 state.altEmpty=UI.Text(state.right,11,COLOR.muted,'body','LEFT');state.altEmpty:SetPoint('TOPLEFT',state.right,'TOPLEFT',4,-232)
 local fh=UI.Text(state.right,10.5,COLOR.gold,'body','LEFT');fh:SetPoint('TOPLEFT',state.right,'TOPLEFT',2,-368);fh:SetText('WO FARMEN?')
 for i=1,3 do
  local r=listRow(state.right,-390-(i-1)*44,state.farmRows,i);r.icon:SetIcon(SKULL)
 end
 state.farmEmpty=UI.Text(state.right,11,COLOR.muted,'body','LEFT');state.farmEmpty:SetPoint('TOPLEFT',state.right,'TOPLEFT',4,-394);state.farmEmpty:SetWidth(rw)
 S.OnChange(function()if page:IsVisible()then UI.lootRefresh()end end)
end

UI.RegisterTab({key='loot',label='Beute',order=3,icon=SKULL,build=function(page)
 local S=Sim()
 if S and not S.Available('loot')then
  UI.LockedNotice(page,'Ab Stufe 50 verfügbar','Dein Pre-BiS, die besten Drops und wo du sie bekommst gibt es ab Stufe 50. Du bist Stufe '..tostring(S.Level())..'.')
  state.locked=true;return
 end
 build(page)
end,show=function(page)
 local S,L=Sim(),Loot()
 if state.locked and S and S.Available('loot')then state.locked=false;for _,c in ipairs({page:GetChildren()})do c:Hide()end;build(page)end
 if S and L and state.left then
  S.LoadPresets(function()L.Reset();UI.lootRefresh()end)
  L.LoadWeights(function()UI.lootRefresh()end)
  L.Poll(60);UI.lootRefresh()
 end
end,refresh=function()UI.lootRefresh()end})
