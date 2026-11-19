local M = {}
local fields = require("wraith.manager.spec_fields")

-- normalized compares package and module names without host-specific suffixes.
local function normalized(name)
  return name:lower():gsub("^wraith%-", ""):gsub("%.wraith$", "")
    :gsub("%.lua$", ""):gsub("%-lua$", ""):gsub("[^a-z0-9]", "")
end

-- select resolves setup metadata without exposing paths or executing an entrypoint.
function M.select(spec, path, owned)
  assert(wraith.api_version >= 2 and wraith.capabilities.module_sources,
    "package entry selection requires host module sources; update wraith")
  local preloads = rawget(package, "preload")
  assert(type(preloads) == "table", "package preload table was replaced; use /reload")
  local entry
  if spec.main ~= nil then
    local name = fields.main(spec.main)
    local preload = rawget(preloads, name)
    if owned then
      assert(owned.entry.name == name and preload == owned.wrapper,
        "package entry binding changed; use /reload: " .. spec.name)
      if owned.entry.kind == "preload" then return owned.entry end
    end
    if preload ~= nil and not owned then
      assert(type(preload) == "function", "package " .. spec.name .. " has an invalid preload: " .. name)
      return {name=name, kind="preload", identity=preload, load=function() return preload(name) end}
    end
    entry = wraith.modules.source(path, name)
    assert(entry, "package " .. spec.name .. " has no entry " .. name .. " in " .. path .. "; set main or config")
  else
    local candidates = wraith.modules.catalog(path)
    local matches, names = {}, {}
    for _, candidate in ipairs(candidates) do
      if normalized(candidate.name) == normalized(spec.name) then matches[#matches + 1] = candidate end
      if #names < 8 then names[#names + 1] = candidate.name end
    end
    if #matches == 1 then entry = matches[1]
    elseif #matches == 0 and #candidates == 1 then entry = candidates[1] end
    if #candidates > #names then names[#names + 1] = "..." end
    assert(entry, "package " .. spec.name .. " cannot infer main in " .. path
      .. " (candidates: " .. (#names == 0 and "none" or table.concat(names, ", ")) .. "); set main or config")
    fields.main(entry.name)
    local preload = rawget(preloads, entry.name)
    assert(owned or preload == nil, "package " .. spec.name .. " inferred main " .. entry.name
      .. " has a preload; set explicit main for an intentional override")
  end
  if owned then
    assert(owned.entry.name == entry.name and rawget(preloads, entry.name) == owned.wrapper
      and owned.entry.identity == entry.identity,
      "package entry source changed; use /reload: " .. spec.name)
    return owned.entry
  end
  return entry
end

return M
