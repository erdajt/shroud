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

fragments follow declaration order, including imports and nested dependencies. the first fragment establishes ordering. later scalar fields replace earlier fields, including `false`. omitted fields preserve earlier values. the first resolved source stays selected; changing it under the same name is an error. remote URLs with or without a trailing `.git` match, but different transports and local directories remain distinct.

| field | repeated declarations |
| --- | --- |
| `opts` | nested maps merge; lists replace |
| `opts_extend` | dotted paths whose lists append; inherited by later fragments |
| `dependencies` | names combine in first-seen order; nested declarations also merge |
| `cmd`, `event` | triggers combine in first-seen order |
| `keys` | later action replaces the same normalized key and mode |
| `init`, `config`, `enabled`, `lazy`, `priority`, `main`, `pin` | last supplied value wins |

`opts_extend` takes effect from its declaration onward. it does not change earlier merges. an empty list resets extension paths. when both inherited and new targets are tables, both must be lists; otherwise the value follows normal merge rules. duplicate key aliases inside one fragment remain an error; overrides belong in separate fragments.

choose one revision selector across the merged plugin: `branch`, `tag` or `commit`. selectors are validated before merging; they do not silently override a selector of another kind. this stricter rule differs from lazy.nvim's selector precedence.

## option callbacks

```lua
{ "tool.wraith", opts = function(plugin, opts)
  opts.window.width = 100
end }
```

callbacks receive the final plugin spec and options inherited so far. returning `nil` retains mutations; returning a table replaces the options. `wraith.json.null` in a table declaration removes a map value. an empty map preserves inherited map fields, while an empty table replaces an inherited list. options and callback arguments are detached from the input declarations.

option callbacks run when the plugin activates. `enabled` runs once per merged plugin during normalization. `init` and `config` retain their lifecycle timing. invalid declarations, cycles and structural limits fail before initialization. option failures during activation roll back owned registrations; a later load can retry.

specs allow 256 fragments and 63 enabled plugins. option copying allows 4096 entries and depth 16, including inherited recipes and callback results. these are structural limits, not byte limits for strings.

## startup order

plugins declared only inside `dependencies` default to lazy loading. a separate top-level declaration makes that plugin eager unless it has triggers or an explicit `lazy = true`. `lazy = false` always requests startup loading. a completed import does not create another declaration, so repeating a dependency import at the top level does not change its loading default.

`priority` defaults to `50`; explicit zero and negative values remain valid. eager plugins start in descending priority, with first declaration order breaking ties. each plugin loads its dependencies before its own configuration. a high-priority lazy plugin does not pull its dependencies ahead in the startup queue.
