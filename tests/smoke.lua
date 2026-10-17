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
local nav = html.page_nav('<link rel="prev" title="4. Flow" href="flow.html"><a rel="next prefetch" title="Next chapter" href="ch5.html">→</a><iframe src="../toc.html"></iframe>')
check(nav.prev.href == "flow.html" and nav.prev.title == "4. Flow" and nav.next.href == "ch5.html" and nav.next.title == nil
  and nav.contents.href == "../toc.html", "page prev/next/contents links")
local toc = html.render('<ol class="chapter"><li><a href="a">Foreword</a></li><li><a href="b"><strong>1.</strong> Start</a><ol class="section"><li><a href="c"><strong>1.1.</strong> Install</a></li></ol></li></ol><ol><li>2. Self-numbered</li><li>plain</li></ol>', { width = 60 })
check(toc.lines[1] == "Foreword[1]" and toc.lines[2] == "1. Start[2]" and toc.lines[3] == "  1.1. Install[3]"
  and toc.lines[5] == "2. Self-numbered" and toc.lines[6] == "2. plain", "contents lists aren't numbered twice: " .. vim.inspect(toc.lines))

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
local near = devdocs.neighbors("svelte", "$state")
check(near and (near.prev or near.next) and (near.next or near.prev).path ~= "$state", "devdocs previous/next page")

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

-- Results show their distance from the cursor in the number column
require("vimquire.results").search("@wikipedia neovim")
check(wait(function()
  return buffer_text():find("%[wikipedia%]")
end), "results for gutter test")
local function gutter(lnum)
  return vim.api.nvim_eval_statusline(vim.wo.statuscolumn, { use_statuscol_lnum = lnum }).str
end
local titles = {}
for l = 1, vim.api.nvim_buf_line_count(0) do
  if vim.api.nvim_buf_get_lines(0, l - 1, l, false)[1]:find("%[wikipedia%]$") then
    table.insert(titles, l)
  end
end
check(#titles >= 3 and gutter(titles[1]):find("1") and gutter(titles[1] + 1):match("^%s*$"), "result numbers in gutter")
vim.api.nvim_win_set_cursor(0, { titles[2], 0 })
check(gutter(titles[2]):find("❯") and gutter(titles[3]):find("1"), "gutter follows cursor")
vim.cmd("normal q")

-- Stack Exchange key: setup() beats $STACKEXCHANGE_KEY beats the env files
local config = require("vimquire.config")
local env_dir = tmp .. "/env"
vim.fn.mkdir(env_dir, "p")
local env_files = config.env_files
config.env_files = function()
  return { env_dir .. "/vimquire.env", env_dir .. "/.env" }
end
vim.fn.writefile({ "STACKEXCHANGE_KEY=" }, env_dir .. "/vimquire.env")
vim.fn.writefile({ "# comment", 'STACKEXCHANGE_KEY="from-dotenv"' }, env_dir .. "/.env")
config.env(true)
local saved_env = vim.env.STACKEXCHANGE_KEY
vim.env.STACKEXCHANGE_KEY = nil
check(config.stackexchange_key() == "from-dotenv", "key from .env, blank vimquire.env ignored")
vim.fn.writefile({ "STACKEXCHANGE_KEY=from-config" }, env_dir .. "/vimquire.env")
config.env(true)
check(config.stackexchange_key() == "from-config", "vimquire.env beats .env")
vim.env.STACKEXCHANGE_KEY = "from-env-var"
check(config.stackexchange_key() == "from-env-var", "$STACKEXCHANGE_KEY beats files")
config.options.stackexchange_key = "from-setup"
check(config.stackexchange_key() == "from-setup", "setup() beats everything")
config.options.stackexchange_key = nil
vim.env.STACKEXCHANGE_KEY = saved_env
config.env_files = env_files
config.env(true)

-- Following links on a page (fetch faked, so no network)
local http = require("vimquire.http")
local page = require("vimquire.page")
local real_get, real_open = http.get, page.open
http.get = function(_, _, cb)
  cb('<p>Go <a href="/one">one</a> or <a href="https://two.example/">two</a>.</p><pre>see https://bare.example/x.</pre>')
end
vim.cmd("SearchOpen https://test.example/start")
http.get = real_get
local opened
page.open = function(spec)
  opened = spec.url
end
local pb = vim.api.nvim_get_current_buf()
local function line_of(pat)
  for i, l in ipairs(vim.api.nvim_buf_get_lines(pb, 0, -1, false)) do
    if l:find(pat) then
      return i, l
    end
  end
end
vim.cmd("SearchFollow 2")
check(opened == "https://two.example/", ":SearchFollow 2")
local lnum, l = line_of("bare%.example")
vim.api.nvim_win_set_cursor(0, { lnum, (l:find("https")) })
opened = nil
vim.cmd("SearchFollow")
check(opened == "https://bare.example/x", "follows a bare URL under the cursor")
vim.api.nvim_win_set_cursor(0, { (line_of("one")), 0 })
opened = nil
vim.api.nvim_feedkeys(vim.keycode("2<CR>"), "x", false)
check(opened == "https://two.example/", "{n}<CR> follows [n]")
local real_select = vim.ui.select
vim.ui.select = function(items, _, cb)
  cb(items[1])
end
vim.api.nvim_win_set_cursor(0, { 3, 0 }) -- the key help line: no link
opened = nil
vim.cmd("SearchFollow")
check(opened == "https://test.example/one", ":SearchFollow with nothing under the cursor lists links")
vim.ui.select, page.open = real_select, real_open
vim.cmd("normal q")

-- :SearchSite (fetch faked, so no network): mdBook index, crawl, %s template
local custom = require("vimquire.sources.custom")
local site_pages = {
  ["https://book.example/"] = '<title>Intro - The Book</title><script>window.path_to_searchindex_js = "searchindex-ab12.js";</script>',
  ["https://book.example/searchindex-ab12.js"] = [[window.search = Object.assign(window.search, JSON.parse('{"doc_urls":["ch1.html#owning","ch2.html#it\'s"],"index":{"documentStore":{"docs":{"0":{"body":"Each value has an owner.","breadcrumbs":"Basics » Ownership","title":"Ownership"},"1":{"body":"A back\\\\slash","breadcrumbs":"Basics » It\'s","title":"It\'s"}}}}}'));]],
  ["https://crawl.example/docs/"] = '<title>Docs</title><h1>Start</h1><p><a href="a.html">a</a> <a href="/other/">out</a> <a href="pic.png">pic</a> <a HREF="secret/x.html">s</a></p>',
  ["https://crawl.example/docs/a.html"] = '<title>Page A</title><h2 id="tuning">Tuning knobs</h2><p>Turn the frobnicator up.</p>',
  ["https://crawl.example/robots.txt"] = "User-agent: *\nDisallow: /docs/secret/",
}
local fetched = {}
http.get = function(url, _, cb)
  fetched[url] = true
  vim.schedule(function()
    local body = site_pages[url]
    cb(body, body == nil and "The requested URL returned error: 404" or nil, url)
  end)
  return { cancel = function() end }
end
local site_ok
vim.cmd("SearchSite https://book.example/")
check(wait(function()
  return not custom.building("book") and state.custom("book") and state.custom("book").kind ~= nil
end, 5000) and state.custom("book").kind == "mdbook" and state.custom("book").name == "The Book", "mdBook site indexed")
local book = custom.search("book", "ownership", 1, 5)
check(book and book[1] and book[1].url == "https://book.example/ch1.html#owning" and book[1].title == "Basics » Ownership", "mdBook search")
check((custom.search("book", "back\\slash", 1, 5) or {})[1] ~= nil, "mdBook escapes decoded")
require("vimquire").add_site("crawly", "crawl.example/docs/")
check(wait(function()
  return state.custom("crawly") and state.custom("crawly").kind ~= nil
end, 5000) and state.custom("crawly").pages == 2, "crawled 2 pages")
check(not fetched["https://crawl.example/docs/pic.png"] and not fetched["https://crawl.example/other/"]
  and not fetched["https://crawl.example/docs/secret/x.html"], "crawl stays under the URL, skips images and robots.txt rules")
local hit = (custom.search("crawly", "frobnicator", 1, 5) or {})[1]
check(hit and hit.url == "https://crawl.example/docs/a.html#tuning" and hit.title == "Page A » Tuning knobs", "crawled section found")
vim.cmd("SearchSite tmpl https://find.example/?q=%s")
wait(function()
  return state.custom("tmpl") ~= nil
end, 2000)
check(custom.search_url("tmpl", "a b&c") == "https://find.example/?q=a%20b%26c", "template URL filled in")
check(#require("vimquire.sources").targets("crawly") == 1, "@crawly picks the site")
page.open = function(spec)
  opened = spec.url
end
opened = nil
vim.cmd("Search @crawly")
check(opened == "https://crawl.example/docs/", ":Search @site with no query opens the site")
opened = nil
vim.cmd("Search @tmpl")
check(opened == "https://find.example/", ":Search @site for a %s site opens its home page")
page.open = real_open
vim.cmd("SearchRemove book crawly tmpl")
check(wait(function()
  return #state.custom_ids() == 0
end, 5000) and vim.uv.fs_stat(custom.dir("book")) == nil, "sites removed and files deleted")
http.get = real_get

-- Help and health
check(pcall(vim.cmd, "helptags " .. vim.fn.fnameescape(vim.fn.getcwd() .. "/doc")) and pcall(vim.cmd, "help vimquire-key"), ":help vimquire-key")
vim.cmd("silent! helpclose")
local ok_health, health_err = pcall(vim.cmd, "checkhealth vimquire")
local report = buffer_text()
check(ok_health and report:find("vimquire " .. config.version) and not report:find("ERROR"), "checkhealth vimquire" .. (ok_health and "" or (": " .. tostring(health_err))))
print(report)

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
