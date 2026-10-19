from pathlib import Path
exec(Path('wowmock_live.py').read_text().split("lua.execute(root.joinpath('LiveUI.lua').read_text())")[0])
for c in ['warlock','mage','shaman','priest','paladin','hunter','rogue','warrior','druid']:
 lua.execute((root/'Classes'/f'{c}.lua').read_text())
for f in ['Classes/shaman_melee.lua','CombatEngine.lua','UniversalRules.lua','Optimizers.lua']:
 lua.execute((root/f).read_text())
lua.execute('''
UIParent=CreateFrame();SlashCmdList={};ForeverSimBridgeDB={};level=13
function UnitClass()return 'Rogue','ROGUE'end
function UnitName()return 'Test'end
function UnitRace()return 'Orc','Orc'end
function UnitFactionGroup()return 'Horde'end
function UnitExists(unit)return unit~='pet'end
function UnitStat(unit,index)return 20,20,0,0 end
function UnitHealthMax()return 400 end
function UnitPowerMax(unit,power)if power==0 then return 0 else return 100 end end
function GetManaRegen()return 0,0 end
function UnitAttackPower()return 140,20,-10 end
function UnitRangedAttackPower()return 100,10,0 end
function UnitDamage()return 40,60,0,0,0,0,1 end
function UnitAttackSpeed()return 2,nil end
function UnitRangedDamage()return 2.8,30,40,0,0,1 end
function GetCritChance()return 7 end
function GetRangedCritChance()return 9 end
function GetSpellCritChance()return 0 end
function GetSpellBonusDamage()return 0 end
function GetHitModifier()return 0 end
function GetShapeshiftFormID()return 0 end
function IsSpellKnown(id)return id==674 end
function GetWeaponEnchantInfo()return false,0,0,0,false,0,0,0 end
function GetNumSpellTabs()return 1 end
function GetSpellTabInfo()return 'Combat',nil,0,2 end
function GetSpellBookItemInfo(index)return 'SPELL',index==1 and 1752 or 2098 end
function GetSpellBookItemName(index)return index==1 and 'Sinister Strike'or'Eviscerate','Rank 1'end
''')
lua.execute((root/'ForeverSimBridge.lua').read_text())
lua.execute('''
local P=FUSLive;local snap=P.capture(true)
assert(snap.class=='ROGUE'and snap.stats.attackPower==150 and snap.stats.rangedAttackPower==110)
assert(snap.stats.strength==20 and snap.stats.weapons.mainhand.speed==2)
assert(snap.stats.weapons.mainhand.includesAttackPower and snap.stats.weapons.mainhand.attackPower==150)
assert(snap.stats.weapons.ranged.normalizedSpeed==2.8 and snap.dualWield)
local p=P.normalizeSnapshot(snap);assert(not P.coverage(FUSLiveData.rogue,p));assert(p.knownSpellRanks.sinisterStrike[1]==1)
local spec=P.compile(FUSLiveData.rogue,p,P.combine({}),P.candidates(FUSLiveData.rogue,p)[1],30,7331);assert(P.run(spec).total>0)
-- A protected weapon damage multiplier never enters calculations as a guessed public value.
function issecretvalue(x)return type(x)=='table'and x.secret==true end
function UnitDamage()return 40,60,0,0,0,0,{secret=true}end
snap=P.capture(true);assert(not snap.stats.weapons.mainhand)
p=P.normalizeSnapshot(snap);assert(P.coverage(FUSLiveData.rogue,p):find('Waffenwerte fehlen'))
print('PASS: new-class live capture, AP/resource/weapon fields, actually learned ranks, dual wield, secret-weapon fail closed.')
''')
