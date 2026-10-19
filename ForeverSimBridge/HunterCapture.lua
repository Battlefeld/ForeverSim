-- Live values for ForeverCore: any class's pet, and the hunter's ammunition and quiver, read from the client.
-- Nothing here names an item, family or percentage: the client supplies the values and the
-- localized strings, ForeverCore maps them with tables generated from game and engine data.
-- Protected (secret) values make the part 'unreadable' instead of guessing.
FUSLive=FUSLive or {};local P=FUSLive

local function pub(v)return P.publicNumber and P.publicNumber(v)end
local function pubs(v)return P.publicString and P.publicString(v)end
local function number(text)
 if not text then return nil end
 return tonumber((text:gsub(',','.')))
end

local scanner
local function tooltipLines(fill)
 if not CreateFrame then return {} end
 if not scanner then
  scanner=CreateFrame('GameTooltip','ForeverCoreHunterScanner',nil,'GameTooltipTemplate')
  scanner:SetOwner(UIParent,'ANCHOR_NONE')
 end
 -- A tooltip used as a scanner needs its owner set before EVERY use, otherwise it stays empty after the first item
 scanner:SetOwner(UIParent,'ANCHOR_NONE')
 scanner:ClearLines()
 if not pcall(fill,scanner) then return {} end
 local out={}
 for n=1,scanner:NumLines()do
  for _,side in ipairs({'Left','Right'})do
   local line=_G['ForeverCoreHunterScannerText'..side..n]
   local text=line and pubs(line:GetText())
   if text then out[#out+1]=text end
  end
 end
 return out
end

-- Lua pattern from a client format string ("Adds %s damage per second" in any language).
local function templatePattern(template)
 local marked=template:gsub('%%[%d%.]*[sdfg]','\1')
 marked=marked:gsub('([%(%)%.%%%+%-%*%?%[%]%^%$])','%%%1')
 return (marked:gsub('\1','([%%d%%.,]+)'))
end

local function itemStats(link)
 local f=(C_Item and C_Item.GetItemStats)or GetItemStats
 if type(f)~='function' then return nil end
 local ok,stats=pcall(f,link)
 return ok and stats or nil
end

local function ammoTooltipDPS(lines)
 if type(AMMO_DAMAGE_TEMPLATE)~='string'then return nil end
 local pattern=templatePattern(AMMO_DAMAGE_TEMPLATE)
 for _,text in ipairs(lines)do
  -- Hyperlink tooltips may contain formatting escapes around the DPS number.
  text=text:gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r',''):gsub('|n',' ')
  local v=number(text:match(pattern))
  if v and v>0 then return v end
 end
end

local function structuredLines(fn,...)
 if type(fn)~='function'then return {} end
 local ok,data=pcall(fn,...)
 if not ok or type(data)~='table'then return {} end
 local out={}
 for _,line in ipairs(data.lines or{})do
  for _,key in ipairs({'leftText','rightText'})do
   local text=pubs(line[key]);if text then out[#out+1]=text end
  end
 end
 return out
end

local function ammo()
 if not GetInventoryItemID then return {status='unreadable'} end
 local slot=INVSLOT_AMMO or 0
 local raw=GetInventoryItemID('player',slot)
 if raw==nil then return {status='none'} end
 local id=pub(raw)
 if not id then return {status='unreadable'} end
 local link=GetInventoryItemLink and pubs(GetInventoryItemLink('player',slot))
 local dps
 local stats=link and itemStats(link)
 if stats then dps=pub(stats.ITEM_MOD_DAMAGE_PER_SECOND_SHORT)end
 if not dps then
  dps=ammoTooltipDPS(tooltipLines(function(t)t:SetInventoryItem('player',slot)end))
 end
 if not dps and link then
  -- Some Classic clients return the ammo identity for slot 0 but do not fill
  -- its inventory tooltip. Read the same equipped item's hyperlink instead.
  dps=ammoTooltipDPS(tooltipLines(function(t)t:SetHyperlink(link)end))
 end
 local info=C_TooltipInfo
 if not dps and info then
  dps=ammoTooltipDPS(structuredLines(info.GetInventoryItem,'player',slot))
  if not dps and link then dps=ammoTooltipDPS(structuredLines(info.GetHyperlink,link))end
 end
 if dps and dps>0 then return {status='ok',itemId=id,dps=dps,link=link}end
 return {status='unreadable',itemId=id,link=link}
end

local function bagSlot(bag)
 local f=(C_Container and C_Container.ContainerIDToInventoryID)or ContainerIDToInventoryID
 if type(f)~='function' then return nil end
 local ok,slot=pcall(f,bag)
 return ok and slot or nil
end
local function isQuiver(id)
 local f=(C_Item and C_Item.GetItemInfoInstant)or GetItemInfoInstant
 if type(f)~='function' then return nil end
 local classID=select(6,f(id))
 local quiverClass=Enum and Enum.ItemClass and Enum.ItemClass.Quiver
 if not quiverClass or classID==nil then return nil end
 return classID==quiverClass
end
local function spellDescription(spellId)
 local f=(C_Spell and C_Spell.GetSpellDescription)or GetSpellDescription
 if type(f)~='function' then return nil end
 local ok,text=pcall(f,spellId)
 return ok and pubs(text)or nil
end

local function rangedHaste(lines)
 for _,text in ipairs(lines)do
  text=text:gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r',''):lower()
  if text:find('ranged attack speed',1,true)or text:find('fernkampfangriffstempo',1,true)or text:find('distanzangriffstempo',1,true)then
   local pct=number(text:match('(%d+[%.,]?%d*)%s*%%'))
   if pct and pct>0 then return pct end
  end
 end
end

local function quiver()
 local itemSpell=(C_Item and C_Item.GetItemSpell)or GetItemSpell
 for bag=1,(NUM_BAG_SLOTS or 4)do
  local slot=bagSlot(bag)
  local id=slot and GetInventoryItemID and pub(GetInventoryItemID('player',slot))
  local kind=id and isQuiver(id)
  if kind==nil and id then return {status='unreadable'}end
  if kind then
   -- Both quivers and ammo pouches share the ammunition-container item class.
   -- Their equip bonus is not always exposed by GetItemSpell in Classic.
   local spellId=type(itemSpell)=='function' and pub(select(2,itemSpell(id)))
   local text=spellId and spellDescription(spellId)
   local pct=text and number(text:match('(%d+[%.,]?%d*)%s*%%'))
   local link=GetInventoryItemLink and pubs(GetInventoryItemLink('player',slot))
   if not pct then pct=rangedHaste(tooltipLines(function(t)t:SetInventoryItem('player',slot)end))end
   if not pct and link then pct=rangedHaste(tooltipLines(function(t)t:SetHyperlink(link)end))end
   local info=C_TooltipInfo
   if not pct and info then
    pct=rangedHaste(structuredLines(info.GetInventoryItem,'player',slot))
    if not pct and link then pct=rangedHaste(structuredLines(info.GetHyperlink,link))end
   end
   if pct and pct>0 then return {status='ok',itemId=id,spellId=spellId,hastePct=pct}end
   return {status='unreadable',itemId=id,spellId=spellId}
  end
 end
 return {status='none'}
end

local function familyId(name)
 local info=C_CreatureInfo
 if not name or not info or type(info.GetCreatureFamilyIDs)~='function' or type(info.GetCreatureFamilyInfo)~='function' then return nil end
 local ok,ids=pcall(info.GetCreatureFamilyIDs)
 if not ok or type(ids)~='table' then return nil end
 for _,id in ipairs(ids)do
  local okInfo,row=pcall(info.GetCreatureFamilyInfo,id)
  if okInfo and type(row)=='table' and pubs(row.name)==name then return id end
 end
end

-- Any class's pet (hunter beast, warlock demon): what the character sheet of the pet shows.
local function pet()
 local family=UnitCreatureFamily and pubs(UnitCreatureFamily('pet'))
 local out={family=family,locale=GetLocale and GetLocale(),level=UnitLevel and pub(UnitLevel('pet'))}
 out.mana=UnitPowerMax and pub(UnitPowerMax('pet',0))
 out.familyId=familyId(family)
 out.speed=UnitAttackSpeed and pub((UnitAttackSpeed('pet')))
 if UnitStat then
  out.stats={}
  for i,key in ipairs({'strength','agility','stamina','intellect','spirit'})do
   local base,effective,pos,neg=UnitStat('pet',i)
   base,effective,pos,neg=pub(base),pub(effective),pub(pos),pub(neg)
   -- Some clients return 0 as the first value for pets although the character sheet shows
   -- real stats; derive the unbuffed value from the effective stat minus buffs in that case.
   if (not base or base==0) and effective and effective>0 then base=math.max(0,effective-(pos or 0)-(neg or 0)) end
   out.stats[key]=base
  end
 end
 if UnitAttackPower then local b,p,n=UnitAttackPower('pet');out.attackPower={base=pub(b),pos=pub(p),neg=pub(n)}end
 if UnitDamage then
  local lo,hi,_,_,p,n,percent=UnitDamage('pet')
  out.damage={min=pub(lo),max=pub(hi),pos=pub(p),neg=pub(n),percent=pub(percent)}
 end
 -- Primary attributes may all read as zero or unavailable in the Forever client.
 -- Hunter live damage needs the combat-sheet AP, damage and attack speed instead.
 local complete=family and out.speed and out.speed>0 and out.attackPower and out.damage
 if complete then
  for _,k in ipairs({'base','pos','neg'})do if out.attackPower[k]==nil then complete=false end end
  for _,k in ipairs({'min','max','pos','neg','percent'})do if out.damage[k]==nil then complete=false end end
 end
 out.status=complete and 'ok' or 'unreadable'
 return out
end

P.capturePet=pet

function P.captureHunter(petActive)
 local out={ammo=ammo(),quiver=quiver()}
 if petActive then out.pet=pet()end
 return out
end
