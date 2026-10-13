-- Stack Overflow through the official Stack Exchange API. No account needed.
-- Without a key the limit is 300 requests a day per IP; a free key from
-- stackapps.com raises it to 10,000.
local config = require("vimquire.config")
local html = require("vimquire.html")
local http = require("vimquire.http")

local M = {
  id = "stackoverflow",
  label = "Stack Overflow",
  aliases = { "so", "stackoverflow", "stack" },
  note = "live, nothing stored",
}

local API = "https://api.stackexchange.com/2.3"
local backoff_until = 0

function M.available()
  return true
end

local function get(path, params, cb)
  if os.time() < backoff_until then
    return vim.schedule(function()
      cb(nil, string.format("Stack Exchange asked us to wait %ds", backoff_until - os.time()))
    end)
  end
  params.site = "stackoverflow"
  params.key = config.options.stackexchange_key
  return http.get(http.url(API .. path, params), { ua = "tool", json = true }, function(data, err)
    if not data then
      return cb(nil, err)
    end
    -- The API tells clients to back off when they send too much; obey it or
    -- the IP gets throttled.
    if data.backoff then
      backoff_until = os.time() + data.backoff
    end
    if data.error_message then
      return cb(nil, data.error_message)
    end
    cb(data)
  end)
end

function M.search(query, page, n, cb)
  return get("/search/advanced", { q = query, order = "desc", sort = "relevance", pagesize = n, page = page }, function(data, err)
    if not data then
      return cb(nil, err)
    end
    local results = {}
    for _, it in ipairs(data.items or {}) do
      local tags = it.tags and #it.tags > 0 and (" · " .. table.concat(it.tags, ", ")) or ""
      table.insert(results, {
        title = html.decode_entities(it.title or ""),
        url = it.link,
        snippet = string.format("%d votes, %d answers%s%s", it.score or 0, it.answer_count or 0,
          it.is_answered and ", answered" or "", tags),
        tag = "stackoverflow",
        open = { kind = "stackoverflow", id = it.question_id },
      })
    end
    cb(results)
  end)
end

local function byline(item)
  local name = item.owner and item.owner.display_name or "unknown"
  return string.format("by %s · score %d", name, item.score or 0)
end

--- Fetch a question and its answers (best first) as one HTML document.
function M.open(id, cb)
  local question, answers, failed
  local function done()
    if failed or question == nil or answers == nil then
      return
    end
    local q = question.items and question.items[1]
    if not q then
      return cb(nil, "question not found")
    end
    local parts = {
      "<p>Asked " .. byline(q) .. " · " .. table.concat(q.tags or {}, ", ") .. "</p>",
      q.body or "",
    }
    for _, a in ipairs(answers.items or {}) do
      table.insert(parts, "<hr><h2>Answer " .. byline(a) .. (a.is_accepted and " · accepted" or "") .. "</h2>")
      table.insert(parts, a.body or "")
    end
    table.insert(parts, "<hr><p>From Stack Overflow, licensed CC BY-SA. Credit the authors if you reuse it.</p>")
    cb({
      title = html.decode_entities(q.title or ""),
      url = q.link,
      base_url = q.link,
      tag = "stackoverflow",
      html = table.concat(parts, "\n"),
    })
  end
  local function fail(err)
    if not failed then
      failed = true
      cb(nil, err)
    end
  end
  get("/questions/" .. id, { filter = "withbody" }, function(data, err)
    if not data then
      return fail(err)
    end
    question = data
    done()
  end)
  get("/questions/" .. id .. "/answers", { filter = "withbody", sort = "votes", order = "desc", pagesize = 10 }, function(data, err)
    if not data then
      return fail(err)
    end
    answers = data
    done()
  end)
end

return M
