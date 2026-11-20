local fields = require("wraith.manager.spec_fields")
local schema = require("wraith.manager.spec")
local M = {}

-- new owns validated detached declarations and the references belonging to each fragment.
function M.new()
	local fragments, groups, order, references = {}, {}, {}, 0
	local self = { order = order }

	function self.add(name, value, origin, parent, dependency)
		schema.name(name)
		assert(#fragments < 256, "package declarations exceed 256")
		assert(parent == nil or fragments[parent.id] == parent and parent.alive, "invalid fragment parent")
		local depth = parent and parent.depth + 1 or 1
		assert(depth <= 16, "package declarations exceed nesting limits")

		local location = fields.copy(origin or { kind = "declaration" })
		location.index = #fragments + 1
		local fragment = {
			id = #fragments + 1,
			name = name,
			value = value,
			origin = location,
			parent = parent and parent.id or nil,
			depth = depth,
			dependency = dependency == true,
			children = {},
			dependencies = {},
			dependency_set = {},
			alive = true,
		}

		local group = groups[name]
		if not group then
			group = { fragments = {}, revision = 0 }
			groups[name], order[#order + 1] = group, name
		end
		group.revision = group.revision + 1
		group.fragments[#group.fragments + 1] = fragment
		fragments[#fragments + 1] = fragment
		if parent then
			parent.children[#parent.children + 1] = fragment
		end

		return fragment
	end

	function self.depend(fragment, name)
		schema.name(name)
		assert(fragments[fragment.id] == fragment and fragment.alive, "invalid dependency owner")
		assert(fragment.name ~= name, "self dependency: " .. name)
		if fragment.dependency_set[name] then
			return false
		end

		assert(references < 1024, "package references exceed 1024")
		fragment.dependency_set[name] = true
		fragment.dependencies[#fragment.dependencies + 1] = name
		groups[fragment.name].revision = groups[fragment.name].revision + 1
		references = references + 1
		return true
	end

	function self.live(name)
		local group, result = groups[name], {}
		if not group then
			return result, 0
		end

		for _, fragment in ipairs(group.fragments) do
			if fragment.alive then
				result[#result + 1] = fragment
			end
		end
		return result, group.revision
	end

	function self.remove(name)
		local group = groups[name]
		if not group then
			return {}
		end

		local dirty, seen = {}, {}
		local function discard(fragment)
			if not fragment.alive then
				return
			end
			fragment.alive = false
			if not seen[fragment.name] then
				seen[fragment.name] = true
				dirty[#dirty + 1] = fragment.name
				groups[fragment.name].revision = groups[fragment.name].revision + 1
			end

			for _, child in ipairs(fragment.children) do
				discard(child)
			end
		end

		for _, fragment in ipairs(group.fragments) do
			discard(fragment)
		end
		return dirty
	end

	return self
end

return M
