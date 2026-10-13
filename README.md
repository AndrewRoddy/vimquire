# vimquire

Search Stack Overflow, Wikipedia, DevDocs and the web from inside Neovim.
Results open in the current window, and pages are rendered as plain text so you
can read them without switching to a browser.

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
```

Requires Neovim 0.10+ and `curl`. This is an early version, so expect rough
edges.

## Installation

[lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "AndrewRoddy/vimquire",
  cmd = { "Search", "SearchOpen", "SearchSources", "SearchAdd", "SearchRemove" },
  init = function()
    -- lets you type :search in lowercase
    vim.cmd([[cnoreabbrev <expr> search getcmdtype() ==# ':' && getcmdline() ==# 'search' ? 'Search' : 'search']])
  end,
  opts = {},
}
```

## Usage

| Command | Description |
|---|---|
| `:Search {query}` | Search all enabled sources |
| `:Search @{source} {query}` | Search one source, e.g. `:Search @rust push` or `:Search @so lifetimes` |
| `:SearchOpen {url}` | Open a web page as text |
| `:SearchSources` | Enable and disable sources |
| `:SearchAdd {source...}` | Enable sources, e.g. `:SearchAdd rust python~3.13` |
| `:SearchRemove {source...}` | Disable sources and delete their downloaded files |

Results buffer:

| Key | Action |
|---|---|
| `<CR>` | Open result |
| `o` | Open in browser |
| `y` | Copy URL |
| `n` / `p` | Next / previous page |
| `s` | Sources |
| `q` | Go back |

Page buffer:

| Key | Action |
|---|---|
| `<CR>` | Follow the `[n]` link under the cursor |
| `<Tab>` / `<S-Tab>` | Next / previous link |
| `o` | Open in browser |
| `y` | Copy URL |
| `q` | Go back |

## Sources

| Source | How it works |
|---|---|
| Stack Overflow | Stack Exchange API. Shows the question and answers sorted by votes. 300 requests/day per IP, or 10,000 with a free key. |
| Wikipedia | MediaWiki API. |
| DevDocs | Downloads a doc's search index and searches it locally. Pages are fetched when opened. |
| SearXNG | General web search through your own SearXNG instance. Off until you set `searxng_url`. |

Stack Overflow and Wikipedia are enabled by default. DevDocs has 843 doc sets
and none are enabled by default.

### Managing sources

`:SearchSources` opens the list of sources. The Websites and DevDocs sections
can be expanded and collapsed, and docs with multiple versions (Python, Node,
etc.) are grouped under their own heading.

```
 vimquire sources   4 on · 5.7 MB on disk
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

| Key | Action |
|---|---|
| `<Space>` / `<CR>` | Enable or disable a source, or expand/collapse a section |
| `l` / `h` | Expand / collapse |
| `O` | Download or delete a doc's offline copy |
| `u` | Update docs that have a newer version |
| `f` / `F` | Filter the list / clear the filter |
| `q` | Close |

Enabling a DevDocs doc downloads its search index (Rust is 4.3 MB, Python
1.4 MB). Disabling it deletes the files, and enabling it again downloads them
again. The offline copy contains every page, so it's bigger (Rust is 70 MB).

Downloads are stored in `stdpath("data")/vimquire`.

## Configuration

Defaults:

```lua
require("vimquire").setup({
  data_dir = vim.fn.stdpath("data") .. "/vimquire",
  curl = "curl",
  timeout = 30,                 -- seconds per request
  results = 20,                 -- results per page
  per_source = 8,               -- max results from each source
  width = 100,                  -- text width for pages
  private = true,               -- remove :Search from command history
  proxy = nil,                  -- e.g. "socks5h://127.0.0.1:9050"
  lowercase_alias = true,       -- expand :search to :Search
  stackexchange_key = nil,
  wikipedia_lang = "en",
  searxng_url = nil,            -- e.g. "http://localhost:8888"
  default_enabled = { "stackoverflow", "wikipedia" },
})
```

To run SearXNG locally:

```sh
docker run -d -p 8888:8080 --name searxng searxng/searxng
```

Then enable JSON output in its `settings.yml` (`search.formats: [html, json]`).

## Privacy

- No cookies are stored and no referrer is sent.
- Searches are removed from command history and nothing is written to disk
  except the enabled sources list and DevDocs downloads.
- DevDocs searches run locally. Only pages you open are fetched.
- Your IP is still visible to every site. Use `proxy` if you want to route
  requests through Tor or a VPN.

## Security

Pages are converted to plain text and never executed. Control characters and
terminal escape sequences are stripped, buffers have `modeline` disabled, and
curl is restricted to http/https. Links in pages that point to localhost or
private network addresses are blocked (`o` still opens them in your browser).

## Notes

- SearXNG gets its results by scraping search engines like Google and Bing,
  which is against their terms. At personal volume it's unlikely to be a
  problem, but those engines can rate-limit or block the IP it runs on.
- Stack Overflow and Wikipedia content is licensed CC BY-SA.
- Pages that depend on JavaScript won't render much. Use `o` to open them in a
  browser.

## Roadmap

- [ ] Python docs from docs.python.org (Sphinx `searchindex.js`)
- [ ] `llms.txt` doc sources (e.g. Svelte)
- [ ] `pydoc` source
- [ ] GitHub search
- [ ] Brave Search and Kagi
- [ ] Optional headless Chrome rendering for JavaScript-heavy pages
- [ ] Optional search history
- [ ] `:help vimquire`

## Development

```sh
nvim --headless -u NONE -l tests/smoke.lua
```

The smoke test hits the real APIs, so it needs an internet connection.
