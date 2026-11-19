local fragments = require("wraith.manager.spec_fragments")
local schema = require("wraith.manager.spec")
local options = require("wraith.manager.spec_options")
local collection = fragments.new(schema.descriptor)
local enabled, evaluated = 0, 0
local parent = collection.add("owner/parent")
local scoped = collection.add({url="https://github.com/owner/tool", opts_extend={"list"},
  opts={list={"scoped"},scoped=true}, cmd="inspect", keys={{"<Enter>","command.help"}}},
  {module="plugins.scoped"}, true, parent)
collection.depend(scoped,"scoped-dependency")
local input = {"owner/tool", opts={list={"root"}}, cmd="status", keys={{"<CR>","command.settings"}},
  enabled=function() enabled=enabled+1; return true end}
local independent = collection.add(input,{module="plugins.root"})
collection.depend(independent,"root-dependency")
local constant = collection.add({"owner/constant",opts=function() evaluated=evaluated+1; return {} end})
local unchanged = collection.merged(constant.name)
local merged, revision = collection.merged("tool")
assert(enabled==0 and evaluated==0 and merged==collection.merged("tool"))
assert(not merged.dependency_only and not merged.top_only)
assert(merged.source.url=="https://github.com/owner/tool")
assert(merged.origins[1].index==2 and merged.origins[2].index==3)
assert(table.concat(merged.dependencies,",")=="scoped-dependency,root-dependency")
input.opts.list[1]="changed"

local by_name, declared, recipes, origins = collection.finish()
assert(#declared==3 and enabled==1 and evaluated==0)
assert(table.concat(options.resolve(by_name.tool,recipes.tool).list,",")=="scoped,root")
assert(by_name.tool.keys[1].action=="command.settings" and #by_name.tool.cmd==2)
by_name.tool.opts.list[1]="public change"
recipes.tool[1].value.scoped=false
origins.tool[1].module="public change"
assert(merged.raw.opts.list[1]=="root" and merged.layers[1].value.scoped)
assert(merged.origins[1].module=="plugins.scoped")

assert(table.concat(collection.remove("parent"),",")=="parent,tool")
local rebuilt, changed = collection.merged("tool")
assert(changed~=revision and rebuilt~=merged and rebuilt.top_only)
assert(collection.merged("constant")==unchanged)
assert(rebuilt.source.url=="https://github.com/owner/tool.git")
assert(#rebuilt.origins==1 and rebuilt.origins[1].index==3)
assert(rebuilt.raw.opts_extend==nil and #rebuilt.layers==1)
assert(table.concat(rebuilt.dependencies,",")=="root-dependency")
assert(#rebuilt.raw.cmd==1 and rebuilt.raw.cmd[1]=="status")
assert(collection.merged("parent")==nil and enabled==1)
by_name, declared, recipes = collection.finish()
assert(enabled==2 and evaluated==0 and #declared==2)
assert(table.concat(options.resolve(by_name.tool,recipes.tool).list,",")=="root")
assert(options.resolve(by_name.tool,recipes.tool).scoped==nil)

collection = fragments.new(schema.descriptor)
parent = collection.add("owner/parent")
collection.add("owner/library",nil,false,parent)
local other = collection.add("owner/other")
collection.add("owner/library",nil,true,other)
assert(not collection.merged("library").dependency_only)
collection.remove("parent")
assert(collection.merged("library").dependency_only)
by_name = collection.finish()
assert(by_name.library.lazy and by_name.other)

local function rejects(fn, expected)
  local ok, err = pcall(fn)
  assert(not ok and tostring(err):find(expected,1,true),tostring(err))
end
rejects(function() collection.add({name="library",priority=false}) end,"priority")
rejects(function() collection.add("different/library") end,"conflicting source")
assert(enabled==2 and evaluated==0)
local recursive = {"owner/tree"}
recursive.dependencies={recursive}
local fragment, dependencies = collection.add(recursive)
assert(dependencies==recursive.dependencies and fragment.value.dependencies==nil)

collection = fragments.new(schema.descriptor)
local first, second = {}, {}
for index=1,2100 do first["first"..index],second["second"..index]=true,true end
collection.add({"owner/tool",opts=first},{module="plugins.first"})
collection.add({name="tool",opts=second},{module="plugins.second"})
rejects(function() collection.merged("tool") end,"plugins.first")
rejects(function() collection.merged("tool") end,"plugins.second")

local original, captured = fragments.new
fragments.new = function(descriptor)
  captured = original(descriptor)
  return captured
end
local imported = {name="shared",import=function() return {"owner/imported"} end}
schema.normalize({{"owner/parent",dependencies={imported}},imported})
assert(not captured.merged("imported").top_only)
assert(#captured.merged("imported").origins==1)
captured.remove("parent")
assert(captured.merged("imported")==nil)

schema.normalize({{"owner/parent",dependencies={
  {"owner/mixed",name="mixed",import=function() return {"owner/imported"} end},
}}})
assert(table.concat(captured.merged("parent").dependencies,",")=="mixed,imported")
captured.remove("mixed")
assert(captured.merged("imported")~=nil)
captured.remove("parent")
assert(captured.merged("imported")==nil)
fragments.new = original

local calls = 0
rejects(function()
  schema.normalize({
    {"owner/earlier",enabled=function() calls=calls+1; return true end},
    {"owner/tool",opts=first}, {name="tool",opts=second},
  })
end,"exceed their limit")
assert(calls==0)
