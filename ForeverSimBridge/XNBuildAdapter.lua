-- XN build import adapter; stores original talent/rotation metadata without reusing XN's DPS calculations.
FUSLive = FUSLive or {}
FUSLive.XNPresets = FUSLive.XNPresets or {}
local A = FUSLive.XNPresets
local function cp(t) if type(t)~='table' then return t end local o={} for k,v in pairs(t)do o[k]=cp(v)end return o end
function A.list()
 local result={} for _,b in ipairs(FUSXNBuildPresets or {})do result[#result+1]={key=b.key,name=b.name,pet=b.pet,sacrifice=b.sacrifice,rotation=cp(b.rotation),limitations=cp(b.limitations)}end
 return result
end
function A.get(key)
 for _,b in ipairs(FUSXNBuildPresets or {})do if b.key==key then return cp(b)end end
 return nil,'XN build not found: '..tostring(key)
end
function A.apply(key,playerProfile)
 local b,err=A.get(key) if not b then return nil,nil,err end
 local p=cp(playerProfile or {})
 p.class='warlock';p.talents={{entries={}}}
 for talent,rank in pairs(b.talents)do p.talents[1].entries[#p.talents[1].entries+1]={classKey=talent,name=talent,rank=rank}end
 p.petActive=b.pet~=nil;p.pet=b.pet and {type=b.pet,level=p.level or 60} or nil
 p.sacrifice=b.sacrifice;p.oil=nil -- Solo: original XN weapon stones/oils are excluded
 local choice={ranks=cp(b.xnRanks),policies=cp(b.policies),tapAtPct=(b.params.lifeTapBelow or {}).pct and (b.params.lifeTapBelow.pct/100) or 0.3,channelClip=(b.key=='wrack_succubus')}
 -- The Lua priority actions are approximations. To reproduce XN exactly, the condition evaluator must be extended.
 return p,choice,cp(b.limitations)
end

-- Only for explicit XN-solo benchmark selections. Does not override /fus optimize,
-- which must still consider the real character's spellbook, items and level.
function A.getOptimizedSoloChoice(key)
 local found=FUSXNOptimizedSolo and FUSXNOptimizedSolo[key]
 if not found then return nil,'No solo rotation optimizer result for '..tostring(key) end
 return cp(found.choice),cp(found)
end
