-- :SearchSources, the list of everything you can search. Websites and
-- DevDocs are accordions; DevDocs docs with several versions (Python,
-- Node...) are accordions inside it. Turning a doc off deletes its files;
-- turning it back on downloads them again. Sites added with :SearchSite are
-- listed under "Your sites" and keep their files while off.
local buf = require("vimquire.buf")
local config = require("vimquire.config")
local custom = require("vimquire.sources.custom")
local devdocs = require("vimquire.sources.devdocs")
local sources = require("vimquire.sources")
local state = require("vimquire.state")
local util = require("vimquire.util")

local M = {}

local expanded = { sites = true, custom = true, devdocs = false }
local filter = nil
local mbuf
local rows = {} -- lnum -> row
local catalog_error

local OPEN, CLOSED = "▾", "▸"

local function pad(s, n)
  local w = vim.api.nvim_strwidth(s)
  return w >= n and (s .. " ") or (s .. string.rep(" ", n - w))
end

local function matches(...)
  if not filter then
    return true
  end
  for _, s in ipairs({ ... }) do
    if s and s:lower():find(filter, 1, true) then
      return true
    end
  end
  return false
end

-- DevDocs docs grouped by name, keeping catalog order: { name, docs = {...} }
local function families()
  local list, by_name = {}, {}
  for _, doc in ipairs(devdocs.catalog() or {}) do
    local fam = by_name[doc.name]
    if not fam then
      fam = { name = doc.name, docs = {} }
      by_name[doc.name] = fam
      table.insert(list, fam)
    end
    table.insert(fam.docs, doc)
  end
  return list
end

local function doc_status(doc)
  local slug = doc.slug
  local what = devdocs.downloading(slug)
  if what == "offline" then
    return "downloading offline copy...", "vimquireBusy"
  elseif what then
    return "downloading...", "vimquireBusy"
  end
  local info = state.doc(slug)
  if info then
    local s = util.human_size(devdocs.disk_size(slug)) .. " on disk" .. (info.offline and ", offline" or "")
    if devdocs.update_available(slug) then
      s = s .. ", update available"
    end
    return s, "vimquireOn"
  end
  return "offline copy " .. util.human_size(doc.db_size), "vimquireDim"
end

local function checkbox(slug)
  if devdocs.downloading(slug) then
    return "[*]"
  end
  return state.doc(slug) and "[x]" or "[ ]"
end

function M.render()
  if not mbuf or not vim.api.nvim_buf_is_valid(mbuf) then
    return
  end
  local width = buf.width(mbuf)
  local lines, hl = {}, {}
  rows = {}
  local function add(text, group, row)
    table.insert(lines, text)
    if group then
      table.insert(hl, { #lines, group })
    end
    rows[#lines] = row
  end
  local function add_check(text, row, on, status, status_group)
    add(text .. status, nil, row)
    local l = lines[#lines]
    local box = l:find("%[[ x%*~]%]")
    if box then
      table.insert(hl, { #lines, on and "vimquireOn" or "vimquireOff", box - 1, box + 2 })
    end
    if status_group then
      table.insert(hl, { #lines, status_group, #l - #status, #l })
    end
  end

  local enabled = state.enabled_docs()
  local disk = 0
  for _, slug in ipairs(enabled) do
    disk = disk + devdocs.disk_size(slug)
  end
  local on_sites = 0
  for _, site in ipairs(sources.sites) do
    if state.site_enabled(site.id) and site.available() then
      on_sites = on_sites + 1
    end
  end
  for _, id in ipairs(custom.ids()) do
    disk = disk + custom.disk_size(id)
    if state.custom(id).enabled then
      on_sites = on_sites + 1
    end
  end

  add(string.format(" vimquire sources   %d on · %s on disk", on_sites + #enabled, util.human_size(disk)), "vimquireHeading")
  add(" <Space> on/off   <CR> open/close   a add site   O offline copy   u update docs   f filter   q close", "vimquireDim")
  if filter then
    add(" filter: " .. filter, "vimquireBusy")
  end
  add(" " .. string.rep("─", width - 1), "vimquireDim")

  -- Websites
  local site_rows = {}
  for _, site in ipairs(sources.sites) do
    if matches(site.label, site.id) then
      table.insert(site_rows, site)
    end
  end
  if #site_rows > 0 then
    local open = expanded.sites or filter ~= nil
    add(" " .. (open and OPEN or CLOSED) .. " Websites", "vimquireGroup", { kind = "group", key = "sites" })
    if open then
      for _, site in ipairs(site_rows) do
        local on = state.site_enabled(site.id) and site.available()
        local note = site.available() and site.note or site.unavailable_note()
        add_check("     " .. (on and "[x] " or "[ ] ") .. pad(site.label, 26) .. pad(site.id, 16),
          { kind = "site", id = site.id, parent = "sites" }, on, note, "vimquireDim")
      end
    end
    add("")
  end

  -- Your sites
  local custom_rows = vim.tbl_filter(function(id)
    local info = state.custom(id)
    return matches(info.name, id, info.url)
  end, custom.ids())
  if not filter or #custom_rows > 0 then
    local open = expanded.custom or filter ~= nil
    add(" " .. pad((open and OPEN or CLOSED) .. " Your sites", 30) .. string.format("%d added", #custom.ids()),
      "vimquireGroup", { kind = "group", key = "custom" })
    if open then
      for _, id in ipairs(custom_rows) do
        local info = state.custom(id)
        local box = custom.building(id) and "[*] " or (info.enabled and "[x] " or "[ ] ")
        local status, group = custom.status(id)
        add_check("     " .. box .. pad(vim.fn.strcharpart(info.name, 0, 25), 26) .. pad(id, 16),
          { kind = "custom", id = id, parent = "custom" }, info.enabled, status, group)
      end
      if #custom_rows == 0 then
        add("     a adds any site by URL, e.g. https://doc.rust-lang.org/book/", "vimquireDim")
      else
        add("     a add   D delete   R download again", "vimquireDim")
      end
    end
    add("")
  end

  -- DevDocs
  local catalog = devdocs.catalog()
  local enabled_names = table.concat(enabled, ", ")
  local summary
  if not catalog then
    summary = catalog_error and ("couldn't load catalog: " .. catalog_error) or "loading catalog..."
  else
    summary = string.format("%d docs, %d on%s", #catalog, #enabled, #enabled > 0 and (": " .. enabled_names) or "")
  end
  local fams = {}
  for _, fam in ipairs(families()) do
    local docs = vim.tbl_filter(function(doc)
      return matches(doc.name, doc.slug, doc.alias, devdocs.label(doc))
    end, fam.docs)
    if #docs > 0 then
      table.insert(fams, { name = fam.name, docs = docs, total = #fam.docs })
    end
  end
  if not filter or #fams > 0 then
    local open = expanded.devdocs or filter ~= nil
    add(" " .. pad((open and OPEN or CLOSED) .. " DevDocs", 30) .. summary, "vimquireGroup", { kind = "group", key = "devdocs" })
    if open then
      for _, fam in ipairs(fams) do
        if fam.total == 1 then
          local doc = fam.docs[1]
          local status, group = doc_status(doc)
          add_check("     " .. checkbox(doc.slug) .. " " .. pad(devdocs.label(doc), 26) .. pad(doc.slug, 16),
            { kind = "doc", slug = doc.slug, parent = "devdocs" }, state.doc(doc.slug) ~= nil, status, group)
        else
          local key = "fam:" .. fam.name
          local on = 0
          for _, doc in ipairs(fam.docs) do
            if state.doc(doc.slug) or devdocs.downloading(doc.slug) then
              on = on + 1
            end
          end
          local box = on == 0 and "[ ]" or "[~]"
          local fopen = expanded[key] or filter ~= nil
          add_check("   " .. (fopen and OPEN or CLOSED) .. " " .. box .. " " .. pad(fam.name, 42),
            { kind = "family", key = key, parent = "devdocs" }, on > 0,
            string.format("%d versions%s", fam.total, on > 0 and (", " .. on .. " on") or ""), "vimquireDim")
          if fopen then
            for _, doc in ipairs(fam.docs) do
              local status, group = doc_status(doc)
              add_check("         " .. checkbox(doc.slug) .. " " .. pad(devdocs.label(doc), 22) .. pad(doc.slug, 16),
                { kind = "doc", slug = doc.slug, parent = key }, state.doc(doc.slug) ~= nil, status, group)
            end
          end
        end
      end
    end
  end
  if filter and #site_rows == 0 and #custom_rows == 0 and #fams == 0 then
    add(" Nothing matches \"" .. filter .. "\". F clears the filter.", "vimquireDim")
  end
  buf.set_lines(mbuf, lines, hl)
end

local function row_key(row)
  return row and (row.key or row.slug or row.id)
end

-- Re-render, keeping the cursor on the same source when it is still shown.
local function rerender(key)
  if not mbuf or not vim.api.nvim_buf_is_valid(mbuf) then
    return
  end
  local win = vim.fn.bufwinid(mbuf)
  local cursor = win ~= -1 and vim.api.nvim_win_get_cursor(win) or { 1, 0 }
  key = key or row_key(rows[cursor[1]])
  M.render()
  if win == -1 then
    return
  end
  for lnum, row in pairs(rows) do
    if row_key(row) == key then
      return pcall(vim.api.nvim_win_set_cursor, win, { lnum, cursor[2] })
    end
  end
  pcall(vim.api.nvim_win_set_cursor, win, { math.min(cursor[1], vim.api.nvim_buf_line_count(mbuf)), cursor[2] })
end

local function current_row()
  return rows[vim.api.nvim_win_get_cursor(0)[1]]
end

--- Turn a source on or off. Docs are downloaded or deleted.
function M.toggle_source(id, on, done)
  if state.custom(id) then
    custom.set_enabled(id, on, function(ok, err)
      if not ok then
        util.notify("couldn't download " .. id .. ": " .. tostring(err), vim.log.levels.ERROR)
      end
      rerender()
    end)
    rerender()
    return done and done(true)
  end
  local site = sources.site(id)
  if site then
    if on and not site.available() then
      util.notify(site.label .. ": " .. site.unavailable_note(), vim.log.levels.WARN)
      return done and done(false)
    end
    state.set_site(id, on)
    rerender()
    return done and done(true)
  end
  local doc = devdocs.get(id)
  if not doc then
    util.notify("unknown source: " .. id, vim.log.levels.WARN)
    return done and done(false)
  end
  if not on then
    if state.doc(id) or devdocs.downloading(id) then
      local freed = devdocs.disable(id)
      util.notify("removed " .. devdocs.label(doc) .. " (deleted " .. util.human_size(freed) .. ")")
    end
    rerender()
    return done and done(true)
  end
  if state.doc(id) or devdocs.downloading(id) then
    return done and done(true)
  end
  devdocs.enable(id, {}, function(ok, err)
    if ok then
      util.notify("added " .. devdocs.label(doc) .. " (" .. util.human_size(devdocs.disk_size(id)) .. ")")
    else
      util.notify("couldn't download " .. devdocs.label(doc) .. ": " .. tostring(err), vim.log.levels.ERROR)
    end
    rerender()
    if done then
      done(ok)
    end
  end)
  rerender()
end

local function is_on(row)
  if row.kind == "site" then
    return state.site_enabled(row.id)
  elseif row.kind == "custom" then
    return state.custom(row.id).enabled
  end
  return state.doc(row.slug) ~= nil or devdocs.downloading(row.slug) ~= nil
end

local function toggle_open(row)
  if row.kind == "group" or row.kind == "family" then
    expanded[row.key] = not expanded[row.key]
    rerender(row.key)
    return true
  end
end

local function on_toggle()
  local row = current_row()
  if not row or toggle_open(row) then
    return
  end
  M.toggle_source(row.id or row.slug, not is_on(row))
end

local function setup_keys(b)
  buf.map(b, "<Space>", on_toggle, "Turn source on/off")
  for _, lhs in ipairs({ "<CR>", "za", "<2-LeftMouse>" }) do
    buf.map(b, lhs, on_toggle, "Open/close group, or turn source on/off")
  end
  buf.map(b, "l", function()
    local row = current_row()
    if row and (row.kind == "group" or row.kind == "family") and not expanded[row.key] then
      toggle_open(row)
    end
  end, "Expand")
  buf.map(b, "h", function()
    local row = current_row()
    if not row then
      return
    end
    if (row.kind == "group" or row.kind == "family") and expanded[row.key] then
      return toggle_open(row)
    end
    if row.parent then
      expanded[row.parent] = false
      rerender(row.parent)
    end
  end, "Collapse")
  buf.map(b, "O", function()
    local row = current_row()
    if not row or row.kind ~= "doc" then
      return util.notify("O works on DevDocs docs")
    end
    local info = state.doc(row.slug)
    local on = not (info and info.offline)
    devdocs.set_offline(row.slug, on, function(ok, err)
      if not ok then
        util.notify("offline copy failed: " .. tostring(err), vim.log.levels.ERROR)
      end
      rerender()
    end)
    rerender()
  end, "Download/delete offline copy")
  buf.map(b, "a", function()
    vim.ui.input({ prompt = "Site URL to search: " }, function(input)
      if input and vim.trim(input) ~= "" then
        require("vimquire").add_site(nil, input)
      end
    end)
  end, "Add a site by URL")
  buf.map(b, "D", function()
    local row = current_row()
    if not row or row.kind ~= "custom" then
      return util.notify("D deletes sites under Your sites")
    end
    local freed = custom.remove(row.id)
    util.notify("deleted " .. row.id .. " (" .. util.human_size(freed) .. ")")
    rerender("custom")
  end, "Delete site")
  buf.map(b, "R", function()
    local row = current_row()
    if not row or row.kind ~= "custom" or state.custom(row.id).kind == "template" then
      return util.notify("R downloads a site under Your sites again")
    end
    custom.build(row.id, function(ok, err)
      util.notify(ok and ("updated " .. row.id) or ("couldn't download " .. row.id .. ": " .. tostring(err)),
        ok and vim.log.levels.INFO or vim.log.levels.ERROR)
      rerender()
    end)
  end, "Download site again")
  buf.map(b, "u", function()
    util.notify("checking for doc updates...")
    devdocs.update(function(updated, err)
      if not updated then
        util.notify("update failed: " .. tostring(err), vim.log.levels.ERROR)
      elseif #updated == 0 then
        util.notify("all docs are up to date")
      else
        util.notify("updated " .. table.concat(updated, ", ") .. (err and " (some failed)" or ""))
      end
      rerender()
    end)
    rerender()
  end, "Update docs")
  buf.map(b, "f", function()
    vim.ui.input({ prompt = "Filter sources: ", default = filter or "" }, function(input)
      if input == nil then
        return
      end
      input = vim.trim(input):lower()
      filter = input ~= "" and input or nil
      M.render()
      pcall(vim.api.nvim_win_set_cursor, 0, { 1, 0 })
    end)
  end, "Filter")
  buf.map(b, "F", function()
    filter = nil
    rerender()
  end, "Clear filter")
  buf.map(b, "q", function()
    mbuf = nil
    buf.close(b)
  end, "Close")
end

function M.open()
  if mbuf and vim.api.nvim_buf_is_valid(mbuf) and vim.fn.bufwinid(mbuf) ~= -1 then
    vim.fn.win_gotoid(vim.fn.bufwinid(mbuf))
    return M.render()
  end
  if mbuf and vim.api.nvim_buf_is_valid(mbuf) then
    pcall(vim.api.nvim_buf_delete, mbuf, { force = true })
  end
  mbuf = buf.create("sources")
  setup_keys(mbuf)
  M.render()
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  devdocs.load_catalog(function(_, err)
    catalog_error = err
    rerender()
  end)
end

-- Keep the downloading... markers honest if a download finishes while the
-- list is open but not focused.
function M.refresh()
  rerender()
end

return M
