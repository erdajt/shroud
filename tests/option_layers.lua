local options = require("wraith.manager.spec_options")
local calls = 0
local initial = { nested = { keep = true, change = 1 }, list = { "first" }, gone = true }
local appended = { nested = { last = true }, list = { "last" }, gone = wraith.json.null }
local layers = {
	{ value = initial },
	{
		value = function(spec, opts)
			assert(spec.name == "tool" and spec.opts == nil)
			calls = calls + 1
			opts.nested.change, opts.added = 2, true
			spec.name = "changed"
		end,
	},
	{ value = appended, extend = { "list" } },
}
local spec = { name = "tool" }
local captured = options.capture(layers)
assert(calls == 0 and captured[1].value ~= initial)
local result = options.resolve(spec, layers)
assert(calls == 1 and spec.name == "tool")
assert(result.nested.keep and result.nested.last and result.nested.change == 2)
assert(result.added and result.gone == nil and table.concat(result.list, ",") == "first,last")
assert(initial.nested.change == 1 and #initial.list == 1 and appended.gone == wraith.json.null)

result.list[1] = "changed"
assert(options.resolve(spec, layers).list[1] == "first" and calls == 2)

local replaced =
	options.resolve(spec, { { value = { list = { 1, 2 }, map = { x = 1 } } }, { value = { list = { 3 }, map = {} } } })
assert(#replaced.list == 1 and replaced.list[1] == 3 and replaced.map.x == 1)

local emptied = options.resolve(spec, { { value = { list = { 1, 2 } } }, { value = { list = {} } } })
assert(next(emptied.list) == nil)

local reset =
	options.resolve(spec, { { value = { keep = true } }, {
		value = function()
			return { new = true }
		end,
	} })
assert(reset.keep == nil and reset.new)

local cleared = options.resolve(spec, { { value = { keep = true } }, {
	value = function()
		return {}
	end,
} })
assert(next(cleared) == nil)

local nested = options.resolve(
	spec,
	{ { value = { a = { list = { 1 } } } }, { value = { a = { list = { 2 } } }, extend = { "a.list" } } }
)
assert(#nested.a.list == 2)

local deleted = options.resolve(spec, { { value = { a = { b = wraith.json.null, c = 1 } } } })
assert(deleted.a.b == nil and deleted.a.c == 1)

for _, layers in ipairs({
	{ { value = false } },
	{ {
		value = function()
			return "invalid"
		end,
	} },
	{ { value = {}, extend = { "a..b" } } },
	{ { value = {}, extend = { ".a" } } },
	{ { value = {}, extend = false } },
	{ { value = {}, extend = { "a\nb" } } },
	{ { value = { a = { key = true } } }, { value = { a = { other = true } }, extend = { "a" } } },
}) do
	assert(not pcall(options.resolve, spec, layers))
end

local cycle = {}
cycle.self = cycle
assert(not pcall(options.resolve, spec, { { value = cycle } }))
assert(not pcall(options.resolve, spec, { {
	value = function()
		return cycle
	end,
} }))

local failing = options.capture({
	{ value = initial },
	{
		value = function(_, opts)
			opts.nested.change = "failed"
			error("callback failed")
		end,
	},
})
local ok, err = pcall(options.resolve, spec, failing)
assert(not ok and tostring(err):find("callback failed", 1, true))
assert(failing[1].value.nested.change == 1 and initial.nested.change == 1)
assert(options.resolve(spec, { { value = failing[1].value } }).nested.change == 1)

local large = {}
for index = 1, 5000 do
	large[index] = index
end
assert(not pcall(options.resolve, spec, { {
	value = function()
		return large
	end,
} }))

local first, second = {}, {}
for index = 1, 2100 do
	first["first" .. index], second["second" .. index] = index, index
end
assert(not pcall(options.resolve, spec, {
	{
		value = function()
			return first
		end,
	},
	{
		value = function(_, opts)
			for key, value in pairs(second) do
				opts[key] = value
			end
		end,
	},
}))
