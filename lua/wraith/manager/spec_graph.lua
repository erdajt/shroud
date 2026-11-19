local fields = require("wraith.manager.spec_fields")
local fragments = require("wraith.manager.spec_fragments")
local M = {}

function M.normalize(input, descriptor)
  local collection = fragments.new(descriptor)
  local imports, tables = {}, {}
  local count = 0
  local walk
  local function add(value, depth)
    local spec, dependencies = collection.add(value)
    if dependencies ~= nil then
      walk(dependencies, depth + 1, function(dependency)
        assert(dependency ~= spec.name, "self dependency: " .. dependency)
        if not spec.dependency_set[dependency] then
          spec.dependency_set[dependency] = true
          spec.dependencies[#spec.dependencies + 1] = dependency
        end
      end)
    end
    return spec.name
  end

  walk = function(value, depth, dependency)
    count = count + 1
    assert(depth <= 16 and count <= 1024, "package declarations exceed nesting or entry limits")
    if type(value) == "string" then
      if dependency and not value:find("[/:]") and value ~= "~" then dependency(value) else
        local name = add(value, depth)
        if dependency then dependency(name) end
      end
      return
    end
    assert(type(value) == "table" and not tables[value], "invalid or cyclic package declarations")
    tables[value] = true
    local keyed = false
    for key in pairs(value) do if type(key) == "string" then keyed = true end end
    if value.import ~= nil then
      for key in pairs(value) do assert(key == "import", "import cannot contain package fields") end
      local module = value.import
      assert(type(module) == "string" and #module <= 128 and module:match("^[A-Za-z0-9_-]+[A-Za-z0-9_.-]*$") and not module:find("..", 1, true), "invalid package import")
      assert(not imports[module], "package import cycle: " .. module)
      imports[module] = true
      walk(require(module), depth + 1, dependency)
      imports[module] = nil
    elseif keyed or type(value[1]) == "string" and #value == 1 and (not dependency or value[1]:find("[/:]") or value[1] == "~") then
      local name = add(value, depth)
      if dependency then dependency(name) end
    else
      for _, child in ipairs(fields.array(value, "package specs", 256)) do walk(child, depth + 1, dependency) end
    end
    tables[value] = nil
  end
  walk(input, 1)
  local by_name, declared, recipes = collection.finish()

  table.sort(declared, function(left, right)
    if left.priority ~= right.priority then return left.priority > right.priority end
    return left.order < right.order
  end)
  local ordered, visited, visiting, modules, commands, keys = {}, {}, {}, {}, {}, {}
  local function visit(spec)
    assert(not visiting[spec.name], "package dependency cycle: " .. spec.name)
    if visited[spec.name] then return end
    visiting[spec.name] = true
    for _, name in ipairs(spec.dependencies) do
      local target = by_name[name]
      assert(target, "unknown dependency " .. name .. " of " .. spec.name)
      assert(not spec.enabled or target.enabled, "enabled package " .. spec.name .. " depends on disabled " .. name)
      visit(target)
    end
    visiting[spec.name], visited[spec.name] = nil, true
    if not spec.enabled then return end
    assert(#ordered < 63, "enabled packages exceed 63")
    assert(not modules[spec.main], "duplicate package main module: " .. spec.main)
    modules[spec.main] = spec.name
    for _, command in ipairs(spec.cmd) do
      assert(not commands[command], "duplicate command trigger: " .. command)
      commands[command] = spec.name
    end
    for _, key in ipairs(spec.keys) do
      local identity = key.mode .. "\0" .. table.concat(wraith.keymap.parse(key.keys), "\0") .. "\0"
      assert(not keys[identity], "duplicate key trigger: " .. key.keys)
      keys[identity] = spec.name
    end
    ordered[#ordered + 1] = spec
  end
  for _, spec in ipairs(declared) do visit(spec) end
  return {ordered=ordered, by_name=by_name, options=recipes}
end

return M
