local schema = require("wraith.manager.spec")
local options = require("wraith.manager.spec_options")
local path = assert(debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*)/[^/]+$"))
wraith.runtimepath.prepend(path .. "/fixtures")
package.loaded["spec_fixture.alpha"] = { stale = true }
local graph = schema.normalize({ { import = "spec_fixture" }, { import = "spec_fixture" } })
local plugin = graph.by_name.example
assert(table.concat(options.resolve(plugin, graph.options.example).order, ",") == "root,alpha,nested,zeta")
assert(#graph.origins.example == 4 and graph.origins.example[2].module == "spec_fixture.alpha")
assert(graph.origins.example[3].path == path .. "/fixtures/lua/spec_fixture/nested/init.lua")
assert(package.loaded["spec_fixture.alpha"] == nil)

local overlap = schema.normalize({ { import = "spec_fixture.alpha" }, { import = "spec_fixture" } })
assert(
	table.concat(options.resolve(overlap.by_name.example, overlap.options.example).order, ",")
		== "alpha,root,alpha,nested,zeta"
)

local reverse = schema.normalize({ { import = "spec_fixture" }, { import = "spec_fixture.alpha" } })
assert(
	table.concat(options.resolve(reverse.by_name.example, reverse.options.example).order, ",")
		== "root,alpha,nested,zeta,alpha"
)

local aliases =
	schema.normalize({ { import = "spec_fixture", name = "first" }, { import = "spec_fixture", name = "second" } })
assert(#aliases.origins.example == 8)

local dependencies = schema.normalize({
	{ import = "spec_fixture.alpha" },
	{ "owner/first", dependencies = { { import = "spec_fixture" } } },
	{ "owner/second", dependencies = { { import = "spec_fixture" } } },
})
assert(#dependencies.by_name.first.dependencies == 1 and dependencies.by_name.first.dependencies[1] == "example")
assert(#dependencies.by_name.second.dependencies == 1 and dependencies.by_name.second.dependencies[1] == "example")
