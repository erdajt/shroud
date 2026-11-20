local normalize = require("wraith.manager.spec").normalize
local parent = { "owner/parent", lazy = true, dependencies = { { "owner/library" } } }
local graph = normalize({ parent })
assert(graph.by_name.library.lazy and #graph.start == 0)

for _, declarations in ipairs({ { parent, { "owner/library" } }, { { "owner/library" }, parent } }) do
	graph = normalize(declarations)
	assert(not graph.by_name.library.lazy and graph.start[1] == "library")
end

graph = normalize({ parent, { name = "library", lazy = false } })
assert(not graph.by_name.library.lazy and #graph.start == 1)

graph = normalize({ { "owner/library", lazy = true }, parent })
assert(graph.by_name.library.lazy and #graph.start == 0)

graph = normalize({ { "owner/parent", dependencies = { { "owner/library", lazy = false } } } })
assert(not graph.by_name.library.lazy and graph.ordered[1].name == "library")

local imported = {
	name = "shared",
	import = function()
		return { { "owner/library" } }
	end,
}
graph = normalize({ { "owner/parent", lazy = true, dependencies = { imported } }, imported })
assert(graph.by_name.library.lazy and #graph.origins.library == 1)

graph = normalize({ imported, { "owner/parent", lazy = true, dependencies = { imported } } })
assert(not graph.by_name.library.lazy and #graph.origins.library == 1)

graph = normalize({ { "owner/library" }, { "owner/parent", dependencies = { "library" } } })
assert(not graph.by_name.library.lazy and #graph.origins.library == 1)

graph = normalize({
	{ "owner/zero", priority = 0 },
	{ "owner/normal" },
	{ "owner/negative", priority = -1 },
	{ "owner/later" },
	{ "owner/disabled", enabled = false, priority = 1000 },
	{ "owner/command", cmd = "activate" },
	{ "owner/event", event = "ready" },
	{ "owner/key", keys = { { "z", function() end } } },
})
assert(graph.by_name.normal.priority == 50 and graph.by_name.zero.priority == 0)
assert(table.concat(graph.start, ",") == "normal,later,zero,negative")
assert(graph.by_name.command.lazy and graph.by_name.event.lazy and graph.by_name.key.lazy)

graph = normalize({
	{ "owner/lazy", lazy = true, priority = 100, dependencies = { { "owner/low", lazy = false, priority = 0 } } },
	{ "owner/normal" },
})
assert(graph.ordered[1].name == "low")
assert(table.concat(graph.start, ",") == "normal,low")
assert(parent.dependencies[1].lazy == nil and parent.priority == nil)

local defaults = { lazy = true }
local snapshots = 0
graph = normalize({
	{
		"owner/implicit",
		cond = function(spec)
			assert(spec.lazy == nil)
			snapshots = snapshots + 1
			return true
		end,
		enabled = function(spec)
			assert(spec.lazy == nil)
			snapshots = snapshots + 1
			return true
		end,
	},
	{ "owner/explicit", lazy = false, cmd = "activate" },
	{ "owner/parent", dependencies = { { "owner/child", lazy = false, event = "ready" } } },
}, defaults)
assert(snapshots == 2 and graph.by_name.implicit.lazy and graph.by_name.parent.lazy)
assert(not graph.by_name.explicit.lazy and not graph.by_name.child.lazy)
assert(table.concat(graph.start, ",") == "explicit,child")

graph = normalize({ { "owner/implicit" }, { "owner/command", cmd = "activate" }, parent }, { lazy = false })
assert(not graph.by_name.implicit.lazy and graph.by_name.command.lazy and graph.by_name.library.lazy)

graph = normalize({ { "owner/tool", lazy = true }, { name = "tool", lazy = false } }, defaults)
assert(not graph.by_name.tool.lazy)

graph = normalize(
	{ { "owner/tool" }, { "owner/disabled", enabled = false, specs = { { name = "tool", lazy = false } } } },
	defaults
)
assert(graph.by_name.tool.lazy and #graph.start == 0)

graph = normalize(
	{ {
		name = "settings",
		import = function()
			defaults.lazy = false
			return { "owner/implicit" }
		end,
	} },
	defaults
)
assert(graph.by_name.implicit.lazy and defaults.lazy == false)

for _, invalid in ipairs({
	"true",
	1,
	{},
	function()
		return true
	end,
}) do
	local calls = 0
	local ok, err = pcall(normalize, {
		{
			name = "invalid",
			import = function()
				calls = calls + 1
				return { "owner/implicit" }
			end,
		},
	}, { lazy = invalid })
	assert(not ok and tostring(err):find("default lazy must be boolean", 1, true) and calls == 0)
end
