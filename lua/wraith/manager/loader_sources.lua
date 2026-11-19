local M, selected = {}, {}
local entries = require("wraith.manager.loader_entry")
local bindings = require("wraith.manager.loader_binding")

-- automatic distinguishes default setup from libraries and user-owned configuration.
function M.automatic(spec)
  return type(spec.config) ~= "function" and (spec.config or spec.opts ~= nil)
end

-- claim checks resolved entry ownership without reserving unused library names.
local function claim(package_name, main)
  if main == nil then return end
  for name, identity in pairs(selected) do
    assert(name == package_name or not identity.binding or identity.binding.entry.name ~= main,
      "package main was already selected by " .. name .. "; use /reload: " .. main)
  end
end

-- capacity derives the lifetime bound from reservations rather than a separate counter.
local function capacity(name)
  if selected[name] then return end
  local count = 0
  for _ in pairs(selected) do count = count + 1 end
  assert(count < 63, "package source identities exceed runtime capacity; use /reload")
end

-- module caches and runtime paths survive package unload, so source identities do too.
function M.check(spec, path, commit)
  local prior = selected[spec.name]
  if prior then
    local source = spec.source
    assert(prior.requested_main == spec.main and prior.path == path and prior.commit == commit
      and prior.kind == source.kind and prior.url == source.url and prior.dir == source.dir,
      "package source changed in this runtime; use /reload: " .. spec.name)
  end
  if M.automatic(spec) then claim(spec.name, spec.main) end
end

-- prepare selects and checks an entry without exposing its wrapper or runtime path.
function M.prepare(spec, path, commit)
  M.check(spec, path, commit)
  local prior = selected[spec.name]
  capacity(spec.name)
  if not M.automatic(spec) then return end
  local owned = prior and prior.binding
  local entry = entries.select(spec, path, owned, function(main) claim(spec.name, main) end)
  if owned then owned.check(); return owned end
  return bindings.new(entry)
end

-- reserve revalidates dependency effects and pins every source before exposing its path.
function M.reserve(spec, path, commit, binding)
  M.check(spec, path, commit)
  local prior = selected[spec.name]
  capacity(spec.name)
  if M.automatic(spec) then
    assert(binding, "package entry was not prepared: " .. spec.name)
    local entry = entries.select(spec, path, prior and prior.binding, function(main) claim(spec.name, main) end)
    assert(entry.name == binding.entry.name and entry.kind == binding.entry.kind
      and entry.identity == binding.entry.identity,
      "package entry changed during dependency activation; use /reload: " .. spec.name)
    binding.check()
  end

  if not prior then
    local source = spec.source
    prior = {requested_main=spec.main, path=path, commit=commit, kind=source.kind, url=source.url, dir=source.dir}
    selected[spec.name] = prior
  end
  if binding then
    prior.binding = binding
    binding.install()
  end
end

-- require loads the entry reserved for this package rather than searching global paths.
function M.require(name)
  local prior = selected[name]
  assert(prior and prior.binding, "package entry is not bound: " .. name)
  return prior.binding.require()
end

-- describe exposes scalar provenance separately from current activation state.
function M.describe(spec, active)
  local prior = selected[spec.name]
  local entry = prior and prior.binding and prior.binding.entry
  return {
    requested_main=spec.main,
    selected_main=entry and entry.name,
    loaded_main=active and M.automatic(spec) and entry and entry.name or nil,
    main_source_kind=entry and entry.kind,
    main_source_path=entry and entry.path,
  }
end

return M
