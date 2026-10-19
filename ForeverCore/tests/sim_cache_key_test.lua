-- Cache key stability: buffs/auras/resources must not change it; gear, talents and level must.
local root=assert(arg[1]);dofile(root..'/_dev/harness/wowmock.lua');dofile(root..'/_dev/harness/gameapi.lua')
local function loadAddon(addon)
 local ns={}
 for line in io.lines(root..'/'..addon..'/'..addon..'.toc')do
  local file=line:gsub('\r',''):gsub('\\','/'):match('^%s*([^#].-%.lua)%s*$')
  if file then assert(loadfile(root..'/'..addon..'/'..file))(addon,ns)end
 end
end
loadAddon('ForeverSimBridge');loadAddon('ForeverCoreBridge')
MOCK.Fire('PLAYER_LOGIN');MOCK.Advance(.5,.05)
local C=ForeverCoreClient;local P=FUSLive
C.engineRevision='test-engine'
local function snap()
 return {schema=1,class='HUNTER',level=20,race='Orc',faction='Horde',name='T',
  equipped={{slot='HeadSlot',link='item:100',id=100,stats={agility=10}}},talents={{id=1,rank=2}},spells={{name='Auto Shot',id=75,rank=1}},
  encounter={mode='quest'},activeAuras={'Battle Shout'},activeAuraInfo={{id=1}},inventory={[6265]=5},soulShards=7,
  stats={attackPower=100,agility=50,rage=10,mana=300,health=400},stealthed=false,form=nil,weaponEnchants={main=1},petActive=true,
  hunter={ammo={dps=3.5,itemId=2519},quiver={hastePct=10},pet={family='Wolf',familyId=1,level=18,attackPower=45}},
  pet={type='wolf',level=18},bagItems={1,2},questRewards={3}}
end
local current=snap()
P.capture=function() return current end
local function ctx() C.revision=C.revision+1;C.simRevision=(C.simRevision or 0)+1;return C.SimCacheContext() end
local base=ctx();assert(base,'context missing')
-- volatile changes: same key
current=snap();current.activeAuras={'Mark of the Wild','Blessing of Might'};current.activeAuraInfo={{id=9},{id=10}}
current.inventory={[6265]=1};current.soulShards=0;current.stats.attackPower=999;current.stats.agility=77;current.stats.rage=0;current.stats.mana=1
current.stealthed=true;current.form=5487;current.weaponEnchants={main=7};current.hunter.pet.attackPower=500;current.bagItems={9};current.questRewards={}
assert(ctx()==base,'volatile state changed the cache key')
-- real changes: different key
current=snap();current.equipped[1].link='item:101';assert(ctx()~=base,'gear change must change the key')
current=snap();current.talents[1].rank=3;assert(ctx()~=base,'talent change must change the key')
current=snap();current.level=21;assert(ctx()~=base,'level change must change the key')
current=snap();current.spells[#current.spells+1]={name='Raptor Strike',id=2973,rank=1};assert(ctx()~=base,'spellbook change must change the key')
current=snap();current.hunter.ammo.dps=4.5;assert(ctx()~=base,'ammo change must change the key')
-- persistence
current=snap();local key=ctx()
C.StoreItemComparison(key,'sig',{percent=3.5,delta=1.2,baselineDps=100,candidateDps=103.5})
local store=ForeverCoreBridgeDB.simItemCache
assert(store and store.version==6 and store.entries[key..'/sig'],'record not stored')
-- transient capture errors (tooltips not loaded yet) are retried, real verdicts are not
assert(C.IsTransientIssue('Munition konnte im Spiel nicht gelesen werden'),'ammo error is transient')
assert(C.IsTransientIssue('Koecher/Munitionsbeutel konnte nicht gelesen werden'),'quiver error is transient')
assert(C.IsTransientIssue('Begleiter konnte im Spiel nicht vollstaendig gelesen werden (im Kampf geschuetzte Werte?)'),'pet error is transient')
assert(not C.IsTransientIssue('Item 5: vollstaendige Basiswerte fehlen oder Spezialeffekt nicht modelliert'),'model gaps are final')
assert(not C.IsTransientIssue(nil) and not C.IsTransientIssue(42),'non-strings are not transient')
io.write('sim cache key tests passed\n')
