-- ForeverSimBridge: canonical, class-neutral Forever talent build validation.
-- Builds are local plans. No protected talent actions, no live-character changes.
local P=FUSLive
if not P then return end
local B={};P.talentBuild=B
local function integer(x) return type(x)=='number' and x==math.floor(x) end
local function all(data)
 local nodes,groups={},{}
 if type(data)~='table' or type(data.talentTrees)~='table' or #data.talentTrees~=3 then
  return nil,nil,'Drei kanonische Forever-Talentbaeume fehlen'
 end
 for i,tree in ipairs(data.talentTrees)do
  local members={};groups[i]={tree=tree,members=members}
  for _,node in ipairs(tree.talents or {})do
   if type(node.key)~='string' or nodes[node.key] then return nil,nil,'Doppelter oder fehlender Talentschluessel' end
   if not integer(node.row) or node.row<0 or node.row>6 or not integer(node.column) or node.column<0 or node.column>3 then
    return nil,nil,'Ungueltige Position: '..node.key
   end
   if not integer(node.maxRank) or node.maxRank<1 then return nil,nil,'Ungueltige Rangzahl: '..node.key end
   nodes[node.key]={node=node,index=i};members[#members+1]=node
  end
 end
 return nodes,groups
end
function B.validate(data,ranks,level)
 local nodes,groups,err=all(data)
 if not nodes then return false,err end
 if type(ranks)~='table' then return false,'Talententwurf ist keine Rangtabelle' end
 local totals={0,0,0};local count=0
 for key,rank in pairs(ranks)do
  if rank~=nil then
   if not nodes[key] then return false,'Unbekanntes Forever-Talent: '..tostring(key) end
   if not integer(rank) or rank<0 or rank>nodes[key].node.maxRank then
    return false,'Ungueltiger Rang fuer '..tostring(key)
   end
  end
 end
 for i,group in ipairs(groups)do
  for _,node in ipairs(group.members)do
   local rank=ranks[node.key] or 0
   if rank>0 then
    local earlier=0
    for _,prior in ipairs(group.members)do if prior.row<node.row then earlier=earlier+(ranks[prior.key]or 0)end end
    if earlier<node.row*(data.talentTreeRowPoints or 5)then
     return false,tostring(node.name)..': zu wenige Punkte in frueheren Reihen'
    end
    if node.prereqKey then
     local prerequisite=nodes[node.prereqKey]
     if not prerequisite or prerequisite.index~=i then return false,'Unbekannte Voraussetzung: '..node.prereqKey end
     if (ranks[node.prereqKey]or 0)<prerequisite.node.maxRank then
      return false,tostring(node.name)..': Voraussetzung '..tostring(prerequisite.node.name)..' fehlt'
     end
    end
   end
   count=count+rank;totals[i]=totals[i]+rank
  end
 end
 if count>(data.talentTreeRankBudget or 51) then return false,'Mehr als 51 Talentpunkte vergeben' end
 if level~=nil then
  if not integer(level) then return false,'Charakterlevel fehlt oder ist ungueltig' end
  -- Legacy "Talented" grants the first points up to five levels early (still max 51).
  local allowed=math.max(0,math.min(51,level-9+(P.talentBonus and (P.talentBonus()) or 0)))
  if count>allowed then return false,'Level '..level..' erlaubt nur '..allowed..' Talentpunkte; Entwurf hat '..count end
 end
 return true,{points=count,treePoints=totals}
end
function B.profile(data,live,ranks)
 local ok,detail=B.validate(data,ranks,live and live.level)
 if not ok then return nil,detail end
 if not P.copy then return nil,'Kopierfunktion fehlt' end
 local profile=P.copy(live);profile.talents={};profile.hypotheticalBuild=true
 local biggest=-1;local biggestIndex=1
 for i,tree in ipairs(data.talentTrees)do
  local entries,points={},0
  for _,node in ipairs(tree.talents or {})do
   local r=ranks[node.key]or 0
   if r>0 then entries[#entries+1]={classKey=node.key,name=node.name,rank=r};points=points+r end
  end
  profile.talents[i]={name=tree.name,points=points,entries=entries}
  if points>biggest then biggest=points;biggestIndex=i end
 end
 if type(data.specs)=='table' and data.specs[biggestIndex]and biggest>0 then
  profile.spec=data.specs[biggestIndex]
 end
 return profile,detail
end
-- Hypothetical builds learn only declared talent-granted abilities, never ordinary
-- trainer spells. The live profile/real spellbook is never modified.
function B.grantAbilities(data,profile)
 if not profile or not profile.hasSpellbook then return profile end
 local talents=P.talents(data,profile)
 profile.knownSpellRanks=P.copy(profile.knownSpellRanks or {})
 local model=P.classModel and P.classModel(data,profile)or data
 for key,ranks in pairs(model.abilities or {})do
  for _,rank in ipairs(ranks)do
   if rank.requiredTalent and (talents[rank.requiredTalent]or 0)>0 and (rank.level or 9999)<=profile.level then
    local known=profile.knownSpellRanks[key]or {};local found=false
    for _,n in ipairs(known)do if n==rank.rank then found=true end end
    if not found then known[#known+1]=rank.rank end
    profile.knownSpellRanks[key]=known
   end
  end
 end
 return profile
end
function B.spellbookIssue(data,live,planned)
 if not planned then return 'Talententwurf fehlt' end
 B.grantAbilities(data,planned)
end
-- Direct declarative references show a possible implementation path, not proof of full DPS parity.
function B.ruleReferences(data)
 local out,seen={},{}
 local fields={talent=true,requiresTalent=true,retentionTalent=true,requiredTalent=true}
 local function inspect(t)
  if type(t)~='table' or seen[t]then return end
  seen[t]=true
  for key,value in pairs(t)do
   if fields[key]and type(value)=='string' then out[value]=true end
   if type(value)=='table'and key~='talentDefinitions'and key~='talentTrees'and key~='talentTreeByKey'and key~='talents' then inspect(value)end
  end
 end
 inspect(data)
 -- Talents read directly by engine code (t.<key>) instead of declarative rules.
 for _,key in ipairs({'bestialDiscipline','elementalWeapons','ferocity','frenzy','improvedPoisons','suppression'})do out[key]=true end
 return out
end
function B.summary(data)
 local refs=B.ruleReferences(data);local total,direct=0,0;local missing={}
 for _,tree in ipairs(data.talentTrees or {})do for _,node in ipairs(tree.talents or {})do
  total=total+1
  if refs[node.key]then direct=direct+1 else missing[#missing+1]=node.name end
 end end
 return {total=total,direct=direct,unverified=total-direct,withoutDirectRule=missing}
end

