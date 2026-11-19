local normalize = require("wraith.manager.spec").normalize
for _, value in ipairs({false, true}) do
  local graph=normalize({{"owner/tool",module=value}})
  assert(graph.by_name.tool.module==value and not graph.by_name.tool.lazy and graph.start[1]=="tool")
  graph=normalize({{"owner/tool",module=not value},{name="tool",module=value}})
  assert(graph.by_name.tool.module==value)
end
assert(normalize({"owner/tool"}).by_name.tool.module==nil)
local graph=normalize({{"owner/tool",module=false},{"owner/parent",enabled=false,specs={{name="tool",module=true}}}})
assert(graph.by_name.tool.module==false)
local calls=0
local ok, err=pcall(normalize, {{"owner/first",enabled=function() calls=calls+1; return true end},
  {"owner/tool",module="bad"},{name="tool",module=false}})
assert(not ok and tostring(err):find("module must be boolean",1,true) and calls==0)
graph=normalize({{"owner/tool",module=false,name="tool",import=function() return {"owner/imported"} end}})
assert(graph.by_name.tool.module==false and graph.by_name.imported)
local imported=0
ok,err=pcall(normalize, {{name="pure",module=false,import=function() imported=imported+1; return {} end}})
assert(not ok and imported==0)
