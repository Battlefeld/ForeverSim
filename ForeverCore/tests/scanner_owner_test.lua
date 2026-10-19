-- Tooltip scanners must be re-owned before every use: the second and third item read through the same scanner
-- must not come back empty. The mock behaves like the real client: without SetOwner a used tooltip stays empty.
local root=assert(arg[1]);dofile(root..'/_dev/harness/wowmock.lua');dofile(root..'/_dev/harness/gameapi.lua')
local owned={}
local origSetOwner=MOCK and nil
for line in io.lines(root..'/ForeverSimBridge/ForeverSimBridge.toc')do
 local file=line:gsub(string.char(13),''):gsub(string.char(92),'/'):match('^%s*([^#].-%.lua)%s*$')
 if file then assert(loadfile(root..'/ForeverSimBridge/'..file))('ForeverSimBridge',{})end
end
MOCK.Fire('PLAYER_LOGIN');MOCK.Advance(.5,.05)
-- a stricter tooltip: after a hyperlink was shown it only works again after SetOwner (like the real client)
local realCreate=CreateFrame
CreateFrame=function(kind,name,...)
 local frame=realCreate(kind,name,...)
 if kind=='GameTooltip' then
  local used=false
  local setOwner,setHyper=frame.SetOwner,frame.SetHyperlink
  rawset(frame,'SetOwner',function(self,...)used=false;return setOwner(self,...)end)
  rawset(frame,'SetHyperlink',function(self,link)
   if used then self.__lines={};return end -- not re-owned: stays empty
   used=true;return setHyper(self,link)
  end)
 end
 return frame
end
MOCK.items[2001]={name='First Axe',quality=1,ilvl=1,req=0,class='Weapon',sub='One-Handed Axes',loc='INVTYPE_WEAPONMAINHAND',classID=2,subID=0,stats={},
 tooltip={{'First Axe'},{'Main Hand','Axe'},{'3 - 6 Damage','Speed 2.10'},{'(2.1 damage per second)'}}}
MOCK.items[2002]={name='Second Gun',quality=1,ilvl=1,req=0,class='Weapon',sub='Guns',loc='INVTYPE_RANGEDRIGHT',classID=2,subID=3,stats={},
 tooltip={{'Second Gun'},{'Ranged','Gun'},{'7 - 14 Damage','Speed 2.10'},{'(5.0 damage per second)'}}}
local a=FUSLive.readItem('item:2001','Test')
local b=FUSLive.readItem('item:2002','Test')
assert(a and a.weapon and a.weapon.max==6,'first weapon is read')
assert(b and b.weapon and b.weapon.max==14,'the second weapon is read too (the scanner is re-owned)')
local c=FUSLive.readItem('item:2001','Test')
assert(c and c.weapon and c.weapon.max==6,'and the same weapon again')
io.write('scanner owner tests passed\n')
