local config = require("vimquire.config")
local devdocs = require("vimquire.sources.devdocs")
local state = require("vimquire.state")

local M = {}

-- Websites, in the order they appear in :SearchSources.
M.sites = {
  require("vimquire.sources.stackoverflow"),
  require("vimquire.sources.wikipedia"),
  require("vimquire.sources.searxng"),
}

function M.site(id)
  for _, site in ipairs(M.sites) do
    if site.id == id then
      return site
    end
  end
end

local function site_matches(site, filter)
  return site.id == filter or vim.tbl_contains(site.aliases, filter)
end

--- Everything :Search should ask, given an optional "@filter".
--- Each target is { name, run = function(query, page, cb) }.
function M.targets(filter)
  local n = config.options.per_source
  local targets = {}
  for _, site in ipairs(M.sites) do
    if state.site_enabled(site.id) and site.available() and (not filter or site_matches(site, filter)) then
      table.insert(targets, {
        name = site.id,
        run = function(query, page, cb)
          return site.search(query, page, n, cb)
        end,
      })
    end
  end
  local slugs = vim.tbl_filter(function(slug)
    return not filter or devdocs.matches(slug, filter)
  end, state.enabled_docs())
  if #slugs > 0 then
    table.insert(targets, {
      name = "devdocs",
      run = function(query, page, cb)
        vim.schedule(function()
          cb(devdocs.search(query, slugs, page, n))
        end)
      end,
    })
  end
  return targets
end

return M
