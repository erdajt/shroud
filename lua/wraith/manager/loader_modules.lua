local M = {}
local sources = require("wraith.manager.loader_sources")
local fields = require("wraith.manager.spec_fields")
local entries = require("wraith.manager.loader_entry")

-- config_source preserves native lookup through symlinks and nondirectory ancestors.
local function config_source(path)
	local current = path
	while current ~= "" do
		local stat = wraith.fs.stat(current, { follow = true, missing_ok = true })
		if stat.exists then
			return current == path or stat.type ~= "directory"
		end
		if current == "/" then
			return false
		end

		current = current:match("^(.*)/[^/]+$")
		if current == "" then
			current = "/"
		end
	end

	return false
end

-- new freezes declarations while reading shared first-usable installation choices.
function M.new(graph, installations, names, config_root)
	assert(
		type(config_root) == "string"
			and config_root:sub(1, 1) == "/"
			and #config_root <= 4096
			and not config_root:find("%c"),
		"invalid package config root"
	)
	config_root = config_root:gsub("/+$", "")

	local original, loaded, preloads = package, rawget(package, "loaded"), rawget(package, "preload")
	assert(type(loaded) == "table" and type(preloads) == "table", "package tables were replaced; use /reload")

	local ordered, by_name, excluded = {}, {}, {}
	for _, source in ipairs(graph.ordered) do
		local spec = {
			name = source.name,
			source = fields.copy(source.source),
			main = source.main,
			config = source.config,
			module = source.module,
		}
		if source.opts ~= nil then
			spec.opts = {}
		end

		local identity = names[source.name]
		local record = {
			name = source.name,
			spec = spec,
			activation = assert(identity and identity.activation, "package activation is missing"),
		}
		ordered[#ordered + 1], by_name[record.name] = record, record
	end
	assert(#ordered <= 63, "package module candidates exceed runtime capacity")

	for name, reason in pairs(graph.excluded or {}) do
		excluded[name] = reason.reason
	end

	-- current captures one installation without retaining a second selection authority.
	local function current(record)
		if not record then
			return
		end
		local chosen = installations.get(record.name)
		return {
			name = record.name,
			spec = record.spec,
			activation = record.activation,
			path = chosen.path,
			commit = chosen.commit,
		}
	end

	-- result detaches selection metadata without copying the canonical binding or bound loader.
	local function result(record, binding, entry)
		return {
			name = record.name,
			spec = fields.copy(record.spec),
			path = record.path,
			commit = record.commit,
			activation = record.activation,
			binding = binding,
			entry = entry,
		}
	end

	return function(name)
		assert(
			rawequal(package, original)
				and rawequal(rawget(original, "loaded"), loaded)
				and rawequal(rawget(original, "preload"), preloads),
			"package tables were replaced; use /reload"
		)
		assert(type(name) == "string", "invalid package module name")
		if
			name == "shroud"
			or name:sub(1, 7) == "shroud."
			or name == "wraith.manager"
			or name:sub(1, 15) == "wraith.manager."
		then
			return
		end

		fields.main(name)
		local owner, binding = sources.lookup(name)
		local active = {}
		if owner then
			local record = current(by_name[owner])
			assert(
				record and record.path,
				"module "
					.. name
					.. " belongs to unavailable package "
					.. owner
					.. (excluded[owner] and " (" .. excluded[owner] .. ")" or "")
					.. "; restore its configuration and reload"
			)
			sources.check(record.spec, record.path, record.commit)
			binding.check()
			if record.spec.module == false then
				for _, plugin in ipairs(wraith.plugins.list()) do
					active[plugin] = true
				end
				assert(
					active[record.activation],
					"module activation is disabled for " .. owner .. "; load the package manually"
				)
			end
			return result(record, binding)
		end

		if rawget(loaded, name) ~= nil or rawget(preloads, name) ~= nil then
			return
		end

		local relative = name:gsub("%.", "/")
		for _, path in ipairs({
			config_root .. "/lua/" .. relative .. ".lua",
			config_root .. "/lua/" .. relative .. "/init.lua",
			config_root .. "/" .. relative .. ".lua",
			config_root .. "/" .. relative .. "/init.lua",
		}) do
			if config_source(path) then
				return
			end
		end

		for _, plugin in ipairs(wraith.plugins.list()) do
			active[plugin] = true
		end

		local candidates, preferred = {}, {}
		local root = entries.normalized(name:match("^[^.]+"))
		for _, declaration in ipairs(ordered) do
			local record = current(declaration)
			if record.path and (record.spec.module ~= false or active[record.activation]) then
				local ok, entry = pcall(wraith.modules.source, record.path, name)
				assert(ok, "package " .. record.name .. " module " .. name .. ": " .. tostring(entry))
				if entry then
					local candidate = { record = record, entry = entry }
					candidates[#candidates + 1] = candidate
					if entries.normalized(record.name) == root then
						preferred[#preferred + 1] = candidate
					end
				end
			end
		end
		if #candidates == 0 then
			return
		end

		local chosen
		if #candidates == 1 then
			chosen = candidates[1]
		elseif #preferred == 1 then
			chosen = preferred[1]
		end
		if chosen then
			return result(chosen.record, nil, chosen.entry)
		end

		local labels = {}
		for index, candidate in ipairs(candidates) do
			if index <= 8 then
				labels[#labels + 1] = candidate.record.name .. " (" .. candidate.record.path:sub(1, 384) .. ")"
			end
		end
		if #candidates > 8 then
			labels[#labels + 1] = tostring(#candidates - 8) .. " more omitted"
		end
		error("ambiguous package module " .. name .. ": " .. table.concat(labels, ", "))
	end
end

return M
