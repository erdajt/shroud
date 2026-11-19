local schema = require("wraith.manager.spec")
local function rejects(value, expected)
  local ok, err=pcall(schema.normalize,value)
  assert(not ok,tostring(err))
  for _, text in ipairs(expected) do assert(tostring(err):find(text,1,true),tostring(err)) end
end
package.preload["settings.missing"]=function() return {{name="missing",opts={}}} end
rejects({{import="settings.missing"}}, {"source is missing", "settings.missing"})
package.preload["settings.first"]=function() return {{"owner/tool",branch="main"}} end
package.preload["settings.second"]=function() return {{name="tool",tag="v1"}} end
rejects({{import="settings.first"},{import="settings.second"}}, {"choose one branch", "settings.first", "settings.second"})
package.preload["settings.enabled"]=function() return {{"owner/tool",enabled=function() error("predicate failed") end}} end
rejects({{import="settings.enabled"}}, {"predicate failed", "settings.enabled"})
package.preload["settings.unknown"]=function() return {{"owner/tool",dependencies={"unknown"}}} end
rejects({{import="settings.unknown"}}, {"unknown dependency", "settings.unknown"})
package.preload["settings.disabled"]=function() return {{"owner/disabled",enabled=false}} end
package.preload["settings.parent"]=function() return {{"owner/tool",dependencies={"disabled"}}} end
local excluded = schema.normalize({{import="settings.parent"},{import="settings.disabled"}})
assert(#excluded.by_name.tool.dependencies==0 and excluded.excluded.disabled.reason=="disabled")
assert(excluded.origins.tool[1].module=="settings.parent")
assert(excluded.excluded.disabled.origins[1].module=="settings.disabled")
package.preload["settings.cycle_a"]=function() return {{"owner/first",dependencies={"second"}}} end
package.preload["settings.cycle_b"]=function() return {{"owner/second",dependencies={"first"}}} end
rejects({{import="settings.cycle_a"},{import="settings.cycle_b"}}, {"dependency cycle", "settings.cycle_a", "settings.cycle_b"})

local calls=0
local declaration={import=function() calls=calls+1; return {{"owner/dependency"}} end,name="shared"}
local graph=schema.normalize({{"owner/parent",dependencies={declaration}}, declaration})
assert(calls==1 and #graph.origins.dependency==1)
assert(schema.normalize({{import=function() return {} end,name="gate",cond=function(...)
  assert(select("#",...)==0); return true
end,enabled=function(...)
  assert(select("#",...)==0); return true
end}}))
local first, second
first=function() return {{import=second,name="second"}} end
second=function() return {{import=first,name="first"}} end
rejects({{import=first,name="first"}}, {"import cycle", "first", "second"})
local path=assert(debug.getinfo(1,"S").source:gsub("^@", ""):match("^(.*)/[^/]+$"))
wraith.runtimepath.prepend(path.."/fixtures")
local many={}
for index=1,65 do many[index]={import="limit_fixture",name="group"..index} end
rejects(many, {"256 source evaluations"})
