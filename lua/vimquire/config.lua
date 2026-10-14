local M = {}

M.version = "0.1.0"

M.defaults = {
  -- Where downloaded indexes and the enabled-sources list live.
  data_dir = vim.fn.stdpath("data") .. "/vimquire",
  curl = "curl",
  timeout = 30,
  -- Results shown per page of :Search, and the most any one source contributes.
  results = 20,
  per_source = 8,
  -- Hard-wrap width for pages (capped to the window width).
  width = 100,
  -- Private mode: :Search commands are removed from command history.
  private = true,
  -- e.g. "socks5h://127.0.0.1:9050" to route everything through Tor.
  proxy = nil,
  -- Expand a lowercase :search into :Search.
  lowercase_alias = true,
  -- Free key from stackapps.com raises the daily limit from 300 to 10,000.
  -- Leave nil to use $STACKEXCHANGE_KEY or a vimquire.env file (see M.env_files).
  stackexchange_key = nil,
  wikipedia_lang = "en",
  -- Sites turned on the first time vimquire runs. Nothing is downloaded for these.
  default_enabled = { "stackoverflow", "wikipedia" },
  -- Re-fetch the DevDocs catalog when it is older than this (seconds).
  catalog_max_age = 7 * 24 * 3600,
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  opts = opts or {}
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts)
  -- tbl_deep_extend merges lists index by index; replace them whole instead.
  if opts.default_enabled then
    M.options.default_enabled = opts.default_enabled
  end
end

-- The plugin folder: this file is lua/vimquire/config.lua inside it.
M.root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")

--- Where KEY=VALUE files are read from, first match wins: vimquire.env in
--- your Neovim config folder, then .env in the plugin folder.
function M.env_files()
  return { vim.fn.stdpath("config") .. "/vimquire.env", M.root .. "/.env" }
end

local function read_env(path)
  local vars = {}
  local f = io.open(path, "r")
  if not f then
    return vars
  end
  for line in f:lines() do
    local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    v = k and (v:match('^"(.*)"$') or v:match("^'(.*)'$") or v)
    -- Skip blank values so an empty KEY= doesn't hide one set elsewhere.
    if v and v ~= "" then
      vars[k] = v
    end
  end
  f:close()
  return vars
end

local env_vars

--- Variables from the env files. Read once, or again with reload.
function M.env(reload)
  if reload or not env_vars then
    env_vars = {}
    for _, path in ipairs(vim.fn.reverse(M.env_files())) do
      env_vars = vim.tbl_extend("force", env_vars, read_env(path))
    end
  end
  return env_vars
end

--- The Stack Exchange key from setup(), $STACKEXCHANGE_KEY or an env file, in that
--- order. nil means no key: the shared limit of 300 requests a day per IP.
function M.stackexchange_key()
  local keys = { M.options.stackexchange_key, vim.env.STACKEXCHANGE_KEY, M.env().STACKEXCHANGE_KEY }
  for i = 1, 3 do
    if keys[i] and keys[i] ~= "" then
      return keys[i]
    end
  end
end

return M
