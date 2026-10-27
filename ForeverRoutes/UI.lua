-- ForeverRoutes owns every frame and setting here. Existing art is reused locally.
local FR=ForeverRoutes
local UI=FR.UI
local C=UI.COLOR
local call=FR.Call
local frame,menu,view
local function label(parent,size,color)
 return UI.Text(parent,size or 12,color or C.text,'body','LEFT')
end
local function tip(button,title,body)
 button:SetScript('OnEnter',function(self)
  GameTooltip:SetOwner(self,'ANCHOR_RIGHT');GameTooltip:AddLine(title,C.gold[1],C.gold[2],C.gold[3])
  if body then GameTooltip:AddLine(body,1,1,1,true)end;GameTooltip:Show()
 end)
 button:SetScript('OnLeave',function()GameTooltip:Hide()end)
end
local function button(parent,text,width,fn)
 local b=CreateFrame('Button',nil,parent);b:SetSize(width,25)
 UI.Style(b,'button');b.label=label(b,11);b.label:SetPoint('CENTER');b.label:SetText(text)
 b:SetScript('OnClick',fn);return b
end
local function position(f,key,defaultPoint,dx,dy)
 f:ClearAllPoints();local p=FR.Config()[key]
 if type(p)=='table'and tonumber(p.x)and tonumber(p.y)then f:SetPoint('CENTER',UIParent,'CENTER',p.x,p.y)
 else f:SetPoint(defaultPoint,UIParent,defaultPoint,dx,dy)end
end
local function movable(f,key)
 f:SetMovable(true);f:EnableMouse(true);f:RegisterForDrag('LeftButton')
 f:SetScript('OnDragStart',function(self)if not FR.Config().locked then self:StartMoving()end end)
 f:SetScript('OnDragStop',function(self)
  self:StopMovingOrSizing();local x,y=self:GetCenter();local ux,uy=UIParent:GetCenter()
  if x and ux then local s=self:GetScale();FR.Config()[key]={x=x-ux/s,y=y-uy/s}end
 end)
end
local function hide()frame:Hide();if menu then menu:Hide()end;FR.Config().hidden=true end
local function refresh()FR.Refresh()end
local function row(parent)
 local r=CreateFrame('Button',nil,parent);r:SetWidth(330);r:SetHeight(25);r:RegisterForClicks('LeftButtonUp','RightButtonUp')
 r.text=label(r,12);r.text:SetPoint('TOPLEFT',0,-2);r.text:SetWidth(330);r.text:SetWordWrap(true)
 r:SetScript('OnClick',function(self,which)
  if which=='RightButton'and self.task then FR.HideTask(self.task);refresh()
  elseif self.q then FR.OpenQuest(self.q)end
 end)
 r:SetScript('OnEnter',function(self)
  if self.item then GameTooltip:SetOwner(self,'ANCHOR_RIGHT');GameTooltip:SetItemByID(self.item);GameTooltip:Show()
  elseif self.q then FR.ShowQuestTooltip(self,self.q,self.objective)
  elseif self.task then GameTooltip:SetOwner(self,'ANCHOR_RIGHT');GameTooltip:AddLine(FR.Text(self.task),1,1,1,true);GameTooltip:AddLine('Rechtsklick: Nebenaufgabe ausblenden');GameTooltip:Show()end
 end)
 r:SetScript('OnLeave',function()GameTooltip:Hide();FR.HideQuestTooltip()end)
 r:Hide();return r
end
local function setRow(r,text,y,color)
 r.text:SetText(text);r.text:SetTextColor(unpack(color or C.text));r:ClearAllPoints();r:SetPoint('TOPLEFT',frame,'TOPLEFT',25,-y)
 local h=math.max(20,r.text:GetStringHeight()+6);r:SetHeight(h);r:Show();return y+h
end
local function makeFrame()
 if frame then return frame end
 frame=CreateFrame('Frame','ForeverRoutesFrame',UIParent);FR.frame=frame
 frame:SetSize(380,300);frame:SetClampedToScreen(true);frame:SetFrameStrata('MEDIUM');UI.Style(frame,'panel')
 movable(frame,'window');position(frame,'window','RIGHT',-35,80)
 frame:SetScale(math.max(.65,math.min(1.5,tonumber(FR.Config().scale)or 1)))
 frame.crystal=CreateFrame('Button',nil,frame);frame.crystal:SetSize(30,30);frame.crystal:SetPoint('TOPLEFT',19,-15)
 frame.crystal.tex=frame.crystal:CreateTexture(nil,'ARTWORK');frame.crystal.tex:SetAllPoints()
 tip(frame.crystal,'ForeverCore','Blau: ForeverCore hat in dieser Sitzung geantwortet. Ohne Verbindung folgt ForeverRoutes der gespeicherten Route.')
 local title=UI.Text(frame,17,C.gold,'title');title:SetPoint('TOPLEFT',56,-21);title:SetText('ForeverRoutes')
 local close=button(frame,'X',25,hide);close:SetPoint('TOPRIGHT',-18,-17)
 local collapse=button(frame,'-',25,function()FR.Config().compact=not FR.Config().compact;refresh()end);collapse:SetPoint('RIGHT',close,'LEFT',-2,0)
 tip(collapse,'Kompaktansicht','Nur den aktuellen Schritt mit Fortschritt zeigen.')
 frame.status=label(frame,10,C.muted);frame.status:SetPoint('TOPLEFT',25,-54);frame.status:SetWidth(330)
 frame.current=CreateFrame('Button',nil,frame);frame.current:SetPoint('TOPLEFT',25,-76);frame.current:SetWidth(330)
 frame.current.text=label(frame.current,14,C.gold);frame.current.text:SetPoint('TOPLEFT');frame.current.text:SetWidth(330);frame.current.text:SetWordWrap(true)
 frame.current:SetScript('OnClick',function()if view and view.step and view.step.q then FR.OpenQuest(view.step.q)end end)
 frame.current:SetScript('OnEnter',function(self)if view and view.step and view.step.q then FR.ShowQuestTooltip(self,view.step.q)end end)
 frame.current:SetScript('OnLeave',FR.HideQuestTooltip)
 frame.hint=label(frame,11,C.muted);frame.hint:SetWidth(330);frame.hint:SetWordWrap(true)
 frame.rows={};for i=1,24 do frame.rows[i]=row(frame)end
 frame.nextLabel=label(frame,10,C.muted)
 frame.nextRows={};for i=1,3 do frame.nextRows[i]=row(frame)end
 frame.back=button(frame,'Zurück',66,function()FR.Back();refresh()end);frame.back:SetPoint('BOTTOMLEFT',21,22)
 frame.skip=button(frame,'Überspringen',105,function()FR.Skip();refresh()end);frame.skip:SetPoint('LEFT',frame.back,'RIGHT',3,0)
 frame.confirm=button(frame,'Erledigt',76,function()FR.Confirm();refresh()end);frame.confirm:SetPoint('LEFT',frame.skip,'RIGHT',3,0)
 tip(frame.confirm,'Schritt bestätigen','Nur für manuelle Aufgaben. Quests werden durch den tatsächlichen Questfortschritt abgeschlossen.')
 frame.options=button(frame,'...',32,function()FR.ToggleMenu()end);frame.options:SetPoint('LEFT',frame.confirm,'RIGHT',3,0)
 tip(frame.skip,'Schritt überspringen','Mit Zurück den letzten übersprungenen Schritt wiederherstellen. Die Quest wird nicht als erledigt markiert.')
 return frame
end
local function optionMenu()
 if menu then return menu end
 menu=CreateFrame('Frame','ForeverRoutesOptions',UIParent);menu:SetSize(360,330);menu:SetFrameStrata('DIALOG');menu:SetClampedToScreen(true);UI.Style(menu,'panel')
 local title=label(menu,15,C.gold);title:SetPoint('TOPLEFT',24,-20);title:SetText('Routenoptionen')
 local close=button(menu,'X',25,function()menu:Hide()end);close:SetPoint('TOPRIGHT',-18,-15)
 local actions={
  {'Mit / ohne Dungeons',function()FR.SetDungeons(not FR.CharDB().dungeons);refresh()end},
  {'Nebenaufgaben wieder anzeigen',function()FR.RestoreTasks();refresh()end},
  {'Übersprungene wiederherstellen',function()FR.RestoreSkipped();refresh()end},
  {'Position sperren / entsperren',function()FR.Config().locked=not FR.Config().locked end},
 }
 for i,a in ipairs(actions)do local b=button(menu,a[1],305,a[2]);b:SetPoint('TOPLEFT',25,-45-(i-1)*28)end
 menu.scroll=CreateFrame('ScrollFrame',nil,menu,'UIPanelScrollFrameTemplate');menu.scroll:SetPoint('TOPLEFT',25,-165);menu.scroll:SetSize(283,136)
 menu.child=CreateFrame('Frame',nil,menu.scroll);menu.child:SetSize(280,136);menu.scroll:SetScrollChild(menu.child);menu.rows={}
 menu:Hide();return menu
end
function FR.ToggleMenu()
 local f=optionMenu();if f:IsShown()then f:Hide();return end
 f:ClearAllPoints();f:SetPoint('CENTER',UIParent,'CENTER',0,0)
 for _,r in ipairs(f.rows)do r:Hide()end
 local opts=FR.Options()
 for i,o in ipairs(opts)do
  local b=f.rows[i]
  if not b then b=button(f.child,'',275,function(self)FR.SetOption(self.option);FR.ToggleMenu();FR.ToggleMenu();refresh()end);f.rows[i]=b end
  b.option=i;b:ClearAllPoints();b:SetPoint('TOPLEFT',0,-(i-1)*30)
  b.label:SetText(((FR.CharDB().opts or{})[o.id]and'[an] 'or'[aus] ')..o.n)
  tip(b,o.n,(o.nt or'')..string.format('\n%+d Min · Abschluss Stufe %d',o.min or 0,o.l or 0));b:Show()
 end
 f.child:SetHeight(math.max(136,#opts*30));f:Show()
end
-- An independent, movable arrow with the same card/crystal art as the route HUD.
local arrow
local function makeArrow()
 if arrow then return end
 arrow=CreateFrame('Frame','ForeverRoutesArrow',UIParent);FR.arrow=arrow;arrow:SetSize(170,99);arrow:SetClampedToScreen(true)
 UI.Style(arrow,'note');movable(arrow,'arrow');position(arrow,'arrow','TOP',0,-110)
 arrow.tex=arrow:CreateTexture(nil,'ARTWORK');arrow.tex:SetSize(32,32);arrow.tex:SetPoint('TOP',0,-9)
 arrow.tex:SetTexture('Interface\\Minimap\\MinimapArrow')
 arrow.distance=label(arrow,12,C.gold);arrow.distance:SetJustifyH('CENTER');arrow.distance:SetPoint('TOP',0,-43);arrow.distance:SetWidth(145)
 arrow.target=label(arrow,10,C.text);arrow.target:SetPoint('TOP',0,-61);arrow.target:SetWidth(143);arrow.target:SetHeight(24);arrow.target:SetJustifyH('CENTER')
 arrow:Hide()
end
local function updateArrow(step)
 local nav=FR.Navigation(step);FR.UpdateWaypoint(step,nav);makeArrow()
 if not nav or FR.Config().arrowHidden then arrow:Hide();return end
 arrow.target:SetText(nav.dying and'Death Skip'or(step.tg or step.n or FR.Text(step)))
 if nav.distance then
  arrow.distance:SetText(nav.arrived and'Ziel erreicht'or(nav.distance>=1000 and string.format('%.1f km',nav.distance/1000)or string.format('%d m',nav.distance)))
 else arrow.distance:SetText('Anderes Gebiet')end
 if nav.rotation and not nav.arrived then arrow.tex:SetRotation(nav.rotation);arrow.tex:Show()else arrow.tex:Hide()end
 arrow:Show()
end
function FR.Refresh()
 view=FR.TaskView();updateArrow(view.step)
 if not frame or not frame:IsShown()then return view.step end
 local connected=FR.Connected();UI.SetArt(frame.crystal.tex,connected and'crystal_on'or'crystal_off')
 local mode=view.live and'Live geplant'or(view.kind=='rxp-fallback'and'Guide-Fallback'or'Gespeicherte Route')
 frame.status:SetText(view.paused and'Route pausiert · Dungeon'or string.format('%s · Schritt %d/%d',mode,math.min(view.index,view.total),view.total))
 frame.current.text:SetText(view.text)
 local ch=math.max(26,frame.current.text:GetStringHeight()+6);frame.current:SetHeight(ch)
 local y=76+ch
 frame.hint:ClearAllPoints();frame.hint:SetPoint('TOPLEFT',25,-y)
 frame.hint:SetText(view.paused and'Nach dem Dungeon geht es beim nächsten offenen Schritt weiter.'or(view.hint or''))
 if frame.hint:GetText()~=''then y=y+frame.hint:GetStringHeight()+9 end
 local ri=0
 local function add(text,color,q,objective,item,task)
  ri=ri+1;local r=frame.rows[ri];if not r then return end
  r.q,r.objective,r.item,r.task=q,objective,item,task;y=setRow(r,text,y,color)
 end
 -- Quest progress comes from the game, not from the route's estimated counts.
 if view.step and view.step.q then
  for i,o in ipairs(FR.Objectives(view.step))do
   add((o.finished and'|cff50df6eOK|r 'or'- ')..(o.text or string.format('%d/%d',o.numFulfilled or 0,o.numRequired or 0)),o.finished and C.good or C.text,view.step.q,i)
  end
 end
 for _,it in ipairs(view.items)do add(it.text,it.done and C.good or C.text,nil,nil,it.id)end
 local bag=FR.BagHint();if bag then add(bag,C.gold)end
 if not FR.Config().compact then
  local _,camp=FR.CampStatus();if camp then add(camp,C.muted)end
  for _,task in ipairs(view.parallel)do add('Nebenbei: '..FR.Text(task),C.muted,nil,nil,nil,task)end
 end
 for i=ri+1,#frame.rows do frame.rows[i]:Hide()end
 frame.nextLabel:Hide();for _,r in ipairs(frame.nextRows)do r:Hide()end
 if not FR.Config().compact and view.step then
  local steps=FR.Steps();local count=0
  for i=view.index+1,#steps do
   local s=steps[i]
   if not FR.Done(s)and(view.live or not FR.CharDB().skipped[i])then
    count=count+1
    if count==1 then frame.nextLabel:ClearAllPoints();frame.nextLabel:SetPoint('TOPLEFT',25,-y-6);frame.nextLabel:SetText('DANACH');frame.nextLabel:Show();y=y+25 end
    local r=frame.nextRows[count];r.q,r.task,r.item,r.objective=s.q,nil,nil,nil
    y=setRow(r,FR.Text(s),y,C.muted);if count==3 then break end
   end
  end
 end
 frame.confirm:SetEnabled(FR.CanConfirm(view.step)and true or false)
 frame.skip:SetEnabled(view.step~=nil and not view.paused);frame.back:SetEnabled(not view.paused and(FR.undo~=nil or not view.live))
 frame:SetHeight(math.max(175,y+62))
 return view.step
end
function FR.Show()makeFrame():Show();FR.Config().hidden=nil;FR.Refresh()end
local driver=CreateFrame('Frame');local elapsed=0;local pending=false;local full=0
local events={'PLAYER_LOGIN','PLAYER_ENTERING_WORLD','QUEST_ACCEPTED','QUEST_TURNED_IN','QUEST_REMOVED','QUEST_LOG_UPDATE','PLAYER_LEVEL_UP','PLAYER_DEAD','PLAYER_UNGHOST','PLAYER_ALIVE','UNIT_AURA','BAG_UPDATE_DELAYED','GET_ITEM_INFO_RECEIVED','PLAYER_REGEN_ENABLED','ADDON_LOADED'}
for _,e in ipairs(events)do pcall(driver.RegisterEvent,driver,e)end
driver:SetScript('OnEvent',function(_,event,unit)
 if event=='UNIT_AURA'and unit~='player'then return end
 if event=='PLAYER_LOGIN'then if not FR.Config().hidden then FR.Show()end;FR.ScanQuestTracker();return end
 if event=='PLAYER_DEAD'then FR.Died()end
 pending=true
end)
driver:SetScript('OnUpdate',function(_,dt)
 elapsed=elapsed+dt;full=full+dt;if elapsed<.15 then return end;elapsed=0
 if pending or full>=1 then pending=false;full=0;FR.Refresh();FR.ScanQuestTracker()
 else updateArrow(view and view.step)end
end)
SLASH_FOREVERROUTES1='/fr'
SlashCmdList.FOREVERROUTES=function(msg)
 msg=strtrim(tostring(msg or'')):lower()
 if msg==''then if frame and frame:IsShown()then hide()else FR.Show()end;return end
 if msg=='hide'then if frame then hide()else FR.Config().hidden=true end;return end
 if msg=='skip'then FR.Skip()elseif msg=='back'or msg=='zurueck'then FR.Back()
 elseif msg=='done'then FR.Confirm()elseif msg=='reset'then FR.Reset()
 elseif msg=='dungeon'or msg=='dungeons'or msg=='mit'or msg=='gruppe'then FR.SetDungeons(true)
 elseif msg=='solo'or msg=='ohne'then FR.SetDungeons(false)
 elseif msg=='lager'or msg=='camp'then FR.Camped()
 elseif msg=='optionen'or msg=='options'or msg=='option'then FR.ToggleMenu();return
 elseif msg:match('^option%s+%d+$')then FR.SetOption(msg:match('(%d+)$'))
 elseif msg=='restore'then FR.RestoreSkipped();FR.RestoreTasks()
 elseif msg=='compact'then FR.Config().compact=not FR.Config().compact
 elseif msg=='lock'then FR.Config().locked=not FR.Config().locked
 elseif msg=='arrow'then FR.Config().arrowHidden=not FR.Config().arrowHidden
 elseif msg:match('^scale%s+[%d%.]+$')then
  FR.Config().scale=math.max(.65,math.min(1.5,tonumber(msg:match('([%d%.]+)$'))or 1));if frame then frame:SetScale(FR.Config().scale)end
 elseif msg=='position'then FR.Config().window=nil;FR.Config().arrow=nil;if frame then position(frame,'window','RIGHT',-35,80)end;if arrow then position(arrow,'arrow','TOP',0,-110)end
 elseif msg~='show'then print('ForeverRoutes: /fr · show · hide · skip · back · done · options · compact · lock · arrow · scale 1 · position · restore');return end
 FR.Show()
end
