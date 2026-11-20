local inspect = require("wraith.manager.store_inspect")
local schema = require("wraith.manager.spec")
local root = wraith.paths.stdpath("data") .. "/inspection-availability"
wraith.fs.mkdir(root, { parents = true })
local options = { root = root .. "/packages", lockfile = root .. "/lock.json" }
local specs = {
	schema.descriptor({ name = "first", source = { kind = "git", url = "https://github.com/owner/first.git" } }),
	schema.descriptor({ name = "second", source = { kind = "git", url = "https://github.com/owner/second.git" } }),
}

local original, calls = wraith.fs.stat, {}
wraith.fs.stat = function(path, settings)
	local key = tostring(settings and settings.follow or false) .. ":" .. path
	calls[key] = (calls[key] or 0) + 1
	return original(path, settings)
end
local ok, rows = pcall(inspect.read, specs, options)
wraith.fs.stat = original
assert(ok, tostring(rows))
assert(rows[1].availability == "absent" and rows[2].availability == "absent")
assert(rows[1].state == "missing" and rows[1].path == nil)
assert(calls["false:" .. options.root] == 1 and calls["false:" .. root] == 1)

wraith.fs.mkdir(options.root .. "/objects/first", { parents = true })
rows = inspect.read(specs, options)
assert(rows[1].availability == "absent" and rows[1].path == nil)
wraith.fs.write(options.root .. "/objects/second", "not a directory")
rows = inspect.read(specs, options)
assert(rows[2].availability == "blocked" and rows[2].error:find("not a directory", 1, true))

local commit = string.rep("a", 40)
wraith.fs.write(
	options.lockfile,
	wraith.json.encode({
		version = 1,
		generation = "fixture",
		packages = {
			first = { source = specs[1].source, selector = { kind = "head" }, pin = false, commit = commit },
		},
	})
)
rows = inspect.read(specs, options)
assert(rows[1].availability == "absent" and rows[1].commit == commit and rows[1].path == nil)
wraith.fs.mkdir(options.root .. "/objects/first/" .. commit)
rows = inspect.read(specs, options)
assert(rows[1].availability == "available" and rows[1].state == "installed")
assert(rows[1].path == options.root .. "/objects/first/" .. commit)

local function local_row(path)
	return inspect.read({ schema.descriptor({ name = "local", source = { kind = "local", dir = path } }) }, options)[1]
end
local local_path = root .. "/local"
assert(local_row(local_path).availability == "absent")
wraith.fs.mkdir(local_path)
assert(local_row(local_path).availability == "available")
wraith.fs.write(local_path .. "/file", "not a parent")
local blocked = local_row(local_path .. "/file/child")
assert(blocked.availability == "blocked" and blocked.error:find(local_path .. "/file", 1, true))

local within = local_row(local_path .. string.rep("/missing", 127))
assert(within.availability == "absent")
local beyond = local_row(local_path .. string.rep("/missing", 128))
assert(beyond.availability == "blocked" and beyond.error:find("128 ancestors", 1, true))
assert(beyond.path == nil)
