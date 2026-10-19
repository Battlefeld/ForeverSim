ForeverCoreClient=ForeverCoreClient or{}
local C=ForeverCoreClient
-- 2,048 bits as a narrow 512 x 4 strip. Each cell targets 2 desktop pixels.
C.protocol={columns=512,rows=4,cell=2,bytes=256,header=18,payload=238,slots=2048}
local function public(v)
 if type(issecretvalue)=='function'then local ok,s=pcall(issecretvalue,v);if not ok or s then return false end end
 if type(canaccessvalue)=='function'then local ok,a=pcall(canaccessvalue,v);if not ok or not a then return false end end
 return true
end
C.public=public
function C.clean(v,depth,seen)
 depth=depth or 0;seen=seen or{};if depth>20 or not public(v)then return nil end
 local kind=type(v)
 if kind=='number'then if v~=v or v==math.huge or v==-math.huge then return nil end;return v end
 if kind=='string'or kind=='boolean'then return v end
 if kind~='table'or seen[v]then return nil end
 seen[v]=true;local out={};for k,x in pairs(v)do if public(k)and(type(k)=='string'or type(k)=='number')then local value=C.clean(x,depth+1,seen);if value~=nil then out[k]=value end end end;seen[v]=nil;return out
end
local function quote(s)return '"'..s:gsub('[%z\1-\31\\"]',function(c)if c=='\\'or c=='"'then return '\\'..c end;return string.format('\\u%04x',c:byte())end)..'"'end
function C.json(v)
 local kind=type(v);if kind=='nil'then return 'null'end
 if kind=='boolean'or kind=='number'then return tostring(v)end
 if kind=='string'then return quote(v)end
 if kind~='table'then return 'null'end
 local n=#v;local count=0;local arr=n>0;for k in pairs(v)do count=count+1;if type(k)~='number'or k<1 or k>n then arr=false end end;if count~=n then arr=false end
 local out={};if arr then for i=1,n do out[#out+1]=C.json(v[i])end
 else local keys={};for k in pairs(v)do keys[#keys+1]=k end;table.sort(keys,function(a,b)return tostring(a)<tostring(b)end);for _,k in ipairs(keys)do out[#out+1]=quote(tostring(k))..':'..C.json(v[k])end end
 return(arr and '['or'{')..table.concat(out,',')..(arr and ']'or'}')
end
-- IEEE CRC32 without a bit-library dependency; lookup table built once.
local function xor(a,b)local r,p=0,1;for _=1,32 do local x,y=a%2,b%2;if x~=y then r=r+p end;a=math.floor(a/2);b=math.floor(b/2);p=p*2 end;return r end
local crcTable={}
for i=0,255 do local c=i;for _=1,8 do if c%2==1 then c=xor(math.floor(c/2),3988292384)else c=math.floor(c/2)end end;crcTable[i]=c end
function C.crc(s)local c=4294967295;for i=1,#s do c=xor(math.floor(c/256),crcTable[xor(c,s:byte(i))%256])end;return xor(c,4294967295)end
local function u16(n)return string.char(math.floor(n/256)%256,n%256)end
local function u32(n)return u16(math.floor(n/65536))..u16(n%65536)end
function C.frame(id,index,total,payload)
 local header='FC3'..string.char(3)..u32(id)..u16(index)..u16(total)..u16(#payload)
 local message=header..u32(C.crc(header..payload))..payload
 return message..string.rep('\0',256-#message)
end
