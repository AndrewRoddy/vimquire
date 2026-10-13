-- General web search through your own SearXNG instance. Enable the json
-- format in its settings.yml (search.formats: [html, json]).
local config = require("vimquire.config")
local http = require("vimquire.http")
local util = require("vimquire.util")

local M = {
  id = "searxng",
  label = "SearXNG (web)",
  aliases = { "web", "searxng", "sx" },
  note = "live, nothing stored",
}

function M.available()
  local url = config.options.searxng_url
  return url ~= nil and url ~= ""
end

function M.unavailable_note()
  return "set searxng_url in setup() to use"
end

function M.search(query, page, n, cb)
  local base = config.options.searxng_url:gsub("/+$", "")
  return http.get(http.url(base .. "/search", { q = query, format = "json", pageno = page }), { ua = "tool", json = true }, function(data, err)
    if not data then
      return cb(nil, err)
    end
    local results = {}
    for _, it in ipairs(data.results or {}) do
      if #results >= n then
        break
      end
      if it.url and util.is_web_url(it.url) then
        table.insert(results, {
          title = it.title or it.url,
          url = it.url,
          snippet = it.content,
          tag = "web",
          open = { kind = "web", url = it.url },
        })
      end
    end
    cb(results)
  end)
end

return M
