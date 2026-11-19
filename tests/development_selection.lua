local development = require("wraith.manager.spec_development")
local sources = require("wraith.manager.spec_source")
local base = wraith.paths.stdpath("data") .. "/development"
wraith.fs.mkdir(base .. "/renamed", {parents=true})
wraith.fs.write(base .. "/file", "regular")
local record = {name="renamed", source={kind="git",url="https://github.com/owner/tool.git"},
  raw={dev=true,branch="work",pin=true,opts={nested={keep=true}}}, selector={kind="branch",value="work"}}
local settings = development.settings({path=base,fallback=true})
local selected = development.select(record, settings)
assert(selected.source.kind=="local" and selected.dir==base.."/renamed" and selected.dev)
assert(selected.declared_source.url==record.source.url and selected.declared_selector.value=="work" and selected.declared_pin)
selected.source.dir, selected.declared_selector.value = "changed", "changed"
assert(record.source.kind=="git" and record.selector.value=="work" and record.raw.opts.nested.keep)

local calls = 0
settings = development.settings({path=function(spec)
  calls=calls+1
  assert(spec.name=="renamed" and spec.dev and spec.dir==nil and spec.url==record.source.url)
  assert(spec.branch=="work" and spec.pin)
  spec.opts.nested.keep=false
  return base.."/renamed"
end,patterns={"owner/"},fallback=true})
record.raw.dev=nil
selected = development.select(record, settings)
assert(calls==1 and selected.dev and selected.dir==base.."/renamed" and record.raw.opts.nested.keep)
record.raw.dev=false
assert(development.select(record, settings).source.kind=="git" and calls==1)
record.raw.dev=nil
assert(development.select(record, development.settings({path=base,patterns={"owner.*"}})).dev==nil)
record.raw.dev=true
assert(development.select(record, development.settings({path=base,patterns={"no-match"}})).source.kind=="local")

record.raw.dir=base.."/explicit-missing"
selected = development.select(record, settings)
assert(selected.dir==record.raw.dir and calls==1 and selected.dev)
record.raw.dev=nil
assert(development.select(record, settings).dev==nil and calls==1)
record.raw.dir=nil
local local_record = {name="local",source={kind="local",dir=base.."/local"},raw={}}
assert(development.select(local_record, settings).dir==base.."/local" and calls==1)
assert(development.select({name="optional",raw={dev=true}}, settings).source==nil and calls==1)

record.raw.dev=true
for _, path in ipairs({base.."/missing",base.."/file",base.."/file/child"}) do
  settings=development.settings({path=function() return path end,fallback=true})
  selected=development.select(record, settings)
  assert(selected.source.kind=="git" and selected.dev==false and selected.dir==nil)
  assert(selected.declared_selector.value=="work" and selected.declared_pin)
  settings.fallback=false
  assert(development.select(record, settings).dir==path)
end

local input={path="./development",patterns={"owner"},fallback=false}
settings=development.settings(input)
input.patterns[1]="changed"
assert(settings.patterns[1]=="owner" and settings.path==wraith.paths.stdpath("config").."/development")
assert(development.settings().path==os.getenv("HOME").."/projects")
assert(sources.local_path("~/a/../b")==os.getenv("HOME").."/b")
for _, invalid in ipairs({false,{path=false},{fallback=1},{unknown=true},{patterns="owner"},
  {patterns={""}},{patterns={"x\ny"}},{patterns={[2]="owner"}},{path="~another"}}) do
  assert(not pcall(development.settings,invalid))
end
for _, invalid in ipairs({false,"",{},"~another/path",string.rep("x",4097)}) do
  settings=development.settings({path=function() return invalid end,fallback=true})
  assert(not pcall(development.select,record,settings))
end
local ok, err=pcall(development.select,record,development.settings({path=function() error("path failed") end}))
assert(not ok and tostring(err):find("path failed",1,true))

local stat=wraith.fs.stat
wraith.fs.stat=function() error("permission denied") end
ok, err=pcall(development.select,record,development.settings({path=base,fallback=true}))
wraith.fs.stat=stat
assert(not ok and tostring(err):find("permission denied",1,true))
assert(not pcall(sources.normalize,{"owner/tool",dir=base}))
