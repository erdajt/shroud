local lock = require("wraith.manager.store_lock")
local M = {}

function M.read(specs, options)
	local current, raw = lock.read(options.lockfile)
	local rows, metadata = wraith.json.array(), {}

	-- stat caches followed and literal paths independently for this inspection only.
	local function stat(path, follow)
		local key = tostring(follow) .. ":" .. path
		if not metadata[key] then
			local ok, value = pcall(wraith.fs.stat, path, { follow = follow, missing_ok = true })
			metadata[key] = { ok = ok, value = value }
		end
		return metadata[key]
	end

	-- directory distinguishes absence from ENOTDIR and broken links without parsing errors.
	local function directory(path, follow)
		local result = stat(path, follow)
		if not result.ok then
			return "blocked", tostring(result.value)
		end
		if result.value.exists then
			if result.value.type == "directory" then
				return "available"
			end
			return "blocked", path .. ": not a directory"
		end

		local ancestor = path
		for _ = 1, 128 do
			local found = stat(ancestor, false)
			if not found.ok then
				return "blocked", tostring(found.value)
			end
			if found.value.exists then
				if found.value.type == "symlink" then
					found = stat(ancestor, true)
					if not found.ok then
						return "blocked", tostring(found.value)
					end
				end
				if found.value.exists and found.value.type == "directory" then
					return "absent", path .. ": does not exist"
				end
				return "blocked", ancestor .. ": not an accessible directory"
			end
			if ancestor == "/" then
				break
			end
			ancestor = ancestor:match("^(.*)/[^/]+$")
			if ancestor == "" then
				ancestor = "/"
			end
		end
		return "blocked", path .. ": cannot establish absence within 128 ancestors"
	end

	for _, spec in ipairs(specs) do
		local row = { name = spec.name, source = spec.source, selector = spec.selector, pin = spec.pin }
		local entry = current.packages[spec.name]
		if spec.source.kind == "local" then
			row.state = "local"
			row.availability, row.error = directory(spec.source.dir, true)
			if row.availability == "available" then
				row.path = spec.source.dir
			else
				row.error = "local package directory: " .. row.error
			end
		elseif entry and wraith.json.encode(entry.source) ~= wraith.json.encode(spec.source) then
			row.state, row.availability, row.error =
				"source-conflict", "blocked", "package source changed; use a distinct name or reconcile the lock"
		else
			row.commit, row.state = entry and entry.commit, "missing"
			local paths = { options.root, options.root .. "/objects", options.root .. "/objects/" .. spec.name }
			if entry then
				paths[#paths + 1] = paths[#paths] .. "/" .. entry.commit
			end
			for _, path in ipairs(paths) do
				row.availability, row.error = directory(path, false)
				if row.availability ~= "available" then
					break
				end
			end
			if row.availability == "available" then
				if entry then
					row.path, row.state = paths[#paths], "installed"
				else
					row.availability = "absent"
				end
			end
		end
		rows[#rows + 1] = row
	end

	return wraith.json.decode(wraith.json.encode(rows)), current, raw
end

return M
