-- ForeverSimBridge: on-demand visualization of ONE engine combat trace.
-- No new spell logic, no fabricated damage values and no background simulation.
local P=_G.FUSLive
if not P then return end
local T={};P.traceUI=T
local root='Interface\\AddOns\\ForeverSimBridge\\Media\\'
local gold={.91,.75,.42};local pale={.92,.90,.86};local blue={.54,.80,1};local green={.48,.86,.60};local muted={.67,.70,.76}
local frame,summary,warning,resourceTitle,spellTitle
local resourceBars,spellRows,castRows={},{},{}
local function safe(fn,...)
 if type(fn)~='function'then return nil end
 local ok,v=pcall(fn,...)
 if ok and (not P.isProtected or not P.isProtected(v))then return v end
end
local function number(v)
 if P.publicNumber then return P.publicNumber(v)end
 if type(v)=='number'and v==v and math.abs(v)<1e12 then return v end
end
local function combat()return safe(InCombatLockdown)==true end
local function label(owner,x,y,w,size,s,color)
 local f=owner:CreateFontString(nil,'OVERLAY',size>17 and'GameFontNormalLarge'or'GameFontNormal')
 f:SetPoint('TOPLEFT',x,y);f:SetWidth(w);f:SetJustifyH('LEFT');f:SetJustifyV('TOP');f:SetWordWrap(true)
 f:SetTextColor(unpack(color or pale));f:SetText(s or'');return f
end
local function panel(parent,x,y,w,h,heading)
 local f=CreateFrame('Frame',nil,parent,'BackdropTemplate');f:SetSize(w,h);f:SetPoint('TOPLEFT',x,y)
 f:SetBackdrop({bgFile=root..'FQDark',edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',edgeSize=12,insets={left=4,right=4,top=4,bottom=4}})
 f:SetBackdropColor(.04,.05,.085,.96);f:SetBackdropBorderColor(.53,.42,.24,.95)
 label(f,14,-13,w-26,18,heading,gold);return f
end
local function button(parent,x,y,w,caption,click)
 local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate');b:SetSize(w,32);b:SetPoint('TOPLEFT',x,y)
 b:SetText(caption);b:SetScript('OnClick',function()if not combat()then click()end end);return b
end
local function construct()
 if frame then return end
 frame=CreateFrame('Frame','ForeverSimTraceStudio',UIParent,'BackdropTemplate');frame:SetSize(955,738);frame:SetPoint('CENTER')
 frame:SetMovable(true);frame:SetClampedToScreen(true);frame:EnableMouse(true);frame:RegisterForDrag('LeftButton')
 frame:SetScript('OnDragStart',function(self)if not combat()then self:StartMoving()end end)
 frame:SetScript('OnDragStop',function(self)self:StopMovingOrSizing()end)
 frame:SetBackdrop({bgFile=root..'FQDark',edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',edgeSize=16,insets={left=6,right=6,top=6,bottom=6}})
 frame:SetBackdropColor(.025,.04,.07,.98);frame:SetBackdropBorderColor(.7,.53,.28,.96)
 label(frame,21,-17,790,26,'FOREVER SIM  /  KAMPF-TRACE STUDIO',gold)
 label(frame,23,-56,865,13,'EIN MANUELLER ENGINE-LAUF  ·  MAX. 60 SEKUNDEN  ·  KEIN DPS-DURCHSCHNITT',blue)
 local close=CreateFrame('Button',nil,frame,'UIPanelCloseButton');frame.appClose=close;close:SetPoint('TOPRIGHT',-7,-8);close:SetScript('OnClick',function()frame:Hide()end)
 local top=panel(frame,13,-91,929,110,'SIMULATIONSERGEBNIS  /  AUS EINEM REPRODUZIERBAREN LAUF')
 summary=label(top,18,-48,892,16,'Noch kein Trace berechnet.',pale)
 local r=panel(frame,13,-211,929,170,'RESSOURCENVERLAUF  /  12 GEMESSENE ZEITSCHNITTE')
 resourceTitle=label(r,17,-47,890,13,'Noch keine Ressourcenwerte.',blue)
 for i=1,12 do
  local bar=CreateFrame('Frame',nil,r);bar:SetSize(65,85);bar:SetPoint('TOPLEFT',16+(i-1)*75,-70)
  local bg=bar:CreateTexture(nil,'BACKGROUND');bg:SetColorTexture(.17,.20,.27,.9);bg:SetPoint('BOTTOMLEFT',17,15);bg:SetSize(31,61)
  local fill=bar:CreateTexture(nil,'ARTWORK');fill:SetColorTexture(.48,.76,.98,.98);fill:SetPoint('BOTTOMLEFT',17,15);fill:SetSize(31,1)
  local value=label(bar,0,-2,65,11,'-',pale);value:SetJustifyH('CENTER')
  local sec=label(bar,0,-72,65,10,tostring(i*5)..'s',muted);sec:SetJustifyH('CENTER')
  resourceBars[i]={fill=fill,number=value}
 end
 local left=panel(frame,13,-391,456,239,'SCHADEN JE ZAUBER  /  ECHTE ENGINE-ROWS')
 spellTitle=label(left,15,-45,420,12,'Die sechs stärksten Einträge nach Gesamtschaden.',blue)
 for i=1,6 do
  local t=label(left,15,-67-(i-1)*27,420,14,'',pale);spellRows[i]=t
 end
 local right=panel(frame,481,-391,461,239,'CAST-ANFÄNGE  /  ECHTE TRACE-EVENTS')
 for i=1,8 do castRows[i]=label(right,15,-53-(i-1)*21,428,13,'',pale)end
 local action=panel(frame,13,-642,929,81,'SIM-KONTROLLE')
 button(action,18,-42,430,'Einzelkampf jetzt simulieren',function()T.Calculate()end)
 button(action,476,-42,433,'Zurueck zum Insight Studio',function()frame:Hide();if P.insightsUI then P.insightsUI.Show('charts')end end)
 warning=label(frame,23,-627,886,11,'Einzeltrace = ein Seed; keine garantierte DPS und keine Raid-Simulation.',muted)
 frame:Hide();-- No writes to Blizzard UISpecialFrames (taint isolation).
end
local function samples(result,choice,initial)
 local log=result.events or {};local attr=choice=='Energie' and 'energy' or choice=='Wut' and 'rage' or 'mana'
 local total=choice=='Mana' and (number(initial) or 0) or 100
 local values={};local j=1;local current=number(initial) or (choice=='Energie' and 100 or 0)
 for i=1,12 do
  local at=i*5
  while j<=#log and (number(log[j].t) or 1e9)<=at do
   local v=number(log[j][attr]);if v then current=v end
   j=j+1
  end
  values[i]=current
 end
 local max=total or 0
 for _,v in ipairs(values)do if v and v>max then max=v end end
 return values,math.max(1,max)
end
local function render()
 if not frame then return end
 local r=T.result
 if T.busy then summary:SetText('SIM-Job laeuft ueber die vorhandene Engine-Warteschlange.\\nKeine Automatik oder Hintergrund-Neuberechnung.')
 elseif T.error then summary:SetText('Trace nicht verfuegbar: '..tostring(T.error))
 elseif r then
  summary:SetText(string.format('%s  ·  Level %d  ·  %.1f DPS  ·  %.0f Gesamtschaden  ·  60s  ·  1 Seed',r.class,r.level,r.dps,r.total))
 else summary:SetText('Noch keine Einzelsimulation. Mit dem Button einen 60-Sekunden-Trace erzeugen.')end
 if not r then
  resourceTitle:SetText('Keine Daten.');spellTitle:SetText('Noch keine Zauberverteilung.')
  for _,bar in ipairs(resourceBars)do bar.fill:SetHeight(1);bar.number:SetText('-')end
  for _,lbl in ipairs(spellRows)do lbl:SetText('')end
  for _,lbl in ipairs(castRows)do lbl:SetText('')end
  return
 end
 local resource=r.resource
 local values,max=samples(r.run,resource,r.initial)
 resourceTitle:SetText(resource..': '..(r.initial and string.format('Start %.0f',r.initial) or 'Start nicht auslesbar')..' · '..string.format('Ende %.0f',r.final or 0)..'  |  Zeitpunkte 5–60s')
 for i,b in ipairs(resourceBars)do local v=values[i];b.fill:SetHeight(math.max(1,math.min(61,61*(v or 0)/max)));b.number:SetText(v and string.format('%.0f',v) or '-')end
 local rows={}
 for key,v in pairs(r.run.bySpell or {})do
  if type(v)=='table' then local dmg=number(v.damage) or 0;local casts=number(v.casts) or 0
   if dmg>0 or casts>0 then rows[#rows+1]={key=tostring(key),damage=dmg,casts=casts}end end
 end
 table.sort(rows,function(a,b)if a.damage~=b.damage then return a.damage>b.damage end return a.key<b.key end)
 spellTitle:SetText(#rows..' Einträge mit Schaden/Casts  |  sortiert nach Gesamtschaden')
 for i,label in ipairs(spellRows)do local v=rows[i];label:SetText(v and string.format('%s: %.0f Schaden  |  %d Casts',v.key,v.damage,v.casts) or '')end
 local starts={}
 for _,v in ipairs(r.run.events or {})do
  if v.kind=='start' then starts[#starts+1]=v;if #starts>=#castRows then break end end
 end
 for i,label in ipairs(castRows)do local v=starts[i];label:SetText(v and string.format('%5.1fs  ·  %s',number(v.t)or 0,tostring(v.key or '?')) or '')end
end
function T.Calculate()
 if combat()then return end
 if T.busy and T.busyRevision~=P.revision then T.busy=false end
 if T.busy then return end
 T.error=nil;T.result=nil
 if not(P.capture and P.normalizeSnapshot and P.coverage and P.combine and P.compile and P.run and P.enqueue and P.candidates and P.copy)then T.error='SIM-Modul unvollstaendig';render();return end
 local snap=safe(P.capture,true)
 if not snap then T.error='Charaktersnapshot fehlt';render();return end
 local good,profile=pcall(P.normalizeSnapshot,snap)
 if not good or not profile then T.error='Profil unvollstaendig: '..tostring(profile);render();return end
 local data=FUSLiveData and FUSLiveData[profile.class]
 if not data then T.error='Klassenmodul fehlt';render();return end
 local ok,issue=pcall(P.coverage,data,profile)
 if not ok or issue then T.error='Klassenmodell nicht abgedeckt: '..tostring(issue);render();return end
 local gearOK,stats=pcall(P.combine,profile.equipped or {})
 if not gearOK then T.error='Ausrüstung nicht berechenbar: '..tostring(stats);render();return end
 local choicesOK,choices=pcall(P.candidates,data,profile)
 if not choicesOK then T.error='Rotationsregeln fehlen: '..tostring(choices);render();return end
 local chosen=not P.stale and P.lastRotation and P.lastRotation.choice or choices[1]
 if not chosen then T.error='Keine Rotation fuer diesen Charakter';render();return end
 local revision=P.revision;T.busy=true;T.busyRevision=revision;render()
 P.enqueue(function()
  local testProfile=P.copy(profile);testProfile.trace=true
  local spec=P.compile(data,testProfile,stats,chosen,60,7331)
  local output=P.run(spec)
  local resource=spec.resource=='energy' and 'Energie' or spec.resource=='rage' and 'Wut' or 'Mana'
  local initial=resource=='Mana' and (spec.initial or {}).mana or resource=='Energie' and ((spec.resources or {}).energy or 100) or ((spec.resources or {}).rage or 0)
  local final=resource=='Mana' and output.manaEnd or resource=='Energie' and output.energyEnd or output.rageEnd
  return {class=profile.class,level=profile.level,resource=resource,initial=initial,final=final,dps=output.dps,total=output.total,run=output}
 end,function(result,err)
  T.busy=false
  if err or not result or not number(result.dps) then T.error='Berechnung fehlgeschlagen: '..tostring(err or 'ohne Ergebnis')else T.result=result;T.resultRevision=revision end
  render()
 end,function()return P.revision==revision end)
end
function T.Show()
 if combat()then return end
 if T.busy and T.busyRevision~=P.revision then T.busy=false;T.error='Profil geaendert; bitte neuen Trace berechnen.'end
 if T.result and T.resultRevision~=P.revision then T.result=nil;T.error='Profil geaendert; bitte neuen Trace berechnen.'end
 construct();frame:Show();render()
end
SLASH_FOREVERSIMTRACE1='/fsimtrace'
SlashCmdList.FOREVERSIMTRACE=function()T.Show()end

-- Expose only the addon-owned root for the embedded app view.
function T.GetFrame() return frame end
