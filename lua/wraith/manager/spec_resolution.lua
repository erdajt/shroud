local fields = require("wraith.manager.spec_fields")
local M = {}

-- resolve removes inactive fragment scopes before final source and graph validation.
function M.resolve(collection, default_cond)
  local records, revisions, known, decisions = {}, {}, {}, {}
  local excluded, retain_lock, retain_install, conditional, calls = {}, {}, {}, {}, 0
  for _, name in ipairs(collection.order) do
    known[name] = true
    records[name], revisions[name] = collection.merged(name)
  end

  local function evaluate(name, record, gate, names, label)
    if type(gate) ~= "function" then return gate ~= false end
    local ok, result = pcall(function()
      calls = calls + 1
      assert(calls <= 1024, "package gate evaluations exceed 1024")
      local snapshot = {}
      for key, value in pairs(record.raw) do snapshot[key] = value end
      snapshot.dependencies = names
      local value = gate(fields.copy(snapshot))
      assert(type(value) == "boolean", label .. " must return boolean")
      return value
    end)
    if not ok then error(fields.failure(name, record.origins, result), 0) end
    return result
  end

  for _, name in ipairs(collection.order) do
    local record = records[name]
    if record then
      local condition = record.raw.cond
      if condition == nil then condition = default_cond end
      if not evaluate(name, record, condition, record.dependencies, "cond") then
        conditional[name] = true
        local stack = {name}
        while #stack > 0 do
          local current = table.remove(stack)
          if records[current] and not retain_install[current] then
            retain_install[current], retain_lock[current] = true, true
            for _, dependency in ipairs(records[current].dependencies) do stack[#stack + 1] = dependency end
          end
        end
      end
    end
  end

  local function dependencies(record)
    local names = {}
    for _, name in ipairs(record.dependencies) do
      if not known[name] or records[name] then names[#names + 1] = name end
    end
    return names
  end

  local function remove(name, reason)
    if reason == "disabled" and not records[name].optional then retain_lock[name] = true end
    for _, changed in ipairs(collection.remove(name)) do
      local previous = records[changed]
      records[changed], revisions[changed] = collection.merged(changed)
      if not records[changed] then
        excluded[changed] = {name=changed, reason=changed == name and reason or "scope", origins=fields.copy(previous.origins)}
      end
    end
  end

  while true do
    local removed = false
    for _, top in ipairs({true, false}) do
      for _, name in ipairs(collection.order) do
        local record = records[name]
        if record and record.top_only == top then
          local names = dependencies(record)
          local signature = table.concat(names, "\0")
          local decision = decisions[name]
          if not decision or decision.revision ~= revisions[name] or decision.dependencies ~= signature then
            local enabled = not conditional[name] and evaluate(name, record, record.raw.enabled, names, "enabled")
            decision = {revision=revisions[name], dependencies=signature, enabled=enabled}
            decisions[name] = decision
          end
          if not decision.enabled then
            remove(name, conditional[name] and "conditional" or "disabled")
            removed = true
            break
          end
        end
      end
      if removed then break end
    end

    if not removed then
      for _, name in ipairs(collection.order) do
        if records[name] and records[name].optional then
          remove(name, "optional")
          removed = true
          break
        end
      end
    end
    if not removed then break end
  end

  local enabled, resolved = {}, {}
  for _, name in ipairs(collection.order) do
    if records[name] then
      enabled[name], resolved[name] = true, dependencies(records[name])
    end
  end
  return {enabled=enabled, dependencies=resolved, excluded=excluded, retain_lock=retain_lock, retain_install=retain_install}
end

return M
