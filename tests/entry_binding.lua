local bindings = require("wraith.manager.loader_binding")
local function rejects(call, expected)
  local ok, err = pcall(call)
  assert(not ok and tostring(err):find(expected, 1, true), tostring(err))
end

local function binding(name, source)
  package.preload[name] = source
  local selected = {name=name, kind="preload", identity=source, load=function() return source(name) end}
  local owned = bindings.new(selected)
  owned.install()
  return owned, selected
end

local calls, expected = 0, {}
local owned, selected = binding("bound_entry", function()
  calls = calls + 1
  return expected, "discarded"
end)
selected.name, selected.load = "redirected", function() error("redirected") end
assert(owned.require()==expected and calls==1)
assert(require("bound_entry")==expected and owned.require()==expected and calls==1)
expected.setup = function() error("setup failed after source returned") end
rejects(expected.setup, "setup failed")
assert(owned.require()==expected and calls==1)
owned.install()
package.loaded.bound_entry = nil
assert(require("bound_entry")==expected and calls==2)
owned.check()
package.loaded.bound_entry = {}
rejects(owned.require, "cache is foreign")
package.loaded.bound_entry = expected
assert(owned.require()==expected)
local equal = {__eq=function() return true end}
setmetatable(expected, equal)
package.loaded.bound_entry = setmetatable({}, equal)
rejects(owned.require, "cache is foreign")
package.loaded.bound_entry = expected
setmetatable(expected, nil)

local nil_calls = 0
local empty = binding("nil_entry", function() nil_calls = nil_calls + 1 end)
package.loaded.nil_entry = true
rejects(empty.wrapper, "requires native require")
assert(nil_calls==0 and package.loaded.nil_entry==true)
rejects(empty.require, "cache is foreign")
package.loaded.nil_entry = nil
assert(empty.require()==true and nil_calls==1)
local false_calls = 0
local falsy = binding("false_entry", function() false_calls = false_calls + 1; return false end)
assert(falsy.require()==false and falsy.require()==false and false_calls==2)

for index, value in ipairs({false, true, {}, newproxy()}) do
  local name = "written_entry_" .. index
  local written = binding(name, function() package.loaded[name]=value; return "ignored" end)
  assert(written.require()==value and package.loaded[name]==value)
end
local erased = binding("erased_entry", function() package.loaded.erased_entry=nil end)
assert(erased.require()==nil and package.loaded.erased_entry==nil)

local attempts = 0
local retry = binding("retry_entry", function()
  attempts = attempts + 1
  if attempts==1 then error("source failed") end
  return {ready=true}
end)
rejects(retry.require, "source failed")
assert(package.loaded.retry_entry==nil)
assert(retry.require().ready and attempts==2)
local external_attempts = 0
binding("external_retry_entry", function()
  external_attempts = external_attempts + 1
  if external_attempts==1 then error("external source failed") end
  return true
end)
rejects(function() require("external_retry_entry") end, "external source failed")
assert(package.loaded.external_retry_entry==nil and require("external_retry_entry")==true)
local recurse = true
local recursive = binding("recursive_entry", function()
  if recurse then return require("recursive_entry") end
  return "recovered"
end)
rejects(recursive.require, "loop or previous error")
assert(package.loaded.recursive_entry==nil)
recurse = false
assert(recursive.require()=="recovered")

local corrupt = {}
local poisoned = binding("poisoned_entry", function()
  package.loaded.poisoned_entry = corrupt
  error("changed cache then failed")
end)
rejects(poisoned.require, "changed cache then failed")
assert(package.loaded.poisoned_entry==corrupt)
package.loaded.poisoned_entry = nil
rejects(poisoned.require, "cache is poisoned")
local replaced
replaced = binding("replaced_entry", function()
  package.preload.replaced_entry = function() end
  error("preload replaced then failed")
end)
rejects(replaced.require, "preload replaced then failed")
package.preload.replaced_entry = replaced.wrapper
rejects(replaced.require, "cache is poisoned")
local foreign = function() error("foreign preload executed") end
package.preload.bound_entry = foreign
rejects(owned.check, "preload changed")
package.preload.bound_entry = owned.wrapper
local original = package
local loaded, preloads = package.loaded, package.preload
package.loaded = {}
rejects(owned.require, "tables were replaced")
rejects(function()
  bindings.new({name="new_entry", kind="file", identity="unused", load=function() end})
end, "tables were replaced")
package.loaded = loaded
package.preload = {}
rejects(owned.require, "tables were replaced")
package.preload = preloads
package = {}
rejects(owned.require, "tables were replaced")
package = original
assert(owned.require()==expected)
local displaced = binding("displaced_entry", function() package.loaded={}; return true end)
rejects(displaced.require, "tables were replaced during entry load")
package.loaded = loaded
rejects(displaced.require, "cache is poisoned")

local pending_source = function() return true end
package.preload.pending_entry = pending_source
local pending = bindings.new({name="pending_entry", kind="preload", identity=pending_source, load=pending_source})
package.loaded.pending_entry = false
rejects(pending.install, "cache is foreign")
assert(package.preload.pending_entry==pending_source)
rejects(function()
  bindings.new({name="pending_entry", kind="preload", identity=pending_source, load=pending_source})
end, "cache is foreign")

local root = wraith.paths.stdpath("data") .. "/bound-file"
wraith.fs.mkdir(root .. "/lua", {parents=true})
local path = root .. "/lua/bound_file.lua"
wraith.fs.write(path, "return function(")
local file = bindings.new(wraith.modules.source(root, "bound_file"))
file.install()
rejects(file.require, "bound_file.lua")
assert(package.loaded.bound_file==nil)
wraith.fs.write(path, "local function deepest_source() error('trace failure') end; deepest_source()", {overwrite=true})
local ok, failure = xpcall(file.require, debug.traceback)
assert(not ok and failure:find("in function <@"..path..":0>", 1, true), failure)
assert(failure:find("in function 'deepest_source'", 1, true), failure)
assert(package.loaded.bound_file==nil)
wraith.fs.write(path, "return {ready=true}", {overwrite=true})
assert(file.require().ready)
