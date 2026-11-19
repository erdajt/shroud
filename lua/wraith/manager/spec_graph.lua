local fields = require("wraith.manager.spec_fields")
local fragments = require("wraith.manager.spec_fragments")
local importer = require("wraith.manager.spec_imports")
local resolver = require("wraith.manager.spec_resolution")
local M = {}

function M.normalize(input, descriptor, defaults)
  defaults = defaults == nil and {} or defaults
  assert(type(defaults) == "table", "package defaults must be a table")
  for key in pairs(defaults) do assert(key == "cond" or key == "lazy", "unknown package default: " .. tostring(key)) end
  assert(defaults.cond == nil or type(defaults.cond) == "boolean" or type(defaults.cond) == "function", "default cond must be boolean or function")
  assert(defaults.lazy == nil or type(defaults.lazy) == "boolean", "default lazy must be boolean")
  defaults = fields.copy(defaults)

  local collection = fragments.new(descriptor)
  local imports, tables = importer.new(), {}
  local count = 0
  local walk
  local function add(value, depth, origin, reference, parent)
    local spec, dependencies, scoped = collection.add(value, origin, reference, parent)
    if dependencies ~= nil then
      walk(dependencies, depth + 1, true, function(dependency)
        collection.depend(spec, dependency)
      end, origin, spec)
    end
    if scoped ~= nil then walk(scoped, depth + 1, false, nil, origin, spec) end
    return spec.name
  end

  walk = function(value, depth, reference, emit, origin, parent)
    count = count + 1
    assert(depth <= 16 and count <= 1024, "package declarations exceed nesting or entry limits")
    if type(value) == "string" then
      local name = value
      if not reference or value:find("[/:]") or value == "~" then name = add(value, depth, origin, reference, parent) end
      if emit then emit(name) end
      return
    end
    assert(type(value) == "table" and not tables[value], "invalid or cyclic package declarations")
    tables[value] = true
    local keyed = false
    for key in pairs(value) do if type(key) == "string" then keyed = true end end
    if value.import ~= nil then
      local declaration = value
      if value[1] ~= nil or value.repo ~= nil or value.url ~= nil or value.dir ~= nil then
        local fragment = {}
        for key, child in pairs(value) do if key ~= "import" then fragment[key] = child end end
        local name = add(fragment, depth, origin, reference, parent)
        if emit then emit(name) end
        declaration = {import=value.import, name=value.name, enabled=value.enabled, cond=value.cond}
      end
      imports.load(declaration, depth, reference, emit, function(child, level, dependency, receive, location)
        walk(child, level, dependency, receive, location, parent)
      end)
    elseif keyed or type(value[1]) == "string" and #value == 1 and (not reference or value[1]:find("[/:]") or value[1] == "~") then
      local name = add(value, depth, origin, reference, parent)
      if emit then emit(name) end
    else
      for _, child in ipairs(fields.array(value, "package specs", 256)) do walk(child, depth + 1, reference, emit, origin, parent) end
    end
    tables[value] = nil
  end
  walk(input, 1)
  local resolution = resolver.resolve(collection, defaults.cond)
  local by_name, declared, recipes, origins = collection.finish(resolution, defaults.lazy)

  table.sort(declared, function(left, right)
    if left.priority ~= right.priority then return left.priority > right.priority end
    return left.order < right.order
  end)
  local ordered, visited, visiting, modules, commands, keys = {}, {}, {}, {}, {}, {}
  local visit
  local function validate(spec)
    assert(not visiting[spec.name], "package dependency cycle: " .. spec.name)
    if visited[spec.name] then return end
    visiting[spec.name] = true
    for _, name in ipairs(spec.dependencies) do
      local target = by_name[name]
      assert(target, "unknown dependency " .. name .. " of " .. spec.name)
      visit(target)
    end
    visiting[spec.name], visited[spec.name] = nil, true
    assert(#ordered < 63, "enabled packages exceed 63")
    if spec.main and modules[spec.main] then
      error(fields.failure(modules[spec.main], origins[modules[spec.main]], "duplicate package main module: " .. spec.main), 0)
    end
    if spec.main then modules[spec.main] = spec.name end
    for _, command in ipairs(spec.cmd) do
      if commands[command] then
        error(fields.failure(commands[command], origins[commands[command]], "duplicate command trigger: " .. command), 0)
      end
      commands[command] = spec.name
    end
    for _, key in ipairs(spec.keys) do
      local identity = key.mode .. "\0" .. table.concat(wraith.keymap.parse(key.keys), "\0") .. "\0"
      if keys[identity] then
        error(fields.failure(keys[identity], origins[keys[identity]], "duplicate key trigger: " .. key.keys), 0)
      end
      keys[identity] = spec.name
    end
    ordered[#ordered + 1] = spec
  end
  visit = function(spec)
    local ok, failure = pcall(validate, spec)
    if not ok then error(fields.failure(spec.name, origins[spec.name], failure), 0) end
  end
  for _, spec in ipairs(declared) do visit(spec) end
  local start = {}
  for _, spec in ipairs(declared) do
    if not spec.lazy then start[#start + 1] = spec.name end
  end
  return {ordered=ordered, by_name=by_name, options=recipes, origins=origins, start=start, excluded=resolution.excluded, retain_lock=resolution.retain_lock, retain_install=resolution.retain_install}
end

return M
