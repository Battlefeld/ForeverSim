-- Classic "Equip:" lines are stats: read into the item, not "special effect".
local root=assert(arg[1]);dofile(root..'/_dev/harness/wowmock.lua');dofile(root..'/_dev/harness/gameapi.lua')
local function loadAddon(addon)
 local ns={}
 for line in io.lines(root..'/'..addon..'/'..addon..'.toc')do
  local file=line:gsub('\r',''):gsub('\\','/'):match('^%s*([^#].-%.lua)%s*$')
  if file then assert(loadfile(root..'/'..addon..'/'..file))(addon,ns)end
 end
end
loadAddon('ForeverSimBridge')
UnitClass=function()return'Schamane','SHAMAN'end
local L=FUSLive.equipLine
local function item()return{stats={},rawStats={}}end
local it=item();assert(L('equip: improves your chance to get a critical strike by 1%.',it,20)and it.stats.critPct==1 and it.rawStats.ITEM_MOD_CRIT_RATING_SHORT>0,'crit chance')
it=item();assert(L('equip: improves your chance to hit by 2%.',it,20)and it.stats.hitPct==2,'hit chance')
it=item();assert(L('equip: restores 3 mana per 5 sec.',it,20)and it.rawStats.ITEM_MOD_MANA_REGENERATION_SHORT==3,'mp5')
it=item();assert(L('equip: increases damage and healing done by magical spells and effects by up to 7.',it,20)and it.rawStats.ITEM_MOD_SPELL_POWER_SHORT==7,'spell power')
it=item();assert(L('equip: +24 attack power.',it,20)and it.rawStats.ITEM_MOD_ATTACK_POWER_SHORT==24,'attack power')
it=item();it.rawStats.ITEM_MOD_ATTACK_POWER_SHORT=24;assert(L('equip: +24 attack power.',it,20)and it.rawStats.ITEM_MOD_ATTACK_POWER_SHORT==24,'no double count when the client lists it')
it=item();assert(L('equip: increased defense +7.',it,20)and next(it.rawStats)==nil,'defense ignored')
it=item();assert(L('equip: +45 attack power when fighting undead.',it,20),'situational ignored')
it=item();assert(L('equip: increases healing done by spells and effects by up to 22.',it,20),'healing ignored')
it=item();assert(not L('equip: when struck in combat inflicts 3 arcane damage to the attacker.',it,20),'unknown effect stays not computable')
io.write('equip stats ok\n')
