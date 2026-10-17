-- :checkhealth vimquire
local M = {}

function M.check()
  local h = vim.health
  local config = require("vimquire.config")
  local o = config.options

  h.start("vimquire " .. config.version)

  if vim.fn.has("nvim-0.10") == 1 then
    h.ok("Neovim " .. tostring(vim.version()))
  else
    h.error("Neovim 0.10 or newer is required")
  end

  if vim.fn.executable(o.curl) == 1 then
    local out = vim.fn.system({ o.curl, "--version" })
    h.ok((out:match("^[^\n]+") or o.curl))
  else
    h.error("curl not found: " .. o.curl, { "Install curl, or set `curl` in setup() to its full path" })
  end

  local dir = o.data_dir
  if vim.fn.mkdir(dir, "p") == 1 and vim.fn.filewritable(dir) == 2 then
    h.ok("data folder is writable: " .. dir)
  else
    h.error("can't write to the data folder: " .. dir, { "Set `data_dir` in setup() to a writable folder" })
  end

  h.start("Stack Overflow")
  local key = config.stackexchange_key()
  if not key then
    h.info("No Stack Exchange key: limited to 300 requests a day per IP address, shared with everyone on your network")
    h.info("For 10,000 a day, put STACKEXCHANGE_KEY=<key> in " .. vim.fs.normalize(config.env_files()[1])
      .. ". Details: :help vimquire-key")
  elseif o.stackexchange_key and o.stackexchange_key ~= "" then
    h.ok("Stack Exchange key set in setup()")
  elseif vim.env.STACKEXCHANGE_KEY and vim.env.STACKEXCHANGE_KEY ~= "" then
    h.ok("Stack Exchange key set from $STACKEXCHANGE_KEY")
  else
    h.ok("Stack Exchange key set from an env file")
  end

  h.start("Sources")
  local state = require("vimquire.state")
  local on = {}
  for _, site in ipairs(require("vimquire.sources").sites) do
    if state.site_enabled(site.id) then
      table.insert(on, site.id)
    end
  end
  for _, id in ipairs(state.custom_ids()) do
    if state.custom(id).enabled then
      table.insert(on, id)
    end
  end
  vim.list_extend(on, state.enabled_docs())
  if #on > 0 then
    h.ok("on: " .. table.concat(on, ", "))
  else
    h.warn("no sources are on, so :Search finds nothing", { "Run :SearchSources to turn some on" })
  end
  if o.proxy and o.proxy ~= "" then
    h.info("requests go through proxy " .. o.proxy)
  end
end

return M
