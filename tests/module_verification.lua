local sources = require("wraith.manager.loader_sources")
local schema = require("wraith.manager.spec")
local root = wraith.paths.stdpath("data") .. "/module-verification"

local function fixture(name, file)
	local path = root .. "/" .. name
	wraith.fs.mkdir(path .. "/lua/" .. (file:match("^(.*)/") or ""), { parents = true })
	wraith.fs.write(path .. "/lua/" .. file, "error('verification executed source')")
	return schema.normalize({ { name = name, dir = path, lazy = true } }).by_name[name], path
end

local function rejects(call, expected)
	local ok, err = pcall(call)
	assert(not ok and tostring(err):find(expected, 1, true), tostring(err))
end

local spec, path = fixture("verify_exact", "namespace/verify.lua")
local entry = assert(wraith.modules.source(path, "namespace.verify"))
local pending = sources.prepare_module(spec, path, "selected", entry)
rejects(function()
	sources.verify(spec, path, "selected", pending)
end, "not canonical")
assert(sources.lookup(entry.name) == nil and package.preload[entry.name] == nil)
local canonical = sources.prepare_module(spec, path, "selected", entry)
sources.reserve_module(spec, path, "selected", canonical)
sources.verify(spec, path, "selected", canonical)
assert(package.loaded[entry.name] == nil and package.preload[entry.name] == canonical.wrapper)

local equal = {
	__eq = function()
		return true
	end,
}
setmetatable(pending, equal)
setmetatable(canonical, equal)
assert(pending == canonical and not rawequal(pending, canonical))
rejects(function()
	sources.verify(spec, path, "selected", pending)
end, "not canonical")
assert(package.preload[entry.name] == canonical.wrapper)
setmetatable(pending, nil)
setmetatable(canonical, nil)
rejects(function()
	sources.verify(spec, path, "changed", canonical)
end, "source changed")
rejects(function()
	sources.verify(spec, path .. "/other", "selected", canonical)
end, "source changed")

local checks = 0
package.preload.verification_probe = function()
	return true
end
local provider = wraith.modules.provider(function(name)
	if name == "verification_probe" then
		sources.verify(spec, path, "selected", canonical)
		checks = checks + 1
	end
end)
assert(require("verification_probe") and checks == 1)
wraith.modules.remove_provider(provider)
assert(package.loaded[entry.name] == nil)
wraith.fs.write(entry.path, "return 'edited local source'", { overwrite = true })
sources.verify(spec, path, "selected", canonical)
assert(canonical.require() == "edited local source")

package.loaded[entry.name] = false
rejects(function()
	sources.verify(spec, path, "selected", canonical)
end, "cache is foreign")
package.loaded[entry.name] = nil
local preload = package.preload[entry.name]
package.preload[entry.name] = function()
	error("foreign source")
end
rejects(function()
	sources.verify(spec, path, "selected", canonical)
end, "preload changed")
package.preload[entry.name] = preload
assert(os.remove(entry.path))
rejects(function()
	sources.verify(spec, path, "selected", canonical)
end, "no exact file source")
assert(sources.lookup(entry.name) == spec.name and package.preload[entry.name] == canonical.wrapper)

local dotted, dotted_path = fixture("verify-flat", "verify.flat.lua")
dotted.opts = {}
local main = sources.prepare(dotted, dotted_path)
sources.reserve(dotted, dotted_path, nil, main)
assert(wraith.modules.source(dotted_path, "verify.flat") == nil)
sources.verify(dotted, dotted_path, nil, main)
dotted.config = function() end
sources.verify(dotted, dotted_path, nil, main)
dotted.config, dotted.opts = nil, nil
sources.verify(dotted, dotted_path, nil, main)
assert(package.loaded[main.entry.name] == nil)

local drift, drift_path = fixture("verify-preferred", "verify_original.lua")
drift.opts = {}
local original = sources.prepare(drift, drift_path)
sources.reserve(drift, drift_path, nil, original)
wraith.fs.write(drift_path .. "/lua/verify_preferred.lua", "error('new preference executed')")
rejects(function()
	sources.verify(drift, drift_path, nil, original)
end, "source changed")
assert(sources.describe(drift, false).selected_main == "verify_original")

local synthetic, synthetic_path = fixture("verify_synthetic", "unused.lua")
synthetic.main, synthetic.opts = "verify_synthetic", {}
local calls = 0
package.preload.verify_synthetic = function()
	calls = calls + 1
	return {}
end
local explicit = sources.prepare(synthetic, synthetic_path)
sources.reserve(synthetic, synthetic_path, nil, explicit)
synthetic.config = function() end
sources.verify(synthetic, synthetic_path, nil, explicit)
assert(calls == 0 and explicit.entry.kind == "preload")
package.preload.verify_synthetic = function()
	error("replaced synthetic source")
end
rejects(function()
	sources.verify(synthetic, synthetic_path, nil, explicit)
end, "preload changed")
