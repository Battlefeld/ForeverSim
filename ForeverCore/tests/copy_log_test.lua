-- Copyable log: every status message is kept; identical neighbours are counted; /fc log clear empties it.
local root=assert(arg[1]);dofile(root..'/_dev/harness/wowmock.lua');dofile(root..'/_dev/harness/gameapi.lua')
local function loadAddon(addon)
 for line in io.lines(root..'/'..addon..'/'..addon..'.toc')do
  local file=line:gsub(string.char(13),''):gsub(string.char(92),'/'):match('^%s*([^#].-%.lua)%s*$')
  if file then assert(loadfile(root..'/'..addon..'/'..file))(addon,{})end
 end
end
loadAddon('ForeverSimBridge');loadAddon('ForeverCoreBridge')
MOCK.Fire('PLAYER_LOGIN');MOCK.Advance(.5,.05)
local C=ForeverCoreClient
for i=#C.logLines,1,-1 do C.logLines[i]=nil end
C.Say('Erste Meldung');C.Say('Zweite Meldung');C.Say('Zweite Meldung');C.Say('|cff00ff00Farbig|r')
local text=C.LogText()
assert(text:find('Erste Meldung',1,true) and text:find('(x2)',1,true),'messages kept, duplicates counted: '..text)
assert(text:find('Farbig',1,true) and not text:find('|cff',1,true),'colour codes removed for copying')
assert(select(2,text:gsub(string.char(10),''))==2,'one line per message')
SlashCmdList.FOREVERCORE('log clear')
assert(C.LogText()=='','log cleared')
for i=1,500 do C.Say('Zeile '..i)end
assert(#C.logLines<=400,'log is bounded')
io.write('copy log tests passed\n')
