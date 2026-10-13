local config = require("vimquire.config")

local M = {}

function M.notify(msg, level)
  vim.notify("vimquire: " .. msg, level or vim.log.levels.INFO)
end

function M.urlencode(s)
  return (tostring(s):gsub("[^%w%-%._~]", function(c)
    return string.format("%%%02X", c:byte())
  end))
end

-- Encode each path segment but keep the slashes.
function M.encode_path(path)
  return (path:gsub("[^/]+", M.urlencode))
end

-- Text from the web is untrusted: drop control characters (ESC, C1 controls,
-- NUL...) so nothing can drive the terminal. Tabs and newlines survive.
function M.clean(s)
  s = s:gsub("\r\n", "\n"):gsub("\r", "\n")
  s = s:gsub("[%z\1-\8\11-\31\127]", "")
  s = s:gsub("\194[\128-\159]", "")
  return s
end

function M.data_dir(sub)
  local dir = config.options.data_dir
  if sub then
    dir = dir .. "/" .. sub
  end
  vim.fn.mkdir(dir, "p")
  return dir
end

function M.read_file(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local data = f:read("*a")
  f:close()
  return data
end

function M.read_json(path)
  local data = M.read_file(path)
  if not data then
    return nil
  end
  local ok, decoded = pcall(vim.json.decode, data, { luanil = { object = true, array = true } })
  return ok and decoded or nil
end

function M.write_json(path, value)
  local tmp = path .. ".tmp"
  local f = assert(io.open(tmp, "wb"))
  f:write(vim.json.encode(value))
  f:close()
  os.remove(path)
  assert(os.rename(tmp, path))
end

function M.file_size(path)
  local stat = vim.uv.fs_stat(path)
  return stat and stat.size or 0
end

function M.dir_size(dir)
  local total = 0
  if vim.uv.fs_stat(dir) then
    for name, kind in vim.fs.dir(dir, { depth = 5 }) do
      if kind == "file" then
        total = total + M.file_size(dir .. "/" .. name)
      end
    end
  end
  return total
end

function M.human_size(bytes)
  if not bytes or bytes <= 0 then
    return "0 B"
  elseif bytes < 1000 then
    return bytes .. " B"
  elseif bytes < 1e6 then
    return string.format("%d KB", math.floor(bytes / 1e3 + 0.5))
  elseif bytes < 1e9 then
    return string.format("%.1f MB", bytes / 1e6)
  end
  return string.format("%.2f GB", bytes / 1e9)
end

function M.utf8_char(cp)
  if cp < 0x80 then
    return string.char(cp)
  elseif cp < 0x800 then
    return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
  elseif cp < 0x10000 then
    return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
  elseif cp < 0x110000 then
    return string.char(
      0xF0 + math.floor(cp / 0x40000),
      0x80 + math.floor(cp / 0x1000) % 0x40,
      0x80 + math.floor(cp / 0x40) % 0x40,
      0x80 + cp % 0x40
    )
  end
  return ""
end

-- Split "https://host:port/path?query#frag" into scheme, host and the rest.
function M.parse_url(url)
  local scheme, authority, rest = url:match("^(%a[%w+.-]*)://([^/?#]*)(.*)$")
  if not scheme then
    return nil
  end
  local host = authority:gsub("^.*@", "")
  if host:sub(1, 1) == "[" then
    host = host:match("^%[(.-)%]") or host
  else
    host = host:gsub(":%d*$", "")
  end
  return { scheme = scheme:lower(), authority = authority, host = host:lower(), rest = rest }
end

local function normalize_path(path)
  -- path always starts with "/", so out[1] is "" and keeps the root.
  local out = {}
  for _, seg in ipairs(vim.split(path, "/", { plain = true })) do
    if seg == ".." then
      if #out > 1 then
        table.remove(out)
      end
    elseif seg ~= "." then
      table.insert(out, seg)
    end
  end
  local result = table.concat(out, "/")
  return result == "" and "/" or result
end

function M.resolve_url(base, href)
  href = vim.trim(href)
  if href:match("^%a[%w+.-]*:") then
    return href
  end
  local u = M.parse_url(base)
  if not u then
    return href
  end
  local origin = u.scheme .. "://" .. u.authority
  if href:sub(1, 2) == "//" then
    return u.scheme .. ":" .. href
  end
  local base_path = u.rest:gsub("[?#].*$", "")
  if base_path == "" then
    base_path = "/"
  end
  if href:sub(1, 1) == "#" then
    return origin .. u.rest:gsub("#.*$", "") .. href
  end
  if href:sub(1, 1) == "?" then
    return origin .. base_path .. href
  end
  local path, suffix = href:match("^([^?#]*)(.*)$")
  if path:sub(1, 1) ~= "/" then
    path = base_path:gsub("[^/]*$", "") .. path
  end
  return origin .. normalize_path(path) .. suffix
end

-- Links that come from page content must not reach your own machine or
-- network (router pages, local dev servers, cloud metadata endpoints...).
function M.is_private_host(host)
  if host == "" or host == "localhost" or host:match("%.localhost$") or host:match("%.local$") then
    return true
  end
  if host:match("^[%d]+$") or host:match("^0x") then
    return true -- integer and hex IPv4 forms
  end
  local a, b = host:match("^(%d+)%.(%d+)%.%d+%.%d+$")
  if a then
    a, b = tonumber(a), tonumber(b)
    return a == 0 or a == 10 or a == 127 or (a == 169 and b == 254) or (a == 172 and b >= 16 and b <= 31)
      or (a == 192 and b == 168) or (a == 100 and b >= 64 and b <= 127)
  end
  if host:find(":") then
    return host == "::1" or host == "::" or host:match("^f[cd]") ~= nil or host:match("^fe[89ab]") ~= nil
      or host:match("^::ffff:") ~= nil
  end
  return false
end

function M.is_web_url(url)
  local u = M.parse_url(url)
  return u ~= nil and (u.scheme == "http" or u.scheme == "https") and u.host ~= ""
end

return M
