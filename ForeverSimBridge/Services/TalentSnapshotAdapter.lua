-- Read-only Forever talent capture. API schema checked against Blizzard's forever UI:
-- https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/ClassTalentsDocumentation.lua
-- https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/SharedTraitsDocumentation.lua
-- No purchasing, refunds, configuration loading, commits or Blizzard UI writes.
local P=_G.FUSLive
if not P then return end
local A={};P.talentSnapshotAdapter=A
local function public(v)
 if P.isProtected then local ok,blocked=pcall(P.isProtected,v);if not ok or blocked then return nil,false end end
 if type(issecretvalue)=='function' then local ok,secret=pcall(issecretvalue,v);if not ok or secret then return nil,false end end
 if type(canaccessvalue)=='function' then local ok,access=pcall(canaccessvalue,v);if not ok or access==false then return nil,false end end
 return v,true
end
local function number(v)
 v=public(v);if type(v)~='number' then return nil end
 if v~=v or v==math.huge or v==-math.huge then return nil end
 return v
end
local function integer(v)local n=number(v);return n and n>=0 and n==math.floor(n) and n or nil end
local function stringValue(v)v=public(v);return type(v)=='string' and v or nil end
local function tableValue(v)v=public(v);return type(v)=='table' and v or nil end
local function read(t,key)
 if not tableValue(t) then return nil end
 local ok,v=pcall(function()return t[key]end);if ok then return public(v)end
end
local function call(fn,...)
 if type(fn)~='function' then return nil end
 local ok,v=pcall(fn,...);if ok then return public(v)end
end
local function status(source)
 return {state='valid',source=source,message='Live-Talente vollstaendig gelesen',issues={},points=0}
end
local function fail(s,message)
 s.state='incomplete';s.issues[#s.issues+1]=message;s.message=s.issues[1];return s
end
local function indexModel(classKey)
 local data=FUSLiveData and FUSLiveData[classKey]
 local canonical=ForeverSimTalentData and ForeverSimTalentData[classKey]
 if data and canonical then
  local originalBySpell={}
  for _,tree in ipairs(data.talentTrees or{})do for _,node in ipairs(tree.talents or{})do if node.spellId then originalBySpell[node.spellId]=node end end end
  local copy={};for key,value in pairs(data)do copy[key]=value end;copy.talentTrees={}
  for ti,tree in ipairs(canonical.talentTrees)do
   local t={name=tree.name,talents={}};copy.talentTrees[ti]=t
   for _,node in ipairs(tree.talents)do
    local n={};for key,value in pairs(node)do n[key]=value end
    local old=originalBySpell[n.spellId]
    n.key=old and old.key or n.fieldName;n.name=old and old.name or n.fieldName
    t.talents[#t.talents+1]=n
   end
  end
  data=copy
 end
 local trees,keys,ids,names={},{},{},{}
 for i,tree in ipairs(data and data.talentTrees or {})do
  trees[i]={name=tree.name or ('Baum '..i),points=0,entries={}}
  for _,node in ipairs(tree.talents or {})do
   keys[node.key]={key=node.key,name=node.name,index=i,maxRank=node.maxRank,tier=(node.row or 0)+1,column=(node.column or 0)+1}
   if type(node.spellId)=='number' then
    ids[node.spellId]=keys[node.key]
    local info=tableValue(call(C_Spell and C_Spell.GetSpellInfo,node.spellId))
    local name=info and stringValue(read(info,'name'))or stringValue(call(GetSpellInfo,node.spellId))
    if name then names[string.lower(name)]=keys[node.key]end
   end
   if type(node.name)=='string' then names[string.lower(node.name)]=keys[node.key]end
  end
 end
 for _,def in ipairs(data and data.talentDefinitions or {})do
  local node=keys[def.key]
  if node then
   if type(def.name)=='string' then names[string.lower(def.name)]=node end
   local spellIDs={def.id};for _,id in ipairs(def.spellIds or {})do spellIDs[#spellIDs+1]=id end
   for _,id in ipairs(spellIDs)do
    if type(id)=='number' then
     ids[id]=node
     local spell=call(C_Spell and C_Spell.GetSpellInfo,id)
     local name=tableValue(spell) and stringValue(read(spell,'name')) or stringValue(call(GetSpellInfo,id))
     if name then names[string.lower(name)]=node end
    end
   end
  end
 end
 return trees,ids,names
end
local function append(trees,s,match,entry)
 local tree
 if match then
  entry.classKey=match.key;entry.tier=match.tier;entry.column=match.column
  tree=trees[match.index]
  if entry.rank>(match.maxRank or 0)then fail(s,'Live-Talentrang passt nicht zum Klassenmodell: '..entry.name)end
 else
  if not trees.unknown then
   tree={name='Nicht zugeordnete Live-Talente',points=0,entries={}}
   trees[#trees+1]=tree;trees.unknown=tree
  end
  tree=trees.unknown
  fail(s,'Live-Talent fehlt im Klassenmodell: '..entry.name)
 end
 tree.entries[#tree.entries+1]=entry;tree.points=tree.points+entry.rank;s.points=s.points+entry.rank
end
local function modern(classKey,configID)
 local s=status('traits');s.configID=configID
 local trees,ids,names=indexModel(classKey)
 if #trees~=3 then fail(s,'Kanonische Talentbaeume fuer die Klasse fehlen')end
 for _,name in ipairs({'GetConfigInfo','GetTreeNodes','GetNodeInfo','GetEntryInfo','GetDefinitionInfo','ConfigHasStagedChanges'})do
  if not C_Traits or type(C_Traits[name])~='function' then fail(s,'Talent-API fehlt: C_Traits.'..name);return trees,s end
 end
 -- GetNodeInfo includes staged ranks/choices. Never label an uncommitted Blizzard
 -- draft as the live build, and never roll it back to obtain a snapshot.
 local staged=call(C_Traits.ConfigHasStagedChanges,configID)
 if type(staged)~='boolean' then fail(s,'Live-Talentstatus ist nicht oeffentlich lesbar');return trees,s end
 if staged then fail(s,'Blizzard-Talententwurf noch nicht bestaetigt; Live-Build erneut lesen nach Uebernehmen oder Verwerfen');return trees,s end
 local config=tableValue(call(C_Traits.GetConfigInfo,configID))
 local treeIDs=tableValue(read(config,'treeIDs'))
 if not treeIDs or #treeIDs==0 then fail(s,'Aktive Talentkonfiguration hat keine lesbaren Baumdaten');return trees,s end
 local seen,seenKeys,nodeCount={},{},0
 for _,rawTreeID in ipairs(treeIDs)do
  local treeID=integer(rawTreeID)
  local nodeIDs=treeID and treeID>0 and tableValue(call(C_Traits.GetTreeNodes,treeID)) or nil
  if not nodeIDs or #nodeIDs==0 then fail(s,'Talentbaum konnte nicht vollstaendig gelesen werden')
  else for _,rawNodeID in ipairs(nodeIDs)do
   local nodeID=integer(rawNodeID)
   if not nodeID or nodeID==0 then fail(s,'Ungueltige oder geschuetzte Talentknoten-ID')
   elseif not seen[nodeID]then
    seen[nodeID]=true;nodeCount=nodeCount+1
    local node=tableValue(call(C_Traits.GetNodeInfo,configID,nodeID))
    local rank=integer(read(node,'activeRank'))
    if not node or not rank then fail(s,'Talentknoten nicht vollstaendig oeffentlich lesbar')
    elseif rank>0 then
     local activeEntry=tableValue(read(node,'activeEntry'))
     local entryID=integer(read(activeEntry,'entryID'))
     local entry=entryID and entryID>0 and tableValue(call(C_Traits.GetEntryInfo,configID,entryID)) or nil
     local definitionID=integer(read(entry,'definitionID'))
     local definition=definitionID and definitionID>0 and tableValue(call(C_Traits.GetDefinitionInfo,definitionID)) or nil
     local spellID=integer(read(definition,'spellID'))
     local spell=spellID and spellID>0 and tableValue(call(C_Spell and C_Spell.GetSpellInfo,spellID)) or nil
     local name=stringValue(read(definition,'overrideName')) or stringValue(read(spell,'name'))
     if not name and spellID then name=stringValue(call(GetSpellInfo,spellID))end
     local match=spellID and ids[spellID] or name and names[string.lower(name)]
     local maxRank=integer(read(entry,'maxRanks')) or integer(read(node,'maxRanks'))
     if not entry or not definition or not maxRank or maxRank<rank then fail(s,'Aktive Talentdefinition ist unvollstaendig')end
     name=name or (match and match.name) or ('Talent '..tostring(spellID or nodeID))
     if match and seenKeys[match.key] then fail(s,'Doppelter aktiver Talenteintrag: '..name)
     else
      if match then seenKeys[match.key]=true end
      append(trees,s,match,{name=name,rank=rank,maxRank=maxRank,spellID=spellID,nodeID=nodeID,entryID=entryID})
     end
    end
   end
  end end
 end
 if nodeCount==0 then fail(s,'Keine Talentknoten gelesen; Live-Build ist unvollstaendig')end
 trees.unknown=nil
 return trees,s
end
local function legacy(classKey)
 local s=status('legacy');local trees,_,names=indexModel(classKey)
 if #trees~=3 then fail(s,'Kanonische Talentbaeume fuer die Klasse fehlen')end
 local count=integer(call(GetNumTalentTabs))
 if not count or count<1 then fail(s,'Legacy-Talentbaeume sind nicht lesbar');return trees,s end
 for tab=1,count do
  local countHere=integer(call(GetNumTalents,tab))
  if not countHere or countHere<1 then fail(s,'Legacy-Talentbaum ist unvollstaendig')
  else for i=1,countHere do
   local ok,name,_,tier,column,rank,maxRank=pcall(GetTalentInfo,tab,i)
   name=stringValue(name);rank=integer(rank);maxRank=integer(maxRank)
   if not ok or not name or not rank or not maxRank or rank>maxRank then fail(s,'Legacy-Talentknoten ist nicht oeffentlich lesbar')
   elseif rank>0 then append(trees,s,names[string.lower(name)],{name=name,rank=rank,maxRank=maxRank,tier=integer(tier),column=integer(column)})end
  end end
 end
 trees.unknown=nil
 return trees,s
end
function A.Capture(classKey,level)
 if InCombatLockdown and InCombatLockdown()then return {},fail(status('unavailable'),'Live-Talente werden erst ausserhalb des Kampfes gelesen')end
 classKey=stringValue(classKey);level=integer(level)
 if not classKey or not level then return {},fail(status('unavailable'),'Klasse oder Level fehlt fuer den Talent-Snapshot')end
 classKey=string.lower(classKey)
 if level<P.minSimLevel() then local trees=indexModel(classKey);local s=status('level');s.message='Talentpunkte erst ab Level '..P.minSimLevel();return trees,s end
 if C_ClassTalents and type(C_ClassTalents.GetActiveConfigID)=='function' then
  local ok,rawID=pcall(C_ClassTalents.GetActiveConfigID)
  local safeID,accessible=public(rawID);local configID=integer(safeID)
  if not ok or not accessible or safeID~=nil and not configID then
   return {},fail(status('traits'),'Aktive Talentkonfiguration ist nicht oeffentlich lesbar')
  end
  if configID and configID>0 then return modern(classKey,configID)end
 end
 if type(GetNumTalentTabs)=='function' and type(GetTalentTabInfo)=='function' and type(GetNumTalents)=='function' and type(GetTalentInfo)=='function' then return legacy(classKey)end
 return {},fail(status('unavailable'),'Keine aktive Talentkonfiguration verfuegbar; Talente erneut lesen sobald der Client bereit ist')
end
