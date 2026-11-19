# shroud

package management for wraith. declare plugins in lua, configure their options and load them through owned lifecycle hooks.

```lua
require("shroud").setup({
  {
    "owner/plugin.wraith",
    main = "plugin",
    opts = {},
  },
})
```

shroud keeps installed revisions separate from loaded code. changes to an exposed module take effect in a fresh runtime. package operations use a versioned lock, immutable checkouts and recoverable publication.

requires wraith host api 2 and git. this repository contains the package source; wraith integration tests validate the selected package commit through the host runtime.

see [source declarations](docs/sources.md) for GitHub URLs, SSH, local directories and options. package-owned assertions in `tests/` run against the installed candidate bundle through wraith's contract suite.

licensed under [gnu gpl v3](LICENSE).
