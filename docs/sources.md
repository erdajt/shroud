# sources

[readme](../README.md) · [configuration](configuration.md)

use a repository shorthand, full URL or explicit local directory:

```lua
require("shroud").setup({
  { "https://github.com/owner/plugin.wraith", main = "plugin", opts = {} },
})
```

| declaration | source |
| --- | --- |
| `"owner/tool"` | `https://github.com/owner/tool.git` |
| `"https://github.com/owner/tool.git"` | the exact HTTPS URL |
| `"git@github.com:owner/tool.git"` | the exact SSH source |
| `{ url = "ssh://git@example.com/owner/tool" }` | the exact SSH URL |
| `{ dir = "packages/tool" }` | a directory below wraith's effective config directory |
| `{ "owner/tool", dir = "~/projects/local-copy" }` | the local copy, with `owner/tool` retained as its remote identity |
| `"./packages/tool"` | a directory below the effective config directory |
| `"~/projects/tool"` | a directory below your home |
| `"/path/to/tool"` | an absolute local module root |

repository strings also work in the first table position or the `repo` field. choose one remote field: positional, `repo` or `url`. an explicit `dir` may override that remote. a positional local path cannot also supply `dir`. an explicit `url` preserves its bytes; `url = "/path/to/repository"` selects a git repository rather than a local module root. dependency declarations accept the same forms.

names use the lowercase remote basename without `.git`, or the local basename when no remote exists. `name` overrides that identity; `main` chooses the Lua module. local paths resolve without consulting the working directory or testing whether a similarly named repository exists. local directories are never installed or rewritten.

a named declaration can add or replace a local directory before or after the remote declaration:

```lua
{ "owner/tool", branch = "work", pin = true },
{ name = "tool", dir = "~/projects/tool" },
```

`{ "tool", dir = "~/projects/tool" }` and `{ repo = "tool", dir = "~/projects/tool" }` also name a local override. `name` can rename these explicit local sources; a bare name without `dir` remains a reference and cannot rename another package. `url` still requires a valid git source. the last surviving `dir` wins. removing a scoped override restores the previous local directory or remote source. different remote identities for one name remain an error. branch, tag, commit and pin remain declared remote intent; local activation uses no git revision or pin and never checks out your working tree. `declared_source`, `declared_selector` and `declared_pin` expose that intent to callbacks after normalization. standalone local declarations cannot select or pin git revisions. an explicit local override removes an old git pin from the active lock on install/update.

HTTP, credentials embedded in URLs, query strings, fragments, control characters and option-shaped hosts or refs are rejected. configure authentication through the manager's git environment options. installing a plugin grants it your user account's permissions.

open `/packages` to inspect and install Git packages. a first usable installation becomes available in the current runtime after completion or an explicit `load`. local directories created after setup can also become available on `load`. automatic installation and the remaining lazy.nvim workflows are still being implemented.

available selections stay fixed for the runtime, even before their first activation. updates require `/reload`; failed or unloaded source reservations also keep their identity. a missing checkout observed at commit A can adopt a first usable commit B when source, selector and pin still match. installation choices come from the validated lock and inspected paths, never from a completion message alone. a committed choice may survive rejected UI publication; an explicit `load` reconciles it without fetching again. status remains observational. package-row `restart_required` compares the current disk installation with the selected source; the storage operation's `restart_required` list records changed revisions and does not account for runtime adoption.

## development copies

```lua
require("shroud").setup({
  { "owner/tool", dev = true, opts = {} },
}, {
  dev = { path = "~/projects", patterns = { "owner/" }, fallback = false },
})
```

`dev.path` defaults to `~/projects`. a string selects `path/name`; a function receives a detached plugin snapshot and returns the full directory. relative paths resolve below wraith's effective config directory. `patterns` defaults to `{}` and matches literal substrings of the declared remote URL. `dev = true` selects a development copy; `dev = false` suppresses pattern matching. an explicit `dir` wins and skips the development callback and fallback check. local directories do not imply `dev = true`.

`fallback` defaults to `false`: a missing development directory stays local and reports its path when loading fails. with `fallback = true`, a followed directory is local; a missing path, dangling symlink, regular file or file ancestor selects the remote instead. permission failures, symlink loops and cancellation remain errors. invalid callback results never trigger fallback.

path callbacks see `name`, the declared `url`, original revision fields and `dev = true`, with no selected `dir` yet. cond and enabled callbacks see the selected `dir` and `dev`; remote fallback has `dev = false` and no local directory. selection is cached per surviving fragment revision. removing a scope recomputes changed plugins; removing only a dependency edge does not rerun the path callback. each normalization permits at most 1024 path callback invocations. disabled or optional plugins may run path callbacks before pruning.

normalization does not fetch or run git. local copies preserve their files and use no operational git selector or pin. remote fallback keeps the declared selector and pin. status reports `dev` and detached `declared_source`, `declared_selector` and `declared_pin` from the selected configuration. switching a source already exposed to Lua requires `/reload`; a disappearing local directory does not trigger a mid-load remote fetch.
