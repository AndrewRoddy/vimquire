-- DevDocs (devdocs.io). There is no search API, so this works the way the
-- DevDocs site itself does: download a doc set's index once and search it
-- locally. Queries never leave your machine. Pages are fetched one at a time
-- when opened, or read from disk when the offline copy is downloaded.
local config = require("vimquire.config")
local http = require("vimquire.http")
local state = require("vimquire.state")
local util = require("vimquire.util")

local M = {}

M.HOST = "https://devdocs.io"
M.DOCS = "https://documents.devdocs.io"

local catalog, by_slug
local indexes = {} -- slug -> entries, loaded on first search
local dbs = {} -- slug -> offline pages, loaded on first open
local downloads = {} -- slug -> { what = "index" | "offline", handle }

local function root()
  return util.data_dir("devdocs")
end

function M.dir(slug)
  return root() .. "/" .. slug
end

local function catalog_path()
  return root() .. "/docs.json"
end

local function set_catalog(list)
  catalog, by_slug = list, {}
  for _, doc in ipairs(list) do
    by_slug[doc.slug] = doc
  end
end

--- The catalog from disk, or nil if it was never downloaded.
function M.catalog()
  if not catalog then
    local data = util.read_json(catalog_path())
    if type(data) == "table" and data[1] then
      set_catalog(data)
    end
  end
  return catalog
end

--- Make sure the catalog is loaded, downloading it if missing or stale.
function M.load_catalog(cb, force)
  local cached = M.catalog()
  local stat = vim.uv.fs_stat(catalog_path())
  local fresh = stat and (os.time() - stat.mtime.sec) < config.options.catalog_max_age
  if cached and fresh and not force then
    return cb(cached)
  end
  http.get(M.HOST .. "/docs.json", { ua = "tool", json = true }, function(data, err)
    if type(data) ~= "table" or not data[1] then
      if cached then
        return cb(cached) -- offline: keep using the old one
      end
      return cb(nil, err or "unexpected catalog format")
    end
    util.write_json(catalog_path(), data)
    set_catalog(data)
    cb(data)
  end)
end

function M.get(slug)
  M.catalog()
  return by_slug and by_slug[slug]
end

function M.label(doc)
  if doc.version and doc.version ~= "" then
    return doc.name .. " " .. doc.version
  end
  return doc.name
end

function M.downloading(slug)
  return downloads[slug] and downloads[slug].what
end

function M.update_available(slug)
  local info, doc = state.doc(slug), M.get(slug)
  return info and doc and (doc.mtime or 0) > (info.mtime or 0)
end

function M.disk_size(slug)
  return util.dir_size(M.dir(slug))
end

-- Download the index (and the offline pages if wanted) into the doc's folder.
-- Files are written to "*.part" first, so a failed update keeps the old copy.
local function download(slug, offline, cb)
  local doc = M.get(slug)
  if not doc then
    return cb(nil, "unknown DevDocs doc: " .. slug)
  end
  if downloads[slug] then
    return cb(nil, "already downloading " .. slug)
  end
  local dir = M.dir(slug)
  vim.fn.mkdir(dir, "p")
  local bust = "?" .. tostring(doc.mtime or "")
  local job = { what = offline and "offline" or "index" }
  downloads[slug] = job

  local function done(ok, err)
    downloads[slug] = nil
    if not ok then
      return cb(nil, err)
    end
    indexes[slug], dbs[slug] = nil, nil
    state.set_doc(slug, { name = M.label(doc), release = doc.release, mtime = doc.mtime, offline = offline or nil })
    cb(true)
  end

  job.handle = http.get(M.DOCS .. "/" .. slug .. "/index.json" .. bust, { ua = "tool", output = dir .. "/index.json" }, function(ok, err)
    if not ok or not offline then
      return done(ok, err)
    end
    job.handle = http.get(M.DOCS .. "/" .. slug .. "/db.json" .. bust, { ua = "tool", output = dir .. "/db.json" }, done)
  end)
end

--- Turn a doc on: downloads its index (and offline pages if opts.offline).
function M.enable(slug, opts, cb)
  local fresh = state.doc(slug) == nil
  download(slug, opts and opts.offline, function(ok, err)
    if not ok and fresh then
      vim.fn.delete(M.dir(slug), "rf")
    end
    cb(ok, err)
  end)
end

--- Turn a doc off: stops any download, deletes its files and drops it from search.
--- Returns the number of bytes freed.
function M.disable(slug)
  local job = downloads[slug]
  if job and job.handle and job.handle.cancel then
    job.handle:cancel()
  end
  downloads[slug] = nil
  local freed = M.disk_size(slug)
  vim.fn.delete(M.dir(slug), "rf")
  indexes[slug], dbs[slug] = nil, nil
  state.set_doc(slug, nil)
  return freed
end

--- Download or delete the offline copy of an enabled doc.
function M.set_offline(slug, on, cb)
  local info = state.doc(slug)
  if not info then
    return M.enable(slug, { offline = on }, cb)
  end
  if on then
    return download(slug, true, cb)
  end
  os.remove(M.dir(slug) .. "/db.json")
  dbs[slug] = nil
  info.offline = nil
  state.set_doc(slug, info)
  cb(true)
end

--- Re-download every enabled doc that has a newer version in the catalog.
function M.update(cb)
  M.load_catalog(function(_, err)
    if err then
      return cb(nil, err)
    end
    local todo = vim.tbl_filter(M.update_available, state.enabled_docs())
    if #todo == 0 then
      return cb({})
    end
    local left, failed = #todo, {}
    for _, slug in ipairs(todo) do
      download(slug, state.doc(slug).offline, function(ok, e)
        if not ok then
          failed[slug] = e
        end
        left = left - 1
        if left == 0 then
          cb(todo, next(failed) and failed or nil)
        end
      end)
    end
  end, true)
end

local function load_index(slug)
  if indexes[slug] then
    return indexes[slug]
  end
  local data = util.read_json(M.dir(slug) .. "/index.json")
  if type(data) ~= "table" or type(data.entries) ~= "table" then
    return nil
  end
  for _, e in ipairs(data.entries) do
    e.lname = e.name:lower()
    e.norm = e.lname:gsub("[^%w]", "")
    e.ltype = (e.type or ""):lower()
    e.tail = e.lname:match("[%w_$]+[^%w_$]*$")
    e.tail = e.tail and e.tail:match("^[%w_$]+")
  end
  indexes[slug] = data.entries
  return data.entries
end

local function score(e, q, qnorm, tokens)
  local extra = math.min(12, (#e.lname - #q) / 4)
  if e.lname == q then
    return 100
  elseif qnorm ~= "" and e.norm == qnorm then
    return 96
  elseif e.tail == q then
    return 92 - extra / 2
  elseif #qnorm > 2 and e.norm:sub(-#qnorm) == qnorm then
    -- "vec push" -> "std::vec::Vec::push"
    return 91 - extra / 2
  elseif e.lname:sub(1, #q) == q then
    return 86 - extra
  elseif e.lname:find(q, 1, true) then
    return 74 - extra
  elseif qnorm ~= "" and e.norm:find(qnorm, 1, true) then
    return 66 - extra
  end
  for _, t in ipairs(tokens) do
    if not e.lname:find(t, 1, true) and not e.ltype:find(t, 1, true) then
      return nil
    end
  end
  return 50 - extra
end

--- Does "@filter" pick this doc? Matches the slug, "python" for "python~3.13",
--- the DevDocs alias ("rs", "py") or the doc's name.
function M.matches(slug, filter)
  local doc = M.get(slug) or {}
  return slug == filter or slug:match("^(.-)~") == filter or doc.alias == filter
    or (doc.name and doc.name:lower() == filter)
end

function M.page_url(slug, path)
  return M.HOST .. "/" .. slug .. "/" .. path
end

--- Search the downloaded indexes of the given docs. Synchronous and local.
function M.search(query, slugs, page, per_source)
  local q = vim.trim(query:lower())
  local qnorm = q:gsub("[^%w]", "")
  local tokens = vim.split(q, "%s+", { trimempty = true })
  local results = {}
  for _, slug in ipairs(slugs) do
    local entries = load_index(slug)
    if entries then
      local hits = {}
      for _, e in ipairs(entries) do
        local s = score(e, q, qnorm, tokens)
        if s then
          table.insert(hits, { e = e, s = s })
        end
      end
      table.sort(hits, function(a, b)
        if a.s ~= b.s then
          return a.s > b.s
        end
        return a.e.name < b.e.name
      end)
      for i = (page - 1) * per_source + 1, math.min(#hits, page * per_source) do
        local e = hits[i].e
        table.insert(results, {
          title = e.name,
          url = M.page_url(slug, e.path),
          snippet = e.type,
          tag = slug,
          score = hits[i].s,
          open = { kind = "devdocs", slug = slug, path = e.path, title = e.name },
        })
      end
    end
  end
  return results
end

--- The pages before and after path, in the order the doc's index lists them
--- within the page's type (e.g. the Rust Book's chapters under "Guide").
--- Returns { prev, next }, each { path, name }, or nil if the doc's index
--- isn't downloaded.
function M.neighbors(slug, path)
  local entries = load_index(slug)
  if not entries then
    return nil
  end
  local page = path:gsub("#.*$", "")
  local kind
  for _, e in ipairs(entries) do
    if e.path:gsub("#.*$", "") == page then
      kind = e.type
      break
    end
  end
  if not kind then
    return nil
  end
  local pages, names = {}, {}
  for _, e in ipairs(entries) do
    local p = e.path:gsub("#.*$", "")
    if e.type == kind and not names[p] then
      table.insert(pages, p)
      names[p] = e.name
    end
  end
  for i, p in ipairs(pages) do
    if p == page then
      local prev, nxt = pages[i - 1], pages[i + 1]
      return {
        prev = prev and { path = prev, name = names[prev] },
        next = nxt and { path = nxt, name = names[nxt] },
      }
    end
  end
end

--- Get a page's HTML: from the offline copy if there is one, else from DevDocs.
function M.fetch_page(slug, path, cb)
  local file = path:gsub("#.*$", "")
  local info = state.doc(slug)
  if info and info.offline then
    dbs[slug] = dbs[slug] or util.read_json(M.dir(slug) .. "/db.json")
    local html = dbs[slug] and dbs[slug][file]
    if html then
      return vim.schedule(function()
        cb(html)
      end)
    end
  end
  local doc = M.get(slug)
  local url = M.DOCS .. "/" .. slug .. "/" .. util.encode_path(file) .. ".html"
  if doc and doc.mtime then
    url = url .. "?" .. doc.mtime
  end
  return http.get(url, { ua = "tool" }, cb)
end

--- Split "https://devdocs.io/<slug>/<path>" into slug and path.
function M.parse_url(url)
  local slug, path = url:match("^https?://devdocs%.io/([^/#?]+)/([^?]+)")
  if slug then
    return slug, vim.uri_decode(path)
  end
end

return M
