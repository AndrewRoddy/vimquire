# vimquire

Search the web and programming docs without leaving Neovim. Type
`:Search <query>` and results from Stack Overflow, Wikipedia, DevDocs and
(optionally) your own SearXNG instance show up merged into one list in the
buffer you're in. Press `<CR>` on a result to read it as plain text, follow
its links, and press `q` to go back.

```
:Search vec push
```

```
 vimquire » vec push
 24 results from stackoverflow, wikipedia, devdocs
 ─────────────────────────────────────────────────────────────────────────

  1. std::vec::Vec::push  [rust]
     devdocs.io/rust/std/vec/struct.vec#method.push
     std::vec

  2. How do you push values to a vec inside an enum stuct in Rust?  [stackoverflow]
     stackoverflow.com/questions/75701102/how-do-you-push-values-to-a-vec-...
     6 votes, 2 answers, answered · rust
 ─────────────────────────────────────────────────────────────────────────
 <CR> open   o browser   y yank URL   n/p next/prev page   s sources   q back
```

## Status

vimquire is an early **Neovim plugin** (0.10 or newer, written in Lua). Here's
what works today and what's planned.

### Working now

- **`:Search`** asks every source you've turned on at once and merges the
  results into one ranked list, tagged by where each came from. Results show
  up as each source answers, so a slow site doesn't hold up the rest.
- **Sources:**
  - **Stack Overflow** through the official Stack Exchange API. Opening a
    result shows the question and its answers, best-voted first.
  - **Wikipedia** through the MediaWiki API. Opening a result shows the
    article as text.
  - **DevDocs**: any of its 843 doc sets (Rust, Python, Svelte, JavaScript,
    React, Go...). Each one's search index is downloaded once and searched
    **on your machine**, so those queries never leave it.
  - **SearXNG** for general web results, if you run an instance and set
    `searxng_url`.
- **`@source` filter**: `:Search @rust push` or `:Search @so borrow checker`
  searches one source only.
- **Page reader**: pages render as text in the same window, with headings, code
  blocks and lists. Links are numbered `[n]`. `<CR>` follows a link, `<Tab>`
  jumps between links, and DevDocs links to `#sections` jump within the page.
  Every page ends with a numbered list of its links.
- **`:SearchSources`**: a list of every source you can search, with
  collapsible sections (see below).
- **Private by default**: no cookies, no history, searches removed from
  command history (see [Private mode](#private-mode)).
- **Lowercase `:search`** works too. It's expanded to `:Search`.

### Planned

- **Python docs straight from docs.python.org.** Any site built with Sphinx
  publishes a `searchindex.js` that could be downloaded and searched locally
  the same way DevDocs is.
- **`llms.txt` sources.** Projects like Svelte publish their whole docs as
  plain text for tools to read. vimquire would add those as sources.
- **`pydoc`**: Python's built-in docs, fully offline with no network at all.
- **GitHub** repository and code search.
- **Brave Search and Kagi** as paid or keyed alternatives to SearXNG.
- **Headless Chrome "render" mode**, opt-in only, for pages that show nothing
  without JavaScript. It would run with a throwaway profile and its sandbox
  on (see [Risks](#risks)).
- **Opt-in search history**, kept local.
- **A `:help vimquire` page.**

## Install

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "AndrewRoddy/vimquire",
  cmd = { "Search", "SearchOpen", "SearchSources", "SearchAdd", "SearchRemove" },
  init = function()
    -- Let a lowercase :search work before the plugin has loaded.
    vim.cmd([[cnoreabbrev <expr> search getcmdtype() ==# ':' && getcmdline() ==# 'search' ? 'Search' : 'search']])
  end,
  opts = {},
}
```

To work on a local checkout, point `dir` at it. This uses the checkout when
the folder exists and clones from GitHub on any machine that doesn't have it:

```lua
dir = vim.uv.fs_stat("C:/Coding/vimquire") and "C:/Coding/vimquire" or nil,
```

vimquire uses `curl` for every request. It ships with Windows 10 and newer,
macOS and most Linux distributions.

## Commands

| Command | What it does |
|---|---|
| `:Search {query}` | Search every enabled source. `@name` at the start searches one. |
| `:SearchOpen {url}` | Read any web page as text |
| `:SearchSources` | Turn sources on and off |
| `:SearchAdd {id...}` | Turn sources on, e.g. `:SearchAdd rust python~3.13` (tab-completes) |
| `:SearchRemove {id...}` | Turn sources off and delete their downloads |

**In the results:** `<CR>` open, `o` open in your browser, `y` copy the URL,
`n`/`p` next/previous page, `s` sources, `q` back.

**On a page:** `<CR>` follow the `[n]` link under the cursor, `<Tab>`/`<S-Tab>`
next/previous link, `o` open in your browser, `y` copy the URL, `q` back.

## Managing sources

`:SearchSources` lists everything you can search. **Websites** and **DevDocs**
are collapsible sections, and DevDocs docs that come in several versions
(Python, Node, Qt...) collapse into their own section inside it.

```
 vimquire sources   4 on · 5.7 MB on disk
 <Space> on/off   <CR> open/close   O offline copy   u update docs   f filter   F clear   q close
 ─────────────────────────────────────────────────────────────────────────
 ▾ Websites
     [x] Stack Overflow            stackoverflow   live, nothing stored
     [x] Wikipedia                 wikipedia       live, nothing stored
     [ ] SearXNG (web)             searxng         set searxng_url in setup() to use

 ▾ DevDocs                     843 docs, 2 on: python~3.13, rust
     [ ] Angular                   angular         offline copy 5.1 MB
   ▾ [~] Python                                    12 versions, 1 on
         [ ] Python 3.14           python~3.14     offline copy 20.8 MB
         [x] Python 3.13           python~3.13     1.4 MB on disk
     [x] Rust                      rust            4.3 MB on disk
```

- **`<Space>`** turns a source on or off. On a section header it opens or
  closes the section instead.
- **Turning a DevDocs doc on** downloads its search index (Rust is 4.3 MB,
  Python 1.4 MB, Svelte 6 KB). **Turning it off** stops any download in
  progress, deletes its files and removes it from search. Turning it back on
  downloads it again.
- **`O`** also downloads every page of a doc so it works with no internet
  (Rust 70 MB, Python 19 MB, Svelte 1 MB). Press `O` again to delete it.
- **`u`** re-downloads any doc that DevDocs has a newer version of.
- **`f`** filters the list (`f` then `python` shows only Python docs); `F`
  clears it. `h`/`l` close and open sections.
- Websites store nothing, so turning one off only removes it from search.

Everything vimquire downloads lives in `stdpath("data")/vimquire`
(`~/AppData/Local/nvim-data/vimquire` on Windows). With a handful of docs
turned on it's usually 10 to 20 MB. Downloading every DevDocs doc for offline
use would be about 8.8 GB, the absolute worst case.

## Configuration

These are the defaults:

```lua
require("vimquire").setup({
  data_dir = vim.fn.stdpath("data") .. "/vimquire",
  curl = "curl",
  timeout = 30,                 -- seconds per request
  results = 20,                 -- results per page of :Search
  per_source = 8,               -- most results any one source contributes
  width = 100,                  -- wrap width for pages (capped to the window)
  private = true,               -- remove searches from command history
  proxy = nil,                  -- e.g. "socks5h://127.0.0.1:9050" for Tor
  lowercase_alias = true,       -- expand :search into :Search
  stackexchange_key = nil,      -- raises Stack Exchange's limit from 300 to 10,000 a day
  wikipedia_lang = "en",
  searxng_url = nil,            -- e.g. "http://localhost:8888"
  default_enabled = { "stackoverflow", "wikipedia" }, -- turned on the first time only
})
```

Running SearXNG locally:

```sh
docker run -d -p 8888:8080 --name searxng searxng/searxng
# then turn on JSON output in its settings.yml:  search.formats: [html, json]
```

## Private mode

Private mode is on by default:

- **No cookies.** Every request starts fresh, so the sites can't link one
  search to the next by cookie.
- **No history.** Searches and pages are never written to disk. Search
  commands are removed from Neovim's command history, so they don't show up in
  `q:` or survive a restart. Buffers are named by a counter, never by the
  query, and are wiped when you leave them.
- **DevDocs searches stay local.** Only the page you open is fetched.
- **No referrer.** Sites you open don't learn you came from a search.
- **Web pages get a common browser user agent.** APIs (Stack Exchange,
  Wikipedia, DevDocs) get `vimquire/0.1` instead, because Wikipedia requires
  tools to identify themselves. That names the tool, not you.

What private mode **can't** hide, same as a browser's incognito window:

- **Your IP address.** Every site you search or open sees it. Set `proxy` to
  route through Tor or a VPN if that matters.
- **Your network.** Your ISP, school or employer can see which sites you
  connect to.
- **An API key.** If you set `stackexchange_key`, that key ties your requests
  together.

## Development

```sh
nvim --headless -u NONE -l tests/smoke.lua
```

The smoke test talks to the real DevDocs, Stack Overflow and Wikipedia, so it
needs internet. It uses a temporary data folder and cleans up after itself.

## Risks

### Accounts and terms of service

- **There's no account to ban.** Every source is an official API or a
  published file, used the way it's meant to be. That's the difference from a
  third-party Discord client, which acts as your logged-in account against
  terms that forbid it.
- **Rate limits.** Stack Exchange allows 300 requests a day per IP without a
  key. vimquire obeys its "back off" signal; ignoring it gets the IP throttled.
- **Scraping search engines** (Google, Bing, DuckDuckGo pages) breaks their
  terms. vimquire doesn't do it. The planned headless Chrome mode is only for
  rendering a page you chose, never for scraping result pages. If you ever add
  scraping, expect CAPTCHAs and IP blocks, which hit everyone on a shared
  network. Use a fresh, throwaway browser profile, never your logged-in one.
- **Licenses.** Stack Overflow and Wikipedia content is CC BY-SA. Reading it is
  fine; reposting it means crediting the authors.
- **DevDocs runs on donations.** vimquire downloads each doc once and only
  re-downloads when it changes. Keep it that way.

### Security

Web pages are hostile input. What vimquire does about it:

- **Nothing from a page is ever run.** Pages are turned into plain text.
  Buffers have `modeline` off, and no page text reaches `:execute` or
  `:normal`.
- **Control characters are stripped**, including terminal escape sequences, so
  a page can't drive your terminal.
- **The query can't run shell commands.** curl is started with an argument
  list, never a shell string, and the query is URL-encoded.
- **Only `http` and `https`**, including through redirects. No `file://`.
- **Links from pages can't reach your own network.** Following a link to
  `localhost`, `192.168.x.x`, `10.x.x.x` and similar is blocked. (`o` still
  opens it in your browser if you really mean it.) This checks the address
  written in the link; it doesn't stop a public hostname that resolves to a
  private address.
- **API keys** belong in environment variables, not in a config that lives in
  a public dotfiles repo.

If the headless Chrome mode gets built, it needs its sandbox on (never
`--no-sandbox`), a throwaway profile, and its remote-debugging port bound to
`127.0.0.1` only. That port has no password.

### Practical

- Pages that need JavaScript show little or nothing. Press `o` to open them in
  your browser.
- Wikipedia results are often off-topic for programming searches. Turn it off
  in `:SearchSources`, or search with `@rust`, `@so` and so on.

## License

MIT (planned; there's no LICENSE file yet)
