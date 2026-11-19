local M = {}

-- normalize resolves repository declarations without inspecting the working directory.
function M.normalize(value)
  assert(value[1] == nil or value.repo == nil, "choose one repository field")
  local repo = value.repo
  if repo == nil then repo = value[1] end
  local count = (repo ~= nil and 1 or 0) + (value.url ~= nil and 1 or 0) + (value.dir ~= nil and 1 or 0)
  assert(count == 1, "choose exactly one repo, url or dir")
  local location = value.dir or value.url or repo
  assert(type(location) == "string" and #location > 0, "package source must be a nonempty string")
  local path = location:sub(1, 1) == "/" or location == "~" or location:sub(1, 2) == "~/"
    or location:sub(1, 2) == "./" or location:sub(1, 3) == "../"
  local source

  if value.dir ~= nil or repo ~= nil and path then
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
    source = {kind="local", dir=location}
  elseif repo ~= nil and location:match("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$") then
    source = {kind="git", url="https://github.com/" .. location .. (location:sub(-4) == ".git" and "" or ".git")}
  else
    source = {kind="git", url=location}
  end

  local basename = location:gsub("/+$", ""):match("([^/:]+)$") or ""
  return source, basename:gsub("%.git$", "")
end

return M
