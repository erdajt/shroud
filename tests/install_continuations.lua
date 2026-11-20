local continuations = require("wraith.manager.install_continuations")

local function rejects(call, expected)
	local ok, err = pcall(call)
	assert(not ok and tostring(err):find(expected, 1, true), tostring(err))
end

local function attempt()
	error("receipt contract must not execute queued work")
end

assert(#continuations.pending() == 0)
for _, operation in ipairs({ "", string.rep("x", 129), "control\n", false, {} }) do
	rejects(function()
		continuations.add(operation, attempt)
	end, "invalid continuation operation")
	rejects(function()
		continuations.wake(operation)
	end, "invalid continuation operation")
end
rejects(function()
	continuations.add("valid", {})
end, "must be a function")
assert(#continuations.pending() == 0)
continuations.wake("no-receipts")

local outside = wraith.events.on("shroud.test.unrelated", attempt)
assert(not continuations.cancel(outside))
assert(wraith.events.listeners("shroud.test.unrelated")[1] == outside)
wraith.events.off(outside)

local ids = {}
for index = 1, 16 do
	ids[index] = continuations.add("operation-" .. index, attempt)
end
assert(#continuations.pending() == 16)
rejects(function()
	continuations.add("overflow", attempt)
end, "exceed 16")
assert(#continuations.pending() == 16)
local detached = continuations.pending()
detached[1] = "foreign"
assert(continuations.pending()[1] == ids[1])
rejects(function()
	continuations.cancel(false)
end, "invalid continuation listener")
assert(continuations.cancel(ids[1]) and not continuations.cancel(ids[1]))
local replacement = continuations.add("replacement", attempt)
assert(replacement ~= ids[1] and #continuations.pending() == 16)

rejects(function()
	continuations.wake("not-a-matching-operation")
end, "runtime operations are disabled during setup and teardown")
assert(#continuations.pending() == 16)
continuations.cancel_all()
assert(#continuations.pending() == 0 and not continuations.cancel(replacement))
continuations.cancel_all()
