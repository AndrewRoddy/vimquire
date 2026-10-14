local M = {}

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
  -- Leave nil to use $STACKEXCHANGE_KEY or the .env file in the plugin folder.
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

local env_file

--- KEY=VALUE pairs from the .env file in the plugin folder. Read once.
function M.env()
  if env_file then
    return env_file
  end
  env_file = {}
  local f = io.open(M.root .. "/.env", "r")
  if not f then
    return env_file
  end
  for line in f:lines() do
    local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if k then
      env_file[k] = v:match('^"(.*)"$') or v:match("^'(.*)'$") or v
    end
  end
  f:close()
  return env_file
end

--- The Stack Exchange key from setup(), $STACKEXCHANGE_KEY or .env, in that
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
