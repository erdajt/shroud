local spec = require("wraith.manager.spec")
local forms = {
	{ "owner/tool", "https://github.com/owner/tool.git" },
	{ "owner/tool.git", "https://github.com/owner/tool.git" },
	{ "https://github.com/owner/tool", "https://github.com/owner/tool" },
	{ "https://github.com/owner/tool.git", "https://github.com/owner/tool.git" },
	{ "ssh://git@github.com/owner/tool.git", "ssh://git@github.com/owner/tool.git" },
	{ "git@github.com:owner/tool.git", "git@github.com:owner/tool.git" },
	{ "git@example.com:tool.git", "git@example.com:tool.git" },
}

for _, form in ipairs(forms) do
	for _, declaration in ipairs({ form[1], { form[1] }, { repo = form[1] }, { url = form[2] } }) do
		local graph = spec.normalize({ declaration })
		assert(#graph.ordered == 1 and graph.by_name.tool, form[1])
		assert(graph.by_name.tool.source.url == form[2], form[1])
	end
end

local config, home = wraith.paths.stdpath("config"), assert(os.getenv("HOME"))
for _, form in ipairs({
	{ "./packages/../tool", config .. "/tool" },
	{ "../tool", config:match("^(.*)/[^/]+$") .. "/tool" },
	{ "~/packages/tool", home .. "/packages/tool" },
	{ "/explicit/tool", "/explicit/tool" },
}) do
	for _, declaration in ipairs({ form[1], { form[1] }, { dir = form[1] } }) do
		local package = spec.normalize({ declaration }).by_name.tool
		assert(package and package.source.kind == "local" and package.source.dir == form[2], form[1])
	end
end
assert(spec.normalize({ { dir = "packages/tool" } }).by_name.tool.source.dir == config .. "/packages/tool")

local input = { "https://github.com/owner/tool.git", opts = { nested = { keep = true } } }
local graph = spec.normalize({ input })
assert(input[1] == "https://github.com/owner/tool.git" and input.repo == nil and input.url == nil)
graph.by_name.tool.opts.nested.keep = false
assert(input.opts.nested.keep)

for _, source in ipairs({
	"https://token@example.com/tool",
	"https://example.com/tool?token=secret",
	"https://example.com/tool#fragment",
	"http://example.com/tool",
	"-remote",
	"ssh://user:password@example.com/tool",
	"git@-host:tool",
	"git@host:-tool",
	"ext::program",
	"relative/nested/tool",
	"https://example.com/a\nb",
}) do
	assert(not pcall(spec.normalize, { source }), source)
end

for _, declaration in ipairs({
	{ "owner/tool", repo = "owner/other" },
	{ "./tool", dir = "./other" },
	{ "owner/tool", url = "https://example.com/tool" },
	{ dir = "~another/tool" },
	{ dir = "" },
	{ url = false },
}) do
	assert(not pcall(spec.normalize, { declaration }))
end

for _, dependency in ipairs({ "git@example.com:tool.git", { "git@example.com:tool.git" } }) do
	local graph = spec.normalize({ { "owner/app", dependencies = { dependency } } })
	assert(graph.by_name.app.dependencies[1] == "tool")
	assert(graph.by_name.tool.source.url == "git@example.com:tool.git")
end
