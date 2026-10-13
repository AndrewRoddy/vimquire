-- Live smoke test. Hits DevDocs, Stack Overflow and Wikipedia.
-- Run from the repo root:
--   nvim --headless -u NONE -l tests/smoke.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.cmd("runtime plugin/vimquire.lua")

local tmp = vim.fn.tempname()
require("vimquire").setup({ data_dir = tmp })

local failures = 0
local function check(cond, msg)
  print((cond and "ok   " or "FAIL ") .. msg)
  if not cond then
    failures = failures + 1
  end
end

local function wait(pred, ms)
  return vim.wait(ms or 20000, pred, 50)
end

local function buffer_text()
  return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
end

local util = require("vimquire.util")
check(util.resolve_url("https://devdocs.io/rust/std/vec/struct.vec", "../macro.vec") == "https://devdocs.io/rust/std/macro.vec", "resolve ../")
check(util.resolve_url("https://a.com/x/y?q=1", "#frag") == "https://a.com/x/y?q=1#frag", "resolve #frag")
check(util.resolve_url("https://a.com", "b/c") == "https://a.com/b/c", "resolve relative from root")
check(util.is_private_host("192.168.1.1") and util.is_private_host("localhost") and not util.is_private_host("example.com"), "private hosts")
check(util.clean("a\27[31mb\0c") == "a[31mbc", "control characters stripped")

local html = require("vimquire.html")
local r = html.render('<h1>T</h1><p>See <a href="/x">this</a> and <code>v[0]</code>.</p><pre>a\n  b</pre><script>alert("<p>")</script>', { width = 60 })
check(r.lines[1] == "# T", "heading rendered")
check(#r.links == 1 and #r.spots == 1, "one link, one spot")
check(not table.concat(r.lines, "\n"):find("alert"), "script dropped")

-- Sources on by default
local state = require("vimquire.state")
check(state.site_enabled("stackoverflow") and state.site_enabled("wikipedia"), "default sites on")

-- DevDocs: enable svelte (small), search, open, disable
local devdocs = require("vimquire.sources.devdocs")
local done
require("vimquire").add({ "svelte" })
check(wait(function()
  return state.doc("svelte") ~= nil
end), "svelte downloaded")
check(vim.uv.fs_stat(devdocs.dir("svelte") .. "/index.json") ~= nil, "svelte index on disk")

local hits = devdocs.search("$state", { "svelte" }, 1, 5)
check(#hits > 0 and hits[1].title == "$state", "devdocs finds $state first")

vim.cmd("Search $state")
check(wait(function()
  return buffer_text():find("results from")
end), "results rendered")
print(buffer_text())

require("vimquire.page").open(hits[1].open)
check(wait(function()
  return buffer_text():find("%$state", 1) and not buffer_text():find("Loading")
end), "devdocs page loaded")
print(table.concat(vim.api.nvim_buf_get_lines(0, 0, 25, false), "\n"))

-- Stack Overflow
local so = require("vimquire.sources.stackoverflow")
local so_results
so.search("reverse a list python", 1, 3, function(res, err)
  so_results = res or err
end)
wait(function()
  return so_results ~= nil
end)
check(type(so_results) == "table" and #so_results > 0, "stack overflow search: " .. vim.inspect(type(so_results) == "table" and #so_results or so_results))
if type(so_results) == "table" and so_results[1] then
  require("vimquire.page").open(so_results[1].open)
  check(wait(function()
    return buffer_text():find("Answer by")
  end), "stack overflow question + answers loaded")
end

-- Wikipedia
local wiki = require("vimquire.sources.wikipedia")
local w
wiki.search("Vim text editor", 1, 3, function(res, err)
  w = res or err
end)
wait(function()
  return w ~= nil
end)
check(type(w) == "table" and #w > 0, "wikipedia search")
if type(w) == "table" and w[1] then
  require("vimquire.page").open(w[1].open)
  check(wait(function()
    return buffer_text():find("CC BY%-SA")
  end), "wikipedia article loaded")
end

-- Manager renders the accordion
require("vimquire.manager").open()
check(wait(function()
  return buffer_text():find("DevDocs%s+%d+ docs")
end), "sources list shows DevDocs catalog")
print(buffer_text())

-- Removing deletes the files and drops it from search
require("vimquire").remove({ "svelte" })
check(wait(function()
  return state.doc("svelte") == nil
end, 5000), "svelte turned off")
check(vim.uv.fs_stat(devdocs.dir("svelte")) == nil, "svelte files deleted")
check(#require("vimquire.sources").targets("svelte") == 0, "svelte no longer searched")

vim.fn.delete(tmp, "rf")
print(failures == 0 and "ALL PASSED" or (failures .. " FAILED"))
vim.cmd(failures == 0 and "qa!" or "cq!")
