local failures = { missing = {}, invalid = { setup = 42 }, scalar = "not a module" }
local declarations, paths = {}, {}
for _, name in ipairs({ "missing", "invalid", "scalar" }) do
	declarations[#declarations + 1] = { name = name, main = name, dir = "/tmp/" .. name, config = true, lazy = true }
	paths[name] = "/tmp/" .. name
	package.preload[name] = function()
		return failures[name]
	end
end

package.preload.failure_test = function()
	return {
		setup = function() end,
		run = function()
			local graph = require("wraith.manager.spec").normalize(declarations)
			local loader = require("wraith.manager.loader").new(graph, paths, "failure_test")
			loader.initialize()
			for _, name in ipairs({ "missing", "invalid", "scalar" }) do
				local ok, err = pcall(loader.load, name)
				assert(not ok and err ~= nil)
				assert(not loader.is_loaded(name) and loader.is_managed(name))
			end

			local count = 0
			failures.missing.setup = function()
				count = count + 1
			end
			loader.load("missing")
			assert(count == 1 and loader.is_loaded("missing"))

			loader.unload_all()
		end,
	}
end
wraith.plugins.load("failure_test")
wraith.plugins.call("failure_test", "run")
