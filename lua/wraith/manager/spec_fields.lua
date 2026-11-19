local M = {}
local sources = require("wraith.manager.spec_source")
local specification = require("wraith.manager.spec")
local allowed = {name=true, repo=true, url=true, dir=true, main=true, dependencies=true, enabled=true,
  priority=true, lazy=true, cmd=true, event=true, keys=true, init=true, opts=true, config=true,
  branch=true, tag=true, commit=true, pin=true, opts_extend=true}

function M.array(value, label, limit)
  assert(type(value) == "table", label .. " must be an array")
  local count = 0
  for key in pairs(value) do
    assert(type(key) == "number" and key % 1 == 0 and key >= 1 and key <= #value, label .. " must be consecutive")
    count = count + 1
  end
  assert(count == #value and count <= limit, label .. " exceeds its limit")
  return value
end

function M.copy(value)
  local active, count = {}, 0
  local function visit(item, depth)
    if type(item) ~= "table" then return item end
    assert(depth <= 16 and not active[item], "package options contain a cycle or exceed depth 16")
    active[item] = true
    local result = {}
    for key, child in pairs(item) do
      count = count + 1
      assert(count <= 4096 and (type(key) == "string" or type(key) == "number"), "package options exceed their limit or contain invalid keys")
      result[key] = visit(child, depth + 1)
    end
    active[item] = nil
    return result
  end
  return visit(value, 1)
end

-- failure retains bounded configuration origins after the import stack has unwound.
function M.failure(name, origins, failure)
  local lines = {tostring(failure):sub(1,4096), "package " .. name .. " declared at:"}
  local seen = {}
  for index, origin in ipairs(origins or {}) do
    if index <= 4 or index > #origins - 4 then
      local location = origin.module and ((origin.import or origin.module) .. ": " .. origin.module) or "fragment " .. origin.index
      if origin.path then location = location .. " (" .. origin.path .. ")" end
      if not seen[location] then
        seen[location] = true
        lines[#lines + 1] = location:sub(1,384)
      end
    elseif index == 5 then
      lines[#lines + 1] = "additional origins omitted"
    end
  end
  return table.concat(lines, "\n"):sub(1,8192)
end

local function strings(value, label)
  if value == nil then return {} end
  if type(value) == "string" then value = {value} end
  local result, seen = {}, {}
  for _, item in ipairs(M.array(value, label, 64)) do
    assert(type(item) == "string" and #item > 0 and #item <= 128 and not item:find("%c"), "invalid " .. label)
    assert(not seen[item], "duplicate " .. label .. ": " .. item)
    seen[item], result[#result + 1] = true, item
  end
  return result
end

-- main validates an explicit or inferred entry module.
local function main(value)
  assert(type(value) == "string" and #value <= 128 and value:match("^[A-Za-z0-9_-]+[A-Za-z0-9_.-]*$") and not value:find("..", 1, true) and value:sub(-1) ~= ".", "invalid package main module")
  assert(value ~= "wraith.manager" and value:sub(1, 15) ~= "wraith.manager.", "manager module namespace is reserved")
  return value
end

-- triggers validates declarations and resolves defaults only for the final package identity.
local function triggers(value, name)
  local commands, events, keys = strings(value.cmd, "command trigger"), strings(value.event, "event trigger"), {}
  local seen = {}
  for _, command in ipairs(commands) do
    assert(#command <= 80 and command:match("^[a-z][a-z0-9.%-]*!?$") and not command:find("..", 1, true) and not command:find("%.!*$"), "invalid command trigger: " .. command)
    for segment in command:gsub("!$", ""):gmatch("[^.]+") do
      assert(segment:match("^[a-z0-9][a-z0-9%-]*$"), "invalid command trigger segment: " .. command)
    end
  end
  for _, event in ipairs(events) do wraith.events.listeners(event) end
  for _, key in ipairs(M.array(value.keys == nil and {} or value.keys, "key triggers", 64)) do
    assert(type(key) == "table", "key trigger requires explicit keys and action")
    for field in pairs(key) do
      assert(field == 1 or field == 2 or field == "keys" or field == "action" or field == "mode" or field == "desc" or field == "description", "unknown key trigger field")
    end
    assert(not (key[1] ~= nil and key.keys ~= nil) and not (key[2] ~= nil and key.action ~= nil) and not (key.desc ~= nil and key.description ~= nil), "duplicate key trigger fields")
    local mapping = {keys=key.keys == nil and key[1] or key.keys, action=key.action == nil and key[2] or key.action, mode=key.mode == nil and "chat.normal" or key.mode, description=key.description == nil and (key.desc == nil and "load " .. name or key.desc) or key.description}
    assert(type(mapping.keys) == "string" and #mapping.keys > 0 and #mapping.keys <= 256 and not mapping.keys:find("%c"), "invalid key trigger keys")
    assert(type(mapping.action) == "function" or type(mapping.action) == "string" and #mapping.action > 0 and #mapping.action <= 256, "key trigger requires an explicit action or function")
    assert(type(mapping.mode) == "string" and type(mapping.description) == "string", "invalid key trigger mode or description")
    wraith.keymap.validate(mapping.mode, mapping.keys)
    local identity = mapping.mode .. "\0" .. table.concat(wraith.keymap.parse(mapping.keys), "\0")
    assert(not seen[identity], "duplicate key trigger: " .. mapping.keys)
    seen[identity], keys[#keys + 1] = true, mapping
  end
  return commands, events, keys
end

-- revision validates raw selectors before later declarations can replace them.
local function revision(value)
  local selected, count = {kind="head"}, 0
  for _, kind in ipairs({"branch", "tag", "commit"}) do
    if value[kind] ~= nil then selected, count = {kind=kind, value=value[kind]}, count + 1 end
  end
  assert(count <= 1, "choose one branch, tag or commit")
  return specification.selector(selected)
end

-- declaration validates a raw fragment without evaluating callbacks or traversing dependencies.
function M.declaration(value)
  if type(value) == "string" then value = {repo=value} end
  assert(type(value) == "table", "package spec must be a table or repository")
  local detached = {}
  for key, child in pairs(value) do
    assert(key == 1 or allowed[key], "unknown package field: " .. tostring(key))
    if key ~= "dependencies" then detached[key] = child end
  end
  if value.name ~= nil then specification.name(value.name) end
  assert(value.pin == nil or type(value.pin) == "boolean", "pin must be boolean")
  local selected = revision(value)
  local repo = value.repo == nil and value[1] or value.repo
  if value.url ~= nil or value.dir ~= nil or repo ~= nil then
    assert(value[1] == nil or value.repo == nil, "choose one repository field")
    if value.url == nil and value.dir == nil and type(repo) == "string" and not repo:find("[/:]") and repo ~= "~" then
      specification.name(repo)
      assert(value.name == nil or value.name == repo, "name-only declaration cannot rename a package")
    else
      local source = specification.source(sources.normalize(value))
      assert(source.kind ~= "local" or selected.kind == "head" and not value.pin, "local packages cannot select or pin git revisions")
    end
  else
    assert(value.name ~= nil, "package override requires a name or source")
  end
  if value.main ~= nil then main(value.main) end
  assert(value.enabled == nil or type(value.enabled) == "boolean" or type(value.enabled) == "function", "enabled must be boolean or function")
  assert(value.priority == nil or type(value.priority) == "number" and value.priority % 1 == 0 and math.abs(value.priority) <= 1000000, "priority must be an integer within 1000000")
  assert(value.lazy == nil or type(value.lazy) == "boolean", "lazy must be boolean")
  assert(value.init == nil or type(value.init) == "function", "init must be a function")
  assert(value.config == nil or type(value.config) == "boolean" or type(value.config) == "function", "config must be boolean or function")
  assert(value.dependencies == nil or type(value.dependencies) == "table" or type(value.dependencies) == "string", "dependencies must be declarations or a package name")
  require("wraith.manager.spec_options").capture({{value=value.opts, extend=value.opts_extend}})
  triggers(value, value.name or "package")

  detached = M.copy(detached)
  detached.dependencies = value.dependencies
  return detached
end

-- normalize resolves one validated merged declaration and evaluates enabled once.
function M.normalize(value, descriptor, dependency)
  value = M.declaration(value)
  local source, basename = sources.normalize(value)
  local result = descriptor({name=value.name == nil and basename:lower() or value.name, source=source, selector=revision(value), pin=value.pin})
  result.main = main(value.main == nil and basename or value.main)
  result.priority = value.priority == nil and 50 or value.priority
  result.init, result.opts, result.config = value.init, M.copy(value.opts), value.config
  result.opts_extend = M.copy(value.opts_extend)
  result.cmd, result.event, result.keys = triggers(value, result.name)
  result.lazy = value.lazy
  if result.lazy == nil then result.lazy = dependency == true or #result.cmd + #result.event + #result.keys > 0 end

  result.enabled = value.enabled ~= false
  if type(value.enabled) == "function" then
    result.enabled = value.enabled(M.copy(value))
    assert(type(result.enabled) == "boolean", "enabled must return boolean")
  end
  return result
end

return M
