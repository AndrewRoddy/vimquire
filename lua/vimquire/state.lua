-- Which sources are turned on. Saved to <data_dir>/state.json. Holds no
-- queries or history.
local config = require("vimquire.config")
local util = require("vimquire.util")

local M = {}

local state

local function path()
  return util.data_dir() .. "/state.json"
end

function M.get()
  if state then
    return state
  end
  state = util.read_json(path())
  if type(state) ~= "table" then
    state = { sites = {}, devdocs = {}, custom = {} }
    for _, id in ipairs(config.options.default_enabled) do
      state.sites[id] = true
    end
    M.save()
  end
  state.sites = state.sites or {}
  state.devdocs = state.devdocs or {}
  state.custom = state.custom or {}
  return state
end

function M.save()
  util.write_json(path(), state)
end

function M.site_enabled(id)
  return M.get().sites[id] == true
end

function M.set_site(id, on)
  M.get().sites[id] = on or nil
  M.save()
end

--- Info about an enabled DevDocs doc: { name, release, mtime, offline }.
function M.doc(slug)
  return M.get().devdocs[slug]
end

function M.set_doc(slug, info)
  M.get().devdocs[slug] = info
  M.save()
end

function M.enabled_docs()
  local slugs = vim.tbl_keys(M.get().devdocs)
  table.sort(slugs)
  return slugs
end

--- A site added with :SearchSite: { url, name, kind, enabled, count, pages }.
function M.custom(id)
  return M.get().custom[id]
end

function M.set_custom(id, info)
  M.get().custom[id] = info
  M.save()
end

function M.custom_ids()
  local ids = vim.tbl_keys(M.get().custom)
  table.sort(ids)
  return ids
end

return M
