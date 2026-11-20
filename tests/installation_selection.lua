local installations = require("wraith.manager.loader_installations")
local sources = require("wraith.manager.loader_sources")
local schema = require("wraith.manager.spec")
local copy = require("wraith.manager.spec_fields").copy
local root = wraith.paths.stdpath("data") .. "/installation-selection"
local graph = schema.normalize({
	{ "owner/adopt_first", branch = "work", pin = true },
	{ "owner/adopt_second" },
	{ name = "adopt_local", dir = root .. "/local" },
})

local function row(name, path, commit)
	local spec = graph.by_name[name]
	return {
		name = name,
		source = copy(spec.source),
		selector = copy(spec.selector),
		pin = spec.pin,
		state = path and "installed" or "missing",
		path = path,
		commit = commit,
	}
end

local function lock_for(rows)
	local lock = { packages = {} }
	for _, value in ipairs(rows) do
		if value.source.kind == "git" and value.path then
			lock.packages[value.name] = {
				source = copy(value.source),
				selector = copy(value.selector),
				pin = value.pin,
				commit = value.commit,
			}
		end
	end
	return lock
end

local function rejects(call, message)
	local ok, err = pcall(call)
	assert(not ok and tostring(err):find(message, 1, true), tostring(err))
end

local initial = { row("adopt_first", nil, "old"), row("adopt_second"), row("adopt_local") }
rejects(function()
	installations.new(graph, { initial[1] })
end, "missing inspected package")
rejects(function()
	installations.new(graph, { initial[1], initial[1] })
end, "invalid inspected package")
rejects(function()
	installations.new(graph, { { name = "unknown" } })
end, "invalid inspected package")
local chosen = installations.new(graph, initial)
initial[1].path = "/foreign"
graph.by_name.adopt_first.selector.value = "foreign"
local fresh = {
	row("adopt_first", root .. "/first", "new"),
	row("adopt_second", root .. "/second", "second"),
	row("adopt_local", root .. "/local"),
}
fresh[1].selector.value = "work"
local lock = lock_for(fresh)
local wrong = copy(lock)
wrong.packages.adopt_second = nil
rejects(function()
	chosen.adopt(fresh, wrong, {})
end, "no matching lock")
wrong = copy(lock)
wrong.packages.adopt_second.commit = "other"
rejects(function()
	chosen.adopt(fresh, wrong, {})
end, "no matching lock")
assert(chosen.get("adopt_first").path == nil)
wrong = copy(lock)
wrong.packages.adopt_second.selector = { kind = "tag", value = "other" }
rejects(function()
	chosen.adopt(fresh, wrong, {})
end, "intent changed")
assert(chosen.get("adopt_first").path == nil and chosen.get("adopt_second").path == nil)
wrong = copy(lock)
wrong.packages.adopt_first.pin = false
rejects(function()
	chosen.adopt(fresh, wrong, {})
end, "intent changed")
rejects(function()
	chosen.adopt(fresh, lock, { adopt_second = true })
end, "already exposed")
assert(chosen.get("adopt_first").commit == "old")

chosen.adopt(fresh, lock, {})
assert(chosen.get("adopt_first").commit == "new")
assert(chosen.get("adopt_local").path == root .. "/local")
fresh[1].path = "/changed"
local detached = chosen.get("adopt_first")
detached.path = "/also-changed"
assert(chosen.get("adopt_first").path == root .. "/first")
chosen.adopt(fresh, lock, {})
assert(chosen.get("adopt_first").path == root .. "/first")
assert(chosen.get("unknown") == nil)

local reserved_graph = schema.normalize({ { name = "adopt_reserved", dir = root .. "/reserved" } })
local reserved = reserved_graph.by_name.adopt_reserved
local missing = { { name = reserved.name, source = reserved.source, state = "local" } }
local unavailable = installations.new(reserved_graph, missing)
assert(not sources.exposed(reserved.name))
sources.reserve(reserved, reserved.source.dir, nil, nil)
assert(sources.exposed(reserved.name))
missing[1].path = reserved.source.dir
rejects(function()
	unavailable.adopt(missing, { packages = {} }, {})
end, "already exposed")
assert(unavailable.get(reserved.name).path == nil)

local local_graph = schema.normalize({ { name = "adopt_wrong_local", dir = root .. "/expected" } })
local local_row = { name = "adopt_wrong_local", source = local_graph.by_name.adopt_wrong_local.source }
local local_choice = installations.new(local_graph, { local_row })
local_row.path = root .. "/wrong"
rejects(function()
	local_choice.adopt({ local_row }, { packages = {} }, {})
end, "local directory changed")
assert(local_choice.get(local_row.name).path == nil)
