-- Reading a page as text. Links are numbered [n]; <CR> on one follows it.
local buf = require("vimquire.buf")
local custom = require("vimquire.sources.custom")
local devdocs = require("vimquire.sources.devdocs")
local html = require("vimquire.html")
local http = require("vimquire.http")
local stackoverflow = require("vimquire.sources.stackoverflow")
local util = require("vimquire.util")
local wikipedia = require("vimquire.sources.wikipedia")

local M = {}

local pages = {} -- buf -> { doc, links, spots, anchors }

local function load(spec, cb)
  if spec.kind == "devdocs" then
    local url = devdocs.page_url(spec.slug, spec.path)
    return devdocs.fetch_page(spec.slug, spec.path, function(body, err)
      if not body then
        return cb(nil, err)
      end
      local info = require("vimquire.state").doc(spec.slug)
      local nav = {}
      if spec.path ~= "index" then
        nav.contents = { title = "Contents",
          spec = { kind = "devdocs", slug = spec.slug, path = "index", title = (info and info.name or spec.slug) .. " contents" } }
      end
      local near = devdocs.neighbors(spec.slug, spec.path)
      for _, which in ipairs({ "prev", "next" }) do
        local n = near and near[which]
        if n then
          nav[which] = { spec = { kind = "devdocs", slug = spec.slug, path = n.path, title = n.name }, title = n.name }
        end
      end
      cb({ html = body, title = spec.title, url = url, base_url = url, tag = spec.slug,
        fragment = spec.path:match("#(.+)$"), nav = nav })
    end)
  elseif spec.kind == "stackoverflow" then
    return stackoverflow.open(spec.id, cb)
  elseif spec.kind == "wikipedia" then
    return wikipedia.open(spec.title, cb)
  end
  return http.get(spec.url, { ua = "browser" }, function(body, err)
    if not body then
      return cb(nil, err)
    end
    if body:find("%z") then
      return cb(nil, "this isn't a text page")
    end
    local u = util.parse_url(spec.url)
    local nav = {}
    for which, link in pairs(html.page_nav(body)) do
      local url = util.resolve_url(spec.url, link.href)
      local title = which == "contents" and "Contents" or link.title or custom.title_for(url)
      if url:gsub("#.*$", "") ~= spec.url:gsub("#.*$", "") then
        nav[which] = { url = url, title = title or url:gsub("[?#].*$", ""):match("([^/]+)/?$") or url }
      end
    end
    cb({ html = body, title = spec.title, url = spec.url, base_url = spec.url, tag = u and u.host or "web",
      fragment = spec.url:match("#(.+)$"), nav = nav })
  end)
end

local function spec_url(spec)
  if spec.kind == "devdocs" then
    return devdocs.page_url(spec.slug, spec.path)
  elseif spec.kind == "stackoverflow" then
    return "https://stackoverflow.com/questions/" .. spec.id
  elseif spec.kind == "wikipedia" then
    return wikipedia.article_url(spec.title)
  end
  return spec.url
end

local function header(title, url, width)
  return {
    { " " .. title, "vimquireHeading" },
    { " " .. url, "vimquireUrl" },
    { " <CR> follow [n]   <Tab> next link   gl list links   o browser   y yank URL   q back", "vimquireDim" },
    { " " .. string.rep("─", width - 1), "vimquireDim" },
    { "" },
  }
end

-- " ← [[ What is Ownership?   The Slice Type ]] →   - contents", or nil
-- when the page has no previous, next or contents link.
local function nav_line(nav)
  if not nav or not (nav.prev or nav.next or nav.contents) then
    return nil
  end
  local function short(s)
    s = util.clean(s):gsub("%s+", " ")
    return vim.fn.strcharlen(s) > 40 and (vim.fn.strcharpart(s, 0, 39) .. "…") or s
  end
  local parts = {}
  if nav.prev then
    table.insert(parts, "← [[ " .. short(nav.prev.title))
  end
  if nav.next then
    table.insert(parts, short(nav.next.title) .. " ]] →")
  end
  if nav.contents then
    table.insert(parts, "- contents")
  end
  return " " .. table.concat(parts, "   ")
end

local function show(b, doc)
  local width = buf.width(b)
  local r = doc.text and html.render_text(doc.text, { width = width }) or html.render(doc.html, { width = width })
  local title = util.clean(doc.title or r.title or doc.url):gsub("%s+", " ")
  local lines, hl = {}, {}
  local nav = nav_line(doc.nav)
  for i, h in ipairs(header(title, doc.url, width)) do
    table.insert(lines, h[1])
    if h[2] then
      table.insert(hl, { #lines, h[2] })
    end
    if i == 3 and nav then
      table.insert(lines, nav)
      table.insert(hl, { #lines, "vimquireLink" })
    end
  end
  local offset = #lines
  vim.list_extend(lines, r.lines)
  for _, h in ipairs(r.hl) do
    table.insert(hl, { h[1] + offset, h[2] })
  end

  local links, spots = {}, {}
  for i, href in ipairs(r.links) do
    links[i] = util.resolve_url(doc.base_url or doc.url, href)
  end
  for _, s in ipairs(r.spots) do
    local spot = { s[1] + offset, s[2], s[3], s[4] }
    table.insert(spots, spot)
    table.insert(hl, { spot[1], "vimquireLink", spot[2], spot[3] })
  end

  if #r.lines < 3 and doc.html then
    table.insert(lines, " This page shows little text without JavaScript. Press o to open it in your browser.")
    table.insert(hl, { #lines, "vimquireDim" })
  end
  -- Again at the bottom, where you are when you finish reading.
  if nav then
    vim.list_extend(lines, { "", nav })
    table.insert(hl, { #lines, "vimquireLink" })
  end
  if #links > 0 then
    vim.list_extend(lines, { "", "# References" })
    table.insert(hl, { #lines, "vimquireHeading" })
    for i, url in ipairs(links) do
      local mark = "[" .. i .. "]"
      table.insert(lines, mark .. " " .. util.clean(url))
      table.insert(spots, { #lines, 0, #mark, i })
      table.insert(hl, { #lines, "vimquireLink", 0, #mark })
      table.insert(hl, { #lines, "vimquireUrl", #mark + 1, #lines[#lines] })
    end
  end

  local anchors = {}
  for id, lnum in pairs(r.anchors) do
    anchors[id] = math.min(lnum + offset, #lines)
  end
  pages[b] = { doc = doc, links = links, spots = spots, anchors = anchors, offset = offset }
  buf.set_lines(b, lines, hl)

  local win = vim.fn.bufwinid(b)
  if win ~= -1 then
    local target = (doc.fragment and anchors[doc.fragment]) or (offset + 1)
    pcall(vim.api.nvim_win_set_cursor, win, { math.min(target, #lines), 0 })
    if doc.fragment and anchors[doc.fragment] then
      vim.api.nvim_win_call(win, function()
        vim.cmd("normal! zt")
      end)
    end
  end
end

local function spot_under_cursor(b)
  local p = pages[b]
  if not p then
    return nil
  end
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local first
  for _, s in ipairs(p.spots) do
    if s[1] == row then
      if col >= s[2] and col < s[3] then
        return s
      end
      first = first or s
    end
  end
  return first
end

local function jump_link(b, dir)
  local p = pages[b]
  if not p or #p.spots == 0 then
    return
  end
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local pick
  if dir > 0 then
    for _, s in ipairs(p.spots) do
      if s[1] > row or (s[1] == row and s[2] > col) then
        pick = s
        break
      end
    end
    pick = pick or p.spots[1]
  else
    for i = #p.spots, 1, -1 do
      local s = p.spots[i]
      if s[1] < row or (s[1] == row and s[2] < col) then
        pick = s
        break
      end
    end
    pick = pick or p.spots[#p.spots]
  end
  vim.api.nvim_win_set_cursor(0, { pick[1], pick[2] })
end

local function strip_fragment(url)
  return (url:gsub("#.*$", ""))
end

--- A bare http(s) URL in the text under the cursor, e.g. in a code block.
local function url_under_cursor()
  local url = vim.fn.expand("<cWORD>"):match("https?://[%w%-%._~:/%?#%[%]@!%$&'%*%+,;=%%]+")
  -- Drop punctuation that ends the sentence rather than the URL.
  return url and (url:gsub("[%.,;:!%?%)%]'\"]+$", ""))
end

--- Open url from page p: same-page #anchors jump, known sites open through
--- their API, anything else is fetched as a web page.
local function follow_url(p, url)
  local frag = url:match("#(.+)$")
  if frag and p and strip_fragment(url) == strip_fragment(p.doc.base_url or p.doc.url) then
    local lnum = p.anchors[frag] or p.anchors[vim.uri_decode(frag)]
    if lnum then
      vim.cmd("normal! m'")
      vim.api.nvim_win_set_cursor(0, { lnum, 0 })
      vim.cmd("normal! zt")
    else
      util.notify("no #" .. frag .. " on this page")
    end
    return
  end

  local slug, path = devdocs.parse_url(url)
  if slug then
    return M.open({ kind = "devdocs", slug = slug, path = path })
  end
  local so_id = url:match("^https?://stackoverflow%.com/questions/(%d+)") or url:match("^https?://stackoverflow%.com/q/(%d+)")
  if so_id then
    return M.open({ kind = "stackoverflow", id = tonumber(so_id) })
  end
  local wiki = url:match("^https://" .. require("vimquire.config").options.wikipedia_lang .. "%.wikipedia%.org/wiki/([^#?]+)")
  if wiki and not wiki:find(":") then
    return M.open({ kind = "wikipedia", title = vim.uri_decode(wiki):gsub("_", " ") })
  end

  local u = util.parse_url(url)
  if not util.is_web_url(url) then
    return util.notify("not following non-web link " .. url, vim.log.levels.WARN)
  end
  if util.is_private_host(u.host) then
    return util.notify("blocked link to a local/private address: " .. u.host .. " (o opens it in your browser)", vim.log.levels.WARN)
  end
  M.open({ kind = "web", url = url })
end

--- Go to the page's "prev", "next" or "contents" page.
function M.go(b, which)
  local p = pages[b]
  local target = p and p.doc.nav and p.doc.nav[which]
  if not target then
    local names = { prev = "previous page", next = "next page", contents = "contents page" }
    return util.notify("this page has no " .. names[which] .. " link")
  end
  if target.spec then
    return M.open(target.spec)
  elseif which == "contents" then
    -- Contents pages (mdBook's toc.html) often have no <title>.
    return M.open({ kind = "web", url = target.url, title = "Contents" })
  end
  follow_url(p, target.url)
end

--- Follow link n on page b.
function M.follow(b, n)
  local p = pages[b]
  local url = p and p.links[n]
  if not url then
    return util.notify("no link [" .. n .. "] on this page", vim.log.levels.WARN)
  end
  follow_url(p, url)
end

--- Follow the [n] link or bare URL under the cursor. Returns false if there's none.
function M.follow_cursor(b)
  local s = spot_under_cursor(b)
  if s then
    M.follow(b, s[4])
    return true
  end
  local url = url_under_cursor()
  if url then
    follow_url(pages[b], url)
    return true
  end
  return false
end

--- Pick one of the page's links from a list and follow it.
function M.pick(b)
  local p = pages[b]
  if not p or #p.links == 0 then
    return util.notify("no links on this page")
  end
  local items = {}
  for i = 1, #p.links do
    items[i] = i
  end
  vim.ui.select(items, {
    prompt = "Follow link",
    format_item = function(i)
      return "[" .. i .. "] " .. util.clean(p.links[i])
    end,
  }, function(i)
    if i and vim.api.nvim_buf_is_valid(b) and vim.api.nvim_get_current_buf() == b then
      M.follow(b, i)
    end
  end)
end

--- :SearchFollow [n]: link n, else the link under the cursor, else a list.
function M.follow_command(arg)
  local b = vim.api.nvim_get_current_buf()
  if buf.kinds[b] ~= "page" then
    return util.notify("not on a vimquire page (open one with :Search or :SearchOpen)", vim.log.levels.WARN)
  end
  local n = tonumber(vim.trim(arg or ""):match("^%[?(%d+)%]?$"))
  if n then
    return M.follow(b, n)
  elseif vim.trim(arg or "") ~= "" then
    return util.notify("expected a link number, e.g. :SearchFollow 3", vim.log.levels.WARN)
  end
  if not M.follow_cursor(b) then
    M.pick(b)
  end
end

local function setup_keys(b)
  local function follow()
    if vim.v.count > 0 then
      return M.follow(b, vim.v.count)
    end
    if not M.follow_cursor(b) then
      util.notify("no link under the cursor (gl lists every link)")
    end
  end
  buf.map(b, "<CR>", follow, "Follow link ({n}<CR> follows [n])")
  buf.map(b, "gf", follow, "Follow link")
  buf.map(b, "gl", function()
    M.pick(b)
  end, "List links to follow")
  for _, m in ipairs({ { "]]", "next" }, { "<Right>", "next" }, { "[[", "prev" }, { "<Left>", "prev" } }) do
    buf.map(b, m[1], function()
      M.go(b, m[2])
    end, m[2] == "next" and "Next page" or "Previous page")
  end
  buf.map(b, "-", function()
    M.go(b, "contents")
  end, "Contents")
  buf.map(b, "<Tab>", function()
    jump_link(b, 1)
  end, "Next link")
  buf.map(b, "<S-Tab>", function()
    jump_link(b, -1)
  end, "Previous link")
  buf.map(b, "o", function()
    local s = spot_under_cursor(b)
    local p = pages[b]
    local url = (s and p.links[s[4]]) or url_under_cursor() or (p and p.doc.url) or vim.b[b].vimquire_url
    if url then
      vim.ui.open(url)
    end
  end, "Open link or page in browser")
  buf.map(b, "y", function()
    local p = pages[b]
    local url = (p and p.doc.url) or vim.b[b].vimquire_url
    if url then
      vim.fn.setreg('"', url)
      pcall(vim.fn.setreg, "+", url)
      util.notify("copied " .. url)
    end
  end, "Yank page URL")
  buf.map(b, "q", function()
    pages[b] = nil
    buf.close(b)
  end, "Back")
end

--- Open a page in the current window.
--- spec: {kind="devdocs", slug, path} | {kind="stackoverflow", id} |
---       {kind="wikipedia", title} | {kind="web", url}
function M.open(spec)
  local b = buf.create("page")
  local url = spec_url(spec)
  vim.b[b].vimquire_url = url
  setup_keys(b)
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = b,
    once = true,
    callback = function()
      pages[b] = nil
    end,
  })
  buf.set_lines(b, { " Loading " .. url .. " ..." }, { { 1, "vimquireDim" } })
  load(spec, function(doc, err)
    if not vim.api.nvim_buf_is_valid(b) then
      return
    end
    if not doc then
      buf.set_lines(b, {
        " Couldn't load " .. url,
        " " .. util.clean(tostring(err)):gsub("\n", " "),
        "",
        " o opens it in your browser   q back",
      }, { { 1, "vimquireError" }, { 4, "vimquireDim" } })
      return
    end
    show(b, doc)
  end)
end

return M
