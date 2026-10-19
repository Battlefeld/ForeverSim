-- Auction house bulk path: collect -> export job in the SavedVariables -> resume after reload -> results cached.
local root=assert(arg[1]);dofile(root..'/_dev/harness/wowmock.lua');dofile(root..'/_dev/harness/gameapi.lua')
local function loadAddon(addon)
 for line in io.lines(root..'/'..addon..'/'..addon..'.toc')do
  local file=line:gsub(string.char(13),''):gsub(string.char(92),'/'):match('^%s*([^#].-%.lua)%s*$')
  if file then assert(loadfile(root..'/'..addon..'/'..file))(addon,{})end
 end
end
loadAddon('ForeverSimBridge');loadAddon('ForeverCoreBridge')
UnitLevel=function()return 20 end
MOCK.Fire('PLAYER_LOGIN');MOCK.Advance(.5,.05)
local C=ForeverCoreClient;local P=FUSLive;local AH=C.AH
assert(AH and AH.Calculate and C.StoreExport,'auction module loaded')
C.engineRevision='rev-test'
local items={}
for id=201,205 do items[id]={id=id,slot='head',name='Helm '..id,minLevel=1,stats={},statsComplete=true} end
items[203].minLevel=40
P.readItem=function(link)return items[tonumber(tostring(link):match('item:(%d+)'))]end
P.capture=function()return{class='mage',level=20,faction='Horde',equipped={},spells={},talents={}}end
P.normalizeSnapshot=function(s)return{class='mage',level=20,faction='Horde',equipped={}}end
local reloaded=false;ReloadUI=function()reloaded=true end
C_Item=C_Item or{};C_Item.GetItemInfoInstant=function(id)return id,'Armor','Cloth','INVTYPE_HEAD' end
for id=201,205 do AH.Remember(id,id*100) end
assert(AH.Store().count==5,'items remembered')
local sent={}
local realRequest=C.Request
-- calculate: the unwearable item is sorted out locally, four candidates are exported
C.pending=nil;C.queue={}
local said={};C.Say=function(t)said[#said+1]=tostring(t)end
assert(AH.Calculate()==true,'calculate accepted: '..table.concat(said,' | ')..' pending='..tostring(C.pending)..' queue='..#C.queue)
assert(#C.queue==1 and C.queue[1].export==true and C.queue[1].payload.partial==true and #C.queue[1].payload.items==4,'export job queued with 4 candidates: '..#C.queue)
MOCK.Advance(.5,.05)
local job=ForeverCoreBridgeDB.ahJob
assert(job and type(job.json)=='string' and job.json:find('"partial":true',1,true) and job.json:find('"replyStart":'..C.ExportSlot(),1,true),'job asks for its own reply window')
assert(C.ExportSlot()>128,'export window is away from the normal slots')
assert(#job.sigs==4 and #job.keys==4,'metadata stored')
assert(C.pending==nil,'an export never paints the pixel strip')
MOCK.Advance(2,.1)
-- after the reload: a fresh session resumes the job
C.pending=nil;C.queue={};C.session='new-session'
local slotBefore=C.slot;AH.Resume()
assert(C.slot==C.ExportSlot(),'resumed job polls its own slot window')
assert(C.pending and C.pending.resumed and C.pending.session==job.session and C.pending.noPaint,'job resumed with the old session')
local cb=C.pending.callback;C.pending=nil
cb({baselineDps=100,candidates={{pct=104,dps=104},{pct=99,dps=99},{error='x',pct=0,dps=0},{pct=101,dps=101}}})
assert(ForeverCoreBridgeDB.ahJob==nil,'job removed')
assert(C.slot==slotBefore,'the normal slot counter is restored')
local r=AH.Store().results
assert(r and r[job.keys[1]] and math.abs(r[job.keys[1]].pct-4)<1e-9 and r[job.keys[2]].pct<0 and r[job.keys[3]]==nil,'results kept per item')
-- a stored result is found again through the normal item cache
local entry=C.ItemResult(job.keys[1])
assert(entry and entry.state=='ok' and math.abs(entry.pct-4)<1e-9,'cached comparison used by the tooltip: '..tostring(entry and entry.state))
local lines={};C.Say=function(t)lines[#lines+1]=tostring(t)end
GetItemInfo=function(k)return 'Ring',string.char(124)..'cff1eff00'..string.char(124)..'Hitem:201'..string.char(124)..'h[Ring]'..string.char(124)..'h'..string.char(124)..'r' end
C_Item.GetItemInfo=GetItemInfo
AH.Top(5)
assert(#lines>=2 and lines[2]:find('Ring',1,true) and lines[2]:find('+4.00',1,true),'top list shows names and gains: '..table.concat(lines,' | '))
lines={};AH.Report()
assert(#lines>=3 and lines[1]:find('Bericht',1,true),'report prints groups: '..table.concat(lines,' | '))
local full=C.ItemResult('|cff1eff00|Hitem:'..(job.keys[1]:match('item:(%d+)'))..'::::::::20:::::::|h[Helm]|h|r')
assert(full and full.state=='ok' and math.abs(full.pct-4)<1e-9,'a full auction house link finds the exported result: '..tostring(full and full.state))
assert(C.NormalizeLink('|Hitem:201:5:0:0:0:0:0:777:20:::|h')==C.NormalizeLink('item:201:5'),'without a suffix the unique id is dropped')
assert(C.NormalizeLink('|Hitem:201:5:0:0:0:0:-12:777:20:::|h')=='item:201:0:0:0:0:0:-12:777','with a suffix the unique id stays (the enchant 5 is dropped)')
assert(C.NormalizeLink('|Hitem:201:5:0:0:0:0:-12:777:20:::|h')~=C.NormalizeLink('|Hitem:201:5:0:0:0:0:-12:778:20:::|h'),'other seed, other candidate')
-- random suffix variants of one item id stay separate; an old data version is emptied
local before=AH.Store().count
assert(AH.Remember(300,500,'|cff1eff00|Hitem:300:0:0:0:0:0:-5:111:20|h[Ring of the Bear]|h|r')=='new','suffix variant 1')
assert(AH.Remember(300,400,'|cff1eff00|Hitem:300:0:0:0:0:0:-6:222:20|h[Ring of the Eagle]|h|r')=='new','suffix variant 2 is a separate candidate')
assert(AH.Remember(300,300,'|cff1eff00|Hitem:300:0:0:0:0:0:-5:111:20|h[Ring of the Bear]|h|r')=='known','same suffix and unique id: same candidate')
assert(AH.Store().count==before+2 and AH.Store().items['item:300:0:0:0:0:0:-5:111']==300,'lowest price kept')
C_Item.GetItemInfoInstant=function(id)return id,'Consumable','Potion','' end
assert(AH.Remember(301,10)=='ignored','non-equipment ignored')
local old=AH.Store();old.version=1;old.count=1
AH.Command('')
assert(AH.Store().version==5 and AH.Store().count==0,'old list version is emptied')
-- class and level pre-filter: armor type, weapon type, useless stats
UnitClass=function()return 'Mage','MAGE' end;UnitLevel=function()return 12 end
FUSLiveData=FUSLiveData or{}
FUSLiveData.MAGE=FUSLiveData.MAGE or{equipmentRules={armorTiers={{minLevel=1,maxSubclass=1}},weaponSubclasses={4,7,10,15},rangedSubclasses={19},shield=false}}
local rules=FUSLiveData.MAGE.equipmentRules
C_Item.GetItemInfoInstant=function(id)
 if id==400 then return id,'Armor','Plate','INVTYPE_CHEST','',4,4 end
 if id==401 then return id,'Armor','Cloth','INVTYPE_CHEST','',4,1 end
 if id==402 then return id,'Weapon','Two-Handed Axes','INVTYPE_2HWEAPON','',2,1 end
 if id==403 then return id,'Weapon','Staves','INVTYPE_2HWEAPON','',2,10 end
 return id,'Armor','Misc','INVTYPE_FINGER','',4,0
end
equipCacheReset=nil
assert(AH.Remember(400,1)=='armor','plate is not wearable for a level 12 mage')
assert(AH.Remember(401,1)=='new','cloth is wearable')
assert(AH.Remember(402,1)=='weapon','two-handed axe is not usable by a mage')
assert(AH.Remember(403,1)=='new','staff is usable')
assert(AH.Remember(404,1)=='new','rings have no armor type')
assert(AH.Irrelevant({slot='head',rawStats={ITEM_MOD_STAMINA_SHORT=5,ITEM_MOD_AGILITY_SHORT=3}})=='keine passenden Werte','agility does nothing for a mage')
assert(AH.Irrelevant({slot='head',rawStats={ITEM_MOD_STAMINA_SHORT=5,ITEM_MOD_INTELLECT_SHORT=3}})==nil,'intellect matters for a mage')
assert(AH.Irrelevant({slot='mainhand',rawStats={ITEM_MOD_STAMINA_SHORT=5}})==nil,'weapons are always computed')
assert(AH.Irrelevant({slot='head',rawStats={}})==nil,'unknown stats: let the simulation decide')
UnitClass=function()return 'Hunter','HUNTER' end
assert(AH.Irrelevant({slot='head',rawStats={ITEM_MOD_SPIRIT_SHORT=5,ITEM_MOD_STAMINA_SHORT=5}})==nil,'spirit counts for a hunter: faster mana regeneration')
assert(AH.Irrelevant({slot='head',rawStats={ITEM_MOD_STAMINA_SHORT=5,RESISTANCE0_NAME=20}})=='keine passenden Werte','stamina and armor alone do nothing for damage')
assert(AH.Irrelevant({slot='head',rawStats={ITEM_MOD_AGILITY_SHORT=5}})==nil,'agility matters for a hunter')
UnitClass=function()return 'Paladin','PALADIN' end
assert(AH.Irrelevant({slot='head',rawStats={ITEM_MOD_STRENGTH_SHORT=5}})==nil,'hybrids keep all offensive stats')
-- items the client has not loaded yet are retried by themselves
UnitClass=function()return 'Mage','MAGE' end
C_Item.GetItemInfoInstant=function(id)return id,'Armor','Misc','INVTYPE_FINGER','',4,0 end
local late=false
items[600]={id=600,slot='finger1',name='Late Ring',minLevel=1,stats={},statsComplete=true,rawStats={ITEM_MOD_INTELLECT_SHORT=4}}
local realRead=P.readItem
P.readItem=function(link)if tostring(link):find('item:600:',1,true) and not late then return nil end;return realRead(link)end
ForeverCoreBridgeDB.ahJob=nil;C.pending=nil;C.queue={}
local keep={};for k,v in pairs(AH.Store().items)do keep[k]=v end
AH.Store().items={};AH.Store().count=0;AH.Store().results={}
AH.Remember(600,50)
C.simRevision=C.simRevision+1
assert(AH.Calculate()==true)
MOCK.Advance(1,.1)
assert(ForeverCoreBridgeDB.ahJob==nil,'nothing exported yet: item data is missing')
late=true
MOCK.Advance(4,.1)
assert(ForeverCoreBridgeDB.ahJob and #ForeverCoreBridgeDB.ahJob.keys==1,'the retry found the item and exported it')
-- hunter quiver unreadable right after the game start: wait instead of exporting a job the PC would reject
ForeverCoreBridgeDB.ahJob=nil;C.pending=nil;C.queue={};C.simRevision=C.simRevision+1
local quiver='unreadable'
local baseCapture=P.capture
P.capture=function()local snap=baseCapture();snap.hunter={quiver={status=quiver}};return snap end
assert(AH.Calculate()==true,'waiting is accepted')
MOCK.Advance(1,.1)
assert(ForeverCoreBridgeDB.ahJob==nil,'nothing exported while the quiver is unreadable')
quiver='ok'
MOCK.Advance(5,.1)
assert(ForeverCoreBridgeDB.ahJob and #ForeverCoreBridgeDB.ahJob.keys>=1,'exported once the quiver is readable')
P.capture=baseCapture
-- pixel transport off: no pixel job is queued, the auction house export still is
ForeverCoreBridgeDB.pixelOff=nil;C.pending=nil;C.queue={}
SlashCmdList.FOREVERCORE('pixel aus')
assert(ForeverCoreBridgeDB.pixelOff==true,'pixel off set')
assert(C.Request('ping',{},nil)==false and C.Request('item',{items={}},nil)==false,'no pixel job while off')
C.tuning=nil;C.StartPixelTune(1);assert(#C.queue==0 and not C.tuning,'tuning does not start while off')
assert(C.Request('item',{items={}},nil,{export=true})==true,'the export is still accepted')
C.queue={}
SlashCmdList.FOREVERCORE('pixel an')
assert(ForeverCoreBridgeDB.pixelOff==nil,'pixel on again')
-- hovering: items without any relevant stat answer 0 % at once; with the pixel transport off nothing waits forever
UnitClass=function()return 'Hunter','HUNTER' end
items[650]={id=650,slot='head',name='Spirit Cap',minLevel=1,stats={},statsComplete=true,rawStats={RESISTANCE0_NAME=20,ITEM_MOD_STAMINA_SHORT=4}}
items[651]={id=651,slot='head',name='Agile Cap',minLevel=1,stats={},statsComplete=true,rawStats={ITEM_MOD_AGILITY_SHORT=6}}
C.simRevision=C.simRevision+1;C.queue={};C.pending=nil
local none=C.ItemResult('item:650')
assert(none and none.state=='ok' and none.pct==0 and none.status=='equal','no relevant stat answers 0 % without a job: '..tostring(none and none.state))
ForeverCoreBridgeDB.pixelOff=true
local waiting=C.ItemResult('item:651')
assert(waiting and waiting.state=='unmodeled' and tostring(waiting.reason):find('FC Berechnen',1,true),'pixel off: an honest message instead of busy: '..tostring(waiting and waiting.state))
assert(#C.queue==0,'nothing queued while pixel is off')
ForeverCoreBridgeDB.pixelOff=nil
-- right after the reload the hunter quiver is unreadable: no key, and a waiting result is applied once it is readable
local quiverState='ok'
local keepCapture=P.capture
P.capture=function()return{class='mage',level=20,faction='Horde',equipped={},spells={},talents={},hunter={quiver={status=quiverState}}}end
C.simRevision=C.simRevision+1
local ctxOk=C.SimCacheContext();assert(ctxOk,'a readable quiver gives a key')
quiverState='unreadable';C.simRevision=C.simRevision+1
assert(C.SimCacheContext()==nil,'an unreadable quiver gives no key')
local itemKey='item:201:0:0:0:0:0:0'
AH.Store().results={}
ForeverCoreBridgeDB.ahJob={json='{"replyStart":'..C.ExportSlot()..'}',session='s9',sequence=9,revision='1',context=ctxOk,sigs={'sigX'},keys={itemKey},time=(time and time())or 0}
C.pending=nil;C.queue={}
AH.Resume();local cb2=C.pending.callback;C.pending=nil
cb2({baselineDps=100,candidates={{pct=103,dps=103}}})
assert(AH.Store().results[itemKey]==nil,'nothing is applied while the quiver is unreadable')
quiverState='ok';C.simRevision=C.simRevision+1
MOCK.Advance(4,.1)
assert(AH.Store().results[itemKey] and math.abs(AH.Store().results[itemKey].pct-3)<1e-9,'applied as soon as the quiver is readable')
-- results that already sit in the item cache are taken over into the auction house list by FC Berechnen
do
 local item=items[201];local cand=C.ItemCandidate(item,itemKey)
 local _,ctx,sig=C.CachedItemComparison(item,cand,itemKey)
 C.StoreItemComparison(ctx,sig,{percent=7,delta=2,baselineDps=100,candidateDps=102})
 assert(C.CachedItemComparison(item,cand,itemKey),'stored result is found again: ctx='..tostring(ctx)..' sig='..tostring(sig))
 AH.Store().results={};ForeverCoreBridgeDB.ahJob=nil;C.pending=nil;C.queue={};AH.Remember(201,100)
 local lines2={};local sayKeep=C.Say;C.Say=function(t)lines2[#lines2+1]=tostring(t)end
 AH.Calculate();MOCK.Advance(6,.1);C.Say=sayKeep
 local r=AH.Store().results[itemKey]
 assert(r and math.abs(r.pct-7)<1e-9,'cached result is taken over: '..tostring(r and r.pct)..' | '..table.concat(lines2,' | '))
end
P.capture=keepCapture
-- /fc ah item shows what the addon reads from an item
do
 items[660]={id=660,slot='chest',name='Cloth Chest',minLevel=1,armorType='cloth',quality=2,stats={},statsComplete=true,rawStats={ITEM_MOD_AGILITY_SHORT=4,ITEM_MOD_STAMINA_SHORT=3}}
 local out={};local keepSay=C.Say;C.Say=function(t)out[#out+1]=tostring(t)end
 AH.Command('item item:660:0:0:0:0:0:0')
 C.Say=keepSay
 local text=table.concat(out,' | ')
 assert(text:find('AGILITY=4',1,true) and text:find('Cloth Chest',1,true) and text:find('relevant',1,true),'item dump shows stats and verdict: '..text)
end
-- /fc ah find scans the list that ReplicateItems delivered (mock list with two entries)
do
 local entries={{name="Disciple's Robe of Agility",id=6512,link='|cff1eff00|Hitem:6512:0:0:0:0:0:-5:111:12:::::::|h[Disciple'..string.char(39)..'s Robe of Agility]|h|r',price=50},{name='Linen Cloth',id=2589,link='|Hitem:2589|h[Linen Cloth]|h',price=5}}
 C_AuctionHouse={GetNumReplicateItems=function()return #entries end,
  GetReplicateItemInfo=function(i)local e=entries[i+1];return e.name,0,1,1,true,12,0,0,1,e.price,e.price,false,'','','','',e.id,true end,
  GetReplicateItemLink=function(i)return entries[i+1].link end}
 local out={};local keepSay=C.Say;C.Say=function(t)out[#out+1]=tostring(t)end
 AH.Command('find disciple');MOCK.Advance(.2,.05)
 C.Say=keepSay
 local text=table.concat(out,' | ')
 assert(text:find('itemID=6512',1,true) and text:find('||Hitem:6512',1,true) and text:find('1 Treffer',1,true),'find shows name, id and the raw link: '..text)
 C_AuctionHouse=nil
end
-- the scan is never locked: no fixed wait is known, so the button stays available
do
 ForeverCoreBridgeDB.ahLastScan=time();ForeverCoreBridgeDB.ahRetryUntil=time()+300
 assert(AH.ScanWait()==0,'no scan lock')
 local state={}
 AH.scanButton={Disable=function()state.disabled=true end,Enable=function()state.disabled=false end,SetText=function(_,x)state.text=x end}
 AH.RefreshScanButton()
 assert(state.disabled==false and state.text=='Scannen','the button is always free')
 AH.scanButton=nil
end
-- every scan attempt is logged; /fc ah scans prints the history
do
 ForeverCoreBridgeDB.ahScanLog=nil
 AH.LogScan('ok','58000 eintraege');AH.LogScan('keine antwort','listeneintraege=0')
 local out={};local keepSay=C.Say;C.Say=function(t)out[#out+1]=tostring(t)end
 AH.Command('scans')
 C.Say=keepSay
 assert(#out==2 and out[1]:find('ok',1,true) and out[2]:find('keine antwort',1,true),'history lines: '..table.concat(out,' | '))
 ForeverCoreBridgeDB.ahScanLog=nil
end
-- the Forever client marks "of Agility" variants with bonus ids: they must stay part of the key
do
 local variant='|cnIQ2:|Hitem:6512::::::::12:1485:::1:12728::::::|h[Disciple'..string.char(39)..'s Robe of Agility]|h|r'
 local base='|cnIQ1:|Hitem:6512::::::::12:1485:::::::|h[Disciple'..string.char(39)..'s Robe]|h|r'
 assert(C.NormalizeLink(variant)=='item:6512:0:0:0:0:0:0:0:12:0:0:0:1:12728','bonus ids are kept: '..C.NormalizeLink(variant))
 assert(C.NormalizeLink(base)=='item:6512:0:0:0:0:0:0','the base item stays a short key: '..C.NormalizeLink(base))
 assert(C.NormalizeLink(variant)~=C.NormalizeLink(base),'variant and base item are different candidates')
 local other='|cnIQ2:|Hitem:6512::::::::12:1500:::1:12728::::::|h[x]|h|r'
 assert(C.NormalizeLink(other)==C.NormalizeLink(variant),'viewer specific fields (spec) do not change the key')
end
-- candidates of variants (bonus ids / random suffix) are flagged so that the PC does not use its base item record
do
 local variantLink='|cnIQ2:|Hitem:660::::::::12:1485:::1:12728::::::|h[Cloth Chest of Agility]|h|r'
 local c=C.ItemCandidate(items[660],variantLink)
 assert(c.variant==true and c.variantKey=='item:660:0:0:0:0:0:0:0:12:0:0:0:1:12728','variant flagged: '..tostring(c.variantKey))
 local plain=C.ItemCandidate(items[660],'|cnIQ1:|Hitem:660::::::::12:1485:::::::|h[Cloth Chest]|h|r')
 assert(not plain.variant and plain.variantKey==nil,'a plain item is not a variant')
 local suffix=C.ItemCandidate(items[660],'|Hitem:660:0:0:0:0:0:-5:111:12|h[x]|h')
 assert(suffix.variant==true,'a random suffix makes a variant too')
end
-- the scan button says whether a scan is expected to be answered: not after /reload
do
 local state={}
 AH.scanButton={Disable=function()end,Enable=function()end,SetText=function(_,t)state.text=t end}
 MOCK.Fire('PLAYER_ENTERING_WORLD',true,false);AH.scannedThisSession=false;AH.RefreshScanButton()
 assert(state.text=='Scannen','fresh login: plain label')
 AH.scannedThisSession=true;AH.RefreshScanButton()
 assert(state.text=='Gescannt','after a scan in this session')
 MOCK.Fire('PLAYER_ENTERING_WORLD',false,true);AH.RefreshScanButton()
 assert(state.text=='Scan (Neustart)','after a reload the label asks for a restart')
 AH.scanButton=nil;AH.reloaded=false;AH.scannedThisSession=false
end
-- /fc ah worn explains what is read from worn weapons
do
 items[131]={id=131,slot='mainhand',name='Stone Tomahawk',minLevel=1,stats={},statsComplete=false,itemClass=2,weaponClass=2,itemSubclass=0,weaponSubclass=0}
 local keepInv=GetInventoryItemLink
 GetInventoryItemLink=function(unit,slot)if slot==16 then return 'item:131' end end
 local out={};local keepSay=C.Say;C.Say=function(t)out[#out+1]=tostring(t)end
 AH.Command('worn')
 C.Say=keepSay;GetInventoryItemLink=keepInv
 local text=table.concat(out,' | ')
 assert(text:find('Slot 16 Stone Tomahawk',1,true) and text:find('FEHLEN',1,true) and text:find('vollstaendig=false',1,true),'worn weapon report: '..text)
end
-- characters that cannot be calculated get a clear reason instead of a Lua error
do
 local keepLevel,keepClass,keepLive,keepData=UnitLevel,UnitClass,FUSLive,FUSLiveData
 UnitClass=function()return 'Shaman','SHAMAN' end
 UnitLevel=function()return 4 end
 assert(tostring(AH.CannotCalculate()):find('Stufe 5',1,true),'level 4: MythicSim starts at level 5')
 UnitLevel=function()return 7 end
 assert(AH.CannotCalculate()==nil or not tostring(AH.CannotCalculate()):find('Stufe',1,true),'level 7 is calculated (approximated)')
 UnitLevel=function()return 20 end
 FUSLive=nil
 assert(tostring(AH.CannotCalculate()):find('ForeverSimBridge',1,true),'no ForeverSimBridge for this character')
 -- the item reader is missing: no Lua error, no verdict
 C.simRevision=C.simRevision+1
 assert(C.ItemResult('item:201')==nil,'without ForeverSimBridge an item cannot be read: nil, no error')
 local said={};local keepSay=C.Say;C.Say=function(t)said[#said+1]=tostring(t)end
 assert(AH.Calculate()==false and said[#said]:find('ForeverSimBridge',1,true),'FC Berechnen explains instead of failing: '..tostring(said[#said]))
 FUSLive=keepLive
 FUSLiveData={}
 assert(tostring(AH.CannotCalculate()):find('Klassendaten',1,true),'no class data')
 FUSLiveData=keepData;C.Say=keepSay;UnitLevel,UnitClass=keepLevel,keepClass
 assert(AH.CannotCalculate()==nil or true,'restored')
end
-- the reasons why items could not be computed are counted and printed
do
 local keepCapture=P.capture
 P.capture=function()local snap=keepCapture();snap.hunter={quiver={status='ok'}};return snap end
 C.simRevision=C.simRevision+1
 local ctx=C.SimCacheContext();assert(ctx,'context for the reasons test')
 local k1,k2,k3='item:501:0:0:0:0:0:0','item:502:0:0:0:0:0:0','item:503:0:0:0:0:0:0'
 ForeverCoreBridgeDB.ahJob={json='{"replyStart":'..C.ExportSlot()..'}',session='s7',sequence=7,revision='1',context=ctx,sigs={'a','b','c'},keys={k1,k2,k3},time=(time and time())or 0}
 C.pending=nil;C.queue={}
 AH.Resume();local cbR=C.pending.callback;C.pending=nil
 local out={};local keepSay=C.Say;C.Say=function(t)out[#out+1]=tostring(t)end
 cbR({baselineDps=100,candidates={{error='Item 501: Basis-Waffenschaden fehlt',pct=0,dps=0},{error='Item 502: Basis-Waffenschaden fehlt',pct=0,dps=0},{error='Item 503: vollstaendige Basiswerte fehlen',pct=0,dps=0}}})
 C.Say=keepSay;P.capture=keepCapture
 local t=table.concat(out,' | ')
 assert(t:find('3 nicht berechenbar',1,true),'failed count: '..t)
 assert(t:find('nicht berechenbar (2): Basis-Waffenschaden fehlt',1,true),'the most common reason is counted without item ids: '..t)
end
-- /fc ah top: the best upgrade for every slot, variants of one base item counted as one
do
 local locs={[701]='INVTYPE_2HWEAPON',[702]='INVTYPE_CHEST',[703]='INVTYPE_FINGER',[704]='INVTYPE_FINGER',[705]='INVTYPE_FINGER'}
 local keepInstant=C_Item.GetItemInstant
 local savedInstant=C_Item.GetItemInfoInstant
 C_Item.GetItemInfoInstant=function(id)return id,'x','y',locs[id]or 'INVTYPE_HEAD' end
 local savedInfo=C_Item.GetItemInfo
 C_Item.GetItemInfo=function(k)local id=tostring(k):match('item:(%d+)');return 'Name '..tostring(id),'[Name '..tostring(id)..']' end
 AH.Store().results={
  ['item:701:0:0:0:0:0:-1:11']={pct=5,delta=1},['item:701:0:0:0:0:0:-2:12']={pct=9,delta=2},
  ['item:702:0:0:0:0:0:0']={pct=3,delta=.5},
  ['item:703:0:0:0:0:0:0']={pct=7,delta=1.5},['item:704:0:0:0:0:0:0']={pct=6,delta=1.2},['item:705:0:0:0:0:0:0']={pct=2,delta=.4},
  ['item:706:0:0:0:0:0:0']={pct=-1,delta=-.2}}
 local out={};local keepSay=C.Say;C.Say=function(t)out[#out+1]=tostring(t)end
 AH.Top()
 C.Say=keepSay
 local t=table.concat(out,' | ')
 assert(t:find('Waffe (zweihaendig)',1,true) and t:find('+9.00',1,true) and not t:find('+5.00',1,true),'the best variant of the staff only: '..t)
 assert(t:find('(+1 weitere Varianten)',1,true),'other variants are counted: '..t)
 assert(t:find('Brust',1,true) and t:find('+3.00',1,true),'chest slot present: '..t)
 assert(t:find('+7.00',1,true) and t:find('+6.00',1,true) and not t:find('+2.00',1,true),'rings show the best two: '..t)
 assert(not t:find('-1.00',1,true),'downgrades are not listed')
 C_Item.GetItemInfoInstant=savedInstant;C_Item.GetItemInfo=savedInfo
end
-- enchants never count: the key and the item read ignore them, older enchanted entries are merged once
do
 assert(C.NormalizeLink('item:10518:1887:0:0:0:0:0')=='item:10518:0:0:0:0:0:0','the key has no enchant')
 local link='|cnIQ2:|Hitem:10518:1887::::::::12:1485:::::::::|h[Parachute Cloak]|h|r'
 local plain=C.WithoutEnchant(link)
 assert(plain:find('Hitem:10518::',1,true) and plain:find(':12:1485:',1,true),'only the enchant field is emptied: '..plain)
 local readWith
 local keepRead=P.readItem
 P.readItem=function(l)readWith=l;return{id=10518,slot='back',name='Parachute Cloak',minLevel=1,stats={},rawStats={ITEM_MOD_AGILITY_SHORT=8},statsComplete=true}end
 C.collectOnly={}
 C.ItemResult(link)
 local rec=C.collectOnly[1];C.collectOnly=nil
 assert(readWith and not readWith:find(':1887:',1,true),'the item is read without the enchant: '..tostring(readWith))
 assert(rec and not tostring(rec.candidate.link):find('1887',1,true),'the candidate goes to the PC without the enchant: '..tostring(rec and rec.candidate.link))
 assert(rec.link==link,'the result is stored under the link that was asked for')
 P.readItem=keepRead
 -- an older list with an enchanted and a plain entry of the same item
 local s=AH.Store()
 s.items={['item:500:1887:0:0:0:0:0']=200,['item:500:0:0:0:0:0:0']=300,['item:501:0:0:0:0:0:0']=10}
 s.results={['item:500:1887:0:0:0:0:0']={pct=9,delta=1}}
 s.count=3;s.plainKeys=nil
 s=AH.Store()
 assert(s.items['item:500:1887:0:0:0:0:0']==nil and s.items['item:500:0:0:0:0:0:0']==200 and s.count==2,'merged into the plain item with the lower price')
 assert(s.results['item:500:1887:0:0:0:0:0']==nil,'the result with the enchant is dropped')
end
io.write('auction export tests passed\n')
