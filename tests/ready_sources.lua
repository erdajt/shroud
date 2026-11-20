local bindings = require("wraith.manager.loader_binding")
local ready = require("wraith.manager.loader_ready")

local function bind(name, source)
	package.preload[name] = source
	local binding = bindings.new({ name = name, kind = "preload", identity = source, load = source })
	binding.install()
	return binding
end

local function rejects(call, expected)
	local ok, err = pcall(call)
	assert(not ok and tostring(err):find(expected, 1, true), tostring(err))
end

local original, requests = wraith.events.replay_ready, {}
wraith.events.replay_ready = function(ids)
	requests[#requests + 1] = ids
	original(ids)
end
local baseline = ready.capture()
local inner = bind("ready_inner", function()
	wraith.events.on("ready", function() end)
	return true
end)
local outer = bind("ready_outer", function()
	assert(inner.require())
	wraith.events.on("ready", function() end)
	return true
end)
assert(outer.require())
wraith.events.on("ready", function() end)
ready.replay(baseline)
assert(#requests == 3 and #requests[1] == 1 and #requests[2] == 2 and #requests[3] == 3)
assert(requests[1][1] == requests[2][1] and requests[2][2] == requests[3][2])
assert(outer.require() and #requests == 3)

local falsy = bind("ready_falsy", function()
	wraith.events.on("ready", function() end)
	return false
end)
assert(falsy.require() == false and falsy.require() == false)
assert(#requests == 5 and #requests[4] == 1 and #requests[5] == 1)
assert(requests[4][1] ~= requests[5][1])

local failed = bind("ready_source_failed", function()
	wraith.events.on("ready", function() end)
	error("source failed before replay")
end)
rejects(failed.require, "source failed before replay")
assert(#requests == 5 and package.loaded.ready_source_failed == nil)

wraith.events.replay_ready = function()
	error("replay effect budget exhausted")
end
local attempts = 0
local retry = bind("ready_retry", function()
	attempts = attempts + 1
	wraith.events.on("ready", function() end)
	return true
end)
local proof = retry.check("ready_retry", "before", nil, true)
rejects(retry.require, "replay effect budget exhausted")
assert(package.loaded.ready_retry == nil and attempts == 1)
assert(retry.check("ready_retry", "before", nil, true) == proof)
wraith.events.replay_ready = original
assert(retry.require() and attempts == 2)

local written = {}
wraith.events.replay_ready = function()
	error("replay failed after cache write")
end
local poisoned = bind("ready_poisoned", function()
	wraith.events.on("ready", function() end)
	package.loaded.ready_poisoned = written
	return written
end)
rejects(poisoned.require, "replay failed after cache write")
assert(package.loaded.ready_poisoned == written)
package.loaded.ready_poisoned = nil
rejects(poisoned.require, "cache is poisoned")
wraith.events.replay_ready = original

local capability = wraith.capabilities.ready_replay
wraith.capabilities.ready_replay = false
local ran = false
local unsupported = bind("ready_unsupported", function()
	ran = true
	return true
end)
rejects(unsupported.require, "update wraith")
assert(not ran and package.loaded.ready_unsupported == nil)
wraith.capabilities.ready_replay = capability
assert(unsupported.require() and ran)
