local schema = require("wraith.manager.spec")
local sources = require("wraith.manager.spec_source")
local base = wraith.paths.stdpath("data") .. "/source-overrides"
local remote = "https://github.com/owner/tool.git"
local declarations = {
	{ { "owner/tool", dir = base } },
	{ { repo = "owner/tool", dir = base } },
	{ { url = remote, dir = base } },
	{ { "owner/tool" }, { name = "tool", dir = base } },
	{ { name = "tool", dir = base }, { "owner/tool" } },
	{ { "owner/tool" }, { "tool", dir = base } },
	{ { "tool", dir = base }, { "owner/tool" } },
	{ { "owner/tool" }, { repo = "tool", dir = base } },
	{ { repo = "tool", dir = base }, { "owner/tool" } },
}

for _, input in ipairs(declarations) do
	local spec = schema.normalize(input).by_name.tool
	assert(spec.source.kind == "local" and spec.source.dir == base)
	assert(spec.declared_source.url == remote and spec.declared_selector.kind == "head" and not spec.declared_pin)
	assert(spec.selector.kind == "head" and not spec.pin)
end

for _, input in ipairs({ { "tool", dir = base }, { repo = "tool", dir = base } }) do
	local spec = schema.normalize({ input }).by_name.tool
	assert(spec.source.dir == base and spec.declared_source.kind == "local")
end

local parsed = sources.declaration({ "owner/tool", dir = base })
assert(parsed.basename == "tool" and parsed.remote.url == remote and parsed.dir == base)
assert(schema.normalize({ { "owner/tool", name = "renamed", dir = base } }).by_name.renamed)

for _, selector in ipairs({ { branch = "work" }, { tag = "v1" }, { commit = string.rep("a", 40) } }) do
	local input = { "owner/tool", dir = base, pin = true }
	for key, value in pairs(selector) do
		input[key] = value
	end
	local spec = schema.normalize({ input }).by_name.tool
	assert(spec.source.dir == base and spec.selector.kind == "head" and not spec.pin)
	local kind = next(selector)
	assert(spec.declared_selector.kind == kind and spec.declared_selector.value == selector[kind] and spec.declared_pin)
	spec.declared_source.url, spec.declared_selector.value = "changed", "changed"
	assert(input[1] == "owner/tool" and input[kind] == selector[kind])
end

local graph = schema.normalize({ { "owner/tool", branch = "work", pin = true }, { name = "tool", dir = base } })
assert(graph.by_name.tool.declared_selector.value == "work" and graph.by_name.tool.selector.kind == "head")

graph = schema.normalize({ { "owner/tool", dir = base }, { name = "tool", dir = base .. "/later" } })
assert(graph.by_name.tool.source.dir == base .. "/later")

graph = schema.normalize({ { name = "tool", dir = base }, { name = "tool", dir = base .. "/later" } })
assert(graph.by_name.tool.source.dir == base .. "/later" and graph.by_name.tool.declared_source.kind == "local")

for _, original in ipairs({ { "owner/tool" }, { "owner/tool", dir = base } }) do
	graph = schema.normalize({
		original,
		{ "owner/disabled", enabled = false, specs = {
			{ name = "tool", dir = base .. "/scoped" },
		} },
	})
	local spec = graph.by_name.tool
	if original.dir then
		assert(spec.source.dir == base)
	else
		assert(spec.source.url == remote)
	end
end

graph = schema.normalize({
	{ name = "tool", dir = base },
	{ "owner/disabled", enabled = false, specs = {
		{ "owner/tool" },
	} },
})
assert(graph.by_name.tool.source.dir == base and graph.by_name.tool.declared_source.kind == "local")

local function rejects(input, message)
	local ok, err = pcall(schema.normalize, input)
	assert(not ok and tostring(err):find(message, 1, true), tostring(err))
end
rejects({ { "owner/tool", dir = base }, { "other/tool", dir = base } }, "conflicting source")
rejects(
	{ { "owner/tool", dir = base }, { "owner/disabled", enabled = false, specs = { { "other/tool", dir = base } } } },
	"conflicting source"
)
rejects({ { dir = base, name = "tool", branch = "work" } }, "local packages cannot select")
rejects({ { dir = base, name = "tool" }, { name = "tool", pin = true } }, "local packages cannot select")
rejects({
	{ dir = base, name = "tool" },
	{ name = "tool", branch = "work" },
	{
		"owner/disabled",
		enabled = false,
		specs = { { "owner/tool" } },
	},
}, "local packages cannot select")
rejects({ { "./tool", dir = base } }, "local repository path cannot also specify dir")
rejects({ { "owner/tool", url = remote, dir = base } }, "choose one repo or url")
rejects({ { "owner/tool", repo = "owner/tool", dir = base } }, "choose one repository field")
assert(schema.normalize({ { "tool", name = "renamed", dir = base } }).by_name.renamed.source.dir == base)
rejects({ { "tool", name = "renamed" } }, "name-only declaration cannot rename")
rejects({ { url = "tool", dir = base } }, "git source requires a valid ssh host")
rejects({ { "bad name", dir = base } }, "invalid package name")

local calls = 0
local first = {
	"owner/first",
	enabled = function()
		calls = calls + 1
		return true
	end,
}
local commands = {}
for index = 1, 64 do
	commands[index] = "command" .. index
end
rejects(
	{ first, { "owner/last", cmd = commands }, { name = "last", cmd = "overflow" } },
	"command trigger exceeds its limit"
)
assert(calls == 0)
rejects({ first, { "owner/last", branch = "work" }, { name = "last", tag = "v1" } }, "choose one branch")
assert(calls == 0)
rejects({
	first,
	{ name = "optional", optional = true, branch = "work" },
	{ name = "optional", optional = true, tag = "v1" },
}, "choose one branch")
assert(calls == 0)

for _, value in ipairs({ false, true }) do
	for _, bad in ipairs({
		{ value, name = "tool" },
		{ repo = value, name = "tool" },
		{ url = value, name = "tool" },
		{ value, dir = base },
		{ repo = value, dir = base },
		{ url = value, dir = base },
	}) do
		rejects({ "owner/tool", bad }, "package source must be a nonempty string")
	end
end
