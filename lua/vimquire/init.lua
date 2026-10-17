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
  local only = query:match("^@(%S+)$")
  if only then
    return M.open_source(only:lower())
  end
  require("vimquire.results").search(query)
end

--- :Search @name with no query: open the source's own start page. Sites
--- with no start page (Stack Overflow, Wikipedia) ask for a query instead.
function M.open_source(name)
  local custom = require("vimquire.sources.custom")
  local state = require("vimquire.state")
  local page = require("vimquire.page")
  for _, id in ipairs(state.custom_ids()) do
    if custom.matches(id, name) then
      local info = state.custom(id)
      return page.open({ kind = "web", url = custom.start_url(id),
        title = info.kind == "mdbook" and (info.name .. " contents") or nil })
    end
  end
  local devdocs = require("vimquire.sources.devdocs")
  for _, slug in ipairs(state.enabled_docs()) do
    if devdocs.matches(slug, name) then
      return page.open({ kind = "devdocs", slug = slug, path = "index", title = state.doc(slug).name })
    end
  end
  vim.ui.input({ prompt = "Search @" .. name .. ": " }, function(input)
    if input and vim.trim(input) ~= "" then
      M.search("@" .. name .. " " .. input)
    end
  end)
end

function M.sources()
  require("vimquire.manager").open()
end

local function set_sources(ids, on)
  local custom = require("vimquire.sources.custom")
  local devdocs = require("vimquire.sources.devdocs")
  local manager = require("vimquire.manager")
  local state = require("vimquire.state")
  local util = require("vimquire.util")
  devdocs.load_catalog(function(_, err)
    for _, id in ipairs(ids) do
      if state.custom(id) and not on then
        local freed = custom.remove(id)
        util.notify("removed " .. id .. " (deleted " .. util.human_size(freed) .. ")")
        manager.refresh()
      elseif state.custom(id) then
        manager.toggle_source(id, true)
        util.notify("turned on " .. id)
      elseif not require("vimquire.sources").site(id) and not devdocs.get(id) then
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

--- :SearchAdd. Arguments that look like URLs are added as sites, and
--- ":SearchAdd name url" names the site.
function M.add(args)
  local custom = require("vimquire.sources.custom")
  if #args == 2 and not custom.is_url(args[1]) and custom.is_url(args[2]) then
    return M.add_site(args[1], args[2])
  end
  local ids = {}
  for _, a in ipairs(args) do
    if custom.is_url(a) then
      M.add_site(nil, a)
    else
      table.insert(ids, a)
    end
  end
  if #ids > 0 then
    set_sources(ids, true)
  end
end

--- :SearchSite [name] {url}: search any site. See sources/custom.lua.
function M.add_site(name, url)
  local custom = require("vimquire.sources.custom")
  local manager = require("vimquire.manager")
  local util = require("vimquire.util")
  local id
  local err
  id, err = custom.add(name, url, function(ok, e)
    if ok then
      util.notify("added " .. require("vimquire.state").custom(id).name .. ": " .. custom.status(id)
        .. ". Search it with :Search @" .. id .. " <query>")
    else
      util.notify("couldn't add " .. url .. ": " .. tostring(e), vim.log.levels.ERROR)
    end
    manager.refresh()
  end)
  if not id then
    return util.notify(err, vim.log.levels.WARN)
  end
  util.notify("adding " .. url .. " as @" .. id .. "...")
  manager.refresh()
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
  for _, id in ipairs(state.custom_ids()) do
    if not state.custom(id).enabled then
      table.insert(ids, id)
    end
  end
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
  vim.list_extend(ids, state.custom_ids())
  vim.list_extend(ids, state.enabled_docs())
  return filter_prefix(ids, lead)
end

return M
