local schema = require("wraith.manager.spec")
local calls, gates = 0, 0
package.preload["settings.tools"]=function()
  calls=calls+1
  return {{"owner/tool",dependencies={{"owner/library"}}}}
end
local graph = schema.normalize({
  {import="settings.tools",enabled=function() gates=gates+1; return true end},
  {"owner/first",dependencies={{import="settings.tools",enabled=function() error("repeated gate") end}}},
  {"owner/second",dependencies={{import="settings.tools"}}},
})
assert(calls==1 and gates==1)
assert(#graph.by_name.first.dependencies==1 and graph.by_name.first.dependencies[1]=="tool")
assert(#graph.by_name.second.dependencies==1 and graph.by_name.second.dependencies[1]=="tool")
assert(graph.by_name.tool.dependencies[1]=="library")
assert(graph.origins.tool[1].module=="settings.tools" and graph.origins.tool[1].kind=="preload")
assert(#graph.origins.tool==1 and graph.origins.library[1].import=="settings.tools")
assert(package.loaded["settings.tools"]==nil)
schema.normalize({{import="settings.tools"}})
assert(calls==2)

local named_calls=0
local named=function() named_calls=named_calls+1; return {{"owner/named"}} end
local declared={import=named,name="user settings"}
local names=schema.normalize({declared,declared,{import=named,name="second settings"}})
assert(named_calls==2 and #names.origins.named==2 and declared.name=="user settings")
local skipped=schema.normalize({{import="not_found",cond=false},{import=named,name="skipped",enabled=false}})
assert(#skipped.ordered==0 and named_calls==2)
local gate_calls=0
local mixed=schema.normalize({{name="mixed",dir="/tmp/mixed",import=function()
  return {{"owner/imported"}}
end,enabled=function() gate_calls=gate_calls+1; return true end}})
assert(mixed.by_name.mixed and mixed.by_name.imported and gate_calls==2)

local function rejects(value, expected)
  local ok, err=pcall(schema.normalize,value)
  assert(not ok and tostring(err):find(expected,1,true), tostring(err))
end
for _, value in ipairs({
  {import=named}, {import=named,name=false}, {import="settings.tools",name=false},
  {import=named,name="bad",cond=1}, {import=named,name="bad",enabled="yes"},
  {import=named,name="bad",unknown=true}, {import=false},
}) do rejects({value}, "") end
rejects({{import=named,name="bad",enabled=function() return nil end}}, "must return boolean")
rejects({{import=named,name="same"},{import=function() return {} end,name="same"}}, "conflicting import name")
rejects({{import="settings.tools",name="same"},{import="other.tools",name="same"}}, "conflicting import name")
for _, body in ipairs({function() end,function() return false end,function() return {},nil end,function() return {},{} end}) do
  rejects({{import=body,name="invalid result"}}, "exactly one table")
end
for _, name in ipairs({"shroud","shroud.part","wraith.manager","wraith.manager.spec"}) do
  rejects({{import=name}}, "manager implementation")
end
package.preload["settings.cycle"]=function() return {{import="settings.cycle"}} end
rejects({{import="settings.cycle"}}, "import cycle")
package.preload["settings.alias"]=function() return {{import="settings.alias",name="other alias"}} end
rejects({{import="settings.alias"}}, "import cycle")
package.preload["settings.retry"]=function() error("fixture failure") end
rejects({{import="settings.retry"}}, "fixture failure")
package.preload["settings.retry"]=function() return {{"owner/retry"}} end
assert(schema.normalize({{import="settings.retry"}}).by_name.retry)
local fn
fn=function() return {{import=fn,name="recursive"}} end
rejects({{import=fn,name="recursive"}}, "import cycle")
local many={}
for index=1,129 do many[index]={import=function() return {} end,name="empty"..index} end
rejects(many, "128 identities")
