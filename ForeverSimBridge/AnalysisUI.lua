local P=FUSLive;local U={};P.analysisUI=U
function P.explainItem(result)
 if not result then return {'Noch kein Itemvergleich.'}end
 if not result.eligible then return {'Nicht bewertbar: '..(result.reason or 'Itemdaten fehlen'),'Unbekannte Effekte werden nicht als null Schaden bewertet.'}end
 local out={string.format('Boss-Modell 60 / 90 / 120 s: %.1f → %.1f DPS (%+.2f%%)',result.baseDps or 0,result.newDps or 0,result.percent or 0)}
 if result.confidence95 then out[#out+1]=string.format('95%%-Streubereich der DPS-Differenz: %+.2f bis %+.2f',result.confidence95[1],result.confidence95[2])end
 if result.preview then out[#out+1]='Teilmodell: nicht alle Klasseneffekte unabhängig bestätigt.'end
 if result.leveling then
  local r=result.leveling
  if r.percent then out[#out+1]=string.format('Levelmodell: %+.2f%% Gegner/min',r.percent)end
  out[#out+1]=P.leveling.Text(r.candidate)
  if r.candidate and r.candidate.caveat then out[#out+1]=r.candidate.caveat end
 end
 out[#out+1]='Gemessene Rotationsgewinne >100% bleiben zulässig; der Streubereich ist eine Zusatzinformation.'
 return out
end
local function text()
 if U.tab=='audit'then return table.concat(P.combatAudit.Report(),'\n')end
 if U.tab=='dungeon'then return 'Die Loot-Liste des Dungeons zeigt ForeverCore: im Dungeon /fc dungeon.' end
 local r=P.lastLeveling;local lines={'Leveltempo · Einzelziel und Erholung'}
 if r then
  lines[#lines+1]='Start: '..P.leveling.Text(r.baseline)
  lines[#lines+1]='Beste geprüfte Levelrotation: '..P.leveling.Text(r.result)
  lines[#lines+1]=r.result.caveat
  local ctx=r.result.context or {}
  lines[#lines+1]=string.format('Gegner: %s Leben / Level %s · Weg %s s · Quelle: %s',ctx.targetHealth or '?',ctx.targetLevel or '?',ctx.moveSeconds or 3,ctx.source or 'eigene Angaben / Klassen-Regeneration')
  if ctx.manaPerSecond then lines[#lines+1]='Erholung Mana: '..ctx.manaPerSecond..'/s (Angabe)'end
  if ctx.healthPerSecond then lines[#lines+1]='Erholung Leben: '..ctx.healthPerSecond..'/s (Angabe)'end
 else
  local profile=P.app and P.app.state.character.profile
  local context=profile and P.leveling.Context(profile)
  lines[#lines+1]=context and ('Benchmark: '..tostring(context.targetHealth or '?')..' HP / Level '..tostring(context.targetLevel or '?')..' · Quelle: '..tostring(context.source or '?')) or 'Charakterdaten laden, dann Vergleich starten.'
  lines[#lines+1]='Automatische Live-HP sind deaktiviert. Das gekennzeichnete HP-Modell funktioniert ohne anvisiertes Ziel; manuelle HP überschreiben es.'
 end
 lines[#lines+1]='Boss-DPS und Leveltempo bleiben getrennte Ziele. Ergebnis ist ein Modell, kein gemessenes XP/h.'
 lines[#lines+1]='Eigene Erholungswerte lassen sich unten einstellen. Ohne nötige Lebens-Erholung wird keine Gegner/min-Zahl behauptet.'
 return table.concat(lines,'\n')
end
function U.Show(tab,key)
 if InCombatLockdown and InCombatLockdown()then return end
 local level=UnitLevel and UnitLevel('player');if level and level<FUSLive.minSimLevel() then print('Forever SIM: Auswertung ab Level '..FUSLive.minSimLevel()..'.');return end
 U.tab=tab or U.tab or 'leveling';U.key=key or U.key
 if not U.frame then
  local f=CreateFrame('Frame',nil,UIParent,'BackdropTemplate');U.frame=f
  f:SetSize(720,540);f:SetPoint('CENTER');f:SetFrameStrata('DIALOG');f:SetMovable(true);f:EnableMouse(true);f:RegisterForDrag('LeftButton');f:SetScript('OnDragStart',f.StartMoving);f:SetScript('OnDragStop',f.StopMovingOrSizing)
  local bg=f:CreateTexture(nil,'BACKGROUND');bg:SetAllPoints();bg:SetColorTexture(.03,.03,.05,.97)
  local title=f:CreateFontString(nil,'OVERLAY','GameFontNormalLarge');title:SetPoint('TOPLEFT',16,-14);title:SetText('Forever SIM · Entscheidung und Kampfabgleich')
  local close=CreateFrame('Button',nil,f,'UIPanelCloseButton');f.appClose=close;close:SetPoint('TOPRIGHT');close:SetScript('OnClick',function()f:Hide()end)
  local function button(label,x,fn,y,width)
   local b=CreateFrame('Button',nil,f,'UIPanelButtonTemplate');b:SetSize(width or 210,28);b:SetPoint('TOPLEFT',x,y or -44);b:SetText(label);b:SetScript('OnClick',fn);return b
  end
  button('Leveltempo',16,function()U.Show('leveling')end)
  button('Echte Kämpfe',247,function()U.Show('audit')end)
  button('Dungeon-Empfehlung',478,function()U.Show('dungeon')end)
  local scroll=CreateFrame('ScrollFrame',nil,f,'UIPanelScrollFrameTemplate');scroll:SetPoint('TOPLEFT',16,-88);scroll:SetPoint('BOTTOMRIGHT',-35,132)
  f.scroll=scroll;local edit=CreateFrame('EditBox',nil,scroll);edit:SetSize(662,310);edit:SetMultiLine(true);edit:SetAutoFocus(false);edit:SetFontObject('ChatFontNormal');edit:SetScript('OnEscapePressed',function()f:Hide()end);scroll:SetScrollChild(edit);f.edit=edit
  local fields={{'targetHealth','Gegner-Leben'},{'manaPerSecond','Mana / Sek.'},{'healthPerSecond','Leben / Sek.'},{'moveSeconds','Weg / Sek.'}}
  U.inputs={};U.inputLabels={}
  for i,v in ipairs(fields)do
   local label=f:CreateFontString(nil,'OVERLAY','GameFontNormalSmall');label:SetPoint('BOTTOMLEFT',16+(i-1)*174,101);label:SetText(v[2]);U.inputLabels[#U.inputLabels+1]=label
   local input=CreateFrame('EditBox',nil,f,'InputBoxTemplate');input:SetSize(145,25);input:SetPoint('BOTTOMLEFT',21+(i-1)*174,70);input:SetAutoFocus(false);U.inputs[v[1]]=input
  end
  U.valuesButton=button('Werte übernehmen',16,function()
   ForeverSimBridgeDB.leveling=ForeverSimBridgeDB.leveling or {};local d=ForeverSimBridgeDB.leveling
   local proposed={}
   for k,input in pairs(U.inputs)do
    local raw=input:GetText();local value=tonumber(raw)
    if raw~='' and (not value or value<0 or value>=10000000 or k=='targetHealth' and value<=0)then print('Forever SIM: Bitte gültige positive Zahlen eingeben.');return end
    proposed[k]=value
   end
   for k in pairs(U.inputs)do d[k]=proposed[k]end
   P.invalidate();P.leveling.Optimize()
  end,-495,160)
  U.startButton=button('Vergleich starten',190,function()if U.tab=='leveling' then P.leveling.Optimize()elseif U.tab=='dungeon' then if SlashCmdList.FOREVERCORE then SlashCmdList.FOREVERCORE('dungeon')end else U.Show('audit')end end,-495,160)
  U.applyButton=button('Levelrotation nutzen',364,function()P.leveling.Apply()end,-495,160)
  button('Text kopieren',538,function()f.edit:SetFocus();f.edit:HighlightText()end,-495,160)
  f:SetScript('OnUpdate',function(_,dt)U.elapsed=(U.elapsed or 0)+dt;if U.elapsed>=1 then U.elapsed=0;local nextText=text();if U.lastText~=nextText then U.lastText=nextText;f.edit:SetText(nextText)end end end)
 end
 local d=ForeverSimBridgeDB.leveling or {};local levelTab=U.tab=='leveling'
 for k,input in pairs(U.inputs)do input:SetText(d[k]~=nil and tostring(d[k])or '');input:SetShown(levelTab)end
 for _,label in ipairs(U.inputLabels)do label:SetShown(levelTab)end
 U.valuesButton:SetShown(levelTab);U.applyButton:SetShown(levelTab);U.startButton:SetText(levelTab and 'Vergleich starten' or 'Aktualisieren')
 U.frame.scroll:SetPoint('BOTTOMRIGHT',-35,levelTab and 132 or 56)
 U.frame.edit:SetText(text());U.frame:Show()
end
function U.Command(msg)if msg=='analysis'then U.Show('leveling');return true end end

-- Expose only the addon-owned root for the embedded app view.
function U.GetFrame() return U.frame end
