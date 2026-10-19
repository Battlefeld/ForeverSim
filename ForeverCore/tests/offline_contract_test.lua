local root=assert(arg[1]);dofile(root..'/_dev/harness/wowmock.lua');dofile(root..'/_dev/harness/gameapi.lua')
local inCombat=false;InCombatLockdown=function()return inCombat end
local function forbidden()error('live combat API read')end
for _,name in ipairs({'UnitPower','UnitPowerMax','UnitHealth','UnitHealthMax','UnitAura','UnitBuff','UnitDebuff','CombatLogGetCurrentEventInfo','GetSpellCooldown','GetActionInfo','UnitGUID'})do _G[name]=forbidden end
C_Spell={GetSpellCooldown=forbidden};C_UnitAuras={GetAuraDataByIndex=forbidden}
FUSLive={copy=function(v)return v end,canonical=function()return'profile'end}
for _,file in ipairs({'CombatAudit.lua','Services/TargetHealthProvider.lua'})do assert(loadfile(root..'/ForeverSimBridge/'..file))('ForeverSimBridge',{})end
ForeverSimBridgeDB=ForeverSimBridgeDB or{};ForeverSimBridgeDB.combatAudit={fights={{target={health=999999}}}}
MOCK.Fire('ADDON_LOADED','ForeverSimBridge')
assert(ForeverSimBridgeDB.combatAudit==nil,'old measurements retained')
assert(not FUSLive.combatAudit.levelingContext({}),'audit still produces observations')
local target=assert(FUSLive.targetHealth.Resolve({level=20},{},{targetLevel=20,targetHealth=999999}))
assert(target.sourceCode=='model'and target.targetHealth~=999999,'historical health still used')
assert(#MOCK.errors==0,MOCK.errors[1]and MOCK.errors[1].msg or'')
io.write('offline combat boundary tests passed\n')
