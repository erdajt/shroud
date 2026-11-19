local fields = require("wraith.manager.spec_fields")
local schema = require("wraith.manager.spec")
local sources = require("wraith.manager.spec_source")
local options = require("wraith.manager.spec_options")
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

-- new collects detached declarations before resolving callbacks or graph edges.
function M.new(descriptor)
  local records, ordered, count = {}, {}, 0
  local self = {}

  function self.add(value)
    local raw = fields.declaration(value)
    count = count + 1
    assert(count <= 256, "package declarations exceed 256")
    local repo = raw.repo or raw[1]
    local explicit = raw.url ~= nil or raw.dir ~= nil or type(repo) == "string" and (repo:find("[/:]") or repo == "~")
    local source, name
    if explicit then
      local basename
      source, basename = sources.normalize(raw)
      name = schema.name(raw.name == nil and basename:lower() or raw.name)
      source = schema.source(source)
    else
      name = schema.name(raw.name or repo)
      assert(not repo or repo == name, "name-only declaration cannot rename a package")
    end

    local record = records[name]
    if not record then
      record = {name=name, raw={name=name}, dependencies={}, dependency_set={}, layers={}, extend={}, lists={}, keys={}}
      records[name], ordered[#ordered + 1] = record, record
    end
    if source then
      assert(not record.source or source_key(record.source) == source_key(source), "conflicting source for package " .. name)
      if not record.source then
        record.source = source
        if source.kind == "local" then record.raw.dir = source.dir else record.raw.url = source.url end
      end
    end
    for _, key in ipairs({"main", "enabled", "priority", "lazy", "init", "config", "branch", "tag", "commit", "pin"}) do
      if raw[key] ~= nil then record.raw[key] = raw[key] end
    end

    if raw.opts_extend ~= nil then
      record.extend = fields.copy(raw.opts_extend)
      record.raw.opts_extend = fields.copy(raw.opts_extend)
    end
    if raw.opts ~= nil then
      record.layers[#record.layers + 1] = {value=raw.opts, extend=fields.copy(record.extend)}
      record.layers = options.capture(record.layers)
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
    return record, raw.dependencies
  end

  function self.finish()
    local by_name, declared, recipes = {}, {}, {}
    for index, record in ipairs(ordered) do
      assert(record.source, "package source is missing: " .. record.name)
      record.raw.dependencies = fields.copy(record.dependencies)
      local spec = fields.normalize(record.raw, descriptor)
      spec.dependencies, spec.order = fields.copy(record.dependencies), index
      recipes[spec.name] = options.capture(record.layers)
      by_name[spec.name], declared[#declared + 1] = spec, spec
    end
    return by_name, declared, recipes
  end
  return self
end

return M
