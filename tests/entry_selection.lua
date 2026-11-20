local entries = require("wraith.manager.loader_entry")
local fields = require("wraith.manager.spec_fields")
local base = wraith.paths.stdpath("data") .. "/entry-fixtures"

local function fixture(name, files)
	local root = base .. "/" .. name
	wraith.fs.mkdir(root, { parents = true })
	for path, source in pairs(files) do
		local parent = path:match("^(.*)/")
		if parent then
			wraith.fs.mkdir(root .. "/" .. parent, { parents = true })
		end
		wraith.fs.write(root .. "/" .. path, source)
	end
	return root
end

local function rejects(spec, path, expected, owned)
	local ok, err = pcall(entries.select, spec, path, owned)
	assert(not ok and tostring(err):find(expected, 1, true), tostring(err))
end

local root = fixture("matching", {
	["lua/tool2.lua"] = "return 'selected', ...",
	["lua/extra.lua"] = "error('unselected entry executed')",
	["tool2.lua"] = "error('legacy shadow executed')",
})
for _, name in ipairs({ "tool2", "wraith-tool2", "tool2.wraith", "tool2.lua", "tool2-lua", "wraith-tool2.wraith" }) do
	local spec = { name = name }
	local record = entries.select(spec, root)
	assert(record.name == "tool2" and record.kind == "file")
	assert(record.path == root .. "/lua/tool2.lua" and record.load() == "selected")
	assert(spec.main == nil and package.loaded.tool2 == nil and package.preload.tool2 == nil)
end
rejects({ name = "tool" }, root, "candidates: extra, tool2")
rejects({ name = "tool2", main = "missing" }, root, "has no entry missing")
assert(entries.select({ name = "arbitrary", main = "tool2" }, root).load() == "selected")

local single = fixture("single", { ["lua/another/init.lua"] = "return 42" })
assert(entries.select({ name = "unrelated" }, single).name == "another")

local dotted = fixture("dotted", { ["lua/flat.name.lua"] = "return 'physical'" })
assert(entries.select({ name = "flat-name" }, dotted).load() == "physical")
assert(wraith.modules.source(dotted, "flat.name") == nil)

local ambiguous = fixture("ambiguous", {
	["lua/tool_name.lua"] = "error('ambiguous')",
	["lua/tool-name.lua"] = "error('ambiguous')",
})
rejects({ name = "tool-name" }, ambiguous, "set main or config")

local empty = fixture("empty", { ["legacy/tool.lua"] = "return true" })
rejects({ name = "tool" }, empty, "candidates: none")

local legacy = fixture("legacy", { ["nested/tool.lua"] = "return 'legacy'" })
assert(entries.select({ name = "tool", main = "nested.tool" }, legacy).load() == "legacy")

local foreign = fixture("foreign", { ["lua/tool2.lua"] = "error('config shadow executed')" })
wraith.runtimepath.prepend(foreign)
assert(entries.select({ name = "tool2" }, root).load() == "selected")

local preload_calls = 0

local function synthetic(name)
	preload_calls = preload_calls + 1
	return name, "tail"
end
package.preload.tool2 = synthetic
rejects({ name = "tool2" }, root, "set explicit main")
local override = entries.select({ name = "tool2", main = "tool2" }, root)
assert(override.kind == "preload" and override.identity == synthetic and preload_calls == 0)
package.preload.tool2 = function()
	error("new preload must not redirect bound metadata")
end
local value, tail = override.load()
assert(value == "tool2" and tail == "tail" and preload_calls == 1)
package.preload.tool2 = false
rejects({ name = "tool2", main = "tool2" }, root, "invalid preload")
package.preload.tool2 = nil

local owned = require("wraith.manager.loader_binding").new(entries.select({ name = "tool2" }, root))
local original = owned.entry
owned.install()
assert(entries.select({ name = "tool2" }, root, owned) == original)
assert(entries.select({ name = "tool2", main = "tool2" }, root, owned) == original)
rejects({ name = "tool2" }, foreign, "source changed", owned)
rejects({ name = "tool2", main = "tool2" }, foreign, "source changed", owned)
package.preload.tool2 = synthetic
rejects({ name = "tool2", main = "tool2" }, root, "preload changed", owned)
rejects({ name = "tool2" }, root, "preload changed", owned)
package.preload.tool2 = nil

local preloads, metatable = package.preload, getmetatable(package.preload)
setmetatable(preloads, {
	__index = function()
		error("preload fallback executed")
	end,
})
assert(entries.select({ name = "tool2", main = "tool2" }, root).kind == "file")
assert(entries.select({ name = "tool2" }, root).kind == "file")
setmetatable(preloads, metatable)
package.preload = false
rejects({ name = "tool2" }, root, "preload table was replaced")
package.preload = preloads

for _, name in ipairs({ "tool", "_tool", "tool-name.part_2", "tool2.part" }) do
	assert(fields.main(name) == name)
end
for _, name in ipairs({
	"",
	"1tool",
	"-tool",
	"tool.2part",
	".tool",
	"tool.",
	"tool..part",
	"tool/name",
	string.rep("x", 129),
}) do
	assert(not pcall(fields.main, name), name)
end
for _, name in ipairs({ "shroud", "shroud.part", "wraith.manager", "wraith.manager.part" }) do
	rejects({ name = "reserved", main = name }, root, "namespace is reserved")
end
local reserved = fixture("reserved", { ["lua/shroud.lua"] = "error('reserved entry')" })
rejects({ name = "reserved" }, reserved, "namespace is reserved")
local invalid = fixture("invalid", { ["lua/1tool.lua"] = "error('invalid entry')" })
rejects({ name = "invalid" }, invalid, "invalid discovered module")

local capability = wraith.capabilities.module_sources
wraith.capabilities.module_sources = nil
rejects({ name = "tool2", main = "tool2" }, root, "update wraith")
wraith.capabilities.module_sources = capability
