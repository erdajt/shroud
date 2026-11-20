local fields = require("wraith.manager.spec_fields")
local schema = require("wraith.manager.spec")
local calls = 0
local dependencies = {}
dependencies[1] = dependencies
local input = {
	name = "tool",
	dependencies = dependencies,
	opts = { nested = { value = true } },
	opts_extend = { "nested.list" },
	enabled = function(value)
		calls = calls + 1
		value.name = "changed"
		return true
	end,
	init = function()
		error("init evaluated during declaration")
	end,
	config = function()
		error("config evaluated during declaration")
	end,
}
local raw = fields.declaration(input)
assert(calls == 0 and raw ~= input and raw.opts ~= input.opts and raw.opts.nested ~= input.opts.nested)
assert(raw.dependencies == dependencies)
raw.opts.nested.value = false
raw.opts_extend[1] = "changed"
assert(input.opts.nested.value and input.opts_extend[1] == "nested.list")

local repository = fields.declaration("owner/tool")
assert(repository.repo == "owner/tool" and repository.name == nil and repository.priority == nil)
assert(fields.declaration({ "tool", opts = { x = 1 } })[1] == "tool")
assert(fields.declaration("tool").repo == "tool")
assert(not pcall(fields.declaration, { "tool", repo = "tool" }))
assert(not pcall(fields.declaration, { "tool", name = "renamed" }))

local option_callback = function()
	error("opts evaluated during declaration")
end
assert(fields.declaration({ name = "tool", opts = option_callback }).opts == option_callback)

input.dependencies, input.repo = nil, "owner/tool"
local final = fields.normalize(input, schema.descriptor)
assert(calls == 1 and final.enabled and final.name == "tool" and input.name == "tool")
assert(final.opts_extend[1] == "nested.list")
assert(schema.name("tool") == "tool")
assert(schema.selector({ kind = "commit", value = string.rep("A", 40) }).value == string.rep("a", 40))

local invalid = {
	{ unknown = true },
	{ name = false },
	{ main = false },
	{ main = "trailing." },
	{ main = "wraith.manager.part" },
	{ enabled = "yes" },
	{ pin = 1 },
	{ priority = 0 / 0 },
	{ priority = math.huge },
	{ lazy = 1 },
	{ init = true },
	{ config = "bad" },
	{ opts = false },
	{ opts_extend = { "a..b" } },
	{ branch = false },
	{ tag = "--option" },
	{ commit = "short" },
	{ branch = "main", tag = "v1" },
	{ cmd = { "bad..command" } },
	{ cmd = false },
	{ event = false },
	{ event = { "made_up" } },
	{ keys = { { keys = "j", action = false } } },
	{ keys = { { keys = "j", action = "noop", mode = false } } },
	{ keys = { { keys = "j", [1] = false, action = "noop" } } },
	{ keys = { { "<Enter>", "command.help" }, { "<CR>", "command.help" } } },
	{ dependencies = false },
	{ repo = "owner/tool", url = "https://github.com/owner/tool.git" },
	{ dir = "/tmp/tool", branch = "main" },
}
for index, value in ipairs(invalid) do
	if value.name == nil then
		value.name = "tool"
	end
	assert(not pcall(fields.declaration, value), "accepted invalid fragment " .. index)
end
assert(calls == 1)

local bad = {
	repo = "owner/tool",
	cmd = { "bad..command" },
	enabled = function()
		calls = calls + 1
		return true
	end,
}
assert(not pcall(fields.normalize, bad, schema.descriptor) and calls == 1)

local cyclic = {}
cyclic.self = cyclic
assert(not pcall(fields.declaration, { name = "tool", opts = cyclic }))
assert(not pcall(fields.normalize, {
	repo = "owner/tool",
	enabled = function()
		return "invalid"
	end,
}, schema.descriptor))

assert(fields.declaration({
	name = "tool",
	keys = {
		{ "z", "command.help" },
		{ "zz", "command.help" },
		{ "z", "command.help", mode = "buffer.normal" },
	},
}))
