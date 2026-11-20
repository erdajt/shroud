local M, selected, modules = {}, {}, {}
local entries = require("wraith.manager.loader_entry")
local bindings = require("wraith.manager.loader_binding")
local fields = require("wraith.manager.spec_fields")

-- automatic distinguishes default setup from libraries and user-owned configuration.
function M.automatic(spec)
	return type(spec.config) ~= "function" and (spec.config or spec.opts ~= nil)
end

-- lookup returns the sole binding for a module without exposing package identity records.
function M.lookup(name)
	local record = modules[name]
	if record then
		return record.package, record.binding
	end
end

-- claim checks ownership and returns an existing same-package binding.
local function claim(package_name, name)
	if name == nil then
		return
	end

	local record = modules[name]
	assert(
		not record or record.package == package_name,
		"package module was already selected by " .. (record and record.package or "") .. "; use /reload: " .. name
	)
	return record and record.binding
end

-- capacity derives both lifetime bounds from published reservations.
local function capacity(name, main)
	if not selected[name] then
		local count = 0
		for _ in pairs(selected) do
			count = count + 1
		end
		assert(count < 63, "package source identities exceed runtime capacity; use /reload")
	end

	if main and not modules[main] then
		local count = 0
		for _ in pairs(modules) do
			count = count + 1
		end
		assert(count < 1024, "package module identities exceed runtime capacity; use /reload")
	end
end

-- check pins package provenance across module loads and configuration changes.
function M.check(spec, path, commit)
	local prior = selected[spec.name]
	if prior then
		local source = spec.source
		assert(
			prior.requested_main == spec.main
				and prior.path == path
				and prior.commit == commit
				and prior.kind == source.kind
				and prior.url == source.url
				and prior.dir == source.dir,
			"package source changed in this runtime; use /reload: " .. spec.name
		)
	end

	if M.automatic(spec) then
		claim(spec.name, spec.main)
	end
end

-- matching compares prepared metadata before adopting a later canonical reservation.
local function matching(prepared, entry, name)
	assert(
		prepared
			and entry
			and entry.name == prepared.name
			and entry.kind == prepared.kind
			and entry.identity == prepared.identity
			and entry.path == prepared.path,
		"package entry changed during dependency activation; use /reload: " .. name
	)
end

-- prepare_entry reuses canonical ownership without publishing a fresh wrapper.
local function prepare_entry(spec, entry)
	fields.main(entry.name)
	capacity(spec.name, entry.name)

	local owned = claim(spec.name, entry.name)
	if owned then
		matching(owned.entry, entry, spec.name)
		owned.check()
		return owned
	end

	return bindings.new(entry)
end

-- publish records all ownership before an installation can expose its wrapper.
local function publish(spec, path, commit, prepared, entry, main)
	M.check(spec, path, commit)
	capacity(spec.name, entry and entry.name)

	local prior, canonical = selected[spec.name], prepared
	if entry then
		fields.main(entry.name)
		matching(prepared and prepared.entry, entry, spec.name)
		canonical = claim(spec.name, entry.name) or prepared
		matching(canonical.entry, entry, spec.name)
		canonical.check()
	end
	assert(
		not main or not prior or not prior.main or prior.main == main,
		"package main changed in this runtime; use /reload: " .. spec.name
	)

	if not prior then
		local source = spec.source
		prior = {
			requested_main = spec.main,
			path = path,
			commit = commit,
			kind = source.kind,
			url = source.url,
			dir = source.dir,
		}
		selected[spec.name] = prior
	end
	if entry then
		modules[entry.name] = { package = spec.name, binding = canonical }
	end
	if main then
		prior.main = main
	end

	if canonical then
		canonical.install()
	end
	return canonical
end

-- prepare selects an automatic main without exposing its wrapper or runtime path.
function M.prepare(spec, path, commit)
	M.check(spec, path, commit)
	capacity(spec.name)
	if not M.automatic(spec) then
		return
	end

	local prior = selected[spec.name]
	local owned = prior and prior.main and claim(spec.name, prior.main)
	local entry = entries.select(spec, path, owned, function(main)
		return claim(spec.name, main)
	end)
	return prepare_entry(spec, entry)
end

-- reserve reselects catalog metadata without confusing physical dotted files with nested modules.
function M.reserve(spec, path, commit, binding)
	M.check(spec, path, commit)
	if not M.automatic(spec) then
		return publish(spec, path, commit)
	end

	local prior = selected[spec.name]
	local owned = prior and prior.main and claim(spec.name, prior.main)
	local entry = entries.select(spec, path, owned, function(main)
		return claim(spec.name, main)
	end)
	return publish(spec, path, commit, binding, entry, entry.name)
end

-- prepare_module selects only an exact file source for a requested module.
function M.prepare_module(spec, path, commit, entry)
	M.check(spec, path, commit)
	fields.main(entry.name)

	local current = wraith.modules.source(path, entry.name)
	assert(entry.kind == "file" and current, "package requested module has no exact file source: " .. entry.name)
	matching(entry, current, spec.name)
	return prepare_entry(spec, current)
end

-- reserve_module adopts any equivalent binding exposed during dependency activation.
function M.reserve_module(spec, path, commit, binding)
	M.check(spec, path, commit)
	fields.main(binding.entry.name)

	local entry = wraith.modules.source(path, binding.entry.name)
	assert(
		binding.entry.kind == "file" and entry,
		"package requested module has no exact file source: " .. binding.entry.name
	)
	return publish(spec, path, commit, binding, entry)
end

-- verify rechecks canonical source metadata without publishing or executing a module.
function M.verify(spec, path, commit, binding)
	M.check(spec, path, commit)
	local prior = selected[spec.name]
	local name = binding.entry.name
	local record = modules[name]
	assert(
		prior and record and record.package == spec.name and rawequal(record.binding, binding),
		"package module binding is not canonical; use /reload: " .. name
	)

	local entry
	if prior.main == name then
		entry = entries.select(spec, path, binding, function(main)
			return claim(spec.name, main)
		end)
	else
		entry = wraith.modules.source(path, name)
		assert(entry, "package requested module has no exact file source: " .. name)
	end
	matching(binding.entry, entry, spec.name)
	binding.check()
end

-- require follows the package's pinned main through the module ledger.
function M.require(name)
	local prior = selected[name]
	local binding = prior and prior.main and claim(name, prior.main)
	assert(binding, "package entry is not bound: " .. name)
	return binding.require()
end

-- describe exposes scalar provenance separately from current activation state.
function M.describe(spec, active)
	local prior = selected[spec.name]
	local binding = prior and prior.main and claim(spec.name, prior.main)
	local entry = binding and binding.entry
	return {
		requested_main = spec.main,
		selected_main = entry and entry.name,
		loaded_main = active and M.automatic(spec) and entry and entry.name or nil,
		main_source_kind = entry and entry.kind,
		main_source_path = entry and entry.path,
	}
end

return M
