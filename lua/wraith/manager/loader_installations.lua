local M = {}
local fields = require("wraith.manager.spec_fields")
local schema = require("wraith.manager.spec")
local sources = require("wraith.manager.loader_sources")

-- same_source compares normalized repository or local directory identities.
local function same_source(left, right)
	return left.kind == right.kind and left.url == right.url and left.dir == right.dir
end

-- new shares the first usable installation choice across activation and module discovery.
function M.new(graph, rows)
	local configured, selected = {}, {}
	for _, spec in ipairs(graph.ordered) do
		configured[spec.name] = schema.descriptor({
			name = spec.name,
			source = spec.source,
			selector = spec.selector,
			pin = spec.pin,
		})
	end
	for _, row in ipairs(rows) do
		assert(configured[row.name] and not selected[row.name], "invalid inspected package: " .. tostring(row.name))
		selected[row.name] = fields.copy(row)
	end
	for name in pairs(configured) do
		assert(selected[name], "missing inspected package: " .. name)
	end

	local self = {}

	-- get detaches diagnostics and provenance from the authoritative selection.
	function self.get(name)
		return fields.copy(selected[name])
	end

	-- adopt validates every new usable choice before publishing one snapshot replacement.
	function self.adopt(current, lock, active)
		local next_selected, seen = {}, {}
		for name, row in pairs(selected) do
			next_selected[name] = row
		end
		for _, row in ipairs(current) do
			local name, spec = row.name, configured[row.name]
			assert(spec and not seen[name], "invalid inspected package: " .. tostring(name))
			seen[name] = true
			if not selected[name].path then
				if row.path then
					assert(
						not sources.exposed(name) and not active[name],
						"package source is already exposed; use /reload: " .. name
					)
					assert(
						type(row.source) == "table" and same_source(spec.source, row.source),
						"installed package source changed: " .. name
					)
					if spec.source.kind == "local" then
						assert(row.path == spec.source.dir, "installed local directory changed: " .. name)
					else
						local entry = lock.packages[name]
						assert(
							entry and row.state == "installed" and entry.commit == row.commit,
							"installed package has no matching lock: " .. name
						)
						assert(
							same_source(spec.source, entry.source)
								and spec.selector.kind == entry.selector.kind
								and spec.selector.value == entry.selector.value
								and spec.pin == entry.pin,
							"installed package intent changed: " .. name
						)
					end
				end
				next_selected[name] = fields.copy(row)
			end
		end
		for name in pairs(configured) do
			assert(seen[name], "missing inspected package: " .. name)
		end

		selected = next_selected
	end

	return self
end

return M
