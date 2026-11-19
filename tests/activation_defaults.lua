local normalize = require("wraith.manager.spec").normalize
local parent = {"owner/parent", lazy=true, dependencies={{"owner/library"}}}
local graph = normalize({parent})
assert(graph.by_name.library.lazy and #graph.start==0)

for _, declarations in ipairs({{parent,{"owner/library"}}, {{"owner/library"},parent}}) do
  graph = normalize(declarations)
  assert(not graph.by_name.library.lazy and graph.start[1]=="library")
end
graph = normalize({parent,{name="library",lazy=false}})
assert(not graph.by_name.library.lazy and #graph.start==1)
graph = normalize({{"owner/library",lazy=true},parent})
assert(graph.by_name.library.lazy and #graph.start==0)
graph = normalize({{"owner/parent",dependencies={{"owner/library",lazy=false}}}})
assert(not graph.by_name.library.lazy and graph.ordered[1].name=="library")

local imported = {name="shared",import=function() return {{"owner/library"}} end}
graph = normalize({{"owner/parent",lazy=true,dependencies={imported}},imported})
assert(graph.by_name.library.lazy and #graph.origins.library==1)
graph = normalize({imported,{"owner/parent",lazy=true,dependencies={imported}}})
assert(not graph.by_name.library.lazy and #graph.origins.library==1)
graph = normalize({{"owner/library"},{"owner/parent",dependencies={"library"}}})
assert(not graph.by_name.library.lazy and #graph.origins.library==1)

graph = normalize({
  {"owner/zero",priority=0}, {"owner/normal"}, {"owner/negative",priority=-1},
  {"owner/later"}, {"owner/disabled",enabled=false,priority=1000},
  {"owner/command",cmd="activate"}, {"owner/event",event="ready"},
  {"owner/key",keys={{"z",function() end}}},
})
assert(graph.by_name.normal.priority==50 and graph.by_name.zero.priority==0)
assert(table.concat(graph.start,",")=="normal,later,zero,negative")
assert(graph.by_name.command.lazy and graph.by_name.event.lazy and graph.by_name.key.lazy)

graph = normalize({
  {"owner/lazy",lazy=true,priority=100,dependencies={{"owner/low",lazy=false,priority=0}}},
  {"owner/normal"},
})
assert(graph.ordered[1].name=="low")
assert(table.concat(graph.start,",")=="normal,low")
assert(parent.dependencies[1].lazy==nil and parent.priority==nil)
