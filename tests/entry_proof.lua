local bindings = require("wraith.manager.loader_binding")

local function rejects(call, expected)
	local ok, err = pcall(call)
	assert(not ok and tostring(err):find(expected, 1, true), tostring(err))
end

local function bind(name, source)
	package.preload[name] = source
	local owned = bindings.new({ name = name, kind = "preload", identity = source, load = source })
	owned.install()
	return owned
end

for _, mode in ipairs({ "nil", "false", "truthy" }) do
	local name, runs = "proof_" .. mode, 0
	local owned = bind(name, function()
		runs = runs + 1
		if mode == "nil" then
			package.loaded[name] = nil
			return
		end
		return mode ~= "false"
	end)
	rejects(function()
		owned.check(name, false)
	end, "invalid package entry verification phase")

	for index = 1, 3 do
		local executed = not package.loaded[name]
		local proof = owned.check(name, "before", nil, executed)
		require(name)
		owned.check(name, "after", proof, executed)
		assert(runs == (mode == "truthy" and 1 or index))
	end
end

for _, mode in ipairs({ "nil", "false" }) do
	for _, previous in ipairs({ false, true }) do
		local name = "proof_foreign_" .. mode .. tostring(previous)
		local owned = bind(name, function()
			if mode == "nil" then
				package.loaded[name] = nil
			else
				return false
			end
		end)
		if previous then
			owned.require()
		end

		local searcher, called = package.loaders[1], false
		package.loaders[1] = function(requested)
			if requested == name then
				return function()
					called = true
					if mode == "nil" then
						package.loaded[name] = nil
					else
						package.loaded[name] = false
					end
				end
			end
			return searcher(requested)
		end
		rejects(owned.require, "execution proof is foreign")
		package.loaders[1] = searcher
		assert(called, "foreign source did not execute")
		if mode == "nil" then
			assert(package.loaded[name] == nil)
		else
			assert(package.loaded[name] == false)
		end
		rejects(owned.require, "cache is poisoned")
	end
end

local advanced = bind("proof_advanced", function()
	return false
end)
local earlier = advanced.check("proof_advanced", "before", nil, true)
assert(advanced.require() == false and advanced.require() == false)
advanced.check("proof_advanced", "after", earlier, true)

for index, invalid in ipairs({ -1, 0.5, math.huge, 0 / 0, "0", {} }) do
	local name = "proof_invalid_" .. index
	local owned = bind(name, function()
		return true
	end)
	assert(owned.require())
	rejects(function()
		owned.check(name, "after", invalid, false)
	end, "execution proof is foreign")
	assert(package.loaded[name] == true)
end

local runs = 0
local ceiling = bind("proof_ceiling", function()
	runs = runs + 1
	return true
end)
local found = false
for index = 1, 32 do
	local name = debug.getupvalue(ceiling.wrapper, index)
	if name == "serial" then
		debug.setupvalue(ceiling.wrapper, index, 9007199254740990)
		found = true
		break
	end
end
assert(found)
assert(ceiling.require() and ceiling.require() and runs == 1)

package.loaded.proof_ceiling = nil
rejects(ceiling.require, "serial exhausted")
assert(runs == 1 and package.loaded.proof_ceiling == nil)

local count = 0
local routed = bind("proof_routed", function()
	count = count + 1
	wraith.commands.create("proof-command", function() end)
	return { ready = true }
end)
package.preload.proof_provider = function()
	return {
		setup = function()
			assert(routed.require().ready)
		end,
	}
end

local provider = wraith.modules.provider(function(name)
	if name == "proof_routed" then
		return {
			plugin = "proof_provider",
			check = routed.check,
			activate = function()
				wraith.plugins.load("proof_provider", {}, { dependency = false })
			end,
		}
	end
end)
assert(routed.require().ready and count == 1)
assert(require("proof_routed").ready and count == 1)
assert(wraith.plugins.list()[1] == "proof_provider")
wraith.modules.remove_provider(provider)
rejects(routed.require, "no resolver")
