local config = require("vimquire.config")

local M = {}

function M.setup(opts)
  config.setup(opts)
  if not config.options.lowercase_alias then
    pcall(vim.cmd, "cunabbrev search")
  end
end

--- :Search {query}. With no query, asks for one.
function M.search(query)
  query = vim.trim(query or "")
  if query == "" then
    return vim.ui.input({ prompt = "Search: " }, function(input)
      if input and vim.trim(input) ~= "" then
        M.search(input)
      end
    end)
  end
  require("vimquire.results").search(query)
end

function M.sources()
  require("vimquire.manager").open()
end

local function set_sources(ids, on)
  local devdocs = require("vimquire.sources.devdocs")
  local manager = require("vimquire.manager")
  local util = require("vimquire.util")
  devdocs.load_catalog(function(_, err)
    for _, id in ipairs(ids) do
      if not require("vimquire.sources").site(id) and not devdocs.get(id) then
        util.notify("unknown source: " .. id .. (err and (" (" .. err .. ")") or ""), vim.log.levels.WARN)
      else
        manager.toggle_source(id, on, function(ok)
          if ok and require("vimquire.sources").site(id) then
            util.notify((on and "turned on " or "turned off ") .. id)
          end
        end)
      end
    end
  end)
end

function M.add(ids)
  set_sources(ids, true)
end

function M.remove(ids)
  set_sources(ids, false)
end

--- :SearchOpen {url}: read any page as text.
function M.open(url)
  url = vim.trim(url or "")
  if not url:match("^%a[%w+.-]*://") then
    url = "https://" .. url
  end
  if not require("vimquire.util").is_web_url(url) then
    return require("vimquire.util").notify("not a web URL: " .. url, vim.log.levels.WARN)
  end
  require("vimquire.page").open({ kind = "web", url = url })
end

local function filter_prefix(list, lead)
  lead = lead:lower()
  return vim.tbl_filter(function(s)
    return s:lower():sub(1, #lead) == lead
  end, list)
end

function M.complete_add(lead)
  local ids = {}
  for _, site in ipairs(require("vimquire.sources").sites) do
    if not require("vimquire.state").site_enabled(site.id) then
      table.insert(ids, site.id)
    end
  end
  local state = require("vimquire.state")
  for _, doc in ipairs(require("vimquire.sources.devdocs").catalog() or {}) do
    if not state.doc(doc.slug) then
      table.insert(ids, doc.slug)
    end
  end
  return filter_prefix(ids, lead)
end

function M.complete_remove(lead)
  local state = require("vimquire.state")
  local ids = {}
  for _, site in ipairs(require("vimquire.sources").sites) do
    if state.site_enabled(site.id) then
      table.insert(ids, site.id)
    end
  end
  vim.list_extend(ids, state.enabled_docs())
  return filter_prefix(ids, lead)
end

return M
