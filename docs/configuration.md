# configuration

[readme](../README.md) · [sources](sources.md) · [imports](imports.md)

split plugin declarations across files or add overrides after an imported spec:

```lua
require("shroud").setup({
  {
    "owner/tool.wraith",
    main = "tool",
    opts = { window = { width = 80 }, sources = { "history" } },
  },
  {
    "tool.wraith",
    opts_extend = { "sources" },
    opts = { window = { height = 24 }, sources = { "commands" } },
  },
})
```

both declarations select one plugin. its options contain both window dimensions and both sources. a name-only override can appear before its source declaration; a name without any source is an error.

## merge order

fragments follow declaration order, including imports and nested dependencies. the first fragment establishes ordering. later scalar fields replace earlier fields, including `false`. omitted fields preserve earlier values. the first surviving resolved source stays selected; changing it under the same name is an error. remote URLs with or without a trailing `.git` match, but different transports and local directories remain distinct.

| field | repeated declarations |
| --- | --- |
| `opts` | nested maps merge; lists replace |
| `opts_extend` | dotted paths whose lists append; inherited by later fragments |
| `dependencies` | names combine in first-seen order; nested declarations also merge |
| `cmd`, `event` | triggers combine in first-seen order |
| `keys` | later action replaces the same normalized key and mode |
| `init`, `config`, `enabled`, `cond`, `lazy`, `priority`, `main`, `pin` | last supplied value wins |

`opts_extend` takes effect from its declaration onward. it does not change earlier merges. an empty list resets extension paths. when both inherited and new targets are tables, both must be lists; otherwise the value follows normal merge rules. duplicate key aliases inside one fragment remain an error; overrides belong in separate fragments.

choose one revision selector across the merged plugin: `branch`, `tag` or `commit`. selectors are validated before merging; they do not silently override a selector of another kind. this stricter rule differs from lazy.nvim's selector precedence.

## scoped and optional declarations

```lua
{ "owner/workspace.wraith", enabled = false, specs = {
  { "owner/history.wraith", optional = true, opts = { limit = 200 } },
} }
```

`specs` owns nested declarations without creating dependency edges or dependency-only loading defaults. removing a parent removes its contributions to those children. independently declared children survive with only their remaining settings. cached imports keep their original scope; replay cannot rescue removed declarations. use `dependencies` for activation ordering.

`optional = true` keeps a contribution only when a surviving nonoptional declaration names that plugin. a full dependency declaration or name-only override qualifies; a bare dependency reference does not. optional-only declarations may omit sources. surviving declarations must resolve a source, and cannot borrow one from a removed scope.

collection precedes pruning, including trusted import execution. malformed declarations and conflicting sources fail before pruning. final dependency and trigger checks use survivors. references to known excluded packages disappear; unknown dependencies still fail. scoped self-overrides are allowed.

excluded packages do not run init or setup, register triggers or install missing sources. explicit load, unload and install requests report the exclusion reason. change the configuration and reload to activate them. status distinguishes `disabled`, `conditional`, `optional` and `scope`; an existing explicitly disabled nonoptional package pin is labeled `retained pin`, without claiming an installed checkout. optional-only and scope-removed entries are pruned from the lock on install/update unless a false condition protects them. files are retained; object garbage collection is not implemented.

## conditions

```lua
require("shroud").setup({
  { "owner/review.wraith", cond = function()
    return os.getenv("WRAITH_REVIEW") == "1"
  end },
}, { defaults = { cond = true } })
```

package `cond` overrides `defaults.cond`; both accept booleans or functions returning a boolean. functions receive a detached initial merged spec with original dependency names. each condition runs once in declaration order before disabled/optional pruning. false bypasses enabled evaluation and activation. changing contributions later does not reverse that initial decision. defaults are validated before imports; unsupported defaults fail rather than being ignored.

a false condition protects existing pins for its original declared dependency closure, including optional conditional roots. scoped children are not included by ownership alone. cycles are safe in excluded closures; unknown references never protect unrelated pins. a conditional child removed with its parent keeps its protection even when its exclusion reason is scope. independently active dependencies follow their normal source and revision rules, including removal of old git pins when made local.

retention does not install missing plugins, create new pins or verify existing objects. native object cleanup is not implemented. explicit loading cannot override a false condition; change the configuration and reload.

## option callbacks

```lua
{ "tool.wraith", opts = function(plugin, opts)
  opts.window.width = 100
end }
```

callbacks receive the final plugin spec and options inherited so far. returning `nil` retains mutations; returning a table replaces the options. `wraith.json.null` in a table declaration removes a map value. an empty map preserves inherited map fields, while an empty table replaces an inherited list. options and callback arguments are detached from the input declarations.

option callbacks run when the plugin activates. `enabled` runs once per effective contribution and dependency revision during normalization. removing a scope may change that revision; unchanged predicates are not repeated. callbacks receive detached merged fields and effective dependency names, without recursive `specs`. normalization allows at most 1,024 combined `cond` and `enabled` predicate calls. `init` and `config` retain their lifecycle timing. invalid declarations, cycles and structural limits fail before initialization. option failures during activation roll back owned registrations; a later load can retry.

specs allow 256 fragments and 63 enabled plugins. option copying allows 4096 entries and depth 16, including inherited recipes and callback results. these are structural limits, not byte limits for strings.

## startup order

plugins declared only inside `dependencies` default to lazy loading. a separate top-level declaration makes that plugin eager unless it has triggers or an explicit `lazy = true`. `lazy = false` always requests startup loading. a completed import does not create another declaration, so repeating a dependency import at the top level does not change its loading default.

`priority` defaults to `50`; explicit zero and negative values remain valid. eager plugins start in descending priority, with first declaration order breaking ties. each plugin loads its dependencies before its own configuration. a high-priority lazy plugin does not pull its dependencies ahead in the startup queue.

## setup

`opts = {}` or `config = true` requests `require(main).setup(opts)`. an options function runs at activation and can mutate or replace inherited options. the entry module must return a table with a callable `setup`; missing setup is an activation error.

without `opts` or a truthy `config`, activation exposes the package path without requiring its main module. `main` and `opts_extend` alone do not request setup. libraries can be required by their dependents when needed.

`config = false` skips configuration only when no options are declared. with `opts`, automatic setup still runs, matching lazy.nvim. this replaces the earlier behavior where false always suppressed setup.

`config = function(plugin, opts) ... end` owns setup and any require calls. its returned cleanup function runs on unload; shroud does not infer a module teardown for that callback. automatic setup retains its returned cleanup and the module's `teardown`, each called once on unload or failed publication.

unlike lazy.nvim's logged setup errors, failed shroud setup rejects activation and rolls back owned registrations. its original lazy trigger remains available for retry. require caches, runtime paths and arbitrary external effects remain outside that rollback.

## entrypoints

explicit `main` selects that module inside the installed plugin. otherwise, automatic setup inspects immediate files and directories with `init.lua` under its `lua/` directory. it selects one normalized name match, then a sole candidate. missing or ambiguous candidates require `main` or a custom `config` function.

name matching lowercases names, strips `wraith-`, `.wraith`, `.lua` and `-lua` affixes, and ignores separators. digits remain significant. exact module names use dotted identifiers; each part starts with a letter or underscore. `shroud` and `wraith.manager` namespaces are reserved. two explicit `main` declarations cannot claim the same name, even when configuration is skipped.

inferred setup loads the selected file through native `require` caching. it cannot fall back to a same-named configuration file or global preload. explicit `main` may select a deliberate `package.preload` function; diagnostics label that source `preload`. custom config controls its own require calls. libraries without setup do not claim an entrypoint. binding every plugin submodule is a separate capability, not provided by entrypoint selection.

callbacks receive the declared `main`, which stays nil when inferred. status reports `requested_main`, `selected_main`, `loaded_main`, `main_source_kind` and `main_source_path` separately. `loaded_main` exists only during active automatic setup. selected provenance survives unload and failed publication; a checkout commit does not identify a synthetic preload's code.

once exposed, package source, checkout, requested main and resolved entrypoint remain fixed for the runtime. changing them requires `/reload`. unknown cached modules are rejected before setup. clearing an owned cache permits the same source to load again; it does not permit a source change. ordinary source exceptions retry when native require cleared its own marker. setup failures reuse the owned module. source errors that changed the cache or preload require reload.

a timed-out entry load requires `/reload` because its Lua bookkeeping may not finish. shroud preserves source-written cache values and never adopts them after interruption. managed source failures include source stack traces as diagnostic strings. replacing package/cache/preload tables before manager loading is unsupported; replacing captured tables afterward is rejected. direct calls to the manager's private preload wrappers are unsupported; use `require` or a [bound source loader](https://github.com/erdajt/wraith/blob/main/docs/lua/modules.md).
