local fields = require("wraith.manager.spec_fields")
local sources = require("wraith.manager.spec_source")
local M = {}

-- settings validates detached development defaults before declarations can run callbacks.
function M.settings(value)
  value = value == nil and {} or value
  assert(type(value) == "table", "development settings must be a table")
  for key in pairs(value) do
    assert(key == "path" or key == "patterns" or key == "fallback", "unknown development setting: " .. tostring(key))
  end
  local path = value.path == nil and "~/projects" or value.path
  assert(type(path) == "string" or type(path) == "function", "development path must be a string or function")
  if type(path) == "string" then path = sources.local_path(path) end
  assert(value.fallback == nil or type(value.fallback) == "boolean", "development fallback must be boolean")

  local patterns = {}
  for _, pattern in ipairs(fields.array(value.patterns == nil and {} or value.patterns, "development patterns", 64)) do
    assert(type(pattern) == "string" and #pattern > 0 and #pattern <= 4096 and not pattern:find("%c"), "invalid development pattern")
    patterns[#patterns + 1] = pattern
  end
  return {path=path, patterns=patterns, fallback=value.fallback == true}
end

-- select separates declared revision intent from the directory used for activation.
function M.select(record, settings, budget)
  local raw, declared = record.raw, record.source
  local result = {source=fields.copy(declared), dev=raw.dev, declared_source=fields.copy(declared),
    declared_selector=fields.copy(record.selector), declared_pin=raw.pin == true}
  if raw.dir ~= nil or declared and declared.kind == "local" then
    result.dir = sources.local_path(raw.dir or declared.dir)
    result.source = {kind="local", dir=result.dir}
    return result
  end
  if not declared then return result end

  if result.dev == nil then
    for _, pattern in ipairs(settings.patterns) do
      if declared.url:find(pattern, 1, true) then result.dev = true; break end
    end
  end
  if result.dev ~= true then return result end

  local path = settings.path
  if type(path) == "function" then
    local snapshot = {}
    for key, value in pairs(raw) do snapshot[key] = value end
    snapshot.name, snapshot.url, snapshot.dev, snapshot.dir = record.name, declared.url, true, nil
    snapshot = fields.copy(snapshot)
    if budget then
      assert(budget.calls < 1024, "development path evaluations exceed 1024")
      budget.calls = budget.calls + 1
    end
    path = path(snapshot)
  else
    path = path .. "/" .. record.name
  end
  path = sources.local_path(path)
  if settings.fallback then
    local info = wraith.fs.stat(path, {follow=true, missing_ok=true})
    if not info.exists or info.type ~= "directory" then
      result.dev = false
      return result
    end
  end
  result.source, result.dir = {kind="local", dir=path}, path
  return result
end

return M
