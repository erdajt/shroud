local normalize = require("wraith.manager.spec").normalize
local options = require("wraith.manager.spec_options")
local calls = 0
local input = {
	{
		"owner/parent",
		opts = { original = true },
		cond = function(...)
			assert(select("#", ...) == 1)
			local spec = ...
			assert(spec.name == "parent" and spec.dependencies[1] == "child" and spec.specs == nil)
			spec.opts.original = false
			calls = calls + 1
			return false
		end,
		enabled = function()
			error("conditional package evaluated enabled")
		end,
		dependencies = { { "owner/child", dependencies = { "owner/grand" } } },
		specs = { "owner/scoped" },
	},
}
local graph = normalize(input)
assert(calls == 1 and input[1].opts.original and #graph.ordered == 0)
assert(graph.excluded.parent.reason == "conditional" and graph.excluded.child.reason == "scope")
for _, name in ipairs({ "parent", "child", "grand" }) do
	assert(graph.retain_lock[name] and graph.retain_install[name])
end
assert(not graph.retain_install.scoped and not graph.retain_lock.scoped)

graph = normalize({
	{ "owner/parent", cond = false, dependencies = { { "owner/child", opts = { removed = true } } } },
	{ "owner/child", opts = { survives = true } },
})
assert(graph.by_name.child and graph.retain_install.child)
local opts = options.resolve(graph.by_name.child, graph.options.child)
assert(opts.survives and not opts.removed)

graph = normalize({
	{
		"owner/parent",
		enabled = false,
		specs = {
			{ "owner/child", cond = false, dependencies = { "owner/dependency" } },
		},
	},
})
assert(graph.excluded.child.reason == "scope" and not graph.retain_install.parent)
assert(graph.retain_install.child and graph.retain_install.dependency)

graph =
	normalize({ { "owner/child" }, { "owner/parent", enabled = false, specs = { { name = "child", cond = false } } } })
assert(graph.excluded.child.reason == "conditional" and graph.by_name.child == nil)
assert(graph.retain_install.child and graph.retain_lock.parent)

for _, optional in ipairs({ false, true }) do
	graph = normalize({ { name = "missing", cond = false, enabled = false, optional = optional } })
	assert(graph.excluded.missing.reason == "conditional" and graph.retain_lock.missing)
	assert(graph.retain_install.missing)
end

graph = normalize({
	{ "owner/first", cond = false, dependencies = { "second", "unknown" } },
	{ "owner/second", dependencies = { "first" } },
})
assert(graph.retain_install.first and graph.retain_install.second and not graph.retain_install.unknown)
assert(graph.by_name.second and #graph.by_name.second.dependencies == 0)

graph = normalize({ { "owner/tool", cond = false }, { name = "tool", cond = true } })
assert(graph.by_name.tool and not graph.retain_install.tool)

graph = normalize({ "owner/implicit", { "owner/explicit", cond = true } }, { cond = false })
assert(graph.by_name.explicit and graph.excluded.implicit.reason == "conditional")

graph = normalize({ { "owner/explicit", cond = false } }, { cond = true })
assert(graph.excluded.explicit.reason == "conditional")

local order = {}
graph = normalize({
	{
		"owner/first",
		enabled = function()
			order[#order + 1] = "enabled:first"
			return true
		end,
	},
	{ "owner/second", optional = true },
}, {
	cond = function(spec)
		order[#order + 1] = "cond:" .. spec.name
		return true
	end,
})
assert(table.concat(order, ",") == "cond:first,cond:second,enabled:first")
assert(graph.excluded.second.reason == "optional" and not graph.retain_lock.second)

local arities = {}
graph = normalize({
	{
		"owner/mixed",
		name = "mixed",
		cond = function(...)
			arities[#arities + 1] = select("#", ...)
			return true
		end,
		import = function()
			return { "owner/imported" }
		end,
	},
})
assert(table.concat(arities, ",") == "0,1" and graph.by_name.mixed and graph.by_name.imported)

local imported = 0
local defaults = { cond = true }
graph = normalize({
	{
		name = "settings",
		import = function()
			imported = imported + 1
			defaults.cond = false
			return { "owner/imported" }
		end,
	},
}, defaults)
assert(imported == 1 and graph.by_name.imported)

graph = normalize(
	{ {
		name = "settings",
		import = function()
			imported = imported + 1
			return { "owner/imported" }
		end,
	} },
	{ cond = false }
)
assert(imported == 2 and graph.excluded.imported.reason == "conditional")

local function rejects(specs, settings, expected)
	local ok, err = pcall(normalize, specs, settings)
	assert(not ok and tostring(err):find(expected, 1, true), tostring(err))
end

local attempted = 0
for _, invalid in ipairs({ false, "defaults", { unknown = true }, { cond = "yes" } }) do
	rejects(
		{ {
			name = "settings",
			import = function()
				attempted = attempted + 1
				return {}
			end,
		} },
		invalid,
		"default"
	)
end
assert(attempted == 0)
rejects({ { "owner/tool", cond = "yes" } }, nil, "cond must be boolean or function")
rejects({ {
	"owner/tool",
	cond = function()
		return nil
	end,
} }, nil, "cond must return boolean")

package.preload["settings.conditional_error"] = function()
	return { {
		"owner/tool",
		cond = function()
			error("conditional failure")
		end,
	} }
end
rejects({ { import = "settings.conditional_error" } }, nil, "settings.conditional_error")
