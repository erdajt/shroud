local collection = require("wraith.manager.spec_fragments").new(require("wraith.manager.spec").descriptor)
local resolve = require("wraith.manager.spec_resolution").resolve
local calls = 0
for index=1,16 do
  local observer = collection.add({"owner/observer"..index,enabled=function()
    calls=calls+1
    return true
  end})
  for target=1,64 do collection.depend(observer,"target"..target) end
end
for index=1,64 do collection.add({"owner/target"..index,enabled=false}) end
assert(#collection.order==80)

local ok, err = pcall(resolve,collection)
assert(not ok and tostring(err):find("package gate evaluations exceed 1024",1,true),tostring(err))
assert(calls==1024)
for index=1,16 do
  assert(#collection.merged("observer"..index).dependencies==64)
end
