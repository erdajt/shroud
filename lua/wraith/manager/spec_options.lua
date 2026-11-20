local fields = require("wraith.manager.spec_fields")
local M = {}

-- capture validates a flat recipe without evaluating user callbacks.
function M.capture(layers)
	fields.array(layers, "option layers", 256)
	local result = fields.copy(layers)
	for _, layer in ipairs(result) do
		assert(type(layer) == "table", "option layer must be a table")
		for key in pairs(layer) do
			assert(key == "value" or key == "extend", "unknown option layer field")
		end
		assert(
			layer.value == nil or type(layer.value) == "table" or type(layer.value) == "function",
			"opts must be a table or function"
		)
		for _, path in ipairs(fields.array(layer.extend == nil and {} or layer.extend, "opts_extend", 64)) do
			assert(
				type(path) == "string"
					and #path <= 128
					and path:match("^[^.]+")
					and not path:find("..", 1, true)
					and path:sub(-1) ~= "."
					and not path:find("%c"),
				"opts_extend requires nonempty dotted paths"
			)
		end
	end
	return result
end

-- dictionary distinguishes maps and empty tables from consecutive nonempty lists.
local function dictionary(value)
	if type(value) ~= "table" then
		return false
	end
	if next(value) == nil then
		return true
	end

	local count = 0
	for key in pairs(value) do
		if type(key) ~= "number" or key % 1 ~= 0 or key < 1 then
			return true
		end
		count = count + 1
	end
	return count ~= #value
end

-- merge combines maps while replacing lists and deleting explicit null values.
local function merge(previous, value)
	if value == wraith.json.null then
		return nil
	end

	if dictionary(previous) and dictionary(value) then
		for key, child in pairs(value) do
			previous[key] = merge(previous[key], child)
		end
		return previous
	end

	if dictionary(value) then
		local result = {}
		for key, child in pairs(value) do
			result[key] = merge(nil, child)
		end
		return result
	end
	return value
end

-- resolve evaluates ordered option layers without exposing their stored tables to callbacks.
function M.resolve(spec, layers)
	local result = {}
	for _, layer in ipairs(M.capture(layers)) do
		local value = layer.value
		local extensions = {}
		for _, path in ipairs(layer.extend or {}) do
			local parts = {}
			for part in path:gmatch("[^.]+") do
				parts[#parts + 1] = part
			end
			if type(value) == "table" then
				local left, right = result, value
				for _, part in ipairs(parts) do
					left = type(left) == "table" and left[part] or nil
					right = type(right) == "table" and right[part] or nil
				end
				if type(left) == "table" and type(right) == "table" then
					fields.array(left, "extended option list", 4096)
					fields.array(right, "extended option list", 4096)
					local list = fields.copy(left)
					for _, item in ipairs(right) do
						list[#list + 1] = fields.copy(item)
					end
					extensions[#extensions + 1] = { parts = parts, list = list }
				end
			end
		end

		if type(value) == "function" then
			local returned = value(fields.copy(spec), result)
			if returned ~= nil then
				result = returned
			end
			assert(type(result) == "table", "package opts must produce a table")
		elseif value ~= nil then
			result = merge(result, fields.copy(value))
		end
		assert(type(result) == "table", "package opts must produce a table")

		for _, extension in ipairs(extensions) do
			local target = result
			for index = 1, #extension.parts - 1 do
				target = target[extension.parts[index]]
			end
			target[extension.parts[#extension.parts]] = extension.list
		end

		result = fields.copy(result)
	end
	return result
end

return M
