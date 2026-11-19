local schema = require("wraith.manager.spec")
local fragments = require("wraith.manager.spec_fragments")
local development = require("wraith.manager.spec_development")
local base = wraith.paths.stdpath("data") .. "/development-specs"
wraith.fs.mkdir(base .. "/tool", {parents=true})
local calls, gates = 0, 0
local input = {{"owner/tool",branch="work",pin=true,opts={keep=true},
  cond=function(spec)
    assert(spec.dev and spec.dir==base.."/tool" and spec.url=="https://github.com/owner/tool.git")
    assert(spec.branch=="work" and spec.pin and spec.opts.keep)
    spec.opts.keep=false
    gates=gates+1
    return true
  end,enabled=function(spec)
    assert(spec.dev and spec.dir==base.."/tool" and spec.opts.keep)
    gates=gates+1
    return true
  end}}
local settings = {patterns={"owner/"},path=function(spec)
  calls=calls+1
  assert(spec.dev and spec.dir==nil and spec.name=="tool" and spec.branch=="work")
  spec.opts.keep=false
  return base.."/tool"
end,fallback=true}
local graph = schema.normalize(input,nil,settings)
local spec=graph.by_name.tool
assert(calls==1 and gates==2 and spec.dev and spec.source.dir==base.."/tool" and spec.dir==base.."/tool")
assert(spec.selector.kind=="head" and not spec.pin and spec.declared_selector.value=="work" and spec.declared_pin)
assert(input[1].dev==nil and input[1].dir==nil and input[1].opts.keep)
schema.normalize(input,nil,settings)
assert(calls==2 and gates==4)

calls=0
graph=schema.normalize({{"owner/tool",dev=true,dependencies={{"owner/disabled",enabled=false}},
  enabled=function(value) assert(value.dir==base.."/tool"); return true end}},nil,
  {path=function() calls=calls+1; return base.."/tool" end})
assert(calls==1 and #graph.by_name.tool.dependencies==0)

local selected={}
graph=schema.normalize({{"owner/tool",dev=true,opts={root=true}},
  {"owner/disabled",enabled=false,specs={{name="tool",opts={scoped=true}}}}},nil,
  {path=function(value)
    selected[#selected+1]=value.opts.scoped and "scoped" or "root"
    return base.."/"..selected[#selected]
  end})
assert(table.concat(selected,",")=="scoped,root" and graph.by_name.tool.source.dir==base.."/root")

calls=0
graph=schema.normalize({{"owner/tool"},{"owner/disabled",enabled=false,specs={{name="tool",dev=true}}}},nil,
  {path=function() calls=calls+1; return base end})
assert(calls==1 and graph.by_name.tool.source.kind=="git" and graph.by_name.tool.dev==nil)
graph=schema.normalize({{"owner/tool",dev=true},{"owner/disabled",enabled=false,specs={{name="tool",dev=false}}}},nil,
  {path=function() calls=calls+1; return base end})
assert(calls==2 and graph.by_name.tool.dev and graph.by_name.tool.source.dir==base)

graph=schema.normalize({{"owner/tool",dev=true,branch="work",pin=true}},nil,
  {path=function() return base.."/missing" end,fallback=true})
assert(graph.by_name.tool.dev==false and graph.by_name.tool.source.kind=="git" and graph.by_name.tool.dir==nil)
assert(graph.by_name.tool.selector.value=="work" and graph.by_name.tool.pin)
graph=schema.normalize({{"owner/tool",dir=base,dev=true}},nil,{path=function() error("unused") end,fallback=true})
assert(graph.by_name.tool.dev and graph.by_name.tool.source.dir==base)

local imported={patterns={"owner"},path=base}
graph=schema.normalize({{name="settings",import=function()
  imported.patterns[1]="changed"
  imported.path="/changed"
  return {"owner/tool"}
end}},nil,imported)
assert(graph.by_name.tool.dev and graph.by_name.tool.source.dir==base.."/tool")
local function rejects(specs, settings, expected)
  local ok,err=pcall(schema.normalize,specs,nil,settings)
  assert(not ok and tostring(err):find(expected,1,true),tostring(err))
end
calls=0
for _, invalid in ipairs({false,{path=false},{patterns=false},{fallback=1},{unknown=true}}) do
  rejects({{name="side-effect",import=function() calls=calls+1; return {} end}},invalid,"development")
end
assert(calls==0)
rejects({{"owner/tool",dev="yes"}},nil,"dev must be boolean")
rejects({{"owner/tool",dev=true}},{path=function() return false end},"invalid local package directory")
rejects({{name="source",import=function() return {{"owner/tool",dev=true}} end}},
  {path=function() error("path failed") end},"source")

local commands={}
for index=1,64 do commands[index]="command"..index end
local path=function() calls=calls+1; return base end
rejects({{"owner/first",dev=true},{"owner/last",cmd=commands},{name="last",cmd="overflow"}},
  {path=path},"command trigger exceeds its limit")
rejects({{"owner/first",dev=true},{"owner/last",branch="work"},{name="last",tag="v1"}},
  {path=path},"choose one branch")
assert(calls==0)
rejects({{"owner/first",dev=true},{name="last",dir=base},{name="last",branch="work"},
  {"owner/disabled",enabled=false,specs={{name="first",opts={scoped=true}},{"owner/last"}}}},
  {path=path},"local packages cannot select")
assert(calls==1)

local collection=fragments.new(schema.descriptor,development.settings({path=path}))
collection.add({name="optional",optional=true,dev=true})
local absent=collection.selection("optional")
assert(absent.source==nil and collection.selection("optional")==absent and calls==1)
collection.add("owner/optional")
assert(collection.selection("optional").source.kind=="local" and calls==2)
