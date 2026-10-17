-- A small HTML-to-text renderer. Pages are untrusted, so nothing here
-- executes anything: tags only decide where line breaks, bullets and link
-- numbers go.
local util = require("vimquire.util")

local M = {}

local ENTITIES = {
  amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = " ", ensp = " ", emsp = " ", thinsp = " ",
  shy = "", zwj = "", zwnj = "", lrm = "", rlm = "",
  copy = "©", reg = "®", trade = "™", hellip = "…", mdash = "—", ndash = "–", minus = "−",
  lsquo = "‘", rsquo = "’", sbquo = "‚", ldquo = "“", rdquo = "”", bdquo = "„", laquo = "«", raquo = "»",
  times = "×", divide = "÷", middot = "·", bull = "•", deg = "°", plusmn = "±", micro = "µ",
  le = "≤", ge = "≥", ne = "≠", asymp = "≈", infin = "∞", sum = "∑", prod = "∏", radic = "√",
  larr = "←", rarr = "→", uarr = "↑", darr = "↓", harr = "↔", lArr = "⇐", rArr = "⇒", hArr = "⇔",
  para = "¶", sect = "§", dagger = "†", Dagger = "‡", prime = "′", Prime = "″",
  euro = "€", pound = "£", yen = "¥", cent = "¢", iexcl = "¡", iquest = "¿",
}

function M.decode_entities(s)
  return (s:gsub("&(#?)([xX]?)(%w+);", function(hash, x, name)
    if hash == "#" then
      local cp = tonumber(name, x ~= "" and 16 or 10)
      return (cp and cp > 0) and util.utf8_char(cp) or ""
    end
    name = x .. name
    return ENTITIES[name] or ("&" .. name .. ";")
  end))
end

-- Tags whose contents are never shown.
local SKIP = {
  script = true, style = true, noscript = true, template = true, svg = true, iframe = true,
  object = true, canvas = true, select = true, button = true, nav = true, head = true,
}
-- Tags whose contents must not be parsed as HTML.
local RAW = { script = true, style = true, textarea = true, title = true }
local VOID = {
  br = true, hr = true, img = true, input = true, meta = true, link = true, wbr = true, col = true,
  area = true, base = true, source = true, embed = true, param = true, track = true,
}
-- Block tags that end a paragraph and leave a blank line after it.
local PARAGRAPH = {
  p = true, h1 = true, h2 = true, h3 = true, h4 = true, h5 = true, h6 = true, pre = true,
  blockquote = true, table = true, dl = true, figure = true, details = true, section = true, article = true,
}
-- Block tags that only end the current line.
local BLOCK = {
  div = true, main = true, header = true, footer = true, aside = true, li = true, dt = true, dd = true,
  tr = true, figcaption = true, summary = true, form = true, fieldset = true, address = true, center = true,
  ul = true, ol = true, thead = true, tbody = true, tfoot = true, caption = true,
}

local function attr(attrs, name)
  -- Attribute names are case-insensitive: HREF works like href.
  name = name:gsub("%a", function(c)
    return "[" .. c:lower() .. c:upper() .. "]"
  end)
  local v = attrs:match("%s" .. name .. '%s*=%s*"([^"]*)"')
    or attrs:match("%s" .. name .. "%s*=%s*'([^']*)'")
    or attrs:match("%s" .. name .. "%s*=%s*([^%s\"'>]+)")
  return v and M.decode_entities(v)
end

--- The page's own previous/next/contents links, from rel="prev" / rel="next"
--- (mdBook, Sphinx and most doc generators), rel="contents" or "toc", and
--- mdBook's toc.html sidebar. Returns { prev, next, contents }, each
--- { href, title } with title possibly nil.
function M.page_nav(html)
  local nav = {}
  for tag, attrs in html:gmatch("<(%a+)(%s[^>]*)>") do
    tag = tag:lower()
    if tag == "a" or tag == "link" then
      local href = attr(attrs, "href")
      local title = attr(attrs, "title")
      -- mdBook's arrows are titled "Next chapter", which says nothing.
      if title and (title:lower():match("^next") or title:lower():match("^prev")) then
        title = nil
      end
      for word in (attr(attrs, "rel") or ""):lower():gmatch("%S+") do
        local key = (word == "previous" and "prev") or (word == "toc" and "contents") or word
        if href and (key == "prev" or key == "next" or key == "contents") and not nav[key] then
          nav[key] = { href = href, title = title }
        end
      end
    elseif tag == "iframe" and not nav.contents then
      local src = attr(attrs, "src")
      if src and src:match("toc%.html$") then
        nav.contents = { href = src, title = "Contents" }
      end
    end
  end
  return nav
end

-- Case-insensitive pattern for a closing tag, e.g. "</[sS][cC]...".
local function close_pattern(name)
  return "</" .. name:gsub("%a", function(c)
    return "[" .. c:lower() .. c:upper() .. "]"
  end)
end

local function wrap(text, width, first, rest)
  local out = {}
  local line, line_w, has_word = first, vim.api.nvim_strwidth(first), false
  local rest_w = vim.api.nvim_strwidth(rest)
  for word in text:gmatch("%S+") do
    local w = vim.api.nvim_strwidth(word)
    if has_word and line_w + 1 + w > width then
      table.insert(out, line)
      line, line_w = rest .. word, rest_w + w
    elseif has_word then
      line, line_w = line .. " " .. word, line_w + 1 + w
    else
      line, line_w = line .. word, line_w + w
    end
    has_word = true
  end
  if has_word then
    table.insert(out, line)
  end
  return out
end

--- Render HTML to lines.
--- Returns { lines, hl = {{lnum, group}}, links = {url...}, spots = {{lnum, scol, ecol, n}},
---           anchors = {id = lnum}, title }
--- Link numbers are written as "[n]"; spots records exactly where each one is,
--- so "[0]" inside code is never mistaken for a link.
function M.render(html, opts)
  opts = opts or {}
  local width = opts.width or 80
  html = util.clean(html)

  local lines, hl, anchors, links, link_index = {}, {}, {}, {}, {}
  local para, bullet = {}, nil
  local indents = {}
  local lists = {}
  local heading = nil
  local pre_depth, pre_buf = 0, {}
  local link_stack = {}
  local skip_tag, skip_depth = nil, 0
  local row_cells = 0
  local title

  local function prefix()
    return table.concat(indents)
  end

  local function blank()
    if #lines > 0 and lines[#lines] ~= "" then
      table.insert(lines, "")
    end
  end

  local function flush()
    local text = table.concat(para):gsub("[ \t\n]*\n[ \t\n]*", "\n"):gsub("[ \t]+", " ")
    para = {}
    text = vim.trim(text)
    if text == "" then
      return
    end
    if heading then
      blank()
      table.insert(lines, string.rep("#", heading) .. " " .. text:gsub("\n", " "))
      table.insert(hl, { #lines, "vimquireHeading" })
      return
    end
    local p = prefix()
    -- Items that number themselves ("1.2. Hello, World!") don't need ours too.
    if bullet and bullet:match("^%d") and text:match("^%d+%.[%d.]*%s") then
      bullet = ""
    end
    local first = p .. (bullet or "")
    local rest = p .. string.rep(" ", bullet and vim.api.nvim_strwidth(bullet) or 0)
    bullet = nil
    for _, segment in ipairs(vim.split(text, "\n", { plain = true })) do
      for _, l in ipairs(wrap(segment, width, first, rest)) do
        table.insert(lines, l)
      end
      first = rest
    end
  end

  local function add_text(text)
    if skip_depth > 0 then
      return
    end
    text = M.decode_entities(text)
    if pre_depth > 0 then
      table.insert(pre_buf, text)
    else
      table.insert(para, (text:gsub("%s+", " ")))
    end
  end

  local function open_link(href)
    table.insert(link_stack, { href = href, start = #para })
  end

  local function close_link()
    local l = table.remove(link_stack)
    if not l or not l.href or l.href == "" or l.href:match("^javascript:") then
      return
    end
    local target = pre_depth > 0 and pre_buf or para
    local text = table.concat(target, "", l.start + 1)
    if pre_depth == 0 and not text:find("%w") then
      return -- icon or "§" anchors
    end
    local n = link_index[l.href]
    if not n then
      table.insert(links, l.href)
      n = #links
      link_index[l.href] = n
    end
    table.insert(target, "\1" .. n .. "\2")
  end

  local function open_tag(name, attrs)
    local id = attr(attrs, "id") or (name == "a" and attr(attrs, "name"))
    if id and not anchors[id] then
      anchors[id] = #lines + 1
    end
    if pre_depth > 0 then
      if name == "br" then
        table.insert(pre_buf, "\n")
      elseif name == "a" then
        open_link(attr(attrs, "href"))
      end
      return
    end
    if name == "a" then
      open_link(attr(attrs, "href"))
    elseif name == "br" then
      table.insert(para, "\n")
    elseif name == "img" then
      local alt = attr(attrs, "alt")
      if alt and alt:find("%w") then
        table.insert(para, " [image: " .. alt .. "] ")
      end
    elseif name == "hr" then
      flush()
      blank()
      table.insert(lines, prefix() .. string.rep("-", math.min(width, 40)))
      table.insert(hl, { #lines, "vimquireDim" })
      blank()
    elseif name == "pre" then
      flush()
      blank()
      pre_depth, pre_buf = 1, {}
    elseif name:match("^h[1-6]$") then
      flush()
      heading = tonumber(name:sub(2))
    elseif name == "ul" or name == "ol" then
      flush()
      table.insert(indents, #lists > 0 and "  " or "")
      -- Tables of contents (mdBook's "chapter"/"section" lists) number
      -- their own entries, or leave them unnumbered on purpose.
      local class = (attr(attrs, "class") or ""):lower()
      local toc = class:find("chapter", 1, true) or class:find("section", 1, true) or class:find("toc", 1, true)
      table.insert(lists, { ordered = name == "ol", n = 0, plain = toc ~= nil })
    elseif name == "li" then
      flush()
      local list = lists[#lists]
      if list and list.plain then
        bullet = ""
      elseif list and list.ordered then
        list.n = list.n + 1
        bullet = list.n .. ". "
      else
        bullet = "- "
      end
    elseif name == "dd" then
      flush()
      table.insert(indents, "    ")
    elseif name == "blockquote" then
      flush()
      blank()
      table.insert(indents, "> ")
    elseif name == "tr" then
      flush()
      row_cells = 0
    elseif name == "td" or name == "th" then
      if row_cells > 0 then
        table.insert(para, " | ")
      end
      row_cells = row_cells + 1
    elseif PARAGRAPH[name] then
      flush()
      blank()
    elseif BLOCK[name] then
      flush()
    end
  end

  local function close_tag(name)
    if pre_depth > 0 then
      if name == "a" then
        close_link()
      elseif name == "pre" then
        pre_depth = 0
        local text = table.concat(pre_buf):gsub("^\n", ""):gsub("%s+$", ""):gsub("\t", "    ")
        local p = prefix()
        for _, l in ipairs(vim.split(text, "\n", { plain = true })) do
          table.insert(lines, p .. "    " .. l)
          table.insert(hl, { #lines, "vimquireCode" })
        end
        blank()
      end
      return
    end
    if name == "a" then
      close_link()
    elseif name:match("^h[1-6]$") then
      flush()
      heading = nil
      blank()
    elseif name == "ul" or name == "ol" then
      flush()
      table.remove(lists)
      table.remove(indents)
      if #lists == 0 then
        blank()
      end
    elseif name == "dd" or name == "blockquote" then
      flush()
      table.remove(indents)
      if name == "blockquote" then
        blank()
      end
    elseif PARAGRAPH[name] then
      flush()
      blank()
    elseif BLOCK[name] then
      flush()
    end
  end

  local pos, n = 1, #html
  while pos <= n do
    local lt = html:find("<", pos, true)
    if not lt then
      add_text(html:sub(pos))
      break
    end
    if lt > pos then
      add_text(html:sub(pos, lt - 1))
    end
    local nxt = html:sub(lt + 1, lt + 1)
    if html:sub(lt, lt + 3) == "<!--" then
      local e = html:find("-->", lt + 4, true)
      pos = e and e + 3 or n + 1
    elseif nxt == "!" or nxt == "?" then
      local e = html:find(">", lt, true)
      pos = e and e + 1 or n + 1
    else
      local closing, name = html:match("^<(/?)([%a][%w:%-]*)", lt)
      if not name then
        add_text("<")
        pos = lt + 1
      else
        -- Find the ">" that ends the tag, skipping quoted attribute values.
        local i = lt + 1 + #closing + #name
        local gt
        while true do
          local j = html:find("[>\"']", i)
          if not j then
            break
          end
          local c = html:sub(j, j)
          if c == ">" then
            gt = j
            break
          end
          local q = html:find(c, j + 1, true)
          if not q then
            break
          end
          i = q + 1
        end
        gt = gt or n
        local attrs = " " .. html:sub(lt + 1 + #closing + #name, gt - 1)
        pos = gt + 1
        name = name:lower()

        if closing == "" and RAW[name] then
          local s, e = html:find(close_pattern(name) .. "[^>]*>", pos)
          if name == "title" then
            title = title or vim.trim(M.decode_entities(html:sub(pos, (s or n + 1) - 1)):gsub("%s+", " "))
          end
          pos = e and e + 1 or n + 1
        elseif skip_depth > 0 then
          if name == skip_tag and not VOID[name] then
            skip_depth = skip_depth + (closing == "" and 1 or -1)
          end
        elseif closing == "" and SKIP[name] then
          if not attrs:match("/%s*$") then
            skip_tag, skip_depth = name, 1
          end
        elseif closing == "" then
          open_tag(name, attrs)
        else
          close_tag(name)
        end
      end
    end
  end
  flush()
  while #lines > 0 and lines[#lines] == "" do
    table.remove(lines)
  end

  -- Swap the "\1n\2" markers for "[n]" and remember where each one landed.
  local spots = {}
  for lnum, l in ipairs(lines) do
    if l:find("\1", 1, true) then
      local out, col, p = {}, 0, 1
      while true do
        local s, e, num = l:find("\1(%d+)\2", p)
        if not s then
          table.insert(out, l:sub(p))
          break
        end
        table.insert(out, l:sub(p, s - 1))
        col = col + (s - p)
        local mark = "[" .. num .. "]"
        table.insert(spots, { lnum, col, col + #mark, tonumber(num) })
        table.insert(out, mark)
        col = col + #mark
        p = e + 1
      end
      lines[lnum] = table.concat(out)
    end
  end

  return { lines = lines, hl = hl, links = links, spots = spots, anchors = anchors, title = title }
end

--- Render plain text where "== Heading ==" lines are headings (Wikipedia extracts).
function M.render_text(text, opts)
  local parts = {}
  for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
    local eq, heading = line:match("^(=+)%s*(.-)%s*=+%s*$")
    local escaped = (heading or line):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
    if heading then
      local level = math.min(#eq, 6)
      table.insert(parts, string.format("<h%d>%s</h%d>", level, escaped, level))
    elseif vim.trim(line) ~= "" then
      table.insert(parts, "<p>" .. escaped .. "</p>")
    end
  end
  return M.render(table.concat(parts, "\n"), opts)
end

return M
