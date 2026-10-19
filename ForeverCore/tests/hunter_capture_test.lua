-- Hunter live capture against a mocked client. Usage: lua5.1 hunter_capture_test.lua <repo root>
local root=assert(arg[1])
local secret={}
FUSLive={publicNumber=function(v)if v==secret or type(v)~='number'then return nil end return v end,
 publicString=function(v)if v==secret or type(v)~='string'then return nil end return v end}
UIParent={}
local tooltipText={}
function CreateFrame()
 local t={}
 function t:SetOwner()end
 function t:ClearLines()for k in pairs(_G)do if type(k)=='string'and k:match('^ForeverCoreHunterScannerTextLeft')then _G[k]=nil end end;self.n=0 end
 function t:SetInventoryItem(_,slot)for i,line in ipairs(tooltipText[slot]or {})do _G['ForeverCoreHunterScannerTextLeft'..i]={GetText=function()return line end};self.n=i end end
 function t:SetHyperlink(link)self:ClearLines();for i,line in ipairs(tooltipText[link]or{})do _G['ForeverCoreHunterScannerTextLeft'..i]={GetText=function()return line end};self.n=i end end
 function t:NumLines()return self.n or 0 end
 return t
end
assert(loadfile(root..'/ForeverSimBridge/HunterCapture.lua'))()

local inventory,stats={},{}
function GetInventoryItemID(_,slot)return inventory[slot]end
function GetInventoryItemLink(_,slot)return inventory[slot]and('item:'..inventory[slot])end
function GetItemStats(link)return stats[link]end
Enum={ItemClass={Quiver=11}}
local classes,spells,descriptions={},{},{}
function GetItemInfoInstant(id)return id,nil,nil,nil,nil,classes[id]end
function GetItemSpell(id)if spells[id]then return 'Haste',spells[id]end end
function GetSpellDescription(id)return descriptions[id]end
function ContainerIDToInventoryID(bag)return 19+bag end
GetLocale=function()return 'deDE'end

-- No ammo, no quiver, no pet.
local h=FUSLive.captureHunter(false)
assert(h.ammo.status=='none' and h.quiver.status=='none' and h.pet==nil,'empty hunter')

-- Ammo DPS from the client's item stats.
inventory[0]=2512;stats['item:2512']={ITEM_MOD_DAMAGE_PER_SECOND_SHORT=2}
h=FUSLive.captureHunter(false)
assert(h.ammo.status=='ok' and h.ammo.dps==2 and h.ammo.itemId==2512,'ammo via item stats')

-- Ammo DPS from the tooltip, built from the client's own (here German) template.
stats['item:2512']=nil;AMMO_DAMAGE_TEMPLATE='Verursacht %s zusätzlichen Schaden pro Sekunde.'
tooltipText[0]={'Raue Pfeile','Verursacht 4,5 zusätzlichen Schaden pro Sekunde.'}
h=FUSLive.captureHunter(false)
assert(h.ammo.status=='ok' and math.abs(h.ammo.dps-4.5)<1e-9,'ammo via German tooltip: '..tostring(h.ammo.dps))
AMMO_DAMAGE_TEMPLATE='Adds %.1f damage per second'
tooltipText[0]={'Rough Arrow','Adds 2.0 damage per second'}
h=FUSLive.captureHunter(false)
assert(h.ammo.status=='ok' and h.ammo.dps==2,'ammo via English %.1f template')
tooltipText[0]={'Rough Arrow'}
assert(FUSLive.captureHunter(false).ammo.status=='unreadable','missing DPS must not be guessed')
-- Slot 0 can return an item ID but no inventory tooltip in the live client.
inventory[0]=2519;tooltipText[0]={};AMMO_DAMAGE_TEMPLATE='Adds %s damage per second'
tooltipText['item:2519']={'Test ammunition','Adds |cffffffff3.5|r damage per second'}
h=FUSLive.captureHunter(false)
assert(h.ammo.status=='ok' and h.ammo.itemId==2519 and h.ammo.dps==3.5,'hyperlink ammo tooltip fallback')
-- Structured tooltips are also accepted when the legacy scanner is empty.
tooltipText['item:2519']={}
C_TooltipInfo={GetHyperlink=function(link)assert(link=='item:2519');return{lines={{rightText='Adds 4.5 damage per second'}}}end}
h=FUSLive.captureHunter(false)
assert(h.ammo.status=='ok' and h.ammo.dps==4.5,'structured hyperlink tooltip fallback')
C_TooltipInfo=nil
assert(FUSLive.captureHunter(false).ammo.status=='unreadable','no ammo value guessed')
inventory[0]=secret
assert(FUSLive.captureHunter(false).ammo.status=='unreadable','protected ammo')
inventory[0]=nil

-- Quiver: bag 2 is a quiver with an equip spell; its percentage comes from the spell text.
inventory[21]=7278;classes[7278]=11;spells[7278]=14824;descriptions[14824]='Erhöht das Fernkampfangriffstempo um 10%.'
h=FUSLive.captureHunter(false)
assert(h.quiver.status=='ok' and h.quiver.spellId==14824 and h.quiver.hastePct==10,'quiver')
inventory[20]=4500;classes[4500]=1
assert(FUSLive.captureHunter(false).quiver.status=='ok','ordinary bag before quiver')
spells[7278]=nil
assert(FUSLive.captureHunter(false).quiver.status=='unreadable','missing container haste must not become zero')
-- Ammo pouch with no item spell: read its equip line, not an item-ID default.
inventory[21]=5441;classes[5441]=11;tooltipText[21]={'Small Ammo Pouch','6 Slot Ammo Pouch','Equip: Increases ranged attack speed by 10%.'}
h=FUSLive.captureHunter(false)
assert(h.quiver.status=='ok' and h.quiver.itemId==5441 and h.quiver.hastePct==10 and not h.quiver.spellId,'ammo pouch tooltip haste')
-- A slot count alone is never an attack-speed bonus.
tooltipText[21]={'Small Ammo Pouch','10 Slot Ammo Pouch'}
assert(FUSLive.captureHunter(false).quiver.status=='unreadable','bag capacity mistaken for haste')
tooltipText[21]={'Small Ammo Pouch','Anlegen: Erhöht das Fernkampfangriffstempo um 10%.'}
assert(FUSLive.captureHunter(false).quiver.hastePct==10,'German ammo pouch haste')

-- Pet: every value from the client; family ID resolved through the client's family list.
UnitCreatureFamily=function()return 'Katze'end
UnitLevel=function()return 20 end
UnitAttackSpeed=function()return 2.0 end
local petStats={40,35,50,20,25}
UnitStat=function(_,i)return petStats[i],petStats[i]+5,5,0 end
UnitAttackPower=function()return 60,10,0 end
UnitDamage=function()return 30,40,nil,nil,0,0,1.25 end
C_CreatureInfo={GetCreatureFamilyIDs=function()return {1,2}end,GetCreatureFamilyInfo=function(id)return({{name='Wolf'},{name='Katze'}})[id]end}
h=FUSLive.captureHunter(true)
local p=h.pet
assert(p.status=='ok' and p.family=='Katze' and p.familyId==2 and p.locale=='deDE' and p.level==20,'pet identity')
assert(p.stats.strength==40 and p.stats.spirit==25,'pet base attributes are the unbuffed values')
assert(p.attackPower.base==60 and p.attackPower.pos==10 and p.damage.percent==1.25 and p.speed==2,'pet combat values')
-- Primary attributes can all read as zero while the pet combat sheet is usable.
petStats={0,0,0,0,0}
assert(FUSLive.captureHunter(true).pet.status=='ok','zero pet attributes must not hide valid AP and damage')
UnitStat=function()return secret end
assert(FUSLive.captureHunter(true).pet.status=='ok','unreadable pet attributes must not hide valid AP and damage')
C_CreatureInfo=nil
assert(FUSLive.captureHunter(true).pet.familyId==nil,'no family list: name only')
UnitDamage=function()return secret,40,nil,nil,0,0,1.25 end
assert(FUSLive.captureHunter(true).pet.status=='unreadable','protected pet damage')
print('hunter capture tests passed')
