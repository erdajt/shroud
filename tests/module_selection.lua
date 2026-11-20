local selection = require("wraith.manager.loader_modules")
local sources = require("wraith.manager.loader_sources")
local normalize = require("wraith.manager.spec").normalize
local root = wraith.paths.stdpath("data") .. "/module-selection"
local config = root .. "/config"
wraith.fs.mkdir(config, { parents = true })

local function rejects(call, expected)
	local ok, err = pcall(call)
	assert(not ok and tostring(err):find(expected, 1, true), tostring(err))
end

local function fixture(declarations, files)
	local graph = normalize(declarations)
	local paths, selected, names = {}, {}, {}
	for _, spec in ipairs(graph.ordered) do
		local path = root .. "/" .. spec.name
		paths[spec.name], selected[spec.name] = path, { commit = "frozen" }
		names[spec.name] = { activation = "selection_" .. spec.name:gsub("[.-]", "_") }
		wraith.fs.mkdir(path .. "/lua", { parents = true })
		for _, file in ipairs(files or {}) do
			local parent = file:match("^(.*)/[^/]+$")
			if parent then
				wraith.fs.mkdir(path .. "/lua/" .. parent, { parents = true })
			end
			wraith.fs.write(path .. "/lua/" .. file, "error('selection executed source')")
		end
	end
	return graph, paths, selected, names
end

local function selector(graph, paths, selected, names)
	local rows = {}
	for _, spec in ipairs(graph.ordered) do
		rows[#rows + 1] = { name = spec.name, path = paths[spec.name], commit = selected[spec.name].commit }
	end
	local installations = require("wraith.manager.loader_installations").new(graph, rows)
	return selection.new(graph, installations, names, config), installations
end

local graph, paths, selected, names = fixture({ { "owner/selection_plain", lazy = true } }, { "namespace/util.lua" })
local choose = selector(graph, paths, selected, names)
local found = assert(choose("namespace.util"))
assert(found.name == "selection_plain" and found.entry.path == paths.selection_plain .. "/lua/namespace/util.lua")
assert(found.commit == "frozen" and found.activation == names.selection_plain.activation)
assert(not found.binding and package.loaded["namespace.util"] == nil and package.preload["namespace.util"] == nil)

found.spec.source.url = "changed"
graph.by_name.selection_plain.source.url = "changed"
selected.selection_plain.commit = "changed"
local path = paths.selection_plain
paths.selection_plain = nil
assert(choose("namespace.util").spec.source.url == "https://github.com/owner/selection_plain.git")
assert(choose("namespace.util").commit == "frozen")

assert(choose("later") == nil)
wraith.fs.write(path .. "/lua/later.lua", "return true")
assert(choose("later").name == "selection_plain")
assert(choose("shroud") == nil and choose("wraith.manager.package.internal") == nil)

for _, value in ipairs({ false, true }) do
	package.loaded.later = value
	assert(choose("later") == nil)
end
package.loaded.later = nil
for _, value in ipairs({
	false,
	function()
		error("foreign preload executed")
	end,
}) do
	package.preload.later = value
	assert(choose("later") == nil)
end
package.preload.later = nil

local loaded = package.loaded
package.loaded = {}
rejects(function()
	choose("later")
end, "tables were replaced")
package.loaded = loaded

local missing, absent_paths, absent_selected, absent_names = fixture({ "owner/selection_absent" }, { "absent.lua" })
local absent = absent_paths.selection_absent
absent_paths.selection_absent = nil
local missing_choice, missing_installations = selector(missing, absent_paths, absent_selected, absent_names)
absent_paths.selection_absent = absent
assert(missing_choice("absent") == nil)
local spec = missing.by_name.selection_absent
local entry = { source = spec.source, selector = spec.selector, pin = spec.pin, commit = "first" }
missing_installations.adopt({
	{ name = spec.name, source = spec.source, path = absent, commit = "first", state = "installed" },
}, { packages = { selection_absent = entry } }, {})
assert(missing_choice("absent").path == absent and missing_choice("absent").commit == "first")

local preferred, preferred_paths, preferred_selected, preferred_names = fixture(
	{ "owner/first", "owner/wraith-namespace" },
	{ "namespace/util.lua" }
)
local preferred_choice = selector(preferred, preferred_paths, preferred_selected, preferred_names)
assert(preferred_choice("namespace.util").name == "wraith-namespace")

local ambiguous, ambiguous_paths, ambiguous_selected, ambiguous_names = fixture(
	{ "owner/second", "owner/third" },
	{ "conflict.lua" }
)
rejects(function()
	selector(ambiguous, ambiguous_paths, ambiguous_selected, ambiguous_names)("conflict")
end, "ambiguous package module")

local duplicate, duplicate_paths, duplicate_selected, duplicate_names = fixture(
	{ "owner/wraith-same", "owner/same.wraith" },
	{ "same/util.lua" }
)
rejects(function()
	selector(duplicate, duplicate_paths, duplicate_selected, duplicate_names)("same.util")
end, "ambiguous package module")

local manual, manual_paths, manual_selected, manual_names = fixture(
	{ { "owner/selection_manual", module = false } },
	{ "manual.lua" }
)
local manual_choice = selector(manual, manual_paths, manual_selected, manual_names)
assert(manual_choice("manual") == nil)
local identity = manual_names.selection_manual.activation
package.preload[identity] = function()
	return {
		setup = function()
			assert(manual_choice("manual"))
		end,
	}
end
wraith.plugins.load(identity)
local selected_manual = assert(manual_choice("manual"))
local pending =
	sources.prepare_module(selected_manual.spec, selected_manual.path, selected_manual.commit, selected_manual.entry)
sources.reserve_module(selected_manual.spec, selected_manual.path, selected_manual.commit, pending)
assert(manual_choice("manual").binding == pending)

wraith.plugins.unload(identity)
rejects(function()
	manual_choice("manual")
end, "load the package manually")

local owned, owned_paths, owned_selected, owned_names = fixture(
	{ { "owner/selection_owned", opts = {} } },
	{ "owned.flat.lua" }
)
local owned_spec = owned.by_name.selection_owned
local binding = sources.prepare(owned_spec, owned_paths.selection_owned, "frozen")
sources.reserve(owned_spec, owned_paths.selection_owned, "frozen", binding)
local owned_choice = selector(owned, owned_paths, owned_selected, owned_names)
assert(owned_choice("owned.flat").binding == binding)
assert(wraith.modules.source(owned_paths.selection_owned, "owned.flat") == nil)
local preload = package.preload["owned.flat"]
package.preload["owned.flat"] = function() end
rejects(function()
	owned_choice("owned.flat")
end, "preload changed")
package.preload["owned.flat"] = preload
local excluded = { ordered = {}, by_name = {}, excluded = { selection_owned = { reason = "conditional" } } }
rejects(function()
	selector(excluded, {}, {}, {})("owned.flat")
end, "conditional")
owned_selected.selection_owned.commit = "replacement"
rejects(function()
	selector(owned, owned_paths, owned_selected, owned_names)("owned.flat")
end, "source changed")
