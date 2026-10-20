-- Build every page with a fresh client of the given class and level.
local root=assert(arg[1]);local class=arg[2]or'MAGE';local level=tonumber(arg[3])or 60
dofile(root..'/_dev/harness/wowmock.lua');dofile(root..'/_dev/harness/gameapi.lua')
UnitClass=function()return class,class end;UnitLevel=function()return level end
for _,addon in ipairs({'ForeverSimBridge','ForeverCoreBridge'})do
 for line in io.lines(root..'/'..addon..'/'..addon..'.toc')do
  local file=line:gsub(string.char(13),''):gsub(string.char(92),'/'):match('^%s*([^#].-%.lua)%s*$')
  if file then assert(loadfile(root..'/'..addon..'/'..file))(addon,{})end
 end
end
MOCK.Fire('PLAYER_LOGIN');MOCK.Advance(.5,.05)
local UI=ForeverSimUI;UI.Window()
for _,tab in ipairs(UI.Tabs())do
 UI.Open(tab.key);MOCK.Advance(.1,.05)
 for _,r in ipairs(tab.frame.__regions or{})do
  if r.GetText then assert(not tostring(r:GetText()):find('konnte nicht aufgebaut werden',1,true),class..' '..level..' '..tab.key..': '..tostring(r:GetText()))end
 end
end
assert(#MOCK.errors==0,MOCK.errors[1]and MOCK.errors[1].msg or'')
for method in pairs(MOCK.unknownMethods)do error('unknown widget method '..method)end
io.write(class..' '..level..' UI passed\n')
