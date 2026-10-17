-- Sites you add yourself with :SearchSite {url}. vimquire works out how to
-- search each one, trying these in order:
--   template  the URL has %s where the query goes: opens the site's own results
--   mdbook    mdBook sites (the Rust Book, the Cargo Book...) publish their whole
--             search index as one file: download it and search it locally
--   crawl     anything else: fetch the pages under the URL (up to
--             site_max_pages, obeying robots.txt), keep their text and search
--             that locally
-- Pages that refuse us are skipped. Indexes are searched locally, like DevDocs.
local config = require("vimquire.config")
local html = require("vimquire.html")
local http = require("vimquire.http")
local state = require("vimquire.state")
local util = require("vimquire.util")

local M = {}

local indexes = {} -- id -> entries, loaded on first search
local builds = {} -- id -> { what, pages, handles, cancelled }

-- Crawled links ending in these are fetched; other extensions (images,
-- archives, PDFs...) are not. Paths without an extension always are.
local PAGE_EXT = { html = true, htm = true, xhtml = true, shtml = true, php = true, asp = true, aspx = true }
local CRAWL_JOBS = 3

function M.dir(id)
  return util.data_dir("sites") .. "/" .. id
end

function M.ids()
  return state.custom_ids()
end

--- Does this :SearchAdd argument look like a URL rather than a source name?
function M.is_url(s)
  return s:match("^%a[%w+.-]*://") ~= nil or s:find("/", 1, true) ~= nil
end

local function normalize(url)
  url = vim.trim(url)
  if not url:match("^%a[%w+.-]*://") then
    url = "https://" .. url
  end
  return url
end

local function taken(id)
  return state.custom(id) or require("vimquire.sources").site(id) or require("vimquire.sources.devdocs").get(id)
end

-- "https://doc.rust-lang.org/book/" -> "book", "https://docs.rs/..?q=%s" -> "docs"
local function make_id(url)
  local u = util.parse_url(url)
  local seg
  for s in u.rest:gsub("[?#].*$", ""):gmatch("[^/]+") do
    s = s:gsub("%.%w+$", "")
    if s ~= "index" and not s:find("%", 1, true) then
      seg = s
    end
  end
  local base = (seg or u.host:gsub("^www%.", ""):match("^[^.]+")):lower():gsub("[^%w_-]+", "-"):gsub("^-+", ""):gsub("-+$", "")
  if base == "" then
    base = "site"
  end
  local id, n = base, 1
  while taken(id) do
    n = n + 1
    id = base .. "-" .. n
  end
  return id
end

function M.matches(id, filter)
  local info = state.custom(id)
  return id == filter or (info and info.name and info.name:lower() == filter)
end

--- A template site's URL with the query filled in.
function M.search_url(id, query)
  return (state.custom(id).url:gsub("%%s", function()
    return util.urlencode(query)
  end))
end

function M.building(id)
  local job = builds[id]
  return job and job.what
end

function M.disk_size(id)
  return util.dir_size(M.dir(id))
end

--- One line about a site for :SearchSources, and its highlight group.
function M.status(id)
  local job = builds[id]
  if job then
    if job.what == "crawl" then
      return string.format("crawling... %d pages", job.pages), "vimquireBusy"
    end
    return "downloading...", "vimquireBusy"
  end
  local info = state.custom(id)
  local group = info.enabled and "vimquireOn" or "vimquireDim"
  if info.kind == "template" then
    return "opens the site's own search", group
  elseif info.kind == "mdbook" then
    return string.format("mdBook, %d sections, %s on disk", info.count or 0, util.human_size(M.disk_size(id))), group
  elseif info.kind == "crawl" then
    local pages = info.pages or 0
    local s = string.format("%d page%s, %s on disk", pages, pages == 1 and "" or "s", util.human_size(M.disk_size(id)))
    if (info.refused or 0) > 0 then
      s = s .. string.format(", %d refused", info.refused)
    end
    return s, group
  end
  return "not downloaded" .. (info.error and (": " .. info.error) or "") .. ". R retries", "vimquireError"
end

local function refresh()
  local ok, manager = pcall(require, "vimquire.manager")
  if ok then
    manager.refresh()
  end
end

-- http.get that a cancelled build ignores.
local function fetch(job, url, opts, cb)
  local h
  h = http.get(url, opts, function(...)
    job.handles[h] = nil
    if not job.cancelled then
      cb(...)
    end
  end)
  job.handles[h] = true
end

local function page_title(body)
  local t = body:match("<[Tt][Ii][Tt][Ll][Ee][^>]*>(.-)</[Tt][Ii][Tt][Ll][Ee]>")
  return t and vim.trim(util.clean(html.decode_entities(t)):gsub("%s+", " ")) or nil
end

-- mdBook

local function mdbook_index_url(body, base)
  local path = body:match('path_to_searchindex_js%s*=%s*"([^"]+)"') or body:match('src="([^"]*searchindex[^"]*%.js)"')
  return path and util.resolve_url(base, path)
end

-- searchindex.js is JS: either JSON.parse('<escaped JSON>') (newer mdBook)
-- or a plain object literal (older).
local function parse_mdbook(js, index_url)
  local s = js:find("JSON.parse('", 1, true)
  local json
  if s then
    local e = js:match(".*()'%)")
    if not e or e <= s then
      return nil
    end
    json = js:sub(s + 12, e - 1):gsub("\\(.)", function(c)
      if c == "'" or c == "\\" then
        return c
      end
    end)
  else
    json = js:match("{.*}")
  end
  local ok, data = pcall(vim.json.decode, json or "", { luanil = { object = true, array = true } })
  if not ok or type(data) ~= "table" or type(data.doc_urls) ~= "table" then
    return nil
  end
  local docs = data.index and data.index.documentStore and data.index.documentStore.docs or {}
  local entries = {}
  for i, path in ipairs(data.doc_urls) do
    local d = docs[tostring(i - 1)]
    if d then
      table.insert(entries, {
        n = util.clean(d.breadcrumbs or d.title or path),
        h = util.clean(d.title or ""),
        u = util.resolve_url(index_url, path),
        x = util.clean(d.body or ""),
      })
    end
  end
  return entries
end

-- mdBook titles pages "Chapter - Book name".
local function book_name(title)
  return title and (title:match(".* %- (.-)$") or title)
end

-- Crawling

local function parse_robots(txt)
  local rules, applies, in_agents = {}, false, false
  for line in txt:gmatch("[^\r\n]+") do
    local k, v = line:gsub("#.*$", ""):match("^%s*([%w-]+)%s*:%s*(.-)%s*$")
    if k then
      k = k:lower()
      if k == "user-agent" then
        if not in_agents then
          applies = false
        end
        in_agents = true
        if v == "*" or v:lower():find("vimquire", 1, true) then
          applies = true
        end
      else
        in_agents = false
        if k == "disallow" and applies and v ~= "" then
          local pat = v:gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0"):gsub("%*", ".*")
          -- A trailing $ in robots.txt anchors the rule; it came out escaped.
          pat = pat:gsub("%%%$$", "$")
          table.insert(rules, "^" .. pat)
        end
      end
    end
  end
  return rules
end

-- Split a rendered page into one entry per heading, so results point at
-- the section that matched.
local function page_entries(url, r, suffix)
  local title = util.clean(r.title or url):gsub("%s+", " ")
  if suffix and #title > #suffix and title:sub(-#suffix) == suffix then
    title = title:sub(1, -#suffix - 1)
  end
  local headings = {}
  for _, h in ipairs(r.hl) do
    if h[2] == "vimquireHeading" and not h[3] then
      headings[h[1]] = true
    end
  end
  local at = {}
  for id, lnum in pairs(r.anchors) do
    at[lnum] = at[lnum] or id
  end
  local out, cur = {}, nil
  local function flush()
    if not cur then
      return
    end
    local x = table.concat(cur.parts, " "):gsub("%[%d+%]", ""):gsub("%s+", " ")
    x = vim.trim(x):sub(1, 4000)
    if x ~= "" or cur.h ~= "" then
      local n = title
      if cur.h ~= "" and cur.h:lower() ~= title:lower() then
        n = title .. " » " .. cur.h
      end
      table.insert(out, { n = n, h = cur.h, u = cur.u, x = x })
    end
  end
  for lnum, line in ipairs(r.lines) do
    if headings[lnum] then
      flush()
      local id = at[lnum] or at[lnum - 1] or at[lnum - 2]
      -- Drop the "#+ " markup and the ¶ / # permalink icons docs put on headings.
      local h = vim.trim(util.clean(line:gsub("^#+%s*", "")))
      local before
      repeat
        before = h
        h = vim.trim(h:gsub("¶$", ""):gsub("§$", ""):gsub("#$", ""))
      until h == before
      cur = { h = h, u = url .. (id and ("#" .. id) or ""), parts = {} }
    else
      cur = cur or { h = "", u = url, parts = {} }
      table.insert(cur.parts, line)
    end
  end
  flush()
  return out
end

local function crawl(job, start, first_body, cb)
  local max = config.options.site_max_pages
  local u = util.parse_url(start)
  local prefix = start:gsub("[?#].*$", ""):gsub("[^/]*$", "")
  local seen, queue, entries, rules = {}, {}, {}, {}
  local active, failed_in_row = 0, 0
  job.what, job.refused = "crawl", 0
  -- " — Python 3.15 documentation": the site name every page title ends with.
  local first_title = page_title(first_body) or ""
  local suffix = first_title:match(".*( — .+)$") or first_title:match(".*( – .+)$")
    or first_title:match(".*( | .+)$") or first_title:match(".*( %- .+)$")

  local function allowed(url)
    local path = util.parse_url(url).rest
    for _, pat in ipairs(rules) do
      if path:find(pat) then
        return false
      end
    end
    return true
  end

  local function queue_link(url)
    url = url:gsub("#.*$", "")
    if seen[url] or url:find("?", 1, true) or url:sub(1, #prefix) ~= prefix then
      return
    end
    local ext = url:match("/[^/]*%.(%w+)$")
    if ext and not PAGE_EXT[ext:lower()] then
      return
    end
    seen[url] = true
    if allowed(url) then
      table.insert(queue, url)
    end
  end

  local function index_page(url, body)
    job.pages = job.pages + 1
    local r = html.render(body, { width = 200 })
    vim.list_extend(entries, page_entries(url, r, suffix))
    for _, href in ipairs(r.links) do
      queue_link(util.resolve_url(url, href))
    end
    if job.pages % 5 == 0 then
      refresh()
    end
  end

  local finished = false
  local function pump()
    while active < CRAWL_JOBS and #queue > 0 and job.pages + active < max do
      local url = table.remove(queue, 1)
      active = active + 1
      fetch(job, url, { ua = "tool", effective = true, max_size = 5e6 }, function(body, _, final)
        active = active - 1
        if body and not body:find("%z") then
          failed_in_row = 0
          index_page(final or url, body)
        else
          job.refused = job.refused + 1
          failed_in_row = failed_in_row + 1
          -- The site is turning us away: keep what we have.
          if failed_in_row >= 5 then
            queue = {}
          end
        end
        pump()
      end)
    end
    if active == 0 and not finished then
      finished = true
      cb(entries)
    end
  end

  seen[start:gsub("#.*$", "")] = true
  fetch(job, u.scheme .. "://" .. u.authority .. "/robots.txt", { ua = "tool" }, function(txt)
    rules = txt and parse_robots(txt) or {}
    index_page(start, first_body)
    pump()
  end)
end

--- Download or re-download a site's index. cb(ok, err).
function M.build(id, cb)
  local info = state.custom(id)
  if builds[id] then
    return cb(nil, "already downloading " .. id)
  end
  local job = { what = "index", pages = 0, handles = {} }
  builds[id] = job

  local function done(entries, kind, name, err)
    if builds[id] ~= job then
      return
    end
    builds[id] = nil
    info = state.custom(id)
    if not info then
      return
    end
    if entries and #entries == 0 then
      entries, err = nil, "found no text to search"
    end
    if not entries then
      info.error = err
      state.set_custom(id, info)
      refresh()
      return cb(nil, err)
    end
    vim.fn.mkdir(M.dir(id), "p")
    util.write_json(M.dir(id) .. "/index.json", entries)
    indexes[id] = nil
    info.kind, info.name, info.error = kind, name or info.name, nil
    info.count, info.pages, info.refused = #entries, job.pages, job.refused
    state.set_custom(id, info)
    refresh()
    cb(true)
  end

  fetch(job, info.url, { ua = "tool", effective = true }, function(body, err, final)
    if not body then
      return done(nil, nil, nil, err)
    end
    final = final or info.url
    local name = page_title(body)
    local index_url = mdbook_index_url(body, final)
    if not index_url then
      return crawl(job, final, body, function(entries)
        done(entries, "crawl", name)
      end)
    end
    fetch(job, index_url, { ua = "tool" }, function(js)
      local entries = js and parse_mdbook(js, index_url)
      if entries then
        job.pages = 1
        return done(entries, "mdbook", book_name(name))
      end
      crawl(job, final, body, function(e)
        done(e, "crawl", name)
      end)
    end)
  end)
  refresh()
end

--- :SearchSite. Returns the new id, or nil and why not. cb(ok, err) runs
--- when the site is ready to search.
function M.add(id, url, cb)
  url = normalize(url)
  if not util.is_web_url((url:gsub("%%s", "x"))) then
    return nil, "not a web URL: " .. url
  end
  if id then
    id = id:lower()
    if not id:match("^[%w_][%w_.~-]*$") then
      return nil, "names can only have letters, numbers, - and _: " .. id
    elseif taken(id) then
      return nil, id .. " is already a source. Pick another name: :SearchSite <name> " .. url
    end
  else
    id = make_id(url)
  end
  local host = util.parse_url(url).host
  local info = { url = url, name = host, enabled = true }
  if url:find("%s", 1, true) then
    info.kind = "template"
    state.set_custom(id, info)
    vim.schedule(function()
      cb(true)
    end)
    return id
  end
  state.set_custom(id, info)
  M.build(id, function(ok, err)
    -- A site that never worked isn't worth keeping in the list.
    if not ok then
      M.remove(id)
    end
    cb(ok, err)
  end)
  return id
end

function M.set_enabled(id, on, cb)
  local info = state.custom(id)
  info.enabled = on
  state.set_custom(id, info)
  if on and not info.kind and not builds[id] then
    return M.build(id, cb or function() end)
  end
  if cb then
    cb(true)
  end
end

--- Forget a site and delete its files. Returns the number of bytes freed.
function M.remove(id)
  local job = builds[id]
  if job then
    job.cancelled = true
    for h in pairs(job.handles) do
      h:cancel()
    end
  end
  builds[id] = nil
  local freed = M.disk_size(id)
  vim.fn.delete(M.dir(id), "rf")
  indexes[id] = nil
  state.set_custom(id, nil)
  return freed
end

-- Searching

local function load_index(id)
  if indexes[id] then
    return indexes[id]
  end
  local data = util.read_json(M.dir(id) .. "/index.json")
  if type(data) ~= "table" then
    return nil
  end
  for _, e in ipairs(data) do
    e.lh, e.ln, e.lx = e.h:lower(), e.n:lower(), e.x:lower()
  end
  indexes[id] = data
  return data
end

local function score(e, q, tokens)
  local extra = math.min(10, (#e.lh - #q) / 4)
  if e.lh == q then
    return 100
  elseif e.lh:sub(1, #q) == q then
    return 90 - extra
  elseif e.lh:find(q, 1, true) then
    return 82 - extra
  elseif e.ln:find(q, 1, true) then
    return 74
  end
  local in_name = true
  for _, t in ipairs(tokens) do
    if not e.ln:find(t, 1, true) then
      in_name = false
      if not e.lx:find(t, 1, true) then
        return nil
      end
    end
  end
  if in_name then
    return 66
  elseif e.lx:find(q, 1, true) then
    return 56
  end
  return 44
end

-- Up to ~200 bytes of text around the first match, cut on UTF-8 boundaries.
local function snippet(e, q, tokens)
  local pos = e.lx:find(q, 1, true) or (tokens[1] and e.lx:find(tokens[1], 1, true)) or 1
  local s, f = math.max(1, pos - 60), math.min(#e.x, pos + 140)
  while s > 1 and e.x:byte(s) >= 0x80 and e.x:byte(s) < 0xC0 do
    s = s - 1
  end
  while f < #e.x and e.x:byte(f + 1) >= 0x80 and e.x:byte(f + 1) < 0xC0 do
    f = f + 1
  end
  return (s > 1 and "…" or "") .. e.x:sub(s, f) .. (f < #e.x and "…" or "")
end

--- Search a downloaded site. Synchronous and local.
function M.search(id, query, page, per_source)
  local entries = load_index(id)
  if not entries then
    return nil, "not downloaded yet"
  end
  local q = vim.trim(query:lower())
  local tokens = vim.split(q, "%s+", { trimempty = true })
  local hits = {}
  for i, e in ipairs(entries) do
    local s = score(e, q, tokens)
    if s then
      table.insert(hits, { e = e, s = s, i = i })
    end
  end
  table.sort(hits, function(a, b)
    if a.s ~= b.s then
      return a.s > b.s
    end
    return a.i < b.i
  end)
  local results = {}
  for i = (page - 1) * per_source + 1, math.min(#hits, page * per_source) do
    local e = hits[i].e
    table.insert(results, {
      title = e.n,
      url = e.u,
      snippet = snippet(e, q, tokens),
      tag = id,
      score = hits[i].s,
      open = { kind = "web", url = e.u },
    })
  end
  return results
end

--- The title of a page on a downloaded site, e.g. "The Slice Type" for the
--- Rust Book's ch04-03-slices.html. nil if no added site has the page.
function M.title_for(url)
  url = url:gsub("#.*$", "")
  for _, id in ipairs(M.ids()) do
    local info = state.custom(id)
    local root = info.url:gsub("[?#].*$", ""):gsub("[^/]*$", "")
    if info.kind ~= "template" and url:sub(1, #root) == root then
      for _, e in ipairs(load_index(id) or {}) do
        if e.u:gsub("#.*$", "") == url then
          return e.h ~= "" and e.h or e.n
        end
      end
    end
  end
end

--- Where :Search @id with no query goes: the contents for mdBook sites,
--- the home page for %s sites, else the URL that was added.
function M.start_url(id)
  local info = state.custom(id)
  local u = util.parse_url(info.url)
  if info.kind == "template" then
    return u.scheme .. "://" .. u.authority .. "/"
  elseif info.kind == "mdbook" then
    return util.resolve_url(info.url:gsub("[?#].*$", ""):gsub("[^/]*$", ""), "toc.html")
  end
  return info.url
end

--- The one result a template site gives: its own results page.
function M.template_result(id, query)
  local url = M.search_url(id, query)
  return {
    title = "Search " .. state.custom(id).name .. " for \"" .. query .. "\"",
    url = url,
    snippet = "Opens the site's own search results",
    tag = id,
    score = 45,
    open = { kind = "web", url = url },
  }
end

return M
