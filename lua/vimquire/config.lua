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
  stackexchange_key = nil,
  wikipedia_lang = "en",
  -- Your SearXNG instance with the json format enabled, e.g. "http://localhost:8888".
  searxng_url = nil,
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

return M
