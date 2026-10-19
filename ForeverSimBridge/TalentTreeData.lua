-- Legacy readers use this view. Source of truth: Classes/<class>.lua.
local P=_G.FUSLive
if not P then return end
P.talentTreeLayouts={}
for class,data in pairs(FUSLiveData or {}) do
 if type(data)=="table" and type(data.talentTrees)=="table" then
  P.talentTreeLayouts[class]=data.talentTrees
 end
end
P.talentTreeLayoutBuild="1.60.1.70338 / canonical class module tree schema 2"
