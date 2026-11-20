local sources = require("wraith.manager.loader_sources")
local schema = require("wraith.manager.spec")
local root = wraith.paths.stdpath("data") .. "/module-ledger"

local function rejects(call, expected)
	local ok, err = pcall(call)
	assert(not ok and tostring(err):find(expected, 1, true), tostring(err))
end

local function fixture(name, files)
	local path = root .. "/" .. name
	for file, content in pairs(files) do
		local parent = file:match("(.+)/[^/]+$")
		wraith.fs.mkdir(path .. "/" .. parent, { parents = true })
		wraith.fs.write(path .. "/" .. file, content)
	end
	local spec = schema.normalize({ { name = name, dir = path, lazy = true } }).by_name[name]
	return spec, path
end

local function prepare(spec, path, name)
	return sources.prepare_module(spec, path, nil, assert(wraith.modules.source(path, name)))
end

local spec, path = fixture("ledger_owner", {
	["lua/ledger_owner.lua"] = "return {setup=function() end}",
	["lua/ledger_extra.lua"] = "return 42",
})
local extra = prepare(spec, path, "ledger_extra")
assert(sources.reserve_module(spec, path, nil, extra) == extra)
local owner, canonical = sources.lookup("ledger_extra")
assert(owner == spec.name and canonical == extra and extra.require() == 42)
assert(sources.describe(spec, true).selected_main == nil)

local main = prepare(spec, path, "ledger_owner")
sources.reserve_module(spec, path, nil, main)
spec.opts = {}
assert(sources.prepare(spec, path) == main and sources.reserve(spec, path, nil, main) == main)
assert(sources.describe(spec, true).loaded_main == "ledger_owner")

spec.config = function() end
sources.reserve(spec, path)
assert(sources.describe(spec, true).selected_main == "ledger_owner" and sources.describe(spec, true).loaded_main == nil)
spec.config = nil
assert(sources.prepare(spec, path) == main)

local first, first_path = fixture("ledger_first", { ["lua/ledger_first.lua"] = "return {setup=function() end}" })
first.opts = {}
local automatic = sources.prepare(first, first_path)
sources.reserve(first, first_path, nil, automatic)
assert(prepare(first, first_path, "ledger_first") == automatic)

for _, mode in ipairs({ "automatic", "requested" }) do
	local name = "ledger_late_" .. mode
	local late, late_path = fixture(name, { ["lua/" .. name .. ".lua"] = "return {setup=function() end}" })
	if mode == "automatic" then
		late.opts = {}
	end
	local a = prepare(late, late_path, name)
	local b = prepare(late, late_path, name)
	assert(a ~= b)
	assert(sources.reserve_module(late, late_path, nil, b) == b)
	local adopted
	if mode == "automatic" then
		adopted = sources.reserve(late, late_path, nil, a)
	else
		adopted = sources.reserve_module(late, late_path, nil, a)
	end
	local package_name, current = sources.lookup(name)
	assert(adopted == b and current == b and package_name == name and package.preload[name] == b.wrapper)
end

local left, left_path = fixture("ledger_left", { ["lua/ledger_shared.lua"] = "return true" })
local right, right_path = fixture("ledger_right", { ["lua/ledger_shared.lua"] = "return true" })
local losing, winning = prepare(left, left_path, "ledger_shared"), prepare(right, right_path, "ledger_shared")
sources.reserve_module(right, right_path, nil, winning)
rejects(function()
	sources.reserve_module(left, left_path, nil, losing)
end, "already selected")
assert(sources.lookup("ledger_shared") == right.name and sources.describe(left, false).selected_main == nil)

local pinned, pinned_path =
	fixture("ledger_preferred", { ["lua/ledger_original.lua"] = "return {setup=function() end}" })
pinned.opts = {}
local original = sources.prepare(pinned, pinned_path)
sources.reserve(pinned, pinned_path, nil, original)
wraith.fs.write(pinned_path .. "/lua/ledger_preferred.lua", "return {setup=function() end}")
local preferred = prepare(pinned, pinned_path, "ledger_preferred")
sources.reserve_module(pinned, pinned_path, nil, preferred)
rejects(function()
	sources.prepare(pinned, pinned_path)
end, "entry source changed")
assert(sources.describe(pinned, false).selected_main == "ledger_original")

local dotted, dotted_path = fixture("ledger-dotted", { ["lua/ledger.dotted.lua"] = "return {setup=function() end}" })
dotted.opts = {}
local flat = sources.prepare(dotted, dotted_path)
sources.reserve(dotted, dotted_path, nil, flat)
assert(sources.require(dotted.name).setup and flat.entry.path == dotted_path .. "/lua/ledger.dotted.lua")
assert(wraith.modules.source(dotted_path, "ledger.dotted") == nil)

local interrupted, interrupted_path = fixture("ledger_interrupted", { ["lua/ledger_interrupted.lua"] = "return true" })
local pending = prepare(interrupted, interrupted_path, "ledger_interrupted")
local install = pending.install
pending.install = function()
	install()
	error("publication interrupted")
end
rejects(function()
	sources.reserve_module(interrupted, interrupted_path, nil, pending)
end, "publication interrupted")
pending.install = install
local kept_owner, kept_binding = sources.lookup("ledger_interrupted")
assert(kept_owner == interrupted.name and kept_binding == pending)
assert(prepare(interrupted, interrupted_path, "ledger_interrupted") == pending)
assert(sources.reserve_module(interrupted, interrupted_path, nil, pending) == pending)
rejects(function()
	sources.prepare_module(interrupted, interrupted_path, "changed", pending.entry)
end, "source changed")

local main_before = interrupted.main
interrupted.main = "elsewhere"
rejects(function()
	sources.check(interrupted, interrupted_path)
end, "source changed")
interrupted.main = main_before

for _, explicit in ipairs({ false, true }) do
	local name = "ledger_before_" .. tostring(explicit)
	local retry, retry_path = fixture(name, { ["lua/" .. name .. ".lua"] = "return {setup=function() end}" })
	retry.opts = {}
	if explicit then
		retry.main = name
	end
	local held = sources.prepare(retry, retry_path)
	local original_install = held.install
	held.install = function()
		error("before installation")
	end
	rejects(function()
		sources.reserve(retry, retry_path, nil, held)
	end, "before installation")
	held.install = original_install
	assert(package.preload[name] == nil and sources.describe(retry, false).selected_main == name)
	assert(sources.prepare(retry, retry_path) == held)
	package.preload[name] = function()
		error("foreign preload must not execute")
	end
	rejects(function()
		sources.prepare(retry, retry_path)
	end, "preload changed")
	package.preload[name] = nil
	assert(sources.reserve(retry, retry_path, nil, held) == held and package.preload[name] == held.wrapper)
	assert(sources.require(name).setup)
end

local partial, partial_path =
	fixture("ledger_partial", { ["lua/ledger_partial.lua"] = "return {setup=function() end}" })
partial.opts = {}
local writing = sources.prepare(partial, partial_path)
local original_rawset = rawset
rawset = function(target, name, value)
	original_rawset(target, name, value)
	if target == package.preload and name == "ledger_partial" then
		error("wrapper publication interrupted")
	end
	return target
end
local written, failure = pcall(sources.reserve, partial, partial_path, nil, writing)
rawset = original_rawset
assert(not written and tostring(failure):find("wrapper publication interrupted", 1, true))
assert(package.preload.ledger_partial == writing.wrapper and writing.require().setup)
assert(sources.prepare(partial, partial_path) == writing)
assert(sources.reserve(partial, partial_path, nil, writing) == writing and sources.require(partial.name).setup)

local invalid, invalid_path = fixture("ledger_invalid", { ["lua/shroud.lua"] = "return true" })
rejects(function()
	prepare(invalid, invalid_path, "shroud")
end, "reserved")
assert(sources.lookup("shroud") == nil)
