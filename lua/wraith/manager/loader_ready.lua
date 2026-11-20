local M = {}

-- capture records subscribers before source or setup can add readiness observers.
function M.capture()
	assert(wraith.capabilities.ready_replay, "package ready replay requires lifecycle catchup; update wraith")
	return wraith.events.listeners("ready")
end

-- replay catches up new subscribers through the host's transactional deduplication.
function M.replay(before)
	local seen, added = {}, {}
	for _, id in ipairs(before) do
		seen[id] = true
	end

	for _, id in ipairs(wraith.events.listeners("ready")) do
		if not seen[id] then
			added[#added + 1] = id
		end
	end
	if #added > 0 then
		wraith.events.replay_ready(added)
	end
end

return M
