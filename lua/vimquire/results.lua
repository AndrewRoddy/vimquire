-- The :Search results buffer. Every enabled source is asked at once and
-- results are merged into one ranked list as they arrive.
local buf = require("vimquire.buf")
local config = require("vimquire.config")
local sources = require("vimquire.sources")
local util = require("vimquire.util")

local M = {}

local searches = {} -- buf -> current search

local function cancel(s)
  for _, h in ipairs(s.handles) do
    if type(h) == "table" and h.cancel then
      h:cancel()
    end
  end
end

local function current_item(b)
  local s = searches[b]
  if not s then
    return nil
  end
  return s.line_items[vim.api.nvim_win_get_cursor(0)[1]]
end

local function sorted(s)
  local items = vim.deepcopy(s.items)
  table.sort(items, function(a, b)
    if a.score ~= b.score then
      return a.score > b.score
    end
    return a.order < b.order
  end)
  local out = {}
  for i = 1, math.min(#items, config.options.results) do
    out[i] = items[i]
  end
  return out
end

local function display_url(url)
  return (url:gsub("^https?://", ""):gsub("^www%.", ""))
end

function M.render(b)
  local s = searches[b]
  if not s or not vim.api.nvim_buf_is_valid(b) then
    return
  end
  local width = buf.width(b)
  local lines, hl = {}, {}
  local function add(text, group)
    table.insert(lines, (util.clean(text):gsub("\n", " ")))
    if group then
      table.insert(hl, { #lines, group })
    end
  end

  add(" vimquire » " .. s.query .. (s.page > 1 and ("   (page " .. s.page .. ")") or ""), "vimquireHeading")
  local pending = vim.tbl_keys(s.pending)
  table.sort(pending)
  if #pending > 0 then
    add(" searching " .. table.concat(pending, ", ") .. "...", "vimquireDim")
  else
    add(string.format(" %d results from %s", #s.items, table.concat(s.names, ", ")), "vimquireDim")
  end
  add(" " .. string.rep("─", width - 1), "vimquireDim")

  s.line_items = {}
  local items = sorted(s)
  for i, item in ipairs(items) do
    add("")
    local title = string.format(" %2d. %s", i, item.title)
    local tag = "[" .. item.tag .. "]"
    add(title .. "  " .. tag)
    table.insert(hl, { #lines, "vimquireTitle", 0, #lines[#lines] - #tag - 2 })
    table.insert(hl, { #lines, "vimquireTag", #lines[#lines] - #tag, #lines[#lines] })
    s.line_items[#lines] = item
    add("     " .. display_url(item.url), "vimquireUrl")
    s.line_items[#lines] = item
    if item.snippet and vim.trim(item.snippet) ~= "" then
      local words = vim.trim(util.clean(item.snippet):gsub("%s+", " "))
      local wrapped = require("vimquire.html").render("<p>" .. words:gsub("&", "&amp;"):gsub("<", "&lt;") .. "</p>", { width = width - 5 }).lines
      for j = 1, math.min(2, #wrapped) do
        add("     " .. wrapped[j] .. ((j == 2 and #wrapped > 2) and " …" or ""))
        s.line_items[#lines] = item
      end
    end
  end

  if #items == 0 and #pending == 0 then
    add("")
    if #s.names == 0 then
      add(" No sources are turned on" .. (s.filter and (" that match @" .. s.filter) or "") .. ".")
      add(" Press s (or run :SearchSources) to pick some.")
    else
      add(" No results.")
    end
  end

  local errors = vim.tbl_keys(s.errors)
  table.sort(errors)
  if #errors > 0 then
    add("")
    for _, name in ipairs(errors) do
      add(" ! " .. name .. ": " .. s.errors[name], "vimquireError")
    end
  end

  add("")
  add(" " .. string.rep("─", width - 1), "vimquireDim")
  add(" <CR> open   o browser   y yank URL   n/p next/prev page   s sources   q back", "vimquireDim")
  buf.set_lines(b, lines, hl)
end

local function setup_keys(b)
  buf.map(b, "<CR>", function()
    local item = current_item(b)
    if item then
      require("vimquire.page").open(item.open)
    end
  end, "Open result")
  buf.map(b, "o", function()
    local item = current_item(b)
    if item then
      vim.ui.open(item.url)
    end
  end, "Open result in browser")
  buf.map(b, "y", function()
    local item = current_item(b)
    if item then
      vim.fn.setreg('"', item.url)
      pcall(vim.fn.setreg, "+", item.url)
      util.notify("copied " .. item.url)
    end
  end, "Yank result URL")
  buf.map(b, "n", function()
    M.search(searches[b].raw, searches[b].page + 1)
  end, "Next page")
  buf.map(b, "p", function()
    M.search(searches[b].raw, math.max(1, searches[b].page - 1))
  end, "Previous page")
  buf.map(b, "s", function()
    require("vimquire.manager").open()
  end, "Manage sources")
  buf.map(b, "q", function()
    local s = searches[b]
    if s then
      cancel(s)
    end
    searches[b] = nil
    buf.close(b)
  end, "Back")
end

--- Run a search. "@name query" searches one source only.
function M.search(raw, page)
  raw = vim.trim(raw)
  page = page or 1
  local filter, query = raw:match("^@(%S+)%s+(.+)$")
  if filter then
    filter = filter:lower()
  else
    query = raw
  end

  local b = vim.api.nvim_get_current_buf()
  if buf.is_ours(b, "results") then
    if searches[b] then
      cancel(searches[b])
    end
  else
    b = buf.create("results")
    setup_keys(b)
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = b,
      once = true,
      callback = function()
        if searches[b] then
          cancel(searches[b])
        end
        searches[b] = nil
      end,
    })
  end

  local s = { raw = raw, query = query, filter = filter, page = page, items = {}, pending = {}, errors = {},
    handles = {}, names = {}, line_items = {} }
  searches[b] = s
  local order = 0
  for _, target in ipairs(sources.targets(filter)) do
    table.insert(s.names, target.name)
    s.pending[target.name] = true
    local h = target.run(query, page, function(results, err)
      if searches[b] ~= s then
        return -- a newer search replaced this one
      end
      s.pending[target.name] = nil
      if not results then
        s.errors[target.name] = tostring(err)
      else
        for rank, r in ipairs(results) do
          order = order + 1
          r.order = order
          -- Web sources rank their own results; spread them across the list.
          r.score = r.score or math.max(10, 90 - 6 * (rank - 1))
          table.insert(s.items, r)
        end
      end
      M.render(b)
    end)
    table.insert(s.handles, h)
  end
  M.render(b)
  pcall(vim.api.nvim_win_set_cursor, 0, { 1, 0 })
end

return M
