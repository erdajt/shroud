# imports

[readme](../README.md) · [configuration](configuration.md) · [sources](sources.md)

keep plugin specs under your wraith config directory:

```text
init.lua
lua/plugins/editor.lua
lua/plugins/terminal.lua
```

```lua
-- init.lua
require("shroud").setup({ { import = "plugins" } })
```

```lua
-- lua/plugins/editor.lua
return { { "owner/editor.wraith", main = "editor", opts = {} } }
```

imports discover the module file, directory `init.lua`, immediate `.lua` files and immediate child directories with `init.lua`. sources load in module-name order. deeper directories need an explicit import. each source must return exactly one table containing a plugin declaration or declarations.

selected package namespaces retain their source boundaries. ordinary imports use the first matching runtime root, with `lua/` before legacy root files. later roots cannot fill a matching directory. use `wraith.runtimepath.prepend` or `append` to register another root. simultaneous `plugins.lua` and `plugins/init.lua` are an ambiguity error.

## functions and conditions

```lua
{ name = "local tools", import = function()
  return { { dir = "packages/review", opts = {} } }
end }
```

function imports require a name. string imports can use `name` as an alias. `cond` and `enabled` accept booleans or zero-argument functions returning a boolean. a false gate skips discovery and loading.

an import name evaluates once per normalization. repeated completed names skip gates and reuse their contributed package names, including when several plugins import the same dependencies. reusing a name for a different module or function is an error. distinct aliases and directory/child imports can evaluate the same file again, matching lazy.nvim's name-based behavior.

imports load sources afresh and clear their own `package.loaded` entries without caching the returned specs. a later normalization starts fresh. other modules retain ordinary require caching. recursive imports report their chain; a failed graph does not initialize plugins. arbitrary effects performed by trusted import code cannot be rolled back.

## mixed declarations

```lua
{ "owner/tool.wraith", main = "tool", import = "tool_specs" }
```

a source declaration can also import specs. the package fragment is collected first. an explicit package `name` also names its import; a function import therefore requires an explicit name. `cond` and `enabled` participate in both the zero-argument import gate and package evaluation with a detached spec argument. a shared function can run in both contexts. manager `defaults.cond` applies only to packages, not import gates.

## bounds

normalization allows 128 import identities and 256 source evaluations. graph nesting, fragment and option limits still apply. imports require a host with `wraith.capabilities.modules`; older hosts report that requirement instead of falling back to a different source.

shroud rejects ambiguous sources, recursive imports, conflicting aliases and extra return values. these strict errors differ from lazy.nvim's more permissive cases.
