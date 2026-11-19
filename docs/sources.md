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
| `"./packages/tool"` | a directory below the effective config directory |
| `"~/projects/tool"` | a directory below your home |
| `"/path/to/tool"` | an absolute local module root |

repository strings also work in the first table position or the `repo` field. choose one source field. an explicit `url` preserves its bytes; `url = "/path/to/repository"` selects a git repository rather than a local module root. dependency declarations accept the same forms.

names use the lowercase source basename without `.git`. `name` overrides that identity; `main` chooses the Lua module. local paths resolve without consulting the working directory or testing whether a similarly named repository exists. local directories are never installed or rewritten.

HTTP, credentials embedded in URLs, query strings, fragments, control characters and option-shaped hosts or refs are rejected. configure authentication through the manager's git environment options. installing a plugin grants it your user account's permissions.

open `/packages` to inspect and install Git packages. after installation, `/reload` loads the selected revisions into a fresh runtime. automatic installation and the remaining lazy.nvim workflows are still being implemented.
