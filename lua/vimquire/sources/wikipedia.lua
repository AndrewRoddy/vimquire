-- Wikipedia through the MediaWiki API. No account needed.
local config = require("vimquire.config")
local html = require("vimquire.html")
local http = require("vimquire.http")
local util = require("vimquire.util")

local M = {
  id = "wikipedia",
  label = "Wikipedia",
  aliases = { "wiki", "wikipedia", "wp" },
  note = "live, nothing stored",
}

function M.available()
  return true
end

local function host()
  return "https://" .. config.options.wikipedia_lang .. ".wikipedia.org"
end

function M.article_url(title)
  return host() .. "/wiki/" .. util.urlencode(title:gsub(" ", "_")):gsub("%%2F", "/")
end

local function api(params, cb)
  params.format = "json"
  params.formatversion = 2
  return http.get(http.url(host() .. "/w/api.php", params), { ua = "tool", json = true }, function(data, err)
    if not data then
      return cb(nil, err)
    end
    if data.error then
      return cb(nil, data.error.info or "Wikipedia API error")
    end
    cb(data)
  end)
end

function M.search(query, page, n, cb)
  return api({ action = "query", list = "search", srsearch = query, srlimit = n, sroffset = (page - 1) * n, srprop = "snippet" }, function(data, err)
    if not data then
      return cb(nil, err)
    end
    local results = {}
    for _, it in ipairs(data.query and data.query.search or {}) do
      local snippet = html.decode_entities((it.snippet or ""):gsub("<[^>]*>", ""))
      table.insert(results, {
        title = it.title,
        url = M.article_url(it.title),
        snippet = snippet,
        tag = "wikipedia",
        open = { kind = "wikipedia", title = it.title },
      })
    end
    cb(results)
  end)
end

--- Fetch an article as plain text.
function M.open(title, cb)
  return api({ action = "query", prop = "extracts", explaintext = 1, exsectionformat = "wiki", titles = title, redirects = 1 }, function(data, err)
    if not data then
      return cb(nil, err)
    end
    local page = data.query and data.query.pages and data.query.pages[1]
    if not page or page.missing or not page.extract then
      return cb(nil, "article not found")
    end
    cb({
      title = page.title,
      url = M.article_url(page.title),
      base_url = M.article_url(page.title),
      tag = "wikipedia",
      text = page.extract .. "\n\nFrom Wikipedia, licensed CC BY-SA.",
    })
  end)
end

return M
