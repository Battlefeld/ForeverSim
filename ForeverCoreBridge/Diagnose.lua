-- /fc test: checks in the real client every assumption ForeverCore makes, prints the result and
-- keeps it in ForeverCoreBridgeDB.diagnose (SavedVariables, written on /reload or logout) so the
-- file can be sent back. Reads only; changes nothing.
local C=ForeverCoreClient or {};ForeverCoreClient=C

local function out(lines,ok,text)
 local mark=ok==true and '|cff33ff33OK|r' or ok==false and '|cffff4444FEHLT|r' or '|cffffcc00INFO|r'
 lines[#lines+1]={ok=ok,text=text}
 if print then print('|cff66ccffForeverCore Test|r '..mark..' '..text)end
end
local function has(name)return _G[name]~=nil end

function C.Diagnose()
 local lines={}
 if InCombatLockdown and InCombatLockdown()then out(lines,nil,'Diagnose erst ausserhalb des Kampfes');return lines end
 local P=FUSLive
 out(lines,nil,('Client %s, Sprache %s'):format(tostring(GetBuildInfo and select(2,GetBuildInfo())or '?'),tostring(GetLocale and GetLocale()or '?')))
 if not P or not P.capture then out(lines,false,'ForeverSim (FUSLive) nicht geladen');return lines end
 local ok,snap=pcall(P.capture,true)
 if not ok or type(snap)~='table'then out(lines,false,'Snapshot fehlgeschlagen: '..tostring(snap));return lines end
 out(lines,nil,('%s Level %s'):format(tostring(snap.class),tostring(snap.level)))

 -- Spellbook: complete, and does it list several ranks of the same spell?
 local spells=snap.spells or {}
 local byName,multi={},0
 for _,s in ipairs(spells)do byName[s.name]=(byName[s.name]or 0)+1 end
 for _,n in pairs(byName)do if n>1 then multi=multi+1 end end
 out(lines,(snap.spellbookStatus or {}).state=='valid',('Zauberbuch: %d Eintraege, Status %s'):format(#spells,tostring((snap.spellbookStatus or {}).state)))
 out(lines,nil,('Zauber mit mehreren Raengen im Zauberbuch: %d (0 heisst: nur hoechster Rang sichtbar)'):format(multi))

 -- Every class: stance/form, temporary weapon enchantments, active buffs with their IDs.
 out(lines,nil,('Form/Haltung: Zauber %s'):format(tostring(snap.formSpell)))
 local we=snap.weaponEnchants or {}
 out(lines,nil,('Waffenverzauberung: Haupthand %s, Nebenhand %s'):format(tostring(we.mainhand),tostring(we.offhand)))
 local buffs={}
 for _,a in ipairs(snap.activeAuraInfo or {})do buffs[#buffs+1]=tostring(a.name)..' '..tostring(a.id)end
 out(lines,nil,'Aktive Buffs: '..(#buffs>0 and table.concat(buffs,', ')or 'keine'))
 if snap.petActive and snap.class~='HUNTER'then
  local p=snap.petLive or {}
  local s,d=p.stats or {},p.damage or {}
  out(lines,p.status=='ok',('Begleiter: %s, Familie %s (ID %s), Level %s, Mana %s, Str %s Agi %s Sta %s Int %s Wil %s, Schaden %s-%s Faktor %s'):format(
   tostring(p.status),tostring(p.family),tostring(p.familyId),tostring(p.level),tostring(p.mana),tostring(s.strength),tostring(s.agility),tostring(s.stamina),tostring(s.intellect),tostring(s.spirit),tostring(d.min),tostring(d.max),tostring(d.percent)))
 end
 for _,row in ipairs(snap.petSpellInfo or {})do
  local v={};for i,n in ipairs(row.values or {})do v[i]=tostring(n)end
  out(lines,row.described==true,('Begleiterzauber %s: Zahlen aus der Beschreibung [%s], Kosten %s'):format(tostring(row.id),table.concat(v,' / '),tostring(row.cost)))
 end
 if snap.class=='HUNTER'then
  local h=snap.hunter or {}
  local a=h.ammo or {}
  out(lines,a.status=='ok',('Munition: %s, Item %s, %s DPS'):format(tostring(a.status),tostring(a.itemId),tostring(a.dps)))
  out(lines,nil,'Munitions-Vorlage: '..tostring(AMMO_DAMAGE_TEMPLATE))
  local q=h.quiver or {}
  out(lines,q.status~='unreadable',('Koecher/Munitionstasche: %s, Item %s, Zauber %s, Tempo %s%%'):format(tostring(q.status),tostring(q.itemId),tostring(q.spellId),tostring(q.hastePct)))
  if snap.petActive then
   local p=h.pet or {}
   out(lines,p.status=='ok',('Begleiter: %s, Familie %s (ID %s), Level %s, Tempo %s'):format(tostring(p.status),tostring(p.family),tostring(p.familyId),tostring(p.level),tostring(p.speed)))
   out(lines,p.familyId~=nil,'Familien-ID ueber C_CreatureInfo '..(p.familyId and 'gelesen' or 'nicht verfuegbar (Name reicht mit creature-families.json)'))
   local s,d,ap=p.stats or {},p.damage or {},p.attackPower or {}
   local total=type(ap.base)=='number'and type(ap.pos)=='number'and type(ap.neg)=='number'and(ap.base+ap.pos+ap.neg)or nil
   out(lines,nil,('Begleiterwerte: Str %s Agi %s Sta %s Int %s Wil %s | AP Basis %s + Bonus %s + Korrektur %s = Gesamt %s | Schaden %s-%s, Bonus %s/%s, Faktor %s'):format(
    tostring(s.strength),tostring(s.agility),tostring(s.stamina),tostring(s.intellect),tostring(s.spirit),
    tostring(ap.base),tostring(ap.pos),tostring(ap.neg),tostring(total),tostring(d.min),tostring(d.max),tostring(d.pos),tostring(d.neg),tostring(d.percent)))
  else
   out(lines,nil,'Kein Begleiter aktiv: fuer den Begleitertest Begleiter rufen und /fc test wiederholen')
  end
 end

 local db=ForeverCoreBridgeDB or {}
 out(lines,db.enabled==true,'Automatische Core-Planung '..(db.enabled and 'aktiv' or 'pausiert (/fc on)'))
 ForeverCoreBridgeDB=ForeverCoreBridgeDB or {enabled=false}
 ForeverCoreBridgeDB.diagnose={time=time and time()or 0,lines=lines,hunter=snap.hunter}
 if print then print('|cff66ccffForeverCore Test|r Ergebnis gespeichert. Nach /reload liegt es in WTF\\Account\\<Konto>\\SavedVariables\\ForeverCoreBridge.lua')end
 return lines
end
