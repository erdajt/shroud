# shroud

package management for wraith. declare plugins in lua, configure their options and [activate them through require](docs/configuration.md#require-activation), commands or events.

```lua
require("shroud").setup({
	{
		"owner/plugin.wraith",
		main = "plugin",
		opts = {},
	},
})
```

shroud keeps installed revisions separate from loaded code. changing an exposed source path or revision requires a fresh runtime. package operations use a versioned lock, immutable checkouts and recoverable publication.

requires wraith host api 2 and git. this repository contains the package source; wraith integration tests validate the selected package commit through the host runtime.

see [imports](docs/imports.md) for modular specs, [configuration](docs/configuration.md) for inherited options and repeated declarations, and [source declarations](docs/sources.md) for GitHub URLs, SSH, local directories and options. package-owned assertions in `tests/` run against the installed candidate bundle through wraith's contract suite. a contract may return a function for checks after the host accepts startup changes, including deferred cleanup.

## development

format lua with [stylua](https://github.com/JohnnyMorganz/StyLua) 2.6.0 using the repository's [configuration](stylua.toml):

```sh
stylua --verify lua tests
stylua --check --verify lua tests
```

separate logical steps with blank lines. keep a lookup, its validation and its related assignment together. the formatter handles layout; review the grouping when changing a function. [ci](.github/workflows/format.yml) checks formatting on pushes to main and pull requests.

licensed under [gnu gpl v3](LICENSE).
