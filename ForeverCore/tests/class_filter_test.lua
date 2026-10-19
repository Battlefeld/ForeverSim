-- Scan filter and stat filter for all nine classes with the real class data of ForeverSimBridge.
-- DPS only: healers and tanks are not a goal. Expectations follow the Classic armor / weapon rules.
local root=assert(arg[1]);dofile(root..'/_dev/harness/wowmock.lua');dofile(root..'/_dev/harness/gameapi.lua')
local function loadAddon(addon)
 for line in io.lines(root..'/'..addon..'/'..addon..'.toc')do
  local file=line:gsub(string.char(13),''):gsub(string.char(92),'/'):match('^%s*([^#].-%.lua)%s*$')
  if file then assert(loadfile(root..'/'..addon..'/'..file))(addon,{})end
 end
end
loadAddon('ForeverSimBridge');loadAddon('ForeverCoreBridge')
MOCK.Fire('PLAYER_LOGIN');MOCK.Advance(.5,.05)
local C=ForeverCoreClient;local AH=C.AH
C.Say=function()end
local CLASSES={'WARRIOR','PALADIN','HUNTER','ROGUE','PRIEST','SHAMAN','MAGE','WARLOCK','DRUID'}
for _,token in ipairs(CLASSES)do assert(FUSLiveData[token] or FUSLiveData[token:lower()],'class data exists for '..token)end
local function setChar(token,level)
 UnitClass=function()return token,token end
 UnitLevel=function()return level end
 ForeverCoreBridgeDB.ahChars=nil
end
-- item class / subclass for GetItemInfoInstant
local ITEMS={
 [1001]={'INVTYPE_CHEST',4,1},[1002]={'INVTYPE_CHEST',4,2},[1003]={'INVTYPE_CHEST',4,3},[1004]={'INVTYPE_CHEST',4,4},
 [1005]={'INVTYPE_SHIELD',4,6},[1006]={'INVTYPE_CLOAK',4,1},[1007]={'INVTYPE_FINGER',4,0},
 [1010]={'INVTYPE_WEAPON',2,15},[1011]={'INVTYPE_RANGEDRIGHT',2,19},[1012]={'INVTYPE_RANGED',2,2},[1013]={'INVTYPE_2HWEAPON',2,10},
}
C_Item=C_Item or{}
C_Item.GetItemInfoInstant=function(id)local e=ITEMS[id];if e then return id,'x','y',e[1],'',e[2],e[3]end end
local function wearable(id)local r=AH.Remember(id,10);return r=='new'or r=='known'end
local function expect(token,level,id,want,what)
 setChar(token,level)
 local got=wearable(id)
 assert(got==want,string.format('%s level %d: %s should be %s',token,level,what,want and'wearable'or'filtered'))
end
local function set(list)local t={};for _,v in ipairs(list)do t[v]=true end;return t end
-- armor types
local leather=set{'WARRIOR','PALADIN','HUNTER','ROGUE','SHAMAN','DRUID'}
local mail12=set{'WARRIOR','PALADIN'}
local mail60=set{'WARRIOR','PALADIN','HUNTER','SHAMAN'}
local plate60=set{'WARRIOR','PALADIN'}
local shield=set{'WARRIOR','PALADIN','SHAMAN'}
for _,token in ipairs(CLASSES)do
 for _,level in ipairs({7,12,60})do
  expect(token,level,1001,true,'cloth')
  expect(token,level,1006,true,'cloak')
  expect(token,level,1007,true,'ring')
  expect(token,level,1002,leather[token]==true,'leather')
  expect(token,level,1003,(level==60 and mail60 or mail12)[token]==true,'mail')
  expect(token,level,1004,level==60 and plate60[token]==true,'plate')
  expect(token,level,1005,shield[token]==true,'shield')
 end
end
-- weapons by class (data of the Forever client)
local dagger=set{'WARRIOR','HUNTER','ROGUE','PRIEST','SHAMAN','MAGE','WARLOCK','DRUID'}
local wand=set{'PRIEST','MAGE','WARLOCK'}
local bow=set{'WARRIOR','HUNTER','ROGUE'}
local staff=set{'WARRIOR','HUNTER','PRIEST','SHAMAN','MAGE','WARLOCK','DRUID'}
for _,token in ipairs(CLASSES)do
 expect(token,60,1010,dagger[token]==true,'dagger')
 expect(token,60,1011,wand[token]==true,'wand')
 expect(token,60,1012,bow[token]==true,'bow')
 expect(token,60,1013,staff[token]==true,'staff')
end
-- stats that count for damage; hybrids keep everything offensive; healing, tanking and spirit-less melee do not count
local function relevant(token,stats)
 UnitClass=function()return token,token end
 return AH.Irrelevant({slot='head',rawStats=stats})==nil
end
local MANA={HUNTER=true,PRIEST=true,MAGE=true,WARLOCK=true,PALADIN=true,SHAMAN=true,DRUID=true}
local HYBRID={PALADIN=true,SHAMAN=true,DRUID=true}
local CASTER={PRIEST=true,MAGE=true,WARLOCK=true}
local MELEE={WARRIOR=true,ROGUE=true,HUNTER=true}
for _,token in ipairs(CLASSES)do
 local function check(key,want,why)
  assert(relevant(token,{[key]=5})==want,string.format('%s: %s should be %s (%s)',token,key,want and'relevant'or'irrelevant',why))
 end
 -- never relevant for damage, for anybody
 for _,key in ipairs({'ITEM_MOD_STAMINA_SHORT','ITEM_MOD_SPELL_HEALING_DONE_SHORT','ITEM_MOD_DEFENSE_SKILL_RATING_SHORT','ITEM_MOD_BLOCK_VALUE_SHORT','ITEM_MOD_DODGE_RATING_SHORT','RESISTANCE0_NAME'})do check(key,false,'tank / healer stat')end
 -- mana: regeneration helps whoever casts from mana (the simulation decides how much)
 check('ITEM_MOD_SPIRIT_SHORT',MANA[token]==true,'spirit')
 check('ITEM_MOD_MANA_REGENERATION_SHORT',MANA[token]==true,'mana regeneration')
 -- crit, hit, haste help every damage dealer
 check('ITEM_MOD_CRIT_RATING_SHORT',true,'crit');check('ITEM_MOD_HIT_RATING_SHORT',true,'hit');check('ITEM_MOD_HASTE_RATING_SHORT',true,'haste')
 -- primary and power stats by role
 check('ITEM_MOD_AGILITY_SHORT',(MELEE[token] or HYBRID[token])==true,'agility')
 check('ITEM_MOD_STRENGTH_SHORT',(MELEE[token] or HYBRID[token])==true,'strength')
 check('ITEM_MOD_ATTACK_POWER_SHORT',(MELEE[token] or HYBRID[token])==true,'attack power')
 check('ITEM_MOD_INTELLECT_SHORT',(CASTER[token] or HYBRID[token] or token=='HUNTER')==true,'intellect')
 check('ITEM_MOD_SPELL_POWER_SHORT',(CASTER[token] or HYBRID[token])==true,'spell power')
end
-- weapons are always computed, whatever their stats
UnitClass=function()return 'MAGE','MAGE' end
assert(AH.Irrelevant({slot='mainhand',rawStats={ITEM_MOD_STAMINA_SHORT=5}})==nil,'weapons are always computed')
io.write('class filter tests passed (9 classes, levels 7, 12 and 60)\n')
