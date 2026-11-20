local schema = require("wraith.manager.spec")
local loaders = require("wraith.manager.loader")
local sources = require("wraith.manager.loader_sources")
local root = wraith.paths.stdpath("data") .. "/init-activation"
local runtime = "init_activation_test"
local active_loader, allowed = nil, {}

local function fixture(name, source)
  local path = root .. "/" .. name
  wraith.fs.mkdir(path .. "/lua", {parents=true})
  wraith.fs.write(path .. "/lua/" .. name .. ".lua", source)
  allowed[name] = true
  return path
end

local function create(specs, paths)
  active_loader = loaders.new(schema.normalize(specs), paths, runtime)
  return active_loader
end

package.preload[runtime] = function()
  return {setup=function()
    wraith.modules.provider(function(name)
      local owner, binding = sources.lookup(name)
      if owner and allowed[owner] then
        return {plugin="wraith.manager.package."..owner..".active", check=binding.check,
          activate=function() active_loader.load(owner) end}
      end
    end)
  end, run=function()
    local capability_path=fixture("capability_probe", "return {}")
    local capability_graph=schema.normalize({{name="capability_probe",dir=capability_path,lazy=true}})
    for _, name in ipairs({"plugins_state", "plugins_unload_many"}) do
      local previous=wraith.capabilities[name]
      wraith.capabilities[name]=false
      local ok, err=pcall(loaders.new, capability_graph, {capability_probe=capability_path}, runtime)
      wraith.capabilities[name]=previous
      assert(not ok and tostring(err):find("update wraith",1,true))
      assert(package.preload["wraith.manager.package.capability_probe.init"]==nil)
      assert(package.preload["wraith.manager.package.capability_probe.active"]==nil)
    end
    local trace = {}
    init_trace = trace
    local path = fixture("init_self", [[
      table.insert(init_trace,"source")
      return {setup=function()
        table.insert(init_trace,"setup")
        wraith.commands.create("init-self",function() end)
      end}
    ]])
    local loader = create({{name="init_self",dir=path,lazy=true,opts={},cmd="init-self",init=function()
      table.insert(trace,"before")
      active_loader.load("init_self")
      wraith.plugins.depend("wraith.manager.package.init_self.active")
      table.insert(trace,"after")
    end}}, {init_self=path})
    loader.initialize()
    assert(table.concat(trace,",")=="before,source,setup,after")
    assert(loader.is_loaded("init_self") and loader.is_managed("init_self"))
    loader.unload("init_self")
    assert(not loader.is_loaded("init_self") and not loader.is_managed("init_self"))

    local first, second = fixture("init_first", "return {}"), fixture("init_second", "return {setup=function() end}")
    local first_calls, second_calls, setup_calls = 0, 0, 0
    loader=create({
      {name="init_first",dir=first,lazy=true,init=function()
        first_calls=first_calls+1
        active_loader.load("init_second")
        wraith.plugins.depend("wraith.manager.package.init_second.active")
      end},
      {name="init_second",dir=second,lazy=true,config=function()
        setup_calls=setup_calls+1
      end,init=function()
        second_calls=second_calls+1
        active_loader.load("init_second")
        wraith.plugins.depend("wraith.manager.package.init_second.active")
      end},
    }, {init_first=first,init_second=second})
    loader.initialize()
    assert(first_calls==1 and second_calls==1 and setup_calls==1)
    local ok, err=pcall(loader.unload,"init_second")
    assert(not ok and tostring(err):find("required by",1,true))
    assert(loader.is_managed("init_second") and loader.is_loaded("init_second"))
    loader.unload_all()
    assert(not loader.is_managed("init_first") and not loader.is_loaded("init_second"))

    local failure = fixture("init_retry", [[
      init_retry_sources=(init_retry_sources or 0)+1
      wraith.commands.create("init-retry-source",function() end)
      return {setup=function() end}
    ]])
    local failing, attempts = true, 0
    loader=create({{name="init_retry",dir=failure,lazy=true,opts={},init=function()
      attempts=attempts+1
      active_loader.load("init_retry")
      wraith.plugins.depend("wraith.manager.package.init_retry.active")
      if failing then error("init failed after activation") end
    end}}, {init_retry=failure})
    ok,err=pcall(loader.initialize)
    assert(not ok and tostring(err):find("init failed after activation",1,true))
    assert(not loader.is_managed("init_retry") and not loader.is_loaded("init_retry"))
    assert(package.loaded.init_retry==nil and sources.lookup("init_retry")=="init_retry")
    failing=false
    loader.initialize()
    assert(attempts==2 and init_retry_sources==2 and loader.is_loaded("init_retry"))
    loader.unload_all()
  end}
end
wraith.plugins.load(runtime)
wraith.plugins.call(runtime,"run")
