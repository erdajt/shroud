local development = require("wraith.manager.spec_development")
local calls, budget = 0, {calls=0}
local record = {name="tool",source={kind="git",url="https://github.com/owner/tool.git"},raw={dev=true}}
local settings = development.settings({path=function()
  calls=calls+1
  return "/development/tool"
end})
for _=1,1024 do development.select(record,settings,budget) end
local ok,err=pcall(development.select,record,settings,budget)
assert(not ok and tostring(err):find("development path evaluations exceed 1024",1,true))
assert(calls==1024 and budget.calls==1024)
record.raw.dev=false
development.select(record,settings,budget)
record.raw.dev,record.raw.dir=true,"/explicit/tool"
development.select(record,settings,budget)
assert(calls==1024 and budget.calls==1024)
