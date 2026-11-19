local planner = require("wraith.manager.store_plan")
local source = {kind="git",url="https://example.com/plugin"}
local selector = {kind="head"}
local entry = {source=source,selector=selector,pin=false,commit=string.rep("a",40)}
local specs = {
  {name="selected",source=source,selector=selector,pin=false},
  {name="unselected",source=source,selector=selector,pin=false},
  {name="missing",source=source,selector=selector,pin=false},
  {name="local",source={kind="local",dir="/explicit/plugin"},selector=selector,pin=false},
}
local lock = {version=1,generation="before",packages={
  selected=entry,unselected=entry,disabled=entry,conditional=entry,removed=entry,["local"]=entry,
}}
local retained = {disabled=true,conditional=true,["local"]=true,removed=false}
for _, action in ipairs({"install","update"}) do
  local plan = planner.create(specs,lock,action,{"selected"},retained)
  assert(#plan.packages==1 and plan.packages[1].name=="selected")
  assert(table.concat(plan.removed,",")=="local,removed")
  assert(plan.baseline.packages.disabled.commit==entry.commit)
  plan.baseline.packages.disabled.commit=string.rep("b",40)
  assert(lock.packages.disabled.commit==entry.commit)
end
assert(#planner.create(specs,lock,"restore",{"selected"},retained).removed==0)
local detached = planner.retention(retained)
retained.disabled=false
assert(detached.disabled and not detached.removed)

local function rejects(fn, expected)
  local ok, err = pcall(fn)
  assert(not ok and tostring(err):find(expected,1,true), tostring(err))
end
for _, value in ipairs({false,"disabled",{[1]=true},{disabled="true"},{["../bad"]=true}}) do
  rejects(function() planner.retention(value) end, "")
end
local many = {}
for index=1,257 do many["p"..index]=true end
rejects(function() planner.retention(many) end, "exceed 256")

local crowded = {version=1,generation="before",packages={}}
local keep = {}
for index=1,63 do crowded.packages["p"..index],keep["p"..index]=entry,true end
rejects(function() planner.create(specs,crowded,"install",{"selected"},keep) end, "lock exceeds 63")
keep.p63=false
local boundary = planner.create(specs,crowded,"install",{"selected"},keep)
assert(#boundary.packages==1 and #boundary.removed==1 and boundary.removed[1]=="p63")
assert(crowded.packages.p63 and not crowded.packages.selected)

local selected = {name="p1",source=source,selector=selector,pin=false}
keep.p63=true
local same = planner.create({selected,specs[3]},crowded,"update",{"p1"},keep)
assert(#same.packages==1 and #same.removed==0)
rejects(function() planner.create({selected,specs[3]},crowded,"update",nil,keep) end, "lock exceeds 63")
selected.source={kind="local",dir="/explicit/plugin"}
local freed = planner.create({selected,specs[3]},crowded,"install",{"missing"},keep)
assert(#freed.removed==1 and freed.removed[1]=="p1")

selected.source={kind="git",url="https://other.example/plugin"}
rejects(function() planner.create({selected},crowded,"install",nil,keep) end, "source changed")
selected.source=source
selected.selector={kind="tag",value="v2"}
rejects(function() planner.create({selected},crowded,"install",nil,keep) end, "selector changed")
assert(planner.create({selected},crowded,"restore",nil,keep).packages[1].commit==entry.commit)
