local M = {}

-- single preserves the return count, including trailing nil, when validating a spec source.
local function single(...)
  assert(select("#", ...) == 1 and type((...)) == "table", "spec source must return exactly one table")
  return ...
end

-- new keeps import identities and contribution lists within one normalization attempt.
function M.new()
  local records, active_sources, chain = {}, {}, {}
  local imports, evaluated = 0, 0
  local self = {}

  function self.load(spec, depth, reference, emit, walk)
    for key in pairs(spec) do
      assert(key == "import" or key == "name" or key == "enabled" or key == "cond", "unknown import field: " .. tostring(key))
    end
    local source, name = spec.import, spec.name == nil and spec.import or spec.name
    assert(type(source) == "string" or type(source) == "function", "import must be a module or function")
    assert(type(name) == "string" and #name > 0 and #name <= 128 and not name:find("%c"), "function imports require a bounded name")
    for _, key in ipairs({"enabled", "cond"}) do
      assert(spec[key] == nil or type(spec[key]) == "boolean" or type(spec[key]) == "function", key .. " must be boolean or function")
    end
    if type(source) == "string" then
      assert(source ~= "shroud" and source:sub(1,7) ~= "shroud." and source ~= "wraith.manager"
        and source:sub(1,15) ~= "wraith.manager.", "manager implementation cannot be imported as specs")
    end

    local record = records[name]
    if record then
      assert(record.source == source, "conflicting import name: " .. name)
      assert(record.complete, "package import cycle: " .. table.concat(chain, " -> ") .. " -> " .. name)
      if emit then for _, package in ipairs(record.names) do emit(package) end end
      return
    end
    for _, key in ipairs({"cond", "enabled"}) do
      local gate = spec[key]
      if type(gate) == "function" then
        gate = gate()
        assert(type(gate) == "boolean", "import " .. key .. " must return boolean")
      end
      if gate == false then return end
    end

    imports = imports + 1
    assert(imports <= 128, "imports exceed 128 identities")
    record = {source=source, names={}}
    records[name], chain[#chain + 1] = record, name
    local seen = {}
    local function collect(package)
      if not seen[package] then
        seen[package], record.names[#record.names + 1] = true, package
      end
    end
    local ok, err = pcall(function()
      local sources
      if type(source) == "string" then
        assert(wraith.capabilities.modules, "module imports require host module discovery")
        sources = wraith.modules.discover(source)
        assert(#sources > 0, "no spec sources found: " .. source)
      else
        sources = {{name=name, kind="function", identity="function:" .. name .. ":" .. tostring(source), load=source}}
      end
      for _, item in ipairs(sources) do
        evaluated = evaluated + 1
        assert(evaluated <= 256, "imports exceed 256 source evaluations")
        assert(not active_sources[item.identity], "package import cycle: " .. table.concat(chain, " -> ") .. " (" .. item.name .. ")")
        active_sources[item.identity] = true
        local loaded, failure = pcall(function()
          if item.kind ~= "function" then package.loaded[item.name] = nil end
          local value = single(item.load())
          walk(value, depth + 1, reference, collect, {import=name, module=item.name, path=item.path, kind=item.kind})
        end)
        active_sources[item.identity] = nil
        if not loaded then error("source " .. (item.path or item.name) .. ": " .. tostring(failure), 0) end
      end
    end)
    chain[#chain] = nil
    if not ok then
      records[name] = nil
      error("import " .. name .. ": " .. tostring(err), 0)
    end
    record.complete = true
    if emit then for _, package in ipairs(record.names) do emit(package) end end
  end
  return self
end

return M
