local manager = require("shroud")
local root = wraith.paths.stdpath("data") .. "/module-activation"
local config = wraith.paths.stdpath("config")

local function fixture(name, files)
	local path = root .. "/" .. name
	for file, source in pairs(files) do
		wraith.fs.mkdir(path .. "/lua/" .. (file:match("^(.*)/") or ""), { parents = true })
		wraith.fs.write(path .. "/lua/" .. file, source)
	end
	return path
end

local function rejects(call, expected)
	local ok, err = pcall(call)
	assert(not ok and tostring(err):find(expected, 1, true), tostring(err))
end

local namespace = fixture("namespace", {
	["activation_namespace/util.lua"] = [[
activation_namespace_calls=(activation_namespace_calls or 0)+1
return {value=42}
]],
})
local manual = fixture("manual", {
	["activation_manual.lua"] = "return {value='manual'}",
	["activation_manual/extra.lua"] = "return {value='extra'}",
})
local dotted = fixture("dotted", {
	["activation.flat.lua"] = "return {setup=function() activation_flat_setup=true end}",
})
local shadow = fixture("shadow", {
	["activation_shadow.lua"] = "error('managed shadow must not load')",
})
wraith.fs.mkdir(config .. "/lua", { parents = true })
wraith.fs.write(config .. "/lua/activation_shadow.lua", "return 'config source'")

local changing = fixture("changing", {
	["activation_changing.lua"] = "activation_changed_source_ran=true; return {}",
})
local dependency = fixture("dependency", {
	["never_execute.lua"] = "error('dependency library source ran')",
})
local own = fixture("own-init", {
	["activation_own.lua"] = [[
activation_own_source=(activation_own_source or 0)+1
return {setup=function() activation_own_setup=(activation_own_setup or 0)+1 end}
]],
})
local custom = fixture("custom", {
	["activation_custom.lua"] = "activation_custom_source=(activation_custom_source or 0)+1; return {ready=true}",
})
local initialized, configured, custom_entered = 0, 0, false
manager.setup({
	{ name = "activation-namespace", dir = namespace, lazy = true },
	{ name = "activation-manual", dir = manual, lazy = true, module = false },
	{ name = "activation-flat", dir = dotted, lazy = true, opts = {} },
	{ name = "activation-shadow", dir = shadow, lazy = true },
	{
		name = "activation-changing",
		dir = changing,
		lazy = true,
		dependencies = {
			{
				name = "activation-dependency",
				dir = dependency,
				config = function()
					assert(os.remove(changing .. "/lua/activation_changing.lua"))
				end,
			},
		},
		config = function()
			custom_entered = true
			require("activation_changing")
		end,
	},
	{
		name = "activation-own",
		dir = own,
		lazy = true,
		opts = {},
		init = function()
			initialized = initialized + 1
			assert(require("activation_own").setup)
			assert(activation_own_source == 1 and activation_own_setup == 1)
		end,
	},
	{
		name = "activation-custom",
		dir = custom,
		lazy = true,
		config = function()
			configured = configured + 1
			assert(require("activation_custom").ready)
		end,
	},
})
assert(initialized == 1 and activation_own_source == 1 and activation_own_setup == 1)
assert(require("activation_namespace.util").value == 42)
assert(require("activation_namespace.util").value == 42 and activation_namespace_calls == 1)
assert(require("activation_custom").ready and configured == 1 and activation_custom_source == 1)

rejects(function()
	require("activation_manual")
end, "not found")
manager.load("activation-manual")
assert(require("activation_manual").value == "manual")
assert(require("activation_manual.extra").value == "extra")
manager.unload("activation-manual")
rejects(function()
	require("activation_manual")
end, "load the package manually")

manager.load("activation-flat")
assert(activation_flat_setup and require("activation.flat").setup)
assert(wraith.modules.source(dotted, "activation.flat") == nil)
assert(require("activation_shadow") == "config source")
for _, row in ipairs(manager.status().packages) do
	if row.name == "activation-shadow" then
		assert(not row.loaded)
	end
end

rejects(function()
	require("activation_changing")
end, "no exact file source")
assert(custom_entered and activation_changed_source_ran == nil and package.loaded.activation_changing == nil)
