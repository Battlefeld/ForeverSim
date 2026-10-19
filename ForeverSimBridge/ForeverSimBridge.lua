-- WoW client only: captures character data into SavedVariables. No web/network activity.
-- Snapshot updates on login/level/gear/spells/talents; SavedVariables are written to disk at /reload/logout.
local ADDON = ...
ForeverSimBridgeDB = ForeverSimBridgeDB or {}
-- SavedVariables are assigned after this file runs. Always read and write the
-- live global table so settings such as /fus safety persist across reloads.
local db=setmetatable({},{__index=function(_,k)return ForeverSimBridgeDB[k]end,__newindex=function(_,k,v)ForeverSimBridgeDB[k]=v end})
-- Taint-isolation default: run simulations only on explicit user request, outside combat.
-- Legacy builds continuously inspected auras, cooldowns, target health and loot.
-- Those reads may return secret values on Forever; automatic observers are opt-in.
if db.passiveSafetyMode == nil then db.passiveSafetyMode = true end
function FUSLive.passiveSafetyMode()
 return not (ForeverSimBridgeDB and ForeverSimBridgeDB.passiveSafetyMode == false)
end
-- Record the protected function reported by Blizzard without accessing or
-- evaluating secret values. This is diagnostic; it cannot recover a Lua stack
-- from protected Blizzard code.
local taintEvent=CreateFrame('Frame')
for _,eventName in ipairs({'ADDON_ACTION_BLOCKED','ADDON_ACTION_FORBIDDEN'})do
 pcall(taintEvent.RegisterEvent,taintEvent,eventName)
end
taintEvent:SetScript('OnEvent',function(_,eventName,addonName,actionName)
 if type(addonName)~='string' or addonName~='ForeverSimBridge' then return end
 local action='nicht uebermittelt'
 if type(actionName)=='string' then
  local secret=false
  if type(issecretvalue)=='function' then local ok,v=pcall(issecretvalue,actionName);secret=not ok or v==true end
  if not secret then action=actionName:sub(1,240)end
 end
 db.blockedActionCount=(db.blockedActionCount or 0)+1
 db.lastBlockedAction={event=eventName,action=action}
end)
local slots={'HeadSlot','NeckSlot','ShoulderSlot','BackSlot','ChestSlot','WristSlot','HandsSlot','WaistSlot','LegsSlot','FeetSlot','Finger0Slot','Finger1Slot','Trinket0Slot','Trinket1Slot','MainHandSlot','SecondaryHandSlot','RangedSlot'}
local statkeys={ITEM_MOD_STRENGTH_SHORT='str',ITEM_MOD_ATTACK_POWER_SHORT='ap',ITEM_MOD_RANGED_ATTACK_POWER_SHORT='rap',ITEM_MOD_HOLY_DAMAGE_SHORT='holySp',
 ITEM_MOD_SPELL_PENETRATION_SHORT='pierce',ITEM_MOD_AGILITY_SHORT='agi',ITEM_MOD_INTELLECT_SHORT='int', ITEM_MOD_SPIRIT_SHORT='spi', ITEM_MOD_STAMINA_SHORT='sta',
 ITEM_MOD_SPELL_POWER_SHORT='sp', ITEM_MOD_SPELL_DAMAGE_DONE_SHORT='sp',
 ITEM_MOD_MANA_REGENERATION_SHORT='mp5', ITEM_MOD_SHADOW_DAMAGE_SHORT='shadowSp',ITEM_MOD_FIRE_DAMAGE_SHORT='fireSp',ITEM_MOD_FROST_DAMAGE_SHORT='frostSp',ITEM_MOD_NATURE_DAMAGE_SHORT='natureSp',ITEM_MOD_ARCANE_DAMAGE_SHORT='arcaneSp',
}
local ratingkeys={ITEM_MOD_HIT_RATING_SHORT='hitPct',ITEM_MOD_SPELL_HIT_RATING_SHORT='hitPct',ITEM_MOD_CRIT_RATING_SHORT='critPct',ITEM_MOD_SPELL_CRIT_RATING_SHORT='critPct',ITEM_MOD_HASTE_RATING_SHORT='hastePct',ITEM_MOD_SPELL_HASTE_RATING_SHORT='hastePct'}
-- WoW Forever 1.60.1 can return protected (secret) values in combat.
-- Never compare, format, serialize or simulate with an inaccessible API value.
local function protected(v)
 if type(issecretvalue)=='function' then
  local ok,secret=pcall(issecretvalue,v)
  if not ok or secret then return true end
 end
 if type(canaccessvalue)=='function' then
  local ok,can=pcall(canaccessvalue,v)
  if not ok or can==false then return true end
 end
 return false
end
local function publicNumber(v)
 if protected(v) or type(v)~='number' then return nil end
 local ok,finite=pcall(function()return v==v and v~=math.huge and v~=-math.huge end)
 return ok and finite and v or nil
end
local function publicString(v)
 if protected(v) or type(v)~='string' then return nil end
 return v
end
FUSLive.isProtected=protected
FUSLive.publicNumber=publicNumber
FUSLive.publicString=publicString
-- Read the modern C_Spell namespace first; older clients still expose globals.
-- Icon/name values can also be protected, so only public fields reach the UI.
local function spellDisplay(ref)
 local name,icon
 if C_Spell and type(C_Spell.GetSpellInfo)=='function' then
  local ok,info=pcall(C_Spell.GetSpellInfo,ref)
  if ok and type(info)=='table' and not protected(info) then
   name=publicString(info.name)
   icon=publicNumber(info.iconID) or publicString(info.iconID)
  end
 end
 if type(GetSpellInfo)=='function' and (not name or not icon) then
  local ok,n,_,texture=pcall(GetSpellInfo,ref)
  if ok then name=name or publicString(n);icon=icon or publicNumber(texture) or publicString(texture)end
 end
 if not icon then
  local f=(C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture
  if type(f)=='function' then
   local ok,texture=pcall(f,ref)
   if ok then icon=publicNumber(texture) or publicString(texture) end
  end
 end
 return name,icon
end
FUSLive.spellDisplay=spellDisplay
local function escape(s)
 if protected(s) then s='' end
 s=tostring(s or '')
 return '"'..s:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n'):gsub('\r','\\r'):gsub('\t','\\t')..'"'
end
local function json(value)
 if protected(value) then return 'null' end
 local t=type(value)
 if t=='nil' then return 'null' end
 if t=='number' then if not publicNumber(value) then return 'null' end return tostring(value) end
 if t=='boolean' then return tostring(value) end
 if t=='string' then return escape(value) end
 if t~='table' then return 'null' end
 local isArray=true;local largest=0;local count=0
 for k in pairs(value) do count=count+1;if type(k)~='number' or k<1 or math.floor(k)~=k then isArray=false;break end if k>largest then largest=k end end
 if isArray and count==largest then
  local out={};for i=1,largest do out[i]=json(value[i]) end
  return '['..table.concat(out,',')..']'
 end
 local out={};for k,v in pairs(value) do table.insert(out,escape(k)..':'..json(v)) end
 return '{'..table.concat(out,',')..'}'
end
-- Item capture feeds the live Lua optimizers; tooltip scanning checks modeled effects.
local slotFromEquip={INVTYPE_HEAD='head',INVTYPE_NECK='neck',INVTYPE_SHOULDER='shoulder',INVTYPE_CLOAK='back',INVTYPE_CHEST='chest',INVTYPE_ROBE='chest',INVTYPE_WRIST='wrist',INVTYPE_HAND='hands',INVTYPE_WAIST='waist',INVTYPE_LEGS='legs',INVTYPE_FEET='feet',INVTYPE_FINGER='finger1',INVTYPE_TRINKET='trinket1',INVTYPE_WEAPON='mainhand',INVTYPE_2HWEAPON='mainhand',INVTYPE_WEAPONMAINHAND='mainhand',INVTYPE_WEAPONOFFHAND='offhand',INVTYPE_HOLDABLE='offhand',INVTYPE_SHIELD='offhand',INVTYPE_RELIC='ranged',INVTYPE_RANGED='ranged',INVTYPE_RANGEDRIGHT='ranged'}
-- The Forever 1.60 client exposes item functions under C_Item; the old
-- GetItemInfo/GetItemStats/GetItemSpell globals are not always present.
-- Prefer C_Item, retain legacy fallbacks for other supported clients.
local function itemInfo(ref)
 local f=(C_Item and C_Item.GetItemInfo) or GetItemInfo
 if type(f)~='function' then return nil end
 return f(ref)
end
local function itemStats(ref)
 local f=(C_Item and C_Item.GetItemStats) or GetItemStats
 if type(f)~='function' then return nil end
 return f(ref)
end
local function itemSpell(ref)
 local f=(C_Item and C_Item.GetItemSpell) or GetItemSpell
 if type(f)~='function' then return nil end
 return f(ref)
end
FUSLive.itemInfo=itemInfo
local effectScanner
local function unknownTooltipEffect(link,item)
 if not CreateFrame then return true end
 if not effectScanner then
  effectScanner=CreateFrame('GameTooltip','ForeverSimEffectScanner',nil,'GameTooltipTemplate')
  effectScanner:SetOwner(UIParent,'ANCHOR_NONE')
 end
 effectScanner:SetOwner(UIParent,'ANCHOR_NONE');effectScanner:ClearLines();effectScanner:SetHyperlink(link)
 for n=1,effectScanner:NumLines() do
  local line=_G['ForeverSimEffectScannerTextLeft'..n]
  local text=line and publicString(line:GetText()) or ''
  local lower=string.lower(text or '')
  -- Never score on-use/proc lines as if they were ordinary passive stats.
  if lower:find('^use:') or lower:find('^benutzen:') or lower:find('^chance on hit:') or lower:find('^trefferchance:') then return true end
  if lower:find('^equip:') or lower:find('^anlegen:') then
   -- Only a matching stat already returned by the client is accepted.
   local known=false
   local patterns={ap={'increases attack power','erhöht die angriffskraft'},rap={'increases ranged attack power','erhöht die distanzangriffskraft'},holySp={'increases damage done by holy spells','erhöht durch heiligzauber'},natureSp={'increases damage done by nature spells','erhöht durch naturzauber'},arcaneSp={'increases damage done by arcane spells','erhöht durch arkane zauber'},sp={'increases damage and healing done by magical spells','erhöht durch zauber und magische effekte verursachten schaden'},shadowSp={'increases damage done by shadow spells','erhöht durch schattenzauber'},fireSp={'increases damage done by fire spells','erhöht durch feuerzauber'},frostSp={'increases damage done by frost spells','erhöht durch frostzauber'}}
   for key,names in pairs(patterns) do for _,prefix in ipairs(names)do if lower:find(prefix,1,true) and (item.stats[key] or 0)>0 then known=true end end end
   if not known then return true end
  end
 end
 return false
end
-- The game's own text templates ("Requires %s (%d)", "Classes: %s") turned into Lua patterns, so the
-- requirements of an item are found in every client language.
local function formatPattern(fmt)
 fmt=tostring(fmt):gsub('%%%d*%$?s','\1S'):gsub('%%%d*%$?d','\2D')
 fmt=fmt:gsub('[%^%$%(%)%%%.%[%]%*%+%-%?]','%%%0')
 fmt=fmt:gsub('\1S','(.+)'):gsub('\2D','(%%d+)')
 return '^'..fmt..'$'
end
-- profession / skill requirement, class and race restriction and "Unique" of an item, from its tooltip
local function readRequirements(link,item)
 if not(_G.ITEM_MIN_SKILL or _G.ITEM_CLASSES_ALLOWED or _G.ITEM_RACES_ALLOWED or _G.ITEM_UNIQUE)then return end
 if not effectScanner then unknownTooltipEffect(link,item) end -- creates the scanner on first use
 if not effectScanner then return end
 effectScanner:SetOwner(UIParent,'ANCHOR_NONE');effectScanner:ClearLines();effectScanner:SetHyperlink(link)
 local skillPattern=_G.ITEM_MIN_SKILL and formatPattern(_G.ITEM_MIN_SKILL)
 local classPattern=_G.ITEM_CLASSES_ALLOWED and formatPattern(_G.ITEM_CLASSES_ALLOWED)
 local racePattern=_G.ITEM_RACES_ALLOWED and formatPattern(_G.ITEM_RACES_ALLOWED)
 for n=1,effectScanner:NumLines() do
  local line=_G['ForeverSimEffectScannerTextLeft'..n]
  local text=line and publicString(line:GetText()) or ''
  text=text:gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r',''):gsub('^%s+',''):gsub('%s+$','') -- colour codes of unmet requirements
  if skillPattern then local name,rank=text:match(skillPattern);if name then item.requiresSkill={name=name,rank=tonumber(rank)or 0}end end
  -- "Unique" / "Unique-Equipped" (and "Unique (1)"): two of them cannot be worn at the same time (rings, trinkets);
  -- "Unique (2)" allows two.
  if text~='' then
   local limit=_G.ITEM_UNIQUE_MULTIPLE and tonumber(text:match(formatPattern(_G.ITEM_UNIQUE_MULTIPLE)))
   if text==_G.ITEM_UNIQUE or limit==1 then item.unique=true end
   if text==_G.ITEM_UNIQUE_EQUIPPABLE then item.uniqueEquip=true end
  end
  if classPattern then
   local list=text:match(classPattern)
   local races=racePattern and text:match(racePattern)
   if races then item.allowedRaces={};for c in tostring(races):gmatch('[^,]+')do item.allowedRaces[#item.allowedRaces+1]=c:match('^%s*(.-)%s*$')end end
   if list then item.allowedClasses={};for c in tostring(list):gmatch('[^,]+')do item.allowedClasses[#item.allowedClasses+1]=c:match('^%s*(.-)%s*$')end end
  end
 end
end
local function makeItem(link,source)
 if not link then return nil end
 local iid=type(link)=='number' and link or tonumber(tostring(link):match('item:(%d+)'))
 local name,_,quality,_,requiredLevel,_,subType,_,equipLoc,_,_,classID,subClassID=itemInfo(link)
 if not name then return nil end
 local slot=slotFromEquip[equipLoc]
 if not slot then return nil end
 local parsedStats=itemStats(link)
 if protected(parsedStats) or type(parsedStats)~='table' then parsedStats=nil end
 local item={quality=quality,id=iid,name=name or ('Item #'..tostring(iid or '?')),slot=slot,minLevel=requiredLevel or 1,stats={},rawStats={},source=source,twoHanded=equipLoc=='INVTYPE_2HWEAPON',weaponType=(classID==2 or equipLoc=='INVTYPE_HOLDABLE' or equipLoc=='INVTYPE_WEAPONOFFHAND' or equipLoc=='INVTYPE_WEAPON' or equipLoc=='INVTYPE_WEAPONMAINHAND' or equipLoc=='INVTYPE_2HWEAPON' or equipLoc=='INVTYPE_RANGED' or equipLoc=='INVTYPE_RANGEDRIGHT') and subType or nil,weaponClass=classID,weaponSubclass=subClassID,itemClass=classID,itemSubclass=subClassID,equipLoc=equipLoc,statsComplete=parsedStats~=nil,hasUnmodeledEffects=itemSpell(link)~=nil}
 local subtype=string.lower(tostring(subType or ''))
 if classID==4 and subClassID==1 then item.armorType='cloth'
 elseif classID==4 and subClassID==2 then item.armorType='leather'
 elseif classID==4 and subClassID==3 then item.armorType='mail'
 elseif classID==4 and subClassID==4 then item.armorType='plate'
 elseif subtype=='cloth' or subtype=='stoff' then item.armorType='cloth'
 elseif subtype=='leather' or subtype=='leder' then item.armorType='leather'
 elseif subtype=='mail' or subtype=='schwere rüstung' then item.armorType='mail'
 elseif subtype=='plate' or subtype=='platte' then item.armorType='plate' end
 for rawKey,rawValue in pairs(parsedStats or {}) do
  local key,val=publicString(rawKey),publicNumber(rawValue)
  if not key or not val then item.statsComplete=false
  else
  if key=='ITEM_MOD_DAMAGE_PER_SECOND_SHORT' then item.displayWeaponDps=val end
  item.rawStats[key]=val;local dest=statkeys[key];if dest then item.stats[dest]=(item.stats[dest] or 0)+val end
  local rating=ratingkeys[key];if rating then local _,class=UnitClass('player');local data=FUSLiveData[string.lower(class)];local row=data and data.levelStats[tostring(UnitLevel('player'))];local conversion=row and row.ratingPerPercent and row.ratingPerPercent[rating];if not conversion and data and data.typedCombat and GetCombatRating and GetCombatRatingBonus then local category=({ITEM_MOD_HIT_RATING_SHORT=6,ITEM_MOD_SPELL_HIT_RATING_SHORT=8,ITEM_MOD_CRIT_RATING_SHORT=9,ITEM_MOD_SPELL_CRIT_RATING_SHORT=11,ITEM_MOD_HASTE_RATING_SHORT=18,ITEM_MOD_SPELL_HASTE_RATING_SHORT=20})[key];if category then local amount,bonus=publicNumber(GetCombatRating(category)),publicNumber(GetCombatRatingBonus(category));if amount and bonus and amount>0 and bonus>0 then conversion=amount/bonus end end end;if conversion then item.stats[rating]=(item.stats[rating]or 0)+val/conversion elseif data and data.typedCombat and val~=0 then item.statsComplete=false end end
  end
 end
 item.hasUnmodeledEffects=item.hasUnmodeledEffects or unknownTooltipEffect(link,item)
 pcall(readRequirements,link,item)
 -- Random-suffix items ("of Agility"): the client's stat table can describe only the base item. The plain
 -- "+N Stat" lines of the tooltip are then the truth; keep the larger value per primary stat.
 do
  local suffix=tonumber(tostring(link):match('item:%d+:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:(%-?%d+)'))
  if suffix and suffix~=0 and CreateFrame then
   if not effectScanner then unknownTooltipEffect(link,item) end
   if effectScanner then
    effectScanner:SetOwner(UIParent,'ANCHOR_NONE');effectScanner:ClearLines();effectScanner:SetHyperlink(link)
    local primary={'ITEM_MOD_STRENGTH_SHORT','ITEM_MOD_AGILITY_SHORT','ITEM_MOD_STAMINA_SHORT','ITEM_MOD_INTELLECT_SHORT','ITEM_MOD_SPIRIT_SHORT'}
    for n=1,effectScanner:NumLines() do
     local line=_G['ForeverSimEffectScannerTextLeft'..n]
     local text=line and publicString(line:GetText()) or ''
     local amount,label=text:match('^%+(%d+)%s+(.+)$')
     amount=tonumber(amount)
     if amount and label then
      for _,key in ipairs(primary) do
       local localized=_G[key]
       if localized and label==localized and (item.rawStats[key] or 0)<amount then
        local dest=statkeys[key];if dest then item.stats[dest]=(item.stats[dest] or 0)+(amount-(item.rawStats[key] or 0)) end
        item.rawStats[key]=amount
       end
      end
     end
    end
   end
  end
 end
 if classID==2 and effectScanner then
  -- Weapon damage and speed are printed as paired left/right tooltip lines.
  local low,high,speed
  for index=1,effectScanner:NumLines()do
   for _,side in ipairs({'Left','Right'})do local line=_G['ForeverSimEffectScannerText'..side..index];local text=line and publicString(line:GetText())or''
    local a,b=text:match('(%d+[.,]?%d*)%s*%-%s*(%d+[.,]?%d*)')
    if a and b and(text:lower():find('damage',1,true)or text:lower():find('schaden',1,true))then low=tonumber((a:gsub(',','.')));high=tonumber((b:gsub(',','.')))end
    local v=text:lower():match('speed%s*(%d+[.,]?%d*)')or text:lower():match('geschwindigkeit%s*(%d+[.,]?%d*)');if v then speed=tonumber((v:gsub(',','.')))end
   end
  end
  if low and high and speed and speed>0 then item.weapon={min=low,max=high,speed=speed,subclass=subClassID,normalizedSpeed=(subClassID==15 and 1.7 or item.twoHanded and 3.3 or(subClassID==2 or subClassID==3 or subClassID==18)and 2.8 or 2.4),includesAttackPower=false}end
 end
 return item
end
local function bagCandidates()
 local out,seen={},{}
 for bag=0,4 do
  local count=(C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag)) or (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
  for slot=1,count do
   local link=(C_Container and C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bag,slot)) or (GetContainerItemLink and GetContainerItemLink(bag,slot))
   local item=makeItem(link,'Tasche')
   if item and not seen[link] then table.insert(out,item);seen[link]=true end
  end
 end
 return out
end
local function captureQuestRewards()
 local out={}
 if not GetQuestItemLink then db.questRewards={};return out end
 local choices=GetNumQuestChoices and GetNumQuestChoices() or 0
 local fixed=GetNumQuestRewards and GetNumQuestRewards() or 0
 for n=1,choices do local item=makeItem(GetQuestItemLink('choice',n),'Quest-Belohnung (Auswahl)');if item then table.insert(out,item) end end
 for n=1,fixed do local item=makeItem(GetQuestItemLink('reward',n),'Quest-Belohnung (fest)');if item then table.insert(out,item) end end
 db.questRewards=out
end
-- Enchants never count, also not on the worn gear: otherwise the worn item would always look better than an
-- unenchanted new one. The enchant field of the link is emptied before the item is read.
local function withoutEnchant(link)
 if type(link)~='string' then return link end
 return(link:gsub('item:(%-?%d+):%-?%d*','item:%1:',1))
end
FUSLive.withoutEnchant=withoutEnchant
local function equipment()
 local out={}
 for _,slot in ipairs(slots) do
  local slotId=GetInventorySlotInfo and GetInventorySlotInfo(slot)
  local link=withoutEnchant(slotId and GetInventoryItemLink('player',slotId))
  if link then
   local item=makeItem(link,'Angelegt')
   if item then
    item.slot=slot
    item.link=link
    -- GetItemInfo subtype is localized; preserve it AND the inventory type.
    item.hasUnmodeledEffects=item.hasUnmodeledEffects or false
    table.insert(out,item)
   end
  end
 end
 return out
end
-- Both the classic and Forever 1.60+ spellbook interfaces are supported.
-- SpellBook item slots are NOT spell IDs; never infer known ranks from level alone.
local function spellbookEntry(index,pet)
 local modern=C_SpellBook
 if modern and (modern.GetSpellBookItemType or modern.GetSpellBookItemInfo) then
  local bank=Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank[pet and 'Pet' or 'Player'] or (pet and 1 or 0)
  local kind,id
  if modern.GetSpellBookItemType then kind,id=modern.GetSpellBookItemType(index,bank)
  elseif modern.GetSpellBookItemInfo then
   local info=modern.GetSpellBookItemInfo(index,bank)
   if info then kind,id=info.itemType,info.spellID or info.actionID end
  end
  local spellType=Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell or 1
  if kind~=spellType and kind~='SPELL' then return nil end
  local name,rankText
  if modern.GetSpellBookItemName then name,rankText=modern.GetSpellBookItemName(index,bank)end
  if not name then name=spellDisplay(id) end
  return publicNumber(id),publicString(name),publicString(rankText)
 end
 if type(GetSpellBookItemInfo)=='function' then
  local kind,id=GetSpellBookItemInfo(index,pet and (BOOKTYPE_PET or 'pet') or (BOOKTYPE_SPELL or 'spell'))
  if kind~='SPELL' then return nil end
  local name,rankText
  if type(GetSpellBookItemName)=='function' then
   name,rankText=GetSpellBookItemName(index,pet and (BOOKTYPE_PET or 'pet') or (BOOKTYPE_SPELL or 'spell'))
  end
  if not name then name=spellDisplay(id)end
  return publicNumber(id),publicString(name),publicString(rankText)
 end
 return nil
end
local function spellbook()
 local out={}
 local modern=C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo
 local legacy=type(GetNumSpellTabs)=='function' and type(GetSpellTabInfo)=='function' and type(GetSpellBookItemInfo)=='function'
 if not modern and not legacy then return out,{state="unavailable"} end
 local tabs=modern and C_SpellBook.GetNumSpellBookSkillLines() or GetNumSpellTabs()
 tabs=publicNumber(tabs)
 if not tabs or tabs<1 then return out,{state="unavailable"} end
 local seen={}
 for tab=1,tabs do
  local offset,count
  if modern then
   local line=C_SpellBook.GetSpellBookSkillLineInfo(tab)
   offset=line and publicNumber(line.itemIndexOffset)
   count=line and publicNumber(line.numSpellBookItems)
  else
   local _,_,from,num=GetSpellTabInfo(tab)
   offset,count=publicNumber(from),publicNumber(num)
  end
  if not offset or not count then return out,{state="incomplete"} end
  for index=offset+1,offset+count do
   local id,name,rankText=spellbookEntry(index,false)
   if id and name and not seen[id] then
    seen[id]=true
    local rank=rankText and tonumber(rankText:match('(%d+)')) or nil
    out[#out+1]={name=name,id=id,rankText=rankText or '',rank=rank}
   end
  end
 end
 return out,{state=#out>0 and "valid" or "incomplete"}
end
local function petSpellbook(data)
 local ranks={}
 local modern=C_SpellBook and C_SpellBook.HasPetSpells
 local count=modern and C_SpellBook.HasPetSpells() or (HasPetSpells and HasPetSpells())
 count=publicNumber(count)
 if not count then return ranks,false end
 local ids={}
 for key,rs in pairs(data and data.petSpellRanks or {})do for _,r in ipairs(rs)do ids[r.id]={key,r.rank}end end
 for i=1,count do
  local id=spellbookEntry(i,true)
  local rank=ids[id]
  if rank then ranks[rank[1]]=ranks[rank[1]]or {};ranks[rank[1]][#ranks[rank[1]]+1]=rank[2]end
 end
 return ranks,true
end
local function talents(data)
 if FUSLive.talentSnapshotAdapter then
  local _,class=UnitClass('player')
  return FUSLive.talentSnapshotAdapter.Capture(class, publicNumber(UnitLevel('player')))
 end
 local localized={}
 for _,rule in ipairs(data and data.talentDefinitions or {})do
  localized[string.lower(rule.name)]=rule.key
  for _,id in ipairs(rule.spellIds or {})do local name=GetSpellInfo and GetSpellInfo(id);if name then localized[string.lower(name)]=rule.key end end
 end
 local out={}
 if not GetNumTalentTabs or not GetTalentTabInfo or not GetNumTalents or not GetTalentInfo then return out end
 for tab=1,GetNumTalentTabs() do
  local name,_,points=GetTalentTabInfo(tab)
  local entries={}
  for i=1,GetNumTalents(tab) do
   local talentName,_,tier,column,rank,maxRank=GetTalentInfo(tab,i)
   if talentName and rank and rank>0 then table.insert(entries,{name=talentName,classKey=localized[string.lower(talentName)],rank=rank,tier=tier,column=column,maxRank=maxRank}) end
  end
  table.insert(out,{name=name or ('Tree '..tab),points=points or 0,entries=entries})
 end
 return out
end
local function snapshot(forLive)
 if not UnitClass or not UnitLevel then return end
 local display,class=UnitClass('player');if not class then return end
 local race=UnitRace and(select(2,UnitRace('player'))or UnitRace('player'))or ''
 local faction=UnitFactionGroup and UnitFactionGroup('player') or ''
 local data=FUSLiveData and FUSLiveData[string.lower(class)];local talentsData,talentStatus=talents(data);local equipped=equipment();local spells,spellbookStatus=spellbook()
 local petExists=UnitExists and UnitExists('pet');if protected(petExists) then petExists=false end
 local snap={schema=1,source='ForeverSimBridge',name=UnitName('player'),class=class,level=UnitLevel('player'),race=race,faction=faction,inventory={},activeAuras={},soulShards=GetItemCount and GetItemCount(6265)or 0,petActive=petExists or false,
  spellbookStatus=spellbookStatus,equipped=equipped,talents=talentsData,talentSnapshotStatus=talentStatus,talentStatus=talentStatus,spells=spells,bagItems=forLive and {} or bagCandidates(),questRewards=db.questRewards or {},encounter=db.encounter or {},stats={}}
 for _,key in ipairs(data and data.autoResourceKeys or {})do for _,r in ipairs(data.abilities[key]or {})do if r.requiredItem then snap.inventory[tostring(r.requiredItem)]=GetItemCount and GetItemCount(r.requiredItem)or 0 end end end
 if snap.petActive then local family=UnitCreatureFamily and publicString(UnitCreatureFamily('pet'));local data=FUSLiveData and FUSLiveData[string.lower(class)];local kind=nil
  for key,names in pairs(data and data.actorAliases or {})do for _,name in ipairs(names)do if string.lower(family or '')==name then kind=key end end end
  local known,complete=petSpellbook(data);snap.pet={type=kind,level=publicNumber(UnitLevel('pet')),mana=UnitPowerMax and publicNumber(UnitPowerMax('pet',0)),knownSpellRanks=known,hasSpellbook=complete}
   if data and data.genericPet then local agility=UnitStat and publicNumber(select(2,UnitStat('pet',2)));snap.pet.critPct=agility and agility*.05 end
   if GetPetSpellBonusDamage then snap.pet.spellPower=publicNumber(GetPetSpellBonusDamage()) end
   if UnitDamage and UnitAttackSpeed then
    local lo,hi,_,_,_,_,petMult=UnitDamage('pet')
    local speed=publicNumber(UnitAttackSpeed('pet'))
    lo,hi=publicNumber(lo),publicNumber(hi)
    -- Secret attack speeds (and damage) must not enter DPS math or SavedVariables.
    if lo and hi and speed and speed>0 then
     snap.pet.melee={baseDps=(lo+hi)/2/speed,swing=speed,includesModifiers=true,damageMultiplier=publicNumber(petMult)}
    else
     snap.pet.meleeUnavailable=true
    end
   end
 end
 if class=='HUNTER' and FUSLive.captureHunter then local ok,h=pcall(FUSLive.captureHunter,snap.petActive);snap.hunter=ok and h or {error='capture'} end
 if UnitStat then snap.stats.strength=publicNumber(select(2,UnitStat('player',1)));snap.stats.agility=publicNumber(select(2,UnitStat('player',2)));snap.stats.stamina=publicNumber(select(2,UnitStat('player',3)));snap.stats.intellect=publicNumber(select(2,UnitStat('player',4)));snap.stats.spirit=publicNumber(select(2,UnitStat('player',5))) end
 if GetManaRegen then local x,y=GetManaRegen();snap.stats.manaRegen=publicNumber(x);snap.stats.castingManaRegen=publicNumber(y) end
 if UnitHealthMax then snap.stats.health=publicNumber(UnitHealthMax('player'))end
 if UnitPowerMax then snap.stats.mana=publicNumber(UnitPowerMax('player',0)) end
 if GetCritChance then local v=publicNumber(GetCritChance());snap.stats.meleeCritPct=v;snap.stats.critPct=v;snap.stats.weaponCritIncludesTalents=true end
 if GetSpellPenetration then snap.stats.pierce=publicNumber(GetSpellPenetration())end
 if GetHaste then snap.stats.hastePct=publicNumber(GetHaste())end
 if GetSpellCritChance then for school,index in pairs({physical=1,holy=2,fire=3,frost=5,shadow=6,nature=4,arcane=7})do snap.stats[school..'Crit']=publicNumber(GetSpellCritChance(index))end end
 if GetSpellBonusDamage then snap.stats.holyPower=publicNumber(GetSpellBonusDamage(2));snap.stats.firePower=publicNumber(GetSpellBonusDamage(3));snap.stats.frostPower=publicNumber(GetSpellBonusDamage(5));snap.stats.shadowPower=publicNumber(GetSpellBonusDamage(6));snap.stats.naturePower=publicNumber(GetSpellBonusDamage(4));snap.stats.arcanePower=publicNumber(GetSpellBonusDamage(7)) end
 if data and(data.typedCombat or data.combatModes)then
  if GetMeleeHaste then snap.stats.meleeHastePct=publicNumber(GetMeleeHaste())end;if GetRangedHaste then snap.stats.rangedHastePct=publicNumber(GetRangedHaste())end
  local function primaryCrit(fn,attribute)if not fn or not attribute or attribute<=0 then return nil end;local ok,value=pcall(fn,'player');value=ok and publicNumber(value);if value and value>0 then return value/attribute end end
  snap.stats.critPerAgility=primaryCrit(GetCritChanceFromAgility,snap.stats.agility);snap.stats.critPerIntellect=primaryCrit(GetSpellCritChanceFromIntellect,snap.stats.intellect)
  local function totalAP(fn)if not fn then return nil end;local base,plus,minus=fn('player');base,plus,minus=publicNumber(base),publicNumber(plus),publicNumber(minus);if base and plus and minus then return base+plus+minus end end
  snap.stats.attackPower=totalAP(UnitAttackPower);snap.stats.rangedAttackPower=totalAP(UnitRangedAttackPower)
  if GetRangedCritChance then snap.stats.rangedCritPct=publicNumber(GetRangedCritChance())end
  if GetHitModifier then snap.stats.meleeHitPct=publicNumber(GetHitModifier())end
  if GetShieldBlock then snap.stats.blockValue=publicNumber(GetShieldBlock())end
  if GetExpertise then snap.stats.expertise=publicNumber(GetExpertise())end
  if IsStealthed then local v=IsStealthed();if not protected(v)then snap.stealthed=v==true or v==1 end end
  if GetWeaponEnchantInfo then local mh,_,_,mhID,oh,_,_,ohID=GetWeaponEnchantInfo();if not protected(mh)and not protected(oh)and(not mh or publicNumber(mhID))and(not oh or publicNumber(ohID))then snap.weaponEnchants={mainhand=mh and mhID or 0,offhand=oh and ohID or 0}end end
  snap.dualWield=IsSpellKnown and not protected(IsSpellKnown(674))and IsSpellKnown(674)==true or false
  local form=GetShapeshiftFormID and publicNumber(GetShapeshiftFormID())or 0
  snap.form=({[1]='cat',[5]='bear',[8]='bear',[31]='moonkin',[28]='shadow',[17]='battle',[18]='defensive',[19]='berserker'})[form]or(string.lower(class)=='warrior'and'battle'or'caster')
  if UnitPowerMax then snap.stats.maxEnergy=publicNumber(UnitPowerMax('player',3));snap.stats.maxRage=publicNumber(UnitPowerMax('player',1))end
  -- Start each prospective fight with full energy, zero rage and zero combo points.
  snap.stats.energy=snap.stats.maxEnergy or 100;snap.stats.rage=0;snap.stats.weapons={}
  if UnitDamage and UnitAttackSpeed then
   local lo,hi,ohLo,ohHi,positive,negative,mult=UnitDamage('player');local speed,ohSpeed=UnitAttackSpeed('player')
   lo,hi,ohLo,ohHi,speed,ohSpeed,mult=publicNumber(lo),publicNumber(hi),publicNumber(ohLo),publicNumber(ohHi),publicNumber(speed),publicNumber(ohSpeed),publicNumber(mult)
   for _,hand in ipairs({'mainhand','offhand'})do local l,h,v=hand=='mainhand'and lo or ohLo,hand=='mainhand'and hi or ohHi,hand=='mainhand'and speed or ohSpeed
    if l and h and v and v>0 and mult then local item=nil;for _,it in ipairs(equipped)do if it.slot==(hand=='mainhand'and'MainHandSlot'or'SecondaryHandSlot')then item=it end end
     if hand=='mainhand'or item and item.weaponClass==2 then local baseSpeed=item and item.weapon and item.weapon.speed or v*(1+(snap.stats.meleeHastePct or snap.stats.hastePct or 0)/100);snap.stats.weapons[hand]={min=l,max=h,speed=baseSpeed,includesAttackPower=true,attackPower=snap.stats.attackPower,damageMultiplier=mult or 1,form=snap.form,subclass=item and item.weaponSubclass,normalizedSpeed=(snap.form=='cat'and 1 or snap.form=='bear'and 2.5 or item and item.weapon and item.weapon.normalizedSpeed or 2.4)}end
    end
   end
  end
  if UnitRangedDamage then local speed,lo,hi,positive,negative,mult=UnitRangedDamage('player');speed,lo,hi,mult=publicNumber(speed),publicNumber(lo),publicNumber(hi),publicNumber(mult)
   if speed and lo and hi and speed>0 and mult then snap.stats.weapons.ranged={min=lo,max=hi,speed=speed*(1+(snap.stats.rangedHastePct or snap.stats.hastePct or 0)/100),normalizedSpeed=2.8,includesAttackPower=true,attackPower=snap.stats.rangedAttackPower,damageMultiplier=mult or 1}end
  end
 end
 -- Generic live state for ForeverCore, every class. Public read-only APIs only.
 if not snap.weaponEnchants and GetWeaponEnchantInfo then local mh,_,_,mhID,oh,_,_,ohID=GetWeaponEnchantInfo();if not protected(mh)and not protected(oh)and(not mh or publicNumber(mhID))and(not oh or publicNumber(ohID))then snap.weaponEnchants={mainhand=mh and mhID or 0,offhand=oh and ohID or 0}end end
 if GetNumShapeshiftForms and GetShapeshiftFormInfo then
  local forms=publicNumber(GetNumShapeshiftForms())or 0
  for i=1,forms do local _,active,_,spellID=GetShapeshiftFormInfo(i);if not protected(active)and active then snap.formSpell=publicNumber(spellID)end end
 end
 if snap.petActive then
  local ids={};local count=publicNumber((C_SpellBook and C_SpellBook.HasPetSpells and C_SpellBook.HasPetSpells())or(HasPetSpells and HasPetSpells()))
  for i=1,(count or 0)do local id=spellbookEntry(i,true);if id then ids[#ids+1]=id end end
  snap.petSpells=ids;snap.petSpellsComplete=count~=nil
  -- What the client says each pet spell does at the pet's level: the numbers of its description,
  -- its cost and cast time. ForeverCore decides which of them the engine models.
  local info={}
  local describe=(C_Spell and C_Spell.GetSpellDescription)or GetSpellDescription
  local costs=(C_Spell and C_Spell.GetSpellPowerCost)or GetSpellPowerCost
  for _,id in ipairs(ids)do
   local row={id=id,values={}}
   local ok,text=pcall(describe or function()end,id);text=ok and publicString(text)
   if text then for n in text:gmatch('%d+[%.,]?%d*')do row.values[#row.values+1]=tonumber((n:gsub(',','.')))end end
   local okc,c=pcall(costs or function()end,id)
   if okc and type(c)=='table'and type(c[1])=='table'then row.cost=publicNumber(c[1].cost)end
   row.described=text~=nil;info[#info+1]=row
  end
  snap.petSpellInfo=info
  if FUSLive.capturePet then local ok,p=pcall(FUSLive.capturePet);snap.petLive=ok and p or {status='unreadable'}end
 end
 local data=FUSLiveData and FUSLiveData[string.lower(class)]
 snap.activeAuraInfo={}
 for index=1,40 do local spellId,auraName=nil,nil;if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then local aura=C_UnitAuras.GetAuraDataByIndex('player',index,'HELPFUL');spellId=aura and aura.spellId;auraName=aura and aura.name elseif UnitBuff then auraName=UnitBuff('player',index);spellId=select(10,UnitBuff('player',index))end;if not protected(spellId) and spellId then snap.activeAuras[#snap.activeAuras+1]=spellId;snap.activeAuraInfo[#snap.activeAuraInfo+1]={id=spellId,name=publicString(auraName)};local effect=data and data.profileAuraEffects and data.profileAuraEffects[tostring(spellId)];if effect then snap[effect.field]=effect.value end end end
 if not forLive then db.export=json(snap);db.updated=date and date('%Y-%m-%d %H:%M') or 'in game';db.schema=1 end
 return snap
end
local normalizeSnapshot=FUSLive.normalizeSnapshot
FUSLive.normalizeSnapshot=function(snap)
 local profile=normalizeSnapshot(snap)
 profile.talentSnapshotStatus=snap.talentSnapshotStatus
 profile.talentStatus=snap.talentSnapshotStatus
 -- Live talent ranks are already part of the character sheet; drafts are applied as a delta.
 local data=FUSLiveData and FUSLiveData[profile.class]
 if data and FUSLive.talents then profile.liveTalentRanks=FUSLive.talents(data,profile)end
 return profile
end
function FUSLive.simulationIssue(profile)
 local status=profile and profile.talentSnapshotStatus
 if status and status.state~='valid' then return status.message or 'Live-Talente unvollständig. Im Talent-Tab erneut lesen.' end
end
local coverage=FUSLive.coverage
FUSLive.coverage=function(data,profile)
 return FUSLive.simulationIssue(profile) or coverage(data,profile)
end
FUSLive.capture=snapshot
FUSLive.readItem=makeItem
local event=CreateFrame('Frame');event:RegisterEvent('PLAYER_ENTERING_WORLD');event:RegisterEvent('BAG_UPDATE_DELAYED');event:RegisterEvent('QUEST_COMPLETE');event:RegisterEvent('QUEST_TURNED_IN');event:RegisterEvent('PLAYER_REGEN_ENABLED')
for _,name in ipairs({'PLAYER_LEVEL_UP','PLAYER_EQUIPMENT_CHANGED','SPELLS_CHANGED','CHARACTER_POINTS_CHANGED','LEARNED_SPELL_IN_TAB'}) do pcall(event.RegisterEvent,event,name) end
local pending=false
local function refresh()
 pending=false
 if FUSLive.passiveSafetyMode()then return end
 -- Keep the last complete SavedVariables snapshot while combat APIs are secret.
 if InCombatLockdown and InCombatLockdown() then return end
 snapshot()
end
event:SetScript('OnEvent',function(_,name)
 if FUSLive.passiveSafetyMode() then return end -- no background snapshots in passive mode
 if name=='QUEST_COMPLETE' then captureQuestRewards() end
 if name=='QUEST_TURNED_IN' then db.questRewards={} end
 if pending then return end
 pending=true
 -- Changes can fire in bursts; one snapshot after they settle.
 if C_Timer and C_Timer.After then C_Timer.After(1,refresh) else refresh() end
end)
SLASH_FOREVERSIMBRIDGE1='/fus'
SlashCmdList['FOREVERSIMBRIDGE']=function(msg)
 msg=(msg or ''):lower():gsub('^%s+',''):gsub('%s+$','')
 if msg=='safety' or msg=='safe' or msg=='taint' or msg=='diagnose' then
  print('Forever SIM: Schutzmodus '..(FUSLive.passiveSafetyMode() and 'AKTIV (offline)' or 'AUS (live aktiviert)'))
  local detail=db.lastBlockedAction
  print('Forever SIM: Blockierte Aktionen '..tostring(db.blockedActionCount or 0)..'; letzte: '..(detail and detail.action or 'keine protokolliert'))
  return
 elseif msg=='safety on' or msg=='safe on' then
  db.passiveSafetyMode=true
  print('Forever SIM: Schutzmodus AKTIV. Automatische Live-Lesungen deaktiviert.')
  return
 elseif msg=='safety off' or msg=='safe off' then
  db.passiveSafetyMode=false
  print('Forever SIM: Live-Erkennung aktiviert (nur zur Diagnose). /fus safety on setzt sie zurueck.')
  return
 end
 -- the dungeon loot list belongs to ForeverCore (/fc dungeon, /fc dungeon auto on|off)
 if msg=='dungeon' or msg:find('^dungeon ') then if SlashCmdList.FOREVERCORE then SlashCmdList.FOREVERCORE((msg:gsub(' rescan',''))) else print('Forever SIM: Dungeon-Liste braucht ForeverCoreBridge (/fc dungeon)') end;return end
 local boss=tonumber(msg:match('^boss%s+(%d+)$'));if boss then if FUSLive.encounters then FUSLive.encounters.Configure({mode='standard',offset=boss})end;print('Forever SIM: Standardziel +'..boss);return end
 if msg=='class' then local snap=snapshot(true);if not snap then print('Forever SIM: Charakterdaten fehlen.');return end;local profile=FUSLive.normalizeSnapshot(snap);local model=FUSLiveData[profile.class];if not model then print('Forever SIM: Klassenmodul fehlt.');return end;local issue=FUSLive.coverage(model,profile);print('Forever SIM · '..profile.class..': '..(issue or 'Klassenmodul aktiv · Einzelziel-DPS (Beta; Raid-Abgleich offen).'));return end
 local targetArmor=tonumber(msg:match('^armor%s+(%d+)$'));if targetArmor then if FUSLive.encounters then FUSLive.encounters.Configure({armor=targetArmor})end;print('Forever SIM: Zielrüstung '..targetArmor..' (Benutzereingabe)');return end
 if msg=='status' then print('Forever SIM: '..FUSLive.pendingJobs()..' Jobs, max Frame-Paket '..string.format('%.2f',FUSLive.metrics.maxSliceMs)..' ms');return end
 snapshot()
 print('|cff80ddffForever SIM:|r /fus dungeon, /fus status, /fus class, /fus armor <Wert>, /fus boss <Stufen>, /fus safety')
end
