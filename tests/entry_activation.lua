local schema = require("wraith.manager.spec")
local loaders = require("wraith.manager.loader")
local base = wraith.paths.stdpath("data") .. "/activation-fixtures"

local function fixture(name, files)
	local root = base .. "/" .. name
	wraith.fs.mkdir(root, { parents = true })
	for path, source in pairs(files) do
		local parent = path:match("^(.*)/")
		if parent then
			wraith.fs.mkdir(root .. "/" .. parent, { parents = true })
		end
		wraith.fs.write(root .. "/" .. path, source)
	end
	return root
end

local function rejects(call, expected)
	local ok, err = pcall(call)
	assert(not ok and tostring(err):find(expected, 1, true), tostring(err))
end

local function exercise(specs, paths, run)
	local graph = schema.normalize(specs)
	local rows = {}
	for _, spec in ipairs(graph.ordered) do
		rows[#rows + 1] = { name = spec.name, path = paths[spec.name] }
	end
	local installations = require("wraith.manager.loader_installations").new(graph, rows)
	local loader = loaders.new(graph, installations, "entry_activation_test")
	loader.initialize()
	run(loader, graph)
	loader.unload_all()
end

package.preload.entry_activation_test = function()
	return {
		setup = function() end,
		run = function()
			local root = fixture("inferred", {
				["lua/selected_entry.lua"] = [[
      entry_source_calls=(entry_source_calls or 0)+1
      return {setup=function(opts) assert(opts.ready and opts.source_calls==1) end}
    ]],
			})
			local shadow = fixture("shadow", { ["lua/selected_entry.lua"] = "error('config shadow ran')" })
			wraith.runtimepath.prepend(shadow)
			exercise({
				{
					name = "selected-entry",
					dir = root,
					lazy = true,
					opts = function(spec, opts)
						assert(spec.main == nil)
						assert(type(require("selected_entry").setup) == "function")
						opts.ready, opts.source_calls = true, entry_source_calls
					end,
				},
			}, { ["selected-entry"] = root }, function(loader, graph)
				assert(graph.by_name["selected-entry"].main == nil)
				loader.load("selected-entry")
				loader.load("selected-entry")
				assert(entry_source_calls == 1 and loader.is_loaded("selected-entry"))
			end)

			for _, mode in ipairs({ "custom", "library" }) do
				local spec = { name = "selected-entry", dir = root, lazy = true }
				if mode == "custom" then
					spec.config = function() end
				end
				exercise({ spec }, { ["selected-entry"] = root }, function(loader)
					loader.load("selected-entry")
					local state = loader.states()["selected-entry"]
					assert(state.loaded and state.selected_main == "selected_entry" and state.loaded_main == nil)
					assert(
						state.main_source_kind == "file" and state.main_source_path == root .. "/lua/selected_entry.lua"
					)
					loader.unload("selected-entry")
					state = loader.states()["selected-entry"]
					assert(not state.loaded and state.selected_main == "selected_entry" and state.loaded_main == nil)
				end)
			end

			local library = fixture("library", { ["lua/never_load.lua"] = "error('library was required')" })
			local custom_calls = 0
			exercise({
				{ name = "library-one", dir = library, lazy = true },
				{ name = "library-two", dir = library, lazy = true },
				{
					name = "custom-only",
					dir = library,
					lazy = true,
					config = function(spec, opts)
						custom_calls = custom_calls + 1
						assert(spec.main == nil and next(opts) == nil)
					end,
				},
			}, { ["library-one"] = library, ["library-two"] = library, ["custom-only"] = library }, function(loader)
				loader.load("library-one")
				loader.load("library-two")
				loader.load("custom-only")
				assert(custom_calls == 1 and package.loaded.never_load == nil and package.preload.never_load == nil)
			end)

			for _, order in ipairs({ "explicit", "inferred" }) do
				local main = "collision_" .. order
				local first =
					fixture(order .. "-first", { ["lua/" .. main .. ".lua"] = "return {setup=function() end}" })
				local second =
					fixture(order .. "-second", { ["lua/" .. main .. ".lua"] = "error('conflicting source ran')" })
				local specs = {
					{ name = order .. "-first", dir = first, lazy = true, opts = {} },
					{ name = order .. "-second", dir = second, lazy = true, opts = {} },
				}
				specs[order == "explicit" and 1 or 2].main = main
				exercise(specs, { [order .. "-first"] = first, [order .. "-second"] = second }, function(loader)
					loader.load(order .. "-first")
					rejects(function()
						loader.load(order .. "-second")
					end, "already selected")
					assert(not loader.is_loaded(order .. "-second"))
				end)
			end

			for _, mode in ipairs({ "explicit", "inferred" }) do
				local main = "foreign_" .. mode
				local foreign = fixture(main, { ["lua/" .. main .. ".lua"] = "error('foreign cache source ran')" })
				local cache = {
					setup = function()
						error("foreign cache configured")
					end,
				}
				local spec = { name = main, dir = foreign, opts = {}, lazy = true }
				if mode == "explicit" then
					spec.main, cache = main, false
				end
				package.loaded[main] = cache
				exercise({ spec }, { [main] = foreign }, function(loader)
					rejects(function()
						loader.load(main)
					end, "cache is foreign")
					assert(package.loaded[main] == cache and package.preload[main] == nil)
				end)
			end

			for _, mode in ipairs({ "cache", "preload" }) do
				local main = "opts_" .. mode
				local path = fixture(main, { ["lua/" .. main .. ".lua"] = "error('options redirected source ran')" })
				local spec = {
					name = main,
					dir = path,
					lazy = true,
					opts = function(_, opts)
						if mode == "cache" then
							package.loaded[main] = {
								setup = function()
									error("foreign options module configured")
								end,
							}
						else
							package.preload[main] = function()
								error("options preload ran")
							end
						end
						return opts
					end,
				}
				exercise({ spec }, { [main] = path }, function(loader)
					rejects(function()
						loader.load(main)
					end, mode == "cache" and "cache is foreign" or "preload changed")
					assert(not loader.is_loaded(main))
				end)
			end

			local empty = fixture("unresolved", {})
			exercise(
				{ { name = "correctable", dir = empty, opts = {}, lazy = true } },
				{ correctable = empty },
				function(loader)
					rejects(function()
						loader.load("correctable")
					end, "cannot infer main")
					for _, path in ipairs(wraith.runtimepath.list()) do
						assert(path ~= empty)
					end
				end
			)
			local corrected = fixture("corrected", { ["lua/correctable.lua"] = "return {setup=function() end}" })
			exercise(
				{ { name = "correctable", dir = corrected, opts = {}, lazy = true } },
				{ correctable = corrected },
				function(loader)
					loader.load("correctable")
					assert(loader.is_loaded("correctable"))
				end
			)
			rejects(function()
				local graph = schema.normalize({ { name = "correctable", dir = empty, opts = {}, lazy = true } })
				local installations = require("wraith.manager.loader_installations").new(graph, {
					{ name = "correctable", path = empty },
				})
				loaders.new(graph, installations, "entry_activation_test")
			end, "source changed")

			local parent =
				fixture("prepared", { ["lua/prepared_entry.lua"] = "prepared_ran=true; return {setup=function() end}" })
			local dependency_calls = 0
			exercise({
				{
					name = "prepared-entry",
					dir = parent,
					opts = {},
					lazy = true,
					dependencies = {
						{
							name = "mutating-dependency",
							dir = empty,
							config = function()
								dependency_calls = dependency_calls + 1
								package.preload.prepared_entry = function()
									error("dependency replacement ran")
								end
							end,
						},
					},
				},
			}, { ["prepared-entry"] = parent, ["mutating-dependency"] = empty }, function(loader)
				rejects(function()
					loader.load("prepared-entry")
				end, "preload")
				assert(dependency_calls == 1 and prepared_ran == nil and not loader.is_loaded("prepared-entry"))
			end)

			local retry_path = fixture("retry", { ["lua/retry_source.lua"] = "error('retryable source failure')" })
			exercise(
				{ { name = "retry-source", dir = retry_path, opts = {}, lazy = true } },
				{ ["retry-source"] = retry_path },
				function(loader)
					rejects(function()
						loader.load("retry-source")
					end, "retryable source failure")
					assert(package.loaded.retry_source == nil)
					wraith.fs.write(
						retry_path .. "/lua/retry_source.lua",
						"return {setup=function() end}",
						{ overwrite = true }
					)
					loader.load("retry-source")
					assert(loader.is_loaded("retry-source"))
				end
			)

			local setup_path = fixture("setup-retry", {
				["lua/setup_retry.lua"] = [[
      setup_source_calls=(setup_source_calls or 0)+1
      local attempts=0
      return {setup=function()
        attempts=attempts+1
        if attempts==1 then error("retryable setup failure") end
      end}
    ]],
			})
			exercise(
				{ { name = "setup-retry", dir = setup_path, opts = {}, lazy = true } },
				{ ["setup-retry"] = setup_path },
				function(loader)
					rejects(function()
						loader.load("setup-retry")
					end, "retryable setup failure")
					assert(type(package.loaded.setup_retry) == "table")
					loader.load("setup-retry")
					assert(loader.is_loaded("setup-retry") and setup_source_calls == 1)
				end
			)

			local ordinary_path = fixture("ordinary", { ["lua/ordinary_entry.lua"] = "return {setup=function() end}" })
			exercise(
				{ { name = "ordinary-library", dir = ordinary_path, lazy = true } },
				{ ["ordinary-library"] = ordinary_path },
				function(loader)
					loader.load("ordinary-library")
					assert(type(require("ordinary_entry")) == "table")
				end
			)
			exercise(
				{ { name = "ordinary-library", dir = ordinary_path, opts = {}, lazy = true } },
				{ ["ordinary-library"] = ordinary_path },
				function(loader)
					rejects(function()
						loader.load("ordinary-library")
					end, "cache is foreign")
				end
			)

			local sources = require("wraith.manager.loader_sources")
			for _, mode in ipairs({ "new", "library" }) do
				local name = "publication-" .. mode
				local main = "publication_" .. mode
				local path = fixture(name, { ["lua/" .. main .. ".lua"] = "return {setup=function() end}" })
				if mode == "library" then
					exercise({ { name = name, dir = path, lazy = true } }, { [name] = path }, function(loader)
						loader.load(name)
					end)
				end
				local spec = schema.normalize({ { name = name, dir = path, opts = {}, lazy = true } }).by_name[name]
				local prepared = sources.prepare(spec, path)
				local install = prepared.install
				prepared.install = function()
					install()
					error("publication interrupted")
				end
				rejects(function()
					sources.reserve(spec, path, nil, prepared)
				end, "publication interrupted")
				prepared.install = install
				local state = sources.describe(spec, false)
				assert(state.selected_main == main and state.loaded_main == nil and state.main_source_kind == "file")
				assert(sources.prepare(spec, path) == prepared and prepared.entry.kind == "file")
				sources.reserve(spec, path, nil, prepared)
				assert(type(sources.require(name).setup) == "function")
			end
		end,
	}
end
wraith.plugins.load("entry_activation_test")
wraith.plugins.call("entry_activation_test", "run")
