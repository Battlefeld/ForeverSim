-- Explicit comparisons in the VZ/Food view. Does not modify the item/rotation caches.
local C=ForeverCoreClient
local E={running=false};C.Enhancements=E
function E.CaptureEnchants()
 local out={}
 for _,slot in ipairs(C.Loot.SLOTS)do
  local ok,link=pcall(function()return GetInventoryItemLink and GetInventoryItemLink('player',slot.inv)end)
  if ok and C.public(link)and type(link)=='string'then out[slot.key]=tonumber(link:match('item:%-?%d+:(%d*)'))or 0 end
 end
 return out
end
function E.Context()
 local bits={tostring(C.SimCacheContext and C.SimCacheContext()or C.Sim.Context())}
 local ench=E.CaptureEnchants()
 for _,slot in ipairs(C.Loot.SLOTS)do bits[#bits+1]=slot.key..':'..tostring(ench[slot.key]or'-')end
 return table.concat(bits,'|')
end
function E.Result()
 local r=C.Sim.Store().enhancements
 return r,r and r.context~=E.Context()
end
function E.Run(cb)
 if E.running or not C.Sim.Available('loot')then return false end
 local ctx=E.Context();E.running=true;E.issue=nil;C.Sim.Changed()
 local handled=false
 local function done(result,issue)
  if handled then return end;handled=true;E.running=false
  if type(result)=='table'and type(result.recommendations)=='table'and tonumber(result.baselineDps)then
   result.context=ctx;C.Sim.Store().enhancements=C.clean(result)
  else E.issue=issue or'Kein VZ-/Food-Ergebnis'end
  C.Sim.Changed();if cb then cb(result,E.issue)end
 end
 local ok=C.Request('enhancements',{iterations=500},done,{timeout=1200})
 if not ok then done(nil,'VZ-/Food-Anfrage nicht möglich')end
 return ok
end
