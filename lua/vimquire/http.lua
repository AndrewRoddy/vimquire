local config = require("vimquire.config")
local util = require("vimquire.util")

local M = {}

-- Web pages get a common browser user agent so the request doesn't stand out.
M.BROWSER_UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
-- APIs get an honest one: Wikipedia requires it. It names the tool, not you.
M.TOOL_UA = "vimquire/0.1 (+https://github.com/AndrewRoddy/vimquire)"

--- Fetch a URL with curl without blocking the editor.
--- opts.ua: "browser" (default) or "tool"
--- opts.json: decode the body as JSON
--- opts.output: download to this file instead of returning the body
--- cb(result, err) runs on the main loop. Returns a handle with :cancel().
function M.get(url, opts, cb)
  opts = opts or {}
  local o = config.options
  local cmd = {
    o.curl, "-sS", "-L", "--compressed", "--fail",
    "--max-time", tostring(opts.timeout or o.timeout),
    "--max-redirs", "5",
    -- No file://, gopher://, etc., even through a redirect.
    "--proto", "=http,https", "--proto-redir", "=http,https",
    "-A", opts.ua == "tool" and M.TOOL_UA or M.BROWSER_UA,
  }
  if o.proxy and o.proxy ~= "" then
    vim.list_extend(cmd, { "--proxy", o.proxy })
  end
  local part
  if opts.output then
    part = opts.output .. ".part"
    vim.list_extend(cmd, { "-o", part })
  end
  table.insert(cmd, url)

  local handle = { cancelled = false }
  local function finish(res)
    if handle.cancelled then
      if part then
        os.remove(part)
      end
      return
    end
    if res.code ~= 0 then
      if part then
        os.remove(part)
      end
      local err = vim.trim(res.stderr or "")
      return cb(nil, err ~= "" and err or ("curl exited with code " .. res.code))
    end
    if part then
      os.remove(opts.output)
      local ok, err = os.rename(part, opts.output)
      return cb(ok and true or nil, err)
    end
    local body = res.stdout or ""
    if opts.json then
      local ok, data = pcall(vim.json.decode, body, { luanil = { object = true, array = true } })
      if not ok then
        return cb(nil, "invalid JSON response")
      end
      return cb(data)
    end
    cb(body)
  end

  local ok, proc = pcall(vim.system, cmd, { text = part == nil }, vim.schedule_wrap(finish))
  if not ok then
    vim.schedule(function()
      cb(nil, "could not run curl (" .. tostring(proc) .. ")")
    end)
    return handle
  end
  function handle:cancel()
    self.cancelled = true
    pcall(proc.kill, proc, 9)
  end
  return handle
end

--- Build "base?k=v&k=v" from a table, skipping nil values.
function M.url(base, params)
  local keys = vim.tbl_keys(params)
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do
    if params[k] ~= nil then
      table.insert(parts, util.urlencode(k) .. "=" .. util.urlencode(params[k]))
    end
  end
  if #parts == 0 then
    return base
  end
  return base .. (base:find("?", 1, true) and "&" or "?") .. table.concat(parts, "&")
end

return M
