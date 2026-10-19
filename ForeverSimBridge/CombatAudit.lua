-- Compatibility facade for old views. Combat collection and inferred calibration are removed.
local P=FUSLive
local A={liveCaptureSupported=false};P.combatAudit=A
function A.Signature(p)
 return P.canonical({class=p.class,level=p.level,race=p.race,talents=p.talents,spells=p.knownSpellRanks,equipped=p.equipped,stats=p.stats,pet=p.pet,petActive=p.petActive,auras=p.activeAuras})
end
function A.Report()return {'Kampferfassung entfernt. Ergebnisse stammen aus expliziten Offline-Szenarien; kein Abgleich mit Live-Kampfdaten.'}end
function A.levelingContext()return nil end
function A.Command(msg)
 if msg=='audit'or msg=='audit reset'then
  if print then print('Forever SIM: '..A.Report()[1])end
  return true
 end
end
local f=CreateFrame('Frame');f:RegisterEvent('ADDON_LOADED')
f:SetScript('OnEvent',function(self,_,name)
 if name~='ForeverSimBridge'then return end
 if ForeverSimBridgeDB then ForeverSimBridgeDB.combatAudit=nil end
 self:UnregisterEvent('ADDON_LOADED')
end)
