-- Profession and class requirements: an item that needs a profession the player lacks (or another class) is blocked.
local root=assert(arg[1]);dofile(root..'/_dev/harness/wowmock.lua');dofile(root..'/_dev/harness/gameapi.lua')
local function loadAddon(addon)
 for line in io.lines(root..'/'..addon..'/'..addon..'.toc')do
  local file=line:gsub(string.char(13),''):gsub(string.char(92),'/'):match('^%s*([^#].-%.lua)%s*$')
  if file then assert(loadfile(root..'/'..addon..'/'..file))(addon,{})end
 end
end
loadAddon('ForeverSimBridge');loadAddon('ForeverCoreBridge')
MOCK.Fire('PLAYER_LOGIN');MOCK.Advance(.5,.05)
local C=ForeverCoreClient;local P=FUSLive
C.engineRevision='rev-test'
C.Say=function()end
-- the game's own text templates, as in any client language
ITEM_MIN_SKILL='Requires %s (%d)';ITEM_CLASSES_ALLOWED='Classes: %s'
MOCK.items[7001]={name='Spellpower Goggles Xtreme',quality=2,ilvl=20,req=1,class='Armor',sub='Cloth',loc='INVTYPE_HEAD',classID=4,subID=1,stats={ITEM_MOD_INTELLECT_SHORT=6},
 tooltip={{'Spellpower Goggles Xtreme'},{'Head','Cloth'},{'Requires Engineering (215)'}}}
MOCK.items[7002]={name='Warrior Helm',quality=2,ilvl=20,req=1,class='Armor',sub='Cloth',loc='INVTYPE_HEAD',classID=4,subID=1,stats={ITEM_MOD_INTELLECT_SHORT=6},
 tooltip={{'Warrior Helm'},{'Head','Cloth'},{'Classes: Warrior, Paladin'}}}
MOCK.items[7003]={name='Plain Hat',quality=2,ilvl=20,req=1,class='Armor',sub='Cloth',loc='INVTYPE_HEAD',classID=4,subID=1,stats={ITEM_MOD_INTELLECT_SHORT=6},
 tooltip={{'Plain Hat'},{'Head','Cloth'}}}
local a=P.readItem('item:7001','Test')
assert(a and a.requiresSkill and a.requiresSkill.name=='Engineering' and a.requiresSkill.rank==215,'profession requirement read from the tooltip')
local b=P.readItem('item:7002','Test')
assert(b and b.allowedClasses and b.allowedClasses[1]=='Warrior' and b.allowedClasses[2]=='Paladin','class restriction read')
assert(P.readItem('item:7003','Test').requiresSkill==nil,'a plain item has no requirement')
-- the player: a shaman without engineering
UnitClass=function()return 'Shaman','SHAMAN' end
local skills={{'Mining',false,150},{'Skinning',false,100}}
GetNumSkillLines=function()return #skills end
GetSkillLineInfo=function(i)local s=skills[i];return s[1],s[2],true,s[3]end
assert(C.RequirementVerdict(a):find('Engineering',1,true),'no engineering: blocked')
skills[#skills+1]={'Engineering',false,100}
assert(C.RequirementVerdict(a):find('hast 100',1,true),'engineering 100 is too low for 215')
assert(C.RequirementVerdict(a,true)==nil,'a dungeon preview does not need the rank, only the profession')
skills[#skills].rank=nil;skills[#skills]={'Engineering',false,225}
assert(C.RequirementVerdict(a)==nil,'engineering 225: usable')
assert(tostring(C.RequirementVerdict(b)):find('andere Klassen',1,true),'a shaman cannot use a warrior item')
UnitClass=function()return 'Warrior','WARRIOR' end
assert(C.RequirementVerdict(b)==nil,'the warrior can')
-- without the skill API nothing is blocked (unknown is not "missing")
GetNumSkillLines=nil;GetProfessions=nil
UnitClass=function()return 'Shaman','SHAMAN' end
skills={}
assert(C.RequirementVerdict(a)==nil,'no skill API: no verdict')
-- an older cached result does not make a blocked item look usable
GetNumSkillLines=function()return #skills end
C.simRevision=C.simRevision+1
local e=C.ItemResult('item:7001')
assert(e and e.state=='blocked' and tostring(e.reason):find('Engineering',1,true),'ItemResult blocks before the cache: '..tostring(e and e.state))
-- race restriction
UnitRace=function()return 'Dwarf','Dwarf' end
assert(C.RequirementVerdict({allowedRaces={'Tauren','Orc'}})~=nil,'a Tauren item is blocked for a dwarf')
assert(C.RequirementVerdict({allowedRaces={'Dwarf','Human'}})==nil,'a dwarf item is fine')
-- weapon skills the class can learn are NOT filtered: the player learns them at the weapon master
GetItemSubClassInfo=function(c,s)return ({[15]='Daggers',[4]='One-Handed Maces'})[s]end
skills={{'Mining',false,150},{'One-Handed Maces',false,5}}
assert(C.RequirementVerdict({weaponClass=2,weaponSubclass=15})==nil,'an unlearned but learnable weapon stays in')
-- clients without the skill list: professions via GetProfessions
GetNumSkillLines=nil;GetSkillLineInfo=nil
local profs={'Mining'}
GetProfessions=function()return 1 end
GetProfessionInfo=function(i)return profs[i],'icon',150 end
assert(select(2,C.PlayerSkill('Engineering'))==true and C.PlayerSkill('Engineering')==nil,'profession list: not learned')
assert(C.PlayerSkill('Mining')==150,'profession list: rank')
assert(tostring(C.RequirementVerdict({requiresSkill={name='Engineering',rank=215}})):find('Engineering',1,true),'blocked through GetProfessions')
-- a result stored before the requirement was known (auction house list): the list leaves it out, the next item moves up
do
 local AH=C.AH
 C_Item=C_Item or{}
 C_Item.GetItemInfoInstant=function(id)return tonumber(tostring(id):match('(%d+)')),'Armor','Cloth','INVTYPE_HEAD','icon',4,1 end
 local s=AH.Store()
 s.results['item:7001']={pct=10,delta=1.2};s.results['item:7003']={pct=3,delta=0.4}
 s.items['item:7001']=100;s.items['item:7003']=50
 local rows,total=AH.TopRows(1)
 assert(#rows==1 and rows[1].key=='item:7003','the goggles (engineering) are not shown, the plain hat is: '..tostring(rows[1] and rows[1].key))
 assert(s.results['item:7001']==nil and total==1,'the stale result is removed')
end
-- rings: a best ring that is not unique is shown once as "2x" instead of a second, weaker ring
do
 local AH=C.AH
 ITEM_UNIQUE='Unique';ITEM_UNIQUE_EQUIPPABLE='Unique-Equipped';ITEM_UNIQUE_MULTIPLE='Unique (%d)'
 local function ring(id,name,extra)
  local tip={{name},{'Finger'}};if extra then tip[#tip+1]={extra}end
  MOCK.items[id]={name=name,quality=2,ilvl=20,req=1,class='Armor',sub='Miscellaneous',loc='INVTYPE_FINGER',classID=4,subID=0,stats={ITEM_MOD_INTELLECT_SHORT=4},tooltip=tip}
 end
 ring(7101,'Plain Ring');ring(7102,'Unique Ring','Unique');ring(7103,'Pair Ring','Unique (2)');ring(7104,'Equip Ring','Unique-Equipped')
 assert(not P.readItem('item:7101','Test').unique,'a plain ring is not unique')
 assert(P.readItem('item:7102','Test').unique==true,'"Unique" is read')
 assert(not P.readItem('item:7103','Test').unique,'"Unique (2)" allows two')
 assert(P.readItem('item:7104','Test').uniqueEquip==true,'"Unique-Equipped" is read')
 C_Item.GetItemInfoInstant=function(id)return tonumber(tostring(id):match('(%d+)')),'Armor','Misc','INVTYPE_FINGER','icon',4,0 end
 local s=AH.Store()
 s.results={['item:7101']={pct=8,delta=1},['item:7102']={pct=6,delta=.8},['item:7103']={pct=2,delta=.2}}
 s.items={['item:7101']=100,['item:7102']=90,['item:7103']=80};s.qty=nil
 local rows=AH.TopRows(1)
 assert(#rows==1 and rows[1].key=='item:7101' and rows[1].twice==true,'best ring not unique: shown once as 2x ('..#rows..' rows)')
 s.qty={['item:7101']=1}
 rows=AH.TopRows(1)
 assert(#rows==2 and rows[1].key=='item:7101' and not rows[1].twice and rows[2].key=='item:7102','only one offer: the second ring is a different one')
 s.qty={['item:7101']=3}
 s.results['item:7102']={pct=9,delta=1.2}
 rows=AH.TopRows(1)
 assert(#rows==2 and rows[1].key=='item:7102' and not rows[1].twice and rows[2].key=='item:7101' and rows[2].twice==nil,'a unique best ring: two different rings')
 local out={};local keep=C.Say;C.Say=function(t)out[#out+1]=tostring(t)end
 s.results['item:7102']=nil;AH.Top(1,true,true);C.Say=keep
 assert(table.concat(out,' | '):find('2x tragen',1,true),'the list says that it can be worn twice: '..table.concat(out,' | '))
end
io.write('requirements tests passed\n')
