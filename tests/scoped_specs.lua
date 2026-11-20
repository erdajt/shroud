local normalize = require("wraith.manager.spec").normalize
local options = require("wraith.manager.spec_options")
local graph = normalize({ { "owner/parent", enabled = false, specs = { "owner/child" } } })
assert(#graph.ordered == 0 and graph.excluded.parent.reason == "disabled")
assert(graph.excluded.child.reason == "scope" and graph.retain_lock.parent and not graph.retain_lock.child)
assert(not graph.options.parent and not graph.excluded.parent.opts)

graph = normalize({
	{ "owner/child", opts = { base = true }, cmd = "inspect" },
	{ "owner/parent", enabled = false, specs = { { name = "child", opts = { scoped = true }, cmd = "removed" } } },
})
local opts = options.resolve(graph.by_name.child, graph.options.child)
assert(opts.base and not opts.scoped and #graph.by_name.child.cmd == 1)
assert(#graph.origins.child == 1 and graph.origins.child[1].index == 1)

graph = normalize({ { name = "missing", optional = true, opts = { ignored = true } } })
assert(#graph.ordered == 0 and graph.excluded.missing.reason == "optional")
assert(not graph.retain_lock.missing)

graph = normalize({ { "owner/parent", optional = true, specs = { "owner/child" } } })
assert(#graph.ordered == 0 and graph.excluded.parent.reason == "optional" and graph.excluded.child.reason == "scope")

for _, declarations in ipairs({
	{
		{ "owner/child", optional = true, opts = { overlay = true } },
		{ "owner/parent", dependencies = { "owner/child" } },
	},
	{
		{ "owner/parent", dependencies = { "owner/child" } },
		{ "owner/child", optional = true, opts = { overlay = true } },
	},
}) do
	graph = normalize(declarations)
	assert(#graph.ordered == 2 and graph.by_name.parent.dependencies[1] == "child")
	assert(options.resolve(graph.by_name.child, graph.options.child).overlay)
end

graph = normalize({ { "owner/child", optional = true }, { name = "child", opts = { qualifies = true } } })
assert(graph.by_name.child and not graph.excluded.child)

graph = normalize({ { "owner/child", optional = true }, { "owner/parent", dependencies = { "child" } } })
assert(graph.excluded.child.reason == "optional" and #graph.by_name.parent.dependencies == 0)

graph =
	normalize({ { "owner/parent", opts = { base = true }, specs = { { name = "parent", opts = { scoped = true } } } } })
opts = options.resolve(graph.by_name.parent, graph.options.parent)
assert(opts.base and opts.scoped and #graph.by_name.parent.dependencies == 0)

local calls = 0
graph = normalize({
	{
		"owner/parent",
		lazy = true,
		specs = {
			{
				"owner/child",
				enabled = function(spec)
					calls = calls + 1
					assert(spec.specs == nil and #spec.dependencies == 0)
					return true
				end,
			},
		},
	},
})
assert(calls == 1 and graph.start[1] == "child" and #graph.start == 1)

calls = 0
graph = normalize({
	{
		name = "missing",
		optional = true,
		enabled = function()
			calls = calls + 1
			return true
		end,
	},
})
assert(calls == 1 and graph.excluded.missing.reason == "optional")

graph = normalize({ { name = "missing", optional = true, enabled = false } })
assert(graph.excluded.missing.reason == "disabled" and not graph.retain_lock.missing)

local imported_calls = 0
local imported = {
	name = "shared",
	import = function()
		imported_calls = imported_calls + 1
		return { "owner/imported" }
	end,
}
graph = normalize({ { "owner/parent", enabled = false, specs = { imported } }, imported })
assert(imported_calls == 1 and #graph.ordered == 0 and graph.excluded.imported.reason == "scope")
graph = normalize({
	{
		"owner/parent",
		name = "parent",
		optional = true,
		specs = { "owner/scoped" },
		import = function()
			return { "owner/independent" }
		end,
	},
})
assert(graph.by_name.independent and graph.excluded.parent.reason == "optional")
assert(graph.excluded.scoped.reason == "scope" and #graph.ordered == 1)

local observed = {}
graph = normalize({
	{
		"owner/observer",
		dependencies = { "target" },
		enabled = function(spec)
			observed[#observed + 1] = #spec.dependencies
			return true
		end,
	},
	{ "owner/target", enabled = false },
})
assert(table.concat(observed, ",") == "1,0" and #graph.by_name.observer.dependencies == 0)
graph = normalize({
	{ "owner/first", enabled = false, dependencies = { "second" } },
	{ "owner/second", enabled = false, dependencies = { "first" } },
})
assert(#graph.ordered == 0 and graph.retain_lock.first and graph.retain_lock.second)

local function rejects(value, expected)
	local ok, err = pcall(normalize, value)
	assert(not ok and tostring(err):find(expected, 1, true), tostring(err))
end
rejects(
	{ { "owner/parent", enabled = false, specs = { "owner/child" } }, { name = "child" } },
	"source is missing: child"
)
rejects({ { "owner/parent", enabled = false, specs = { "different/child" } }, "owner/child" }, "conflicting source")
rejects({ { "owner/parent", optional = "yes" } }, "optional must be boolean")
rejects({ { "owner/parent", specs = false } }, "specs must be declarations")
rejects({ { "owner/parent", enabled = false, specs = { { name = "child", priority = false } } } }, "priority")

local recursive = { "owner/parent" }
recursive.specs = { recursive }
rejects({ recursive }, "cyclic package declarations")
