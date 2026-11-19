local M = {}
local globals, original = _G, package
local loaded, preloads = rawget(original, "loaded"), rawget(original, "preload")
local native_require, loading = require, wraith.modules.loading
local same, traceback, describe = rawequal, debug.traceback, tostring

-- tables checks public tables still address the manager's captured native require state.
local function tables()
  return same(rawget(globals, "package"), original) and same(rawget(original, "loaded"), loaded)
    and same(rawget(original, "preload"), preloads)
end

-- new owns one entrypoint's preload and cache without a second package registry.
function M.new(entry)
  assert(wraith.capabilities.module_loading, "package entry binding requires native module loading; update wraith")
  assert(tables() and type(loaded) == "table" and type(preloads) == "table", "package tables were replaced; use /reload")
  local name, source = entry.name, entry.load
  local initial = rawget(preloads, name)
  assert(type(name) == "string" and type(source) == "function", "invalid package entry binding")
  assert(rawget(loaded, name) == nil, "package entry cache is foreign; use /reload: " .. name)
  assert(entry.kind == "preload" and initial == entry.identity and type(initial) == "function"
    or entry.kind == "file" and initial == nil, "package entry preload changed; use /reload: " .. name)
  local installed, running, known, cached, poisoned = false, false, false, nil, false
  local interrupted = false
  local self = {entry={name=name, kind=entry.kind, identity=entry.identity, path=entry.path, load=source}}
  local wrapper

  -- validate rejects replacement state before it can be treated as owned source output.
  local function validate()
    if running and not loading(name) then
      running, interrupted, poisoned = false, true, true
    end
    assert(not interrupted, "package entry load was interrupted; use /reload: " .. name)
    assert(tables(), "package tables were replaced; use /reload: " .. name)
    assert(not poisoned, "package entry cache is poisoned; use /reload: " .. name)
    local expected = initial
    if installed then expected = wrapper end
    assert(rawget(preloads, name) == expected, "package entry preload changed; use /reload: " .. name)
  end

  -- check permits only the recorded value or a cleared cache for the same source.
  function self.check()
    validate()
    local value = rawget(loaded, name)
    assert(value == nil or known and same(value, cached), "package entry cache is foreign; use /reload: " .. name)
  end

  wrapper = function()
    validate()
    if running then
      interrupted, poisoned = true, true
      error("package entry load was interrupted or recursive; use /reload: " .. name)
    end
    assert(installed, "package entry binding is not installed: " .. name)
    assert(loading(name), "package entry loader requires native require: " .. name)
    local marker = rawget(loaded, name)
    running = true
    local ok, value = xpcall(source, function(failure) return traceback(describe(failure), 2) end)
    running = false

    if not tables() then
      poisoned = true
      error("package tables were replaced during entry load; use /reload: " .. name)
    end
    local current = rawget(loaded, name)
    if not ok then
      if not same(current, marker) or rawget(preloads, name) ~= wrapper then poisoned = true end
      error(value, 0)
    end
    if rawget(preloads, name) ~= wrapper then
      poisoned = true
      error("package entry preload changed during load; use /reload: " .. name)
    end

    cached = current
    if same(current, marker) then
      cached = value
      if value == nil then cached = true end
    end
    known = true
    return value
  end
  self.wrapper = wrapper

  -- install publishes only the selected wrapper after rechecking untouched state.
  function self.install()
    self.check()
    if installed then return end
    rawset(preloads, name, wrapper)
    installed = true
  end

  -- require uses native caching and verifies the selected source supplied its result.
  function self.require()
    assert(installed, "package entry binding is not installed: " .. name)
    self.check()
    local value = native_require(name)
    self.check()
    assert(known and same(rawget(loaded, name), cached) and same(value, cached),
      "package entry require result is foreign; use /reload: " .. name)
    return value
  end

  return self
end

return M
