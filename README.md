# vimquire

Search Stack Overflow, Wikipedia and DevDocs from inside Neovim.
Results open in the current window, and pages are rendered as plain text so you
can read them without switching to a browser.

> [!IMPORTANT]
> **Read before using or sharing:**
>
> - **License:** All rights reserved. You may not use, copy, modify or share
>   this software without written permission from the author. See
>   [LICENSE](LICENSE).
> - **Stack Overflow limit is per IP:** Without a key, the Stack Exchange API
>   allows 300 requests a day **per IP address**. On an office or shared
>   network, everyone behind the same IP shares those 300. Each search uses 1
>   request and opening a question uses 2. Set your own free key to get 10,000
>   a day (see [Stack Exchange key](#stack-exchange-key)).
> - **Searches leave your network:** Queries are sent to Stack Exchange,
>   Wikipedia and DevDocs. Don't search for code, names or anything else your
>   company doesn't allow to be sent to outside services.
> - **No API keys are included.** The plugin works without any.

```
:Search vec push
```

```
      vimquire » vec push
      24 results from stackoverflow, wikipedia, devdocs
      ─────────────────────────────────────────────────────────────────────

   ❯  std::vec::Vec::push  [rust]
      devdocs.io/rust/std/vec/struct.vec#method.push
      std::vec

   1  How do you push values to a vec inside an enum stuct in Rust?  [stackoverflow]
      stackoverflow.com/questions/75701102/how-do-you-push-values-to-a-vec-...
      6 votes, 2 answers, answered · rust
```

## Requirements

- Neovim 0.10 or newer
- `curl` on your `PATH` (included with Windows 10 and later, macOS and most
  Linux distributions)

## Installation

[lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "AndrewRoddy/vimquire",
  cmd = { "Search", "SearchOpen", "SearchSources", "SearchAdd", "SearchRemove" },
  init = function()
    -- lets you type :search in lowercase before the plugin has loaded
    vim.cmd([[cnoreabbrev <expr> search getcmdtype() ==# ':' && getcmdline() ==# 'search' ? 'Search' : 'search']])
  end,
  opts = {},
}
```

[vim-plug](https://github.com/junegunn/vim-plug):

```vim
Plug 'AndrewRoddy/vimquire'
```

Without a plugin manager, clone it into your packages folder:

```sh
# Linux / macOS
git clone https://github.com/AndrewRoddy/vimquire ~/.local/share/nvim/site/pack/plugins/start/vimquire
# Windows (PowerShell)
git clone https://github.com/AndrewRoddy/vimquire "$env:LOCALAPPDATA\nvim-data\site\pack\plugins\start\vimquire"
```

Then run `:helptags ALL` once so `:help vimquire` works.

Calling `setup()` is optional. The plugin works with the defaults.

## Getting started

1. Run `:checkhealth vimquire` to make sure Neovim and curl are set up.
2. Search: `:Search rust borrow checker`. Move with `j`/`k`, press `<CR>` to
   read a result, and `q` to go back.
3. Add documentation for what you use: `:SearchAdd rust python~3.13`, or browse
   everything with `:SearchSources`.
4. If you search Stack Overflow a lot, or share a network with other people,
   [set your own key](#stack-exchange-key).

Everything is also in `:help vimquire`.

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
| `j` / `k` | Next / previous result. The number column on the left works like `relativenumber`, but counts results instead of lines, so `3j` goes to the one marked 3. |
| `<CR>` | Open result |
| `o` | Open in browser |
| `y` | Copy URL |
| `n` / `p` | Next / previous page |
| `s` | Sources |
| `q` | Go back |

Page buffer (line numbers follow your `number` / `relativenumber` settings):

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
  stackexchange_key = nil,      -- see "Stack Exchange key" below
  wikipedia_lang = "en",
  default_enabled = { "stackoverflow", "wikipedia" },
})
```

### Stack Exchange key

By default no key is used, so Stack Overflow is limited to 300 requests a day
per IP address, shared with everyone on your network. To use your own free key
(10,000 a day), register an app at
[stackapps.com](https://stackapps.com/apps/oauth/register), then set it in one
of these places. The first one found is used:

1. `stackexchange_key` in `setup()`
2. The `STACKEXCHANGE_KEY` environment variable
3. **Recommended:** a file named `vimquire.env` in your Neovim config folder
   (run `:echo stdpath("config")` to find it), containing:
   ```
   STACKEXCHANGE_KEY=your-key
   ```
   This keeps the key out of your dotfiles' Lua code and survives plugin
   reinstalls.
4. A `.env` file in the plugin folder, same format (copy `.env.example`). It's
   git-ignored, but reinstalling the plugin deletes it.

Restart Neovim after changing an env file. `:checkhealth vimquire` shows
whether a key was found.

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

## Troubleshooting

Start with `:checkhealth vimquire`.

- **"No sources are turned on"**: run `:SearchSources` and turn some on.
- **Stack Overflow says "too many requests from this IP" or "Stack Exchange
  asked us to wait"**: your IP's daily limit is used up, or requests were sent too
  quickly. Wait, or [set a key](#stack-exchange-key).
- **A page is almost empty**: it needs JavaScript. Press `o` to open it in your
  browser.
- **`:search` doesn't turn into `:Search`**: with lazy loading, add the `init`
  line from the [lazy.nvim example](#installation).

## Notes

- Stack Overflow and Wikipedia content is licensed CC BY-SA.
- This is an early version, so expect rough edges.

## Roadmap

- [ ] Python docs from docs.python.org (Sphinx `searchindex.js`)
- [ ] `llms.txt` doc sources (e.g. Svelte)
- [ ] `pydoc` source
- [ ] GitHub search
- [ ] Brave Search and Kagi
- [ ] Optional headless Chrome rendering for JavaScript-heavy pages
- [ ] Optional search history

## Development

```sh
nvim --headless -u NONE -l tests/smoke.lua
```

The smoke test hits the real APIs, so it needs an internet connection. See
[CHANGELOG.md](CHANGELOG.md) for what changed in each version.

## License

Copyright (c) 2026 Andrew Roddy. All rights reserved. See [LICENSE](LICENSE).
