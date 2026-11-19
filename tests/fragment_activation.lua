local options, calls = {}, {init=0, opts=0, config=0}
for index=1,2100 do options["key"..index]=index end
local graph = require("wraith.manager.spec").normalize({
  {name="tool",dir="/tmp/tool",lazy=true,init=function(spec)
    calls.init=calls.init+1
    assert(spec.opts.key2100==2100 and spec.opts_layers==nil)
  end,opts=function(spec, inherited)
    calls.opts=calls.opts+1
    assert(spec.opts.key2100==2100 and spec.opts_layers==nil)
    inherited.added=true
  end},
  {name="tool",opts=options,config=function(spec, opts)
    calls.config=calls.config+1
    assert(spec.opts.key2100==2100 and spec.opts_layers==nil)
    assert(opts.key2100==2100 and opts.added)
    wraith.commands.create("configured",function() end)
  end},
})
assert(calls.init==0 and calls.opts==0 and calls.config==0)
package.preload.fragment_test=function()
  local loader
  return {setup=function() end, configure=function()
    loader=require("wraith.manager.loader").new(graph,{tool="/tmp/tool"},"fragment_test")
    loader.initialize()
    assert(calls.init==1 and calls.opts==0 and calls.config==0)
    loader.load("tool")
    loader.load("tool")
    assert(calls.init==1 and calls.opts==1 and calls.config==1)
    loader.unload_all()
  end}
end
wraith.plugins.load("fragment_test")
wraith.plugins.call("fragment_test","configure")
assert(options.added==nil)
