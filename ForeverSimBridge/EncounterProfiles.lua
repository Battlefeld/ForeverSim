-- Shared, class-neutral enemy benchmark profiles. No NPC-by-NPC quest database.
-- All synthetic defenses are explicit MODELS, never claims about a real mob.
-- Requires CombatEngine.lua (FUSLive and its copy helper); safe without FDQ.
local P = _G.FUSLive
if not P then return end
local M = {revision=1, schema=1}
P.encounters = M
local function copy(v)
 if type(v)~='table' then return v end
 local o={};for k,x in pairs(v)do o[k]=copy(x)end;return o
end
local function int(v,minimum,maximum)
 if type(v)~='number' or v~=v or v==math.huge or v==-math.huge then return nil end
 v=math.floor(v+.5)
 if v<minimum or v>maximum then return nil end
 return v
end
local function text(v)
 if type(v)=='string' and #v>0 and #v<180 then return v end
 return nil
end
local function normMode(mode,level)
 if mode=='quest' or mode=='elite' or mode=='dungeon' or mode=='standard' then return mode end
 -- Level bands of ZIELE.md: 1-30 quest mob, 31-49 dungeon boss, 50-60 raid boss.
 return level>=50 and 'standard' or level>=31 and 'dungeon' or 'quest'
end
M.NORMAL_PROFILES={
 {id='minus1',offset=-1,name='Normal: -1 Level'},
 {id='equal',offset=0,name='Normal: gleiches Level'},
 {id='plus1',offset=1,name='Normal: +1 Level'},
 {id='plus2',offset=2,name='Normal: +2 Level'},
 {id='elite',offset=0,mode='elite',name='Elite: gleiches Level'},
}
-- These coefficients are configurable SIM assumptions, not data-mined NPC armor.
-- A continuous curve avoids the old level-10 fallback of 3,731 boss armor.
M.ARMOR_MODEL={basePerLevel=30,quadratic=0.20,eliteMultiplier=1.20,bossMultiplier=1.35}
function M.EstimateArmor(targetLevel,kind)
 local l=int(targetLevel,1,100)
 if not l then return nil end
 local c=M.ARMOR_MODEL
 local base=c.basePerLevel*l+c.quadratic*l*l
 if kind=='elite' then base=base*c.eliteMultiplier
 elseif kind=='dungeon' then base=base*c.bossMultiplier end
 return math.floor(base+.5)
end
local function fdqCatalog(method,...)
 local api=_G.ForeverSimDungeonAPI
 if not api or type(api.schema)~='number'or api.schema<2 or type(api[method])~='function'then return {}end
 local ok,rows=pcall(api[method],...)
 return ok and type(rows)=='table'and rows or{}
end
function M.ListDungeonRecords()return copy(fdqCatalog('ListDungeons'))end
function M.ListBossRecords(dungeon)return copy(fdqCatalog('ListBosses',dungeon))end
local function knownBoss(dungeon,boss)
 if not dungeon or not boss then return nil end
 for _,row in ipairs(M.ListBossRecords(dungeon))do
  if type(row)=='table'and row.name==boss then
   return {dungeon=dungeon,boss=boss,level=int(tonumber(row.level),1,100),dungeonKey=row.dungeonKey}
  end
 end
end
function M.ListDungeons()
 local out,seen={},{}
 for _,row in ipairs(M.ListDungeonRecords())do
  local name=type(row)=='table'and text(row.name)
  if name and not seen[name]then out[#out+1]=name;seen[name]=true end
 end
 table.sort(out)
 return out
end
function M.ListBosses(dungeon)
 local out,seen={},{}
 for _,row in ipairs(M.ListBossRecords(dungeon))do
  local name=type(row)=='table'and text(row.name)
  if name and not seen[name]then out[#out+1]=name;seen[name]=true end
 end
 table.sort(out)
 return out
end
-- Canonical API: resolve the same request for any of the nine classes.
-- Caller-entered armor is labelled 'manual', not verified. Partial boss records
-- share the same explicit synthetic fallback as generic dungeon elites.
function M.Resolve(characterLevel,requested)
 local level=int(characterLevel,1,100)
 if not level then return nil,'Ungültiges Charakterlevel' end
 local input=type(requested)=='table' and requested or {}
 local out=copy(input)
 local mode=normMode(input.mode,level)
 local explicitOffset=int(input.levelDifference,-10,20)
 local explicitTarget=int(input.targetLevel,1,100)
 local presetOffset=int(input.offset,-5,10)
 local dungeon,boss=text(input.dungeon),text(input.boss)
 local identified=(mode=='dungeon') and knownBoss(dungeon,boss) or nil
 local target=explicitTarget or (identified and identified.level) or nil
 if not target then
  local diff=explicitOffset
  if diff==nil then diff=presetOffset end
  if diff==nil then diff=mode=='standard' and 3 or mode=='dungeon' and 2 or mode=='quest' and 1 or 0 end
  target=math.max(1,math.min(100,level+diff))
 end
 local armorKind=mode
 local armor=int(input.armor,0,1000000)
 local assumed=armor==nil
 local source,confidence
 if armor~=nil then source='Benutzereingabe (nicht verifiziert)';confidence='manual'
 elseif mode=='standard' and level==60 and target==63 then
  -- Preserve historical level-60 benchmark for comparison with XN reference.
  armor=3731;source='Bisheriges Level-60-Referenzmodell (3731, nicht NPC-verifiziert)';confidence='model'
 else
  armor=M.EstimateArmor(target,armorKind)
  source='Generiertes Level-/Gegnertyp-Rüstungsmodell (Annahme)';confidence='model'
 end
 out.mode=mode;out.targetLevel=target;out.levelDifference=target-level
 out.armor=armor;out.armorAssumed=assumed;out.armorSource=source
 out.armorConfidence=confidence;out._profileResolved=true;out._modelRevision=M.revision
 if mode=='dungeon' then
  out.dungeon=dungeon;out.boss=boss
  if identified then
   out.bossLevelSource='FDQ-Dungeonjournal (Beta-Stand, nicht individuell bestätigt)'
   out.identitySource='FDQ-Dungeonjournal';out.bossLevelKnown=identified.level~=nil
  else
   out.bossLevelKnown=false;out.identitySource='Kein passender FDQ-Bossdatensatz; Dungeon-Referenzmodell'
  end
 end
 -- Resistance values remain unknown unless supplied by the user/source.
 -- The engine's existing level-resistance convention is not a verified NPC stat.
 out.resistanceSource=input.targetResist and 'Benutzereingabe (nicht verifiziert)' or 'Keine individuellen Resistenzen bekannt; Engine-Levelmodell'
 if not input.targetResist then out.targetResist={} end
 return out
end
function M.Apply(profile,requested)
 if type(profile)~='table' then return nil,'Charakterprofil fehlt' end
 local result=copy(profile)
 local resolved,err=M.Resolve(result.level,requested or result.encounter)
 if not resolved then return nil,err end
 result.encounter=resolved;result.bossPlus=resolved.levelDifference
 return result
end
-- A dungeon loot pre-calculation temporarily uses a representative boss
-- from the existing FDQ journal. This NEVER mutates SavedVariables.
function M.ForDungeon(profile,dungeon)
 if type(profile)~='table' or not text(dungeon) then return profile end
 local names=M.ListBosses(dungeon)
 if #names==0 then
  local draft=M.Apply(profile,{mode='dungeon',dungeon=dungeon})
  return draft or profile
 end
 local rows={}
 for _,row in ipairs(M.ListBossRecords(dungeon))do
  local level=type(row)=='table'and int(tonumber(row.level),1,100)
  if level and text(row.name)then rows[#rows+1]={name=row.name,level=level}end
 end
 -- Median level avoids arbitrarily optimizing against only the end boss.
 table.sort(rows,function(a,b)if a.level~=b.level then return a.level<b.level end return a.name<b.name end)
 local boss=rows[math.ceil(#rows/2)]
 if boss then
  local draft=M.Apply(profile,{mode='dungeon',dungeon=dungeon,boss=boss.name})
  return draft or profile
 end
 local draft=M.Apply(profile,{mode='dungeon',dungeon=dungeon})
 return draft or profile
end
function M.Describe(encounter)
 if type(encounter)~='table' then return 'Noch kein Gegnerprofil' end
 local kind=encounter.mode=='quest' and 'Questgegner' or encounter.mode=='elite' and 'Elite' or encounter.mode=='dungeon' and 'Dungeon' or 'Standardziel'
 local title=encounter.mode=='dungeon' and encounter.boss and ((encounter.dungeon or 'Dungeon')..' / '..encounter.boss) or kind
 local armor=encounter.armor and tostring(encounter.armor) or '?'
 return title..' · Level '..tostring(encounter.targetLevel or '?')..' · Rüstung '..armor..(encounter.armorAssumed and ' (Modellannahme)' or ' (manuell, ungeprüft)')
end
-- A new request always invalidates old rankings and cached item comparisons.
function M.Configure(patch)
 if type(patch)~='table' then return false,'Einstellungen fehlen' end
 ForeverSimBridgeDB=ForeverSimBridgeDB or {}
 local db=ForeverSimBridgeDB;local old=db.encounter or {};local nextRequest=copy(old)
 for key,val in pairs(patch)do nextRequest[key]=val end
 -- Changing between conceptual targets must not retain the previous target's armor.
 if patch.mode or patch.dungeon or patch.boss or patch.offset~=nil then
  if patch.armor==nil then nextRequest.armor=nil end
  if patch.targetLevel==nil then nextRequest.targetLevel=nil end
  if patch.levelDifference==nil then nextRequest.levelDifference=nil end
 end
 if patch.mode and patch.mode~='dungeon' then nextRequest.dungeon=nil;nextRequest.boss=nil end
 if patch.dungeon and patch.boss==nil then nextRequest.boss=nil end
 if patch.mode and patch.offset==nil then nextRequest.offset=nil end
 if patch.mode or patch.dungeon or patch.boss then nextRequest.targetResist=nil;nextRequest.mobType=nil end
 db.encounter=nextRequest
 if P.invalidate then P.invalidate() end
 return true
end
