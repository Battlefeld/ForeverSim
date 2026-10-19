-- Offline target-health provenance. Never reads target or combat APIs.
-- Coefficients below are configurable SIM assumptions, not verified NPC data.
local P=FUSLive
local H={revision=1,MODEL={base=40,perLevel=15,quadratic=.60,eliteMultiplier=2.5}}
P.targetHealth=H
local function number(value)
 if P.publicNumber then return P.publicNumber(value)end
 if P.isProtected and P.isProtected(value)then return nil end
 if type(value)~='number'or value~=value or value==math.huge or value==-math.huge then return nil end
 return value
end
local function level(value)
 local v=number(value)
 if not v or v<1 or v>100 then return nil end
 return math.floor(v+.5)
end
local function health(value)
 local v=number(value)
 if not v or v<=0 or v>=10000000 then return nil end
 return v
end
function H.Estimate(targetLevel,kind)
 local l=level(targetLevel)
 if not l then return nil end
 local c=H.MODEL
 local estimate=c.base+c.perLevel*l+c.quadratic*l*l
 if kind=='elite'then estimate=estimate*c.eliteMultiplier end
 return math.floor(estimate+.5)
end
-- Historical combat-derived measurements are no longer accepted as model evidence.
function H.Observation()return nil end
function H.Resolve(profile,options)
 profile=profile or {};options=options or {}
 local encounter=profile.encounter or {}
 local manualLevel=level(options.targetLevel)
 if options.targetLevel~=nil and not manualLevel then
  return nil,{code='TARGET_LEVEL_INVALID',message='Manuelles Gegnerlevel muss zwischen 1 und 100 liegen'}
 end
 local encounterLevel=(encounter.mode=='quest' or encounter.mode=='elite')and level(encounter.targetLevel)
 local targetLevel=manualLevel or encounterLevel or level(profile.level)
 if not targetLevel then return nil,{code='TARGET_LEVEL_INVALID',message='Gegnerlevel fehlt oder ist ungültig'}end
 local manual=health(options.targetHealth)
 if options.targetHealth~=nil and not manual then
  return nil,{code='TARGET_HEALTH_INVALID',message='Manuelles Gegnerleben muss eine öffentliche positive Zahl sein'}
 end
 if manual then
  return {targetHealth=manual,targetLevel=targetLevel,source='Manuelle HP-Eingabe (nicht verifiziert)',
   sourceCode='manual',estimated=false,healthConfidence='manual',providerRevision=H.revision}
 end
 local kind=encounter.mode=='elite' and 'elite' or 'normal'
 return {targetHealth=H.Estimate(targetLevel,kind),targetLevel=targetLevel,
  source='Generiertes HP-Modell (Annahme, keine Live-HP)',sourceCode='model',estimated=true,
  healthConfidence='model',modelKind=kind,modelCoefficients=P.copy(H.MODEL),providerRevision=H.revision,
  healthNote='Lebenspunkte sind eine konfigurierbare Benchmark-Annahme, kein verifizierter NPC-Wert.'}
end
