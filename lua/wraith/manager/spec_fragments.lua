local fields = require("wraith.manager.spec_fields")
local schema = require("wraith.manager.spec")
local sources = require("wraith.manager.spec_source")
local options = require("wraith.manager.spec_options")
local forests = require("wraith.manager.spec_forest")
local M = {}

-- source_key compares remote suffix variants without rewriting the first selected transport.
local function source_key(source)
  if source.kind == "local" then return "local:" .. source.dir end
  local url = source.url
  if url:sub(1, 1) ~= "/" and url:sub(1, 5) ~= "file:" then
    url = url:gsub("/+$", ""):gsub("%.git$", "")
  end
  return "git:" .. url
end

-- fold rebuilds a package from one surviving contribution without evaluating callbacks.
local function fold(record, fragment)
  local raw, source = fragment.value, fragment.source
  record.dependency_only = record.dependency_only and fragment.dependency
  record.top_only = record.top_only and fragment.parent == nil
  record.optional = record.optional and raw.optional == true
  record.origins[#record.origins + 1] = fields.copy(fragment.origin)
  if source and not record.source then
    record.source = source
    if source.kind == "local" then record.raw.dir = source.dir else record.raw.url = source.url end
  end
  for _, key in ipairs({"main", "enabled", "cond", "priority", "lazy", "init", "config", "branch", "tag", "commit", "pin"}) do
    if raw[key] ~= nil then record.raw[key] = raw[key] end
  end

  if raw.opts_extend ~= nil then
    record.extend = fields.copy(raw.opts_extend)
    record.raw.opts_extend = fields.copy(raw.opts_extend)
  end
  if raw.opts ~= nil then
    record.layers[#record.layers + 1] = {value=raw.opts, extend=fields.copy(record.extend)}
    record.raw.opts = raw.opts
  end
  for _, key in ipairs({"cmd", "event"}) do
    if raw[key] ~= nil then
      record.raw[key], record.lists[key] = record.raw[key] or {}, record.lists[key] or {}
      local values = type(raw[key]) == "string" and {raw[key]} or raw[key]
      for _, item in ipairs(values) do
        if not record.lists[key][item] then
          record.lists[key][item] = true
          record.raw[key][#record.raw[key] + 1] = item
        end
      end
    end
  end
  for _, key in ipairs(raw.keys or {}) do
    local mode, sequence = key.mode or "chat.normal", key.keys or key[1]
    local identity = mode .. "\0" .. table.concat(wraith.keymap.parse(sequence), "\0") .. "\0"
    record.raw.keys = record.raw.keys or {}
    local index = record.keys[identity] or #record.raw.keys + 1
    record.keys[identity], record.raw.keys[index] = index, fields.copy(key)
  end
  for _, name in ipairs(fragment.dependencies) do
    if not record.dependency_set[name] then
      record.dependency_set[name] = true
      record.dependencies[#record.dependencies + 1] = name
    end
  end
end

-- new collects detached declarations before resolving callbacks or graph edges.
function M.new(descriptor)
  local forest, selected, cache = forests.new(), {}, {}
  local self = {order=forest.order, depend=forest.depend, remove=forest.remove}

  function self.add(value, origin, dependency, parent)
    local raw = fields.declaration(value)
    local repo = raw.repo or raw[1]
    local explicit = raw.url ~= nil or raw.dir ~= nil or type(repo) == "string" and (repo:find("[/:]") or repo == "~")
    local source, name
    if explicit then
      local basename
      source, basename = sources.normalize(raw)
      name = schema.name(raw.name == nil and basename:lower() or raw.name)
      source = schema.source(source)
      assert(not selected[name] or source_key(selected[name]) == source_key(source), "conflicting source for package " .. name)
    else
      name = schema.name(raw.name or repo)
      assert(not repo or repo == name, "name-only declaration cannot rename a package")
    end

    local dependencies, scoped = raw.dependencies, raw.specs
    raw.dependencies, raw.specs = nil, nil
    local fragment = forest.add(name, raw, origin, parent, dependency)
    fragment.source = source
    if source and not selected[name] then selected[name] = source end
    return fragment, dependencies, scoped
  end

  function self.merged(name)
    local live, revision = forest.live(name)
    local previous = cache[name]
    if previous and previous.revision == revision then return previous.record, revision end
    local record
    if #live > 0 then
      record = {name=name, raw={name=name}, dependencies={}, dependency_set={}, layers={}, extend={}, lists={}, keys={}, origins={}, dependency_only=true, top_only=true, optional=true}
      local ok, failure = pcall(function()
        for _, fragment in ipairs(live) do fold(record, fragment) end
        record.raw.dependencies = fields.copy(record.dependencies)
        record.raw.optional = record.optional
        record.layers = options.capture(record.layers)
      end)
      if not ok then error(fields.failure(name, record.origins, failure), 0) end
    end
    cache[name] = {record=record, revision=revision}
    return record, revision
  end

  function self.finish(resolution)
    local by_name, declared, recipes, origins = {}, {}, {}, {}
    for _, name in ipairs(forest.order) do self.merged(name) end
    for index, name in ipairs(forest.order) do
      local record = self.merged(name)
      if record then
        local ok, spec = pcall(function()
          assert(record.source, "package source is missing: " .. name)
          local raw, dependencies = record.raw, record.dependencies
          if resolution then
            raw = {}
            for key, value in pairs(record.raw) do raw[key] = value end
            raw.enabled = resolution.enabled[name]
            assert(type(raw.enabled) == "boolean", "missing resolved package gate: " .. name)
            dependencies = assert(resolution.dependencies[name], "missing resolved dependencies: " .. name)
            raw.dependencies = dependencies
          end
          local value = fields.normalize(raw, descriptor, record.dependency_only)
          value.dependencies, value.order = fields.copy(dependencies), index
          return value
        end)
        if not ok then error(fields.failure(name, record.origins, spec), 0) end
        recipes[name] = options.capture(record.layers)
        origins[name] = fields.copy(record.origins)
        by_name[name], declared[#declared + 1] = spec, spec
      end
    end
    return by_name, declared, recipes, origins
  end
  return self
end

return M
