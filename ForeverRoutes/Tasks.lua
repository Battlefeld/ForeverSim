-- Data-driven HUD tasks. No guessed shopping lists or automatic route rewrites.
local FR=ForeverRoutes
local call=FR.Call
function FR.Config()
 ForeverRoutesDB=ForeverRoutesDB or{}
 return ForeverRoutesDB
end
function FR.ItemCount(id)
 local fn=C_Item and C_Item.GetItemCount or GetItemCount
 return tonumber(call(fn,id,false,false))or 0 -- bags/equipment, never inaccessible bank stock
end
function FR.Items(step)
 local rows={}
 for _,v in ipairs(step and step.items or{})do
  if type(v.id)=='number'and type(v.count)=='number'and v.count>0 then
   local name,link,_,_,_,_,_,_,_,icon=call(GetItemInfo,v.id)
   if not name and C_Item and C_Item.RequestLoadItemDataByID then call(C_Item.RequestLoadItemDataByID,v.id)end
   local owned=FR.ItemCount(v.id)
   rows[#rows+1]={id=v.id,text=string.format('%s %d/%d',name or v.name or('Gegenstand '..v.id),owned,v.count),icon=icon,link=link,done=owned>=v.count}
  end
 end
 return rows
end
local done=FR.Done
function FR.Done(step)
 if not step then return true end
 if step.op=='collect'or step.op=='buy'then
  local rows=FR.Items(step);if #rows==0 then return false end
  for _,v in ipairs(rows)do if not v.done then return false end end
  return true
 end
 if step.op=='travel'then
  local x,y,_,m=call(UnitPosition,'player')
  return type(x)=='number'and type(y)=='number'and m==step.m and type(step.x)=='number'and type(step.y)=='number'and
   (x-step.x)^2+(y-step.y)^2<=(step.radius or 12)^2
 end
 if step.op=='train'then return step.spell and(call(IsPlayerSpell,step.spell)==true or call(IsSpellKnown,step.spell)==true)or false end
 return done(step)
end
local text=FR.Text
function FR.Text(step)
 if not step then return text(step)end
 if step.text then return step.text end
 if step.op=='buy'then return'Beim Händler Vorräte besorgen'end
 if step.op=='collect'then return'Benötigte Gegenstände sammeln'end
 if step.op=='travel'then return step.n or'Zum nächsten Ziel laufen'end
 if step.op=='train'then return step.n or'Beim Lehrer lernen'end
 if step.op=='note'then return step.n or'Hinweis beachten'end
 return text(step)
end
local confirm=FR.CanConfirm
function FR.CanConfirm(st)return not FR.Paused(st)and((st and st.op=='note')or confirm(st))end
function FR.Meta(q)return ForeverRoutesData and ForeverRoutesData.quests and ForeverRoutesData.quests[q]end
function FR.Blocked(step)
 if not step then return nil end
 local q=FR.Meta(step.q)
 if step.op=='a'and q then
  if q.min and(call(UnitLevel,'player')or 0)<q.min then return'Quest erst ab Stufe '..q.min..' verfügbar'end
  for _,id in ipairs(q.preAll or{})do if not FR.Completed(id)then return'Vorquest offen: '..(FR.Meta(id)and FR.Meta(id).name or tostring(id))end end
  if q.preAny and #q.preAny>0 then
   local ok=false;for _,id in ipairs(q.preAny)do ok=ok or FR.Completed(id)end
   if not ok then return'Eine alternative Vorquest ist noch offen'end
  end
 end
 if(step.op=='w'or step.op=='t')and not FR.OnQuest(step.q)and not FR.Completed(step.q)then return'Quest ist nicht im Log. Annahme prüfen oder übersprungenen Schritt wiederherstellen.'end
 return nil
end
function FR.TaskView()
 local step,index=FR.Advance();local steps,live=FR.Steps();local r,key,kind=FR.Route()
 local view={step=step,index=index,total=#steps,live=live,route=r,key=key,kind=kind,items=FR.Items(step),parallel={},paused=FR.Paused(step)}
 view.text=step and FR.Text(step)or((live or(r and r.s))and'Route geschafft'or'Keine Route verfügbar')
 view.hint=step and(FR.Blocked(step)or FR.Hint(step))
 -- Persistent side tasks are authored data, never every future quest forced into the log.
 for _,t in ipairs(r and r.tasks or{})do
  local after=t.after or 0;local untilStep=t.untilStep or math.huge
  if index>after and index<=untilStep and not FR.Done(t)and not(FR.CharDB().hiddenTasks or{})[FR.StepKey(t)]then view.parallel[#view.parallel+1]=t end
 end
 local nextStep=steps[index+1];if nextStep then view.next=FR.Text(nextStep)end
 return view
end
function FR.HideTask(task)
 local c=FR.CharDB();c.hiddenTasks=c.hiddenTasks or{};c.hiddenTasks[FR.StepKey(task)]=true
end
function FR.RestoreTasks()FR.CharDB().hiddenTasks={}end
function FR.BagHint()
 local free=0;local api=C_Container and C_Container.GetContainerNumFreeSlots or GetContainerNumFreeSlots
 if not api then return nil end
 for bag=0,NUM_BAG_SLOTS or 4 do local n,kind=call(api,bag);if kind==0 or kind==nil then free=free+(tonumber(n)or 0)end end
 if free<=1 then return'Taschen fast voll: Händler einplanen ('..free..' freie Plätze)'end
end
function FR.Connected()
 local c=ForeverCoreClient;local ui=c and c.UI
 if not(ui and ui.State)then return false,'Gespeicherte Route'end
 local state=call(ui.State)
 return ui.lastOk~=nil and(state=='ok'or state=='busy'),'ForeverCore'
end
-- Adapter for native quest-line objectives: require identity, not just matching counts.
function FR.ObjectiveMeta(q,index)
 local meta=FR.Meta(q);local objs=FR.Objectives({q=q});local obj=objs[index]
 if not meta or not obj then return nil end
 local candidates={}
 for _,o in ipairs(meta.objectives or{})do
  if obj.objectID and obj.objectID~=0 and o.id==obj.objectID then return o end
  local want=({kill='monster',item='item',object='object',talk='monster',interact='monster',event='event'})[o.kind]
  if want==obj.type and o.count==tonumber(obj.numRequired)then candidates[#candidates+1]=o end
 end
 -- Counts alone are not identity, even when only one candidate survived.
 for _,o in ipairs(candidates)do
  local localized=o.item and call(GetItemInfo,o.item)or o.name
  if localized and obj.text and obj.text:lower():find(localized:lower(),1,true)then return o end
 end
 return nil -- ambiguity deliberately has no invented target/model
end
function FR.OpenQuest(q)
 if QuestMapFrame_OpenToQuestDetails then call(QuestMapFrame_OpenToQuestDetails,q);return end
 local i=C_QuestLog and call(C_QuestLog.GetLogIndexForQuestID,q)or call(GetQuestLogIndexByID,q)
 if i and i>0 then if QuestLogFrame then call(ShowUIPanel,QuestLogFrame)end;call(QuestLog_SetSelection,i)end
end
