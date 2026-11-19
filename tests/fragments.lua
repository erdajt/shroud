local schema = require("wraith.manager.spec")
local options = require("wraith.manager.spec_options")
local enabled, initialized, evaluated = 0, 0, 0
local input = {
  {name="tool", opts={nested={first=true}, list={"first"}}, cmd="inspect"},
  {"owner/tool", priority=12, lazy=true, dependencies={{"owner/library", opts={first=true}}},
    enabled=function(spec) enabled=enabled+1; assert(spec.priority==30); return true end,
    init=function() initialized=initialized+1 end},
  {"https://github.com/owner/tool", priority=30, opts=function(spec, opts)
    evaluated=evaluated+1
    assert(spec.name=="tool" and opts.nested.first)
    opts.nested.second=true
  end, dependencies={"library", {"owner/library", opts={second=true}}}},
  {"tool", opts_extend={"list"}, opts={list={"last"}}, cmd={"inspect", "status"},
    keys={{"<Enter>", "command.help"}}},
  {name="tool", keys={{"<CR>", "command.settings"}}, config=false},
}
local graph = schema.normalize(input)
local tool, library = graph.by_name.tool, graph.by_name.library
assert(enabled==1 and initialized==0 and evaluated==0)
assert(#graph.ordered==2 and graph.ordered[1].name=="library")
assert(#tool.dependencies==1 and tool.dependencies[1]=="library")
assert(tool.source.url=="https://github.com/owner/tool.git" and tool.priority==30)
assert(tool.opts_extend[1]=="list")
assert(tool.lazy and tool.config==false and #tool.cmd==2 and #tool.keys==1)
assert(tool.keys[1].action=="command.settings")
local opts = options.resolve(tool, graph.options.tool)
assert(evaluated==1 and opts.nested.first and opts.nested.second)
assert(table.concat(opts.list, ",")=="first,last")
assert(options.resolve(library, graph.options.library).second)
assert(input[1].opts.nested.second==nil and #input[1].opts.list==1)
opts.list[1]="changed"
local again = schema.normalize(input)
assert(enabled==2 and options.resolve(again.by_name.tool, again.options.tool).list[1]=="first")

local inherited = schema.normalize({
  {"owner/inherited", opts={list={1}}},
  {name="inherited", opts={list={2}}},
  {name="inherited", opts_extend={"list"}},
  {name="inherited", opts={list={3}}},
})
assert(table.concat(options.resolve(inherited.by_name.inherited, inherited.options.inherited).list, ",")=="2,3")
local first = schema.normalize({"https://github.com/owner/tool", "owner/tool"})
assert(first.by_name.tool.source.url=="https://github.com/owner/tool")
local disabled = schema.normalize({{"owner/tool",enabled=true},{name="tool",enabled=false}})
assert(#disabled.ordered==0 and disabled.by_name.tool==nil and disabled.excluded.tool.reason=="disabled")
local stable = schema.normalize({"owner/first", "owner/second", "owner/first"})
assert(stable.ordered[1].name=="first" and stable.ordered[2].name=="second")

local function rejects(value, message)
  local ok, err = pcall(schema.normalize, value)
  assert(not ok and tostring(err):find(message,1,true), tostring(err))
end
rejects({"owner/tool", "other/tool"}, "conflicting source")
assert(schema.normalize({{name="tool",dir="/tmp/tool"},{name="tool",dir="/tmp/tool.git"}}).by_name.tool.source.dir=="/tmp/tool.git")
rejects({{name="tool",url="/tmp/tool"},{name="tool",url="/tmp/tool.git"}}, "conflicting source")
rejects({{name="missing",opts={}}}, "source is missing")
rejects({{"owner/tool",dependencies={"tool"}}}, "self dependency")
rejects({{"owner/tool",dependencies={"library"}},"owner/library",{name="library",dependencies={"tool"}}}, "dependency cycle")
local excluded = schema.normalize({{"owner/tool",dependencies={"library"}},"owner/library",{name="library",enabled=false}})
assert(#excluded.by_name.tool.dependencies==0 and excluded.excluded.library.reason=="disabled")
rejects({{"owner/tool",branch="main"},{name="tool",tag="v1"}}, "choose one branch")
for _, field in ipairs({"priority", "main", "opts", "cmd", "keys", "opts_extend"}) do
  local invalid = {"owner/tool"}; invalid[field]=false
  rejects({invalid,{name="tool",[field]=field=="priority" and 1 or {}}}, "")
end
local cycle = {"owner/tool"}; cycle.dependencies={cycle}
rejects({cycle}, "cyclic package")
local many = {}; for index=1,256 do many[index]={name="tool"} end
rejects({"owner/tool",many}, "declarations exceed 256")
local left, right = {}, {}
for index=1,2100 do left["left"..index],right["right"..index]=true,true end
rejects({{"owner/tool",opts=left},{name="tool",opts=right}}, "exceed their limit")
