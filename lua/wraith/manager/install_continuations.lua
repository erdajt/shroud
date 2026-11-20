local M = {}
local event = "shroud.install.pending"

-- identifier bounds operation and listener identities before touching registrations.
local function identifier(value, label)
	assert(
		type(value) == "string" and #value > 0 and #value <= 128 and not value:find("%c"),
		"invalid continuation " .. label
	)
end

-- pending reads the only authority for unconsumed work: live host subscriptions.
function M.pending()
	return wraith.events.listeners(event)
end

-- contains checks current receipt membership, including staged removals in this callback.
local function contains(id)
	for _, current in ipairs(M.pending()) do
		if current == id then
			return true
		end
	end
	return false
end

-- add keeps immutable operation identity and work inside one owned listener closure.
function M.add(operation, attempt)
	identifier(operation, "operation")
	assert(type(attempt) == "function", "continuation attempt must be a function")
	assert(#M.pending() < 16, "pending installation continuations exceed 16")

	local id
	id = wraith.events.on(event, function(ctx)
		if type(ctx.data) ~= "table" or ctx.data.operation ~= operation then
			return
		end

		wraith.schedule(function(current)
			if not contains(id) then
				return
			end
			wraith.events.off(id)
			attempt(current)
		end)
	end)
	return id
end

-- wake queues attempts without asserting that an installation succeeded.
function M.wake(operation)
	identifier(operation, "operation")
	local listeners = M.pending()
	if #listeners > 0 then
		wraith.events.dispatch(event, { operation = operation }, { listeners = listeners })
	end
end

-- cancel removes only receipts belonging to this private event.
function M.cancel(id)
	identifier(id, "listener")
	if not contains(id) then
		return false
	end
	wraith.events.off(id)
	return true
end

-- cancel_all stages cancellation without retaining a second receipt index.
function M.cancel_all()
	for _, id in ipairs(M.pending()) do
		wraith.events.off(id)
	end
end

return M
