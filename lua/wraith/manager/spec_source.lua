local M = {}

-- local_path expands one local root without inspecting the filesystem.
function M.local_path(location)
  assert(type(location) == "string" and #location > 0 and #location <= 4096 and not location:find("%c"), "invalid local package directory")
  if location:sub(1, 1) == "~" then
    assert(location == "~" or location:sub(1, 2) == "~/", "only the current user's home directory can be expanded")
    local home = os.getenv("HOME")
    assert(type(home) == "string" and home:sub(1, 1) == "/", "home directory is unavailable")
    location = home .. location:sub(2)
  elseif location:sub(1, 1) ~= "/" then
    location = wraith.paths.stdpath("config") .. "/" .. location
  end
  local parts = {}
  for part in location:gmatch("[^/]+") do
    if part == ".." then table.remove(parts) elseif part ~= "." then parts[#parts + 1] = part end
  end
  location = "/" .. table.concat(parts, "/")
  return require("wraith.manager.spec").source({kind="local", dir=location}).dir
end

-- declaration separates a remote identity from its explicit local override.
function M.declaration(value)
  assert(value[1] == nil or value.repo == nil, "choose one repository field")
  local repo = value.repo
  if repo == nil then repo = value[1] end
  assert(repo == nil or value.url == nil, "choose one repo or url")
  local location = value.url
  if location == nil then location = repo end
  assert(location ~= nil or value.dir ~= nil, "choose a repo, url or dir")
  local result = {}
  if location ~= nil then
    assert(type(location) == "string" and #location > 0, "package source must be a nonempty string")
    local path = location:sub(1, 1) == "/" or location == "~" or location:sub(1, 2) == "~/"
      or location:sub(1, 2) == "./" or location:sub(1, 3) == "../"
    if repo ~= nil and path then
      assert(value.dir == nil, "local repository path cannot also specify dir")
      result.dir = M.local_path(location)
      location = result.dir
    elseif repo ~= nil and value.dir ~= nil and not location:find("[/:]") then
      require("wraith.manager.spec").name(location)
    else
      local url = location
      if repo ~= nil and location:match("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$") then
        url = "https://github.com/" .. location .. (location:sub(-4) == ".git" and "" or ".git")
      end
      result.remote = require("wraith.manager.spec").source({kind="git", url=url})
    end
  end
  if value.dir ~= nil then result.dir = M.local_path(value.dir) end
  location = location or result.dir
  local basename = location:gsub("/+$", ""):match("([^/:]+)$") or ""
  result.basename = basename:gsub("%.git$", "")
  return result
end

-- normalize returns the effective source while retaining declared remote metadata.
function M.normalize(value)
  local declared = M.declaration(value)
  local source = declared.dir and {kind="local", dir=declared.dir} or declared.remote
  return source, declared.basename, declared
end

return M
