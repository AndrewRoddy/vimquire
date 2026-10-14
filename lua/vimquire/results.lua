-- The :Search results buffer. Every enabled source is asked at once and
-- results are merged into one ranked list as they arrive.
local buf = require("vimquire.buf")
local config = require("vimquire.config")
local sources = require("vimquire.sources")
local util = require("vimquire.util")

local M = {}

local searches = {} -- buf -> current search
local GUTTER = 4 -- width of the result-number column

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
  s.title_lines = {}
  s.title_index = {}
  local items = sorted(s)
  for i, item in ipairs(items) do
    add("")
    local title = " " .. item.title
    local tag = "[" .. item.tag .. "]"
    add(title .. "  " .. tag)
    table.insert(s.title_lines, #lines)
    s.title_index[#lines] = #s.title_lines
    table.insert(hl, { #lines, "vimquireTitle", 0, #lines[#lines] - #tag - 2 })
    table.insert(hl, { #lines, "vimquireTag", #lines[#lines] - #tag, #lines[#lines] })
    s.line_items[#lines] = item
    add(" " .. display_url(item.url), "vimquireUrl")
    s.line_items[#lines] = item
    if item.snippet and vim.trim(item.snippet) ~= "" then
      local words = vim.trim(util.clean(item.snippet):gsub("%s+", " "))
      local wrapped = require("vimquire.html").render("<p>" .. words:gsub("&", "&amp;"):gsub("<", "&lt;") .. "</p>", { width = width - 1 }).lines
      for j = 1, math.min(2, #wrapped) do
        add(" " .. wrapped[j] .. ((j == 2 and #wrapped > 2) and " …" or ""))
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

-- Index of the result the cursor is on (0 above the first one).
local function current_index(s, row)
  local c = 0
  for i, lnum in ipairs(s.title_lines or {}) do
    if lnum > row then
      break
    end
    c = i
  end
  return c
end

-- Like 'relativenumber', but counting results: the number column shows how
-- many j/k presses away each result is, and the current one gets an arrow.
function M.statuscolumn()
  local win = vim.g.statusline_winid
  local s = searches[vim.api.nvim_win_get_buf(win)]
  local i = s and vim.v.virtnum == 0 and s.title_index[vim.v.lnum]
  if not i then
    return string.rep(" ", GUTTER)
  end
  local c = current_index(s, vim.api.nvim_win_get_cursor(win)[1])
  local label = i == c and "❯" or tostring(math.abs(i - c))
  return "%#" .. (i == c and "vimquireCurrent" or "vimquireNumber") .. "#"
    .. string.rep(" ", GUTTER - 1 - vim.api.nvim_strwidth(label)) .. label .. " "
end

-- Show the result numbers in this window's gutter. Window options are per
-- buffer, so they go away when the window shows something else.
local function show_gutter(b)
  local win = vim.fn.bufwinid(b)
  if win == -1 then
    return
  end
  local wo = vim.wo[win][0]
  -- relativenumber makes Neovim redraw the gutter whenever the cursor moves.
  wo.number = true
  wo.relativenumber = true
  wo.numberwidth = GUTTER
  wo.statuscolumn = "%!v:lua.require'vimquire.results'.statuscolumn()"
end

-- Move the cursor count results down (dir 1) or up (dir -1).
local function jump(b, dir)
  local s = searches[b]
  local titles = s and s.title_lines or {}
  if #titles == 0 then
    return
  end
  local c = current_index(s, vim.api.nvim_win_get_cursor(0)[1])
  if dir < 0 and c == 0 then
    return
  end
  local target = dir > 0 and math.min(#titles, c + vim.v.count1) or math.max(1, c - vim.v.count1)
  vim.api.nvim_win_set_cursor(0, { titles[target], 0 })
end

local function setup_keys(b)
  buf.map(b, "j", function()
    jump(b, 1)
  end, "Next result")
  buf.map(b, "k", function()
    jump(b, -1)
  end, "Previous result")
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
    show_gutter(b)
    -- Coming back from a page restores the buffer; make sure the gutter is too.
    vim.api.nvim_create_autocmd("BufWinEnter", {
      buffer = b,
      callback = function()
        show_gutter(b)
      end,
    })
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
