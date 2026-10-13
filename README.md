# vimquire

Web search from inside Vim. Type `:Search <query>` and the results open in the
buffer you're in. Pick a result to read the page as plain text without leaving
the editor.

> **Status:** early design. Nothing below is implemented yet. This README
> describes the plan.

```
:Search how to reverse a list in python
```

```
 vimquire » how to reverse a list in python                      [brave]
 ──────────────────────────────────────────────────────────────────────
  1. How do I reverse a list in Python? - Stack Overflow
     stackoverflow.com/questions/3940128
     Use list.reverse() to reverse in place, or reversed() / slicing [::-1]...

  2. Python List reverse() Method - W3Schools
     www.w3schools.com/python/ref_list_reverse.asp
     The reverse() method reverses the sorting order of the elements...
 ──────────────────────────────────────────────────────────────────────
 <CR> open   o open in browser   y yank URL   n/p next/prev page   q back
```

## Why `:Search` and not `:search`

Vim only lets plugins define user commands that start with a **capital letter**,
so `:search` isn't possible. If you want to type it in lowercase anyway, add an
abbreviation that only fires at the start of the command line:

```vim
cnoreabbrev <expr> search getcmdtype() ==# ':' && getcmdline() ==# 'search' ? 'Search' : 'search'
```

## How it works

```
:Search foo ──► backend (HTTP JSON API) ──► results buffer ──► <CR> ──► page as text
```

1. **Query.** `:Search` hands the query to a small helper script, run async
   through `job_start()` in Vim or `jobstart()` in Neovim, so the editor never
   freezes.
2. **Backend.** The helper calls a search backend that returns JSON. No
   scraping and no browser by default (see [Backends](#backends)).
3. **Results buffer.** Results go into the current window as a scratch buffer
   (`buftype=nofile`, `bufhidden=wipe`, `filetype=vimquire`). `q` or `<C-o>`
   takes you back to the file you came from.
4. **Reading a page.** `<CR>` on a result fetches the page, strips it down to
   readable text with a readability extractor, and shows it in the same window.
   Links are numbered like footnotes, and `<CR>` on a link number follows it.

## Backends

You choose one in config. They're listed from most to least recommended.

| Backend | Cost | Account? | Terms-of-service safe? | Notes |
|---|---|---|---|---|
| **SearXNG (self-hosted)** | Free | No | Yes, it's your own instance | Meta-search across many engines, has a JSON API. Runs in Docker. **The default.** |
| **Brave Search API** | Free tier, then paid | API key | Yes | Real index, clean JSON, needs a key. |
| **Kagi API** | Paid | API key | Yes | Excellent results, costs money. |
| **Marginalia Search API** | Free | No (shared `public` key) | Yes | Independent index focused on the small, non-commercial web. Not Google-like results, and the shared key is rate-limited. |
| **YaCy (self-hosted)** | Free | No | Yes | Peer-to-peer search engine with its own crawler and index. Runs on your machine. Weaker results, but nobody else's index involved. |
| **Site APIs** (Wikipedia, Stack Exchange, GitHub, MDN…) | Free | No | Yes | Searches specific sites through their official APIs. See [Searching without a search engine](#searching-without-a-search-engine). |
| **DuckDuckGo Instant Answer API** | Free | No | Yes | Only gives instant answers and abstracts, not full web results. |
| **Headless Chrome scraping** | Free | No | **No** | Opt-in only. See [Risks](#risks). |

### Searching without a search engine

You can't search "the web" without an **index**, a giant database built by
crawling billions of pages. Google, Bing, Brave, Mojeek, Marginalia and YaCy
each build their own. Most other engines (DuckDuckGo, Startpage, Ecosia) rent
results from Bing or Google.

If you don't want any of the big engines involved, there are two ways to go:

1. **An independent index.** Marginalia, Mojeek, or a self-hosted YaCy.
2. **The `sites` backend.** Instead of one search engine, fire the query at a
   handful of official site APIs at once and merge the results:

   ```vim
   let g:vimquire_backend = 'sites'
   let g:vimquire_sites   = ['devdocs', 'stackoverflow', 'wikipedia', 'github']
   let g:vimquire_devdocs = ['python~3.12', 'javascript', 'rust']   " docs to download
   ```

   - **Stack Overflow** goes through the official Stack Exchange API
     (`api.stackexchange.com/2.3/search/advanced?site=stackoverflow`).
     Opening a result shows the question and its answers, sorted by votes.
     There's no account, but there is a daily limit: 300 requests per IP
     without a key, or 10,000 with a free app key from stackapps.com.
   - **DevDocs** has no search API, so vimquire works the way the DevDocs
     website does: it downloads each doc set's small search index once
     (`documents.devdocs.io/<slug>/index.json`) and searches it **locally**,
     so the query never leaves your machine. Pages are fetched one at a time
     when you open them. Set `g:vimquire_offline = 1` to also download every
     page up front (`db.json`) so it works with no internet. It only re-downloads when a doc's version changes,
     as listed in `devdocs.io/docs.json`.
   - **Official docs sites directly**, for anything DevDocs doesn't cover or
     doesn't keep up to date:
     - **Python** (and any site built with Sphinx) publishes its search index
       at `/searchindex.js`, e.g. `docs.python.org/3/searchindex.js`.
       Download it once and search locally. For library APIs,
       `python -m pydoc <name>` works fully offline with no network at all.
     - **Svelte** publishes plain-text versions of its whole docs for tools to
       read: `svelte.dev/llms.txt`, which links the full and abridged text
       files. Split them by heading and search locally.
     - Many other projects also publish an `llms.txt`, which is worth
       checking before writing a custom source.

   For programming questions this often beats a general engine. Every source is
   an official API, so there's nothing to break the rules of and no account to
   lose. The tradeoff is that you only find what's on those sites.

### Managing sources

`:SearchSources` opens a searchable list of every available source: all 843
DevDocs doc sets, plus Stack Overflow, Wikipedia, GitHub and the rest. Search
it with `/` like any buffer.

```
 vimquire sources                                    enabled: 4 · 7.3 MB on disk
 ──────────────────────────────────────────────────────────────────────────────
 [x] Rust                    devdocs   rust          4.3 MB index  (70 MB offline)
 [x] Python 3.13             devdocs   python~3.13   1.4 MB index  (19 MB offline)
 [x] Svelte                  devdocs   svelte        6 KB index    (1 MB offline)
 [x] Stack Overflow          api       -             live, nothing stored
 [ ] JavaScript              devdocs   javascript    -             (12 MB offline)
 [ ] React                   devdocs   react         -             (9 MB offline)
 ──────────────────────────────────────────────────────────────────────────────
 <Space> enable/disable   O toggle offline copy   u update   / filter   q close
```

The same thing works from the command line, with tab completion:

```vim
:SearchAdd rust python~3.13
:SearchRemove rust          " also deletes its downloaded files
```

Turning a source off deletes its downloaded files.

**Mixed results.** `:Search` asks every enabled source at once and merges the
results into one ranked list, like a normal search engine. Each result is
tagged with where it came from:

```
  1. Vec::push                                                     [rust]
     doc.rust-lang.org/std/vec/struct.Vec.html#method.push
  2. How do I append to a Vec in Rust?                    [stackoverflow]
     stackoverflow.com/questions/...   214 votes, answered
```

To search one source only, start the query with `@` and the source name:
`:Search @rust push`, `:Search @python~3.13 pathlib`.

Writing your own crawler is possible, but it's a big project of its own (see
[Risks](#risks) for what it involves).

## Private mode (incognito)

Private mode is **on by default.** It leaves nothing behind and doesn't
identify you:

- **No cookies.** Every request starts fresh. Nothing is saved between
  searches, so the backend can't link one search to the next by cookie.
- **No history.** Queries and visited pages aren't written to disk. Result
  buffers are `nofile` and get wiped when you leave them.
- **Nothing in Vim's own files.** Search commands are left out of Vim's
  command history and `viminfo`/`shada`, so they don't show up in `q:` or
  after a restart.
- **No referrer.** Sites you open don't learn that you came from a search.
- **Generic user agent.** Requests send a common browser user agent, not one
  that identifies vimquire.
- **Throwaway browser profile.** If you turn on the headless Chrome mode, it
  runs with `--incognito` and a fresh temporary `--user-data-dir` that's
  deleted when it exits. It never touches your real Chrome profile or your
  Google login.

What private mode **can't** hide (the same is true of a real incognito
window):

- **Your IP address.** The search backend and every site you open still see
  it. Use a VPN or Tor (`g:vimquire_proxy = 'socks5h://127.0.0.1:9050'`) if
  that matters to you. A self-hosted SearXNG sits in between, so the upstream
  engines only see your instance.
- **Your API key.** With Brave or Kagi, the key links all your searches to
  your account with them.
- **Your network.** Your ISP, school or employer can still see which sites
  you connect to.

```vim
let g:vimquire_private = 1                         " default
let g:vimquire_proxy   = ''                        " e.g. socks5h://127.0.0.1:9050 for Tor
```

### Why not headless Chrome by default?

It works, but it's the fragile and risky option:

- Google's and DuckDuckGo's terms forbid automated querying.
- You'll hit CAPTCHAs and IP rate limits.
- The page markup changes often, which breaks the scraper.
- It means shipping or requiring a ~150 MB browser.

A self-hosted SearXNG instance gives you Google-ish results through a JSON API
in about 20 ms, with nothing to scrape on your side.

## Install (planned)

```vim
" vim-plug
Plug 'AndrewRoddy/vimquire'
```

```lua
-- lazy.nvim
{ "AndrewRoddy/vimquire", cmd = "Search" }
```

Running SearXNG locally:

```sh
docker run -d -p 8888:8080 --name searxng searxng/searxng
# then turn on the json format in settings.yml:  search.formats: [html, json]
```

## Configuration (planned)

```vim
let g:vimquire_backend   = 'searxng'               " searxng | brave | kagi | ddg | chrome
let g:vimquire_url       = 'http://localhost:8888' " SearXNG instance
let g:vimquire_api_key   = $BRAVE_API_KEY          " read from the env, never hard-code it
let g:vimquire_results   = 10
let g:vimquire_safesearch = 1
```

## Commands and mappings

| Command | What it does |
|---|---|
| `:Search {query}` | Search and show results in the current window |
| `:SearchOpen {url}` | Fetch a URL and show it as text |
| `:SearchBrowser` | Open the result under the cursor in your system browser |

Mappings in the results buffer: `<CR>` open, `o` system browser, `y` yank URL,
`n`/`p` next/previous page, `q` go back.

## Risks

Here's what you're actually exposed to with this project, and how it compares
to the Discord ban.

### Why this is lower risk than the Discord client

Discord banned your account because a third-party client acts **as you**, with
your token, against a service whose terms explicitly ban "self-bots" and
modified clients. **Plain web search has no account to ban.** The worst a search
engine normally does to an unauthenticated scraper is block the IP or throw a
CAPTCHA.

**One exception:** if the headless Chrome runs with your real Chrome profile,
it's logged in to your Google account, and the automated traffic gets tied to
you. Always use a fresh, throwaway profile (`--user-data-dir` pointing at an
empty temp dir). Never point it at your everyday profile.

### Terms of service and legal

- **Scraping Google, Bing or DuckDuckGo HTML breaks their terms.** In practice
  that means blocks, not lawsuits, for a personal tool. It's a bigger problem if
  you publish a plugin that sends thousands of users' traffic at them.
- **Publishing a scraper vs. using one.** Putting this on GitHub as a
  scraper-by-default makes you the author of a ToS-evading tool. Defaulting to
  official APIs or self-hosted SearXNG keeps the repo clean.
- **API terms.** Brave and Kagi keys come with their own terms (rate limits, no
  reselling, sometimes attribution). Read them before shipping a shared key.
- **Copyright of page content.** Showing a fetched page to *yourself* is the
  same as a browser doing it. Caching or redistributing page text is not.

### Getting blocked

- **IP rate limiting and CAPTCHAs** from scraped engines. On a shared network
  (dorm, office) this can affect other people on the same IP.
- **A public SearXNG instance** will rate-limit or ban you if you hammer it.
  Self-host instead of borrowing someone else's.

### Security

- **Untrusted content in your editor.** Web pages are hostile input. Escape
  everything before it goes in the buffer, and never `:execute`, `:normal` or
  modeline-evaluate anything that came from a page. Set `nomodeline` on result
  buffers. Vim has had real modeline code-execution bugs (CVE-2019-12735).
- **Shell injection.** Never build a shell command by string-concatenating the
  query, since `:Search foo; rm -rf ~` must stay a search for that literal
  text. Pass arguments as a list to `job_start()`/`jobstart()` and URL-encode
  the query.
- **Terminal escape sequences.** Page text can contain ANSI/OSC escapes. Strip
  control characters before display, especially in terminal Vim.
- **Headless Chrome is a full browser** running untrusted JavaScript. Keep it
  sandboxed (don't pass `--no-sandbox`), use a throwaway profile, and keep it
  updated. The `--remote-debugging-port` is unauthenticated, so bind it to
  `127.0.0.1` only, or anything on your network can drive the browser.
- **API keys.** Read them from environment variables. Don't commit them in a
  vimrc that lives in a public dotfiles repo.
- **Following links** fetches arbitrary URLs from your machine. That includes
  `http://localhost:...` and router admin pages (SSRF-style). Consider refusing
  private and loopback addresses for links that came from page content.

### Privacy

- Every query goes to whatever backend you pick. A self-hosted SearXNG hides
  your IP from the upstream engines, but the instance's own IP is still visible
  to them.
- Don't log queries to disk by default. If you add search history, keep it
  local and make it opt-in.

### If you write your own crawler

- **Respect `robots.txt` and rate-limit yourself.** An aggressive crawler can
  get your IP banned, and if it's heavy enough it looks like a denial-of-service
  attack.
- **Storage and bandwidth.** Even a small useful index runs to gigabytes. Your
  ISP may object to sustained crawling from a home connection.
- **Liability for what you index.** A crawler fetches whatever it's pointed at,
  including illegal content. Keep it scoped to sites you choose.

### Practical and maintenance

- Scrapers break whenever the target site changes its markup. APIs don't.
- Many modern pages are JavaScript-only, and a text extractor shows little or
  nothing for them. That's the one real reason to offer headless Chrome as an
  opt-in "render" mode.
- Brave and Kagi can cost money if you go past the free tier.

## License

MIT (planned)
