local fragments = require("wraith.manager.spec_fragments")
local schema = require("wraith.manager.spec")
local resolve = require("wraith.manager.spec_resolution").resolve
local collection = fragments.new(schema.descriptor)
local child_calls = 0
local parent = collection.add({"owner/parent",enabled=false})
collection.add({"owner/child",enabled=function() child_calls=child_calls+1; return true end},nil,true,parent)
local result = resolve(collection)
assert(child_calls==0 and next(result.enabled)==nil)
assert(result.excluded.parent.reason=="disabled" and result.excluded.child.reason=="scope")
assert(result.retain_lock.parent and not result.retain_lock.child)
assert(result.excluded.child.origins[1].index==2)

collection = fragments.new(schema.descriptor)
local observed, stable_calls = {}, 0
local observer = collection.add({"owner/observer",enabled=function(spec)
  observed[#observed+1]=#spec.dependencies
  spec.dependencies[1]="mutated"
  spec.opts.changed=true
  return true
end,opts={}})
collection.depend(observer,"target")
collection.depend(observer,"unknown")
collection.add({"owner/stable",enabled=function() stable_calls=stable_calls+1; return true end})
collection.add({"owner/target",enabled=false})
local original, revision = collection.merged("observer")
result = resolve(collection)
assert(table.concat(observed,",")=="2,1" and stable_calls==1)
assert(result.dependencies.observer[1]=="unknown" and #result.dependencies.observer==1)
local unchanged, after = collection.merged("observer")
assert(original==unchanged and revision==after and not original.raw.opts.changed)
assert(table.concat(original.dependencies,",")=="target,unknown")
assert(result.enabled.observer and result.enabled.stable and not result.enabled.target)

collection = fragments.new(schema.descriptor)
local calls = {}
collection.add({"owner/promoted",enabled=function() calls[#calls+1]="promoted"; return true end})
local doomed = collection.add({"owner/doomed",enabled=false})
collection.add({name="promoted",opts={scoped=true}},nil,false,doomed)
local live_parent = collection.add("owner/live-parent")
collection.add({"owner/scoped",enabled=function() calls[#calls+1]="scoped"; return true end},nil,false,live_parent)
result = resolve(collection)
assert(table.concat(calls,",")=="promoted,scoped")
assert(collection.merged("promoted").top_only and result.enabled.promoted)
assert(not result.excluded.promoted and result.excluded.doomed.reason=="disabled")

collection = fragments.new(schema.descriptor)
local snapshots = {}
local first = collection.add({"owner/shared",enabled=function(spec)
  snapshots[#snapshots+1]=spec.opts and spec.opts.scoped or false
  return true
end})
local outer = collection.add("owner/outer")
local owner = collection.add({"owner/owner",enabled=function() return false end},nil,false,outer)
collection.add({name="shared",opts={scoped=true}},nil,false,owner)
result = resolve(collection)
assert(#snapshots==2 and snapshots[1] and snapshots[2]==false and result.enabled.shared)
assert(first.alive and not owner.alive)

local function rejects(fn, expected)
  local ok, err = pcall(fn)
  assert(not ok and tostring(err):find(expected,1,true),tostring(err))
end
collection = fragments.new(schema.descriptor)
collection.add({"owner/invalid",enabled=function() return nil end},{module="plugins.invalid"})
rejects(function() resolve(collection) end,"enabled must return boolean")
rejects(function() resolve(collection) end,"plugins.invalid")

collection = fragments.new(schema.descriptor)
local before = 0
collection.add({"owner/earlier",enabled=function() before=before+1; return true end})
local left,right = {},{}
for index=1,2100 do left["left"..index],right["right"..index]=true,true end
collection.add({"owner/later",opts=left})
collection.add({name="later",opts=right})
rejects(function() resolve(collection) end,"exceed their limit")
assert(before==0)

collection = fragments.new(schema.descriptor)
local root = collection.add({"owner/root",enabled=false})
collection.add("owner/missing",nil,false,root)
collection.add({name="missing",opts={survives=true}})
result = resolve(collection)
assert(result.enabled.missing and collection.merged("missing").source==nil)
rejects(function() collection.finish() end,"source is missing: missing")

collection = fragments.new(schema.descriptor)
local container = collection.add("owner/container")
local wide, checked = {}, false
for index=1,4080 do wide["field"..index]=true end
local bounded = collection.add({"owner/bounded",opts=wide,enabled=function(spec)
  assert(#spec.dependencies==0 and spec.opts.field4080)
  checked=true
  return true
end},nil,false,container)
for index=1,24 do
  local name="disabled"..index
  collection.add({"owner/"..name,enabled=false})
  collection.depend(bounded,name)
end
result = resolve(collection)
assert(checked and result.enabled.bounded and #collection.merged("bounded").dependencies==24)
