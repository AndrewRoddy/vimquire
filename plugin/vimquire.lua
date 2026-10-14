if vim.g.loaded_vimquire then
  return
end
vim.g.loaded_vimquire = 1

if vim.fn.has("nvim-0.10") == 0 then
  vim.notify("vimquire needs Neovim 0.10 or newer", vim.log.levels.ERROR)
  return
end

local function highlights()
  local links = {
    vimquireHeading = "Title",
    vimquireTitle = "Function",
    vimquireTag = "Special",
    vimquireUrl = "Comment",
    vimquireDim = "Comment",
    vimquireLink = "Underlined",
    vimquireCode = "String",
    vimquireError = "ErrorMsg",
    vimquireGroup = "Title",
    vimquireOn = "DiagnosticOk",
    vimquireOff = "Comment",
    vimquireBusy = "DiagnosticWarn",
    vimquireNumber = "LineNr",
    vimquireCurrent = "CursorLineNr",
  }
  for group, target in pairs(links) do
    vim.api.nvim_set_hl(0, group, { link = target, default = true })
  end
end
highlights()
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("vimquire_highlights", { clear = true }),
  callback = highlights,
})

-- Private mode: drop searches from command history (and so from ShaDa).
local function forget()
  if require("vimquire.config").options.private then
    vim.schedule(function()
      vim.fn.histdel(":", [[\v^\s*(Search|search|SearchOpen)>]])
    end)
  end
end

local command = vim.api.nvim_create_user_command

command("Search", function(o)
  forget()
  require("vimquire").search(o.args)
end, { nargs = "*", desc = "Search the web and docs from Neovim" })

command("SearchOpen", function(o)
  forget()
  require("vimquire").open(o.args)
end, { nargs = 1, desc = "Read a web page as text" })

command("SearchSources", function()
  require("vimquire").sources()
end, { nargs = 0, desc = "Turn search sources on and off" })

command("SearchAdd", function(o)
  require("vimquire").add(o.fargs)
end, {
  nargs = "+",
  desc = "Turn sources on (downloads DevDocs indexes)",
  complete = function(lead)
    return require("vimquire").complete_add(lead)
  end,
})

command("SearchRemove", function(o)
  require("vimquire").remove(o.fargs)
end, {
  nargs = "+",
  desc = "Turn sources off (deletes their downloads)",
  complete = function(lead)
    return require("vimquire").complete_remove(lead)
  end,
})

-- User commands must start with a capital letter, so expand a typed
-- ":search" into ":Search". setup({ lowercase_alias = false }) removes it.
vim.cmd([[cnoreabbrev <expr> search getcmdtype() ==# ':' && getcmdline() ==# 'search' ? 'Search' : 'search']])
