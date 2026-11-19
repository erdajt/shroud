local declarations, paths, calls = {}, {}, {}
local function declare(name, config, opts, main)
  declarations[#declarations + 1] = {name=name,main=main,dir="/tmp/"..name,lazy=true,config=config,opts=opts}
  paths[name], calls[name] = "/tmp/"..name, {required=0,setup=0,cleanup=0,teardown=0}
  package.preload[name] = function()
    local count = calls[name]
    count.required = count.required + 1
    return {
      setup=function(value)
        count.setup = count.setup + 1
        assert(type(value)=="table")
        if name=="function_options" then assert(value.value=="resolved") end
        return function() count.cleanup = count.cleanup + 1 end
      end,
      teardown=function() count.teardown = count.teardown + 1 end,
    }
  end
end

declare("library")
declarations[1].main = "library"
declare("skipped",false)
declarations[2].opts_extend = {"sources"}
declare("configured",true,nil,"configured")
declare("options",nil,{},"options")
declare("false_options",false,{},"false_options")
local option_calls, custom_calls = 0, 0
declare("function_options",false,function(_,opts)
  option_calls = option_calls + 1
  opts.value = "resolved"
end,"function_options")
declare("custom",function(_,opts)
  custom_calls = custom_calls + 1
  assert(next(opts)==nil)
  require("custom")
  return function() calls.custom.cleanup = calls.custom.cleanup + 1 end
end)
declare("custom_options",function(_,opts)
  custom_calls = custom_calls + 1
  assert(opts.value=="custom")
end,{value="custom"})
declare("callable",true,nil,"callable")
package.preload.callable = function()
  return {setup=setmetatable({}, {__call=function(_,opts)
    assert(type(opts)=="table")
    calls.callable.setup = calls.callable.setup + 1
  end})}
end
package.preload.library = function() error("library should not be required") end
package.preload.skipped = function() error("skipped setup should not require main") end

package.preload.setup_test = function()
  return {setup=function() end,run=function()
    local graph = require("wraith.manager.spec").normalize(declarations)
    local loader = require("wraith.manager.loader").new(graph,paths,"setup_test")
    loader.initialize()
    for _, spec in ipairs(declarations) do loader.load(spec.name); loader.load(spec.name) end
    assert(option_calls==1 and custom_calls==2)
    for _, name in ipairs({"configured","options","false_options","function_options"}) do
      assert(calls[name].required==1 and calls[name].setup==1)
    end
    assert(calls.custom.required==1 and calls.custom.setup==0)
    assert(calls.custom_options.required==0 and calls.callable.setup==1)
    assert(calls.library.required==0 and calls.skipped.required==0)
    loader.unload_all()
  end}
end
wraith.plugins.load("setup_test")
wraith.plugins.call("setup_test","run")

return function()
  for _, name in ipairs({"configured","options","false_options","function_options"}) do
    assert(calls[name].cleanup==1 and calls[name].teardown==1, name)
  end
  assert(calls.custom.cleanup==1 and calls.custom.teardown==0)
  assert(calls.library.teardown==0 and calls.skipped.teardown==0)
end
