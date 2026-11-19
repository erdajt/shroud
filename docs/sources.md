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

open `/packages` to inspect and install Git packages. after installation, `/reload` loads the selected revisions into a fresh runtime. automatic installation and the remaining lazy.nvim workflows are still being implemented.
