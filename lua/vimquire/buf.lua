-- Scratch buffers that open in the current window and remember where you
-- came from, so q always takes you back.
local M = {}

M.ns = vim.api.nvim_create_namespace("vimquire")

-- Every buffer we made, by kind ("results", "page", "sources").
M.kinds = {}

local counter = 0

function M.create(kind)
  counter = counter + 1
  local back = vim.api.nvim_get_current_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modeline = false
  vim.bo[buf].undolevels = -1
  -- Named by a counter, never by the query, so nothing leaks into ShaDa.
  pcall(vim.api.nvim_buf_set_name, buf, "vimquire://" .. kind .. "/" .. counter)
  vim.b[buf].vimquire_back = back
  M.kinds[buf] = kind
  vim.api.nvim_win_set_buf(0, buf)
  local wo = vim.wo[0][0]
  wo.number = false
  wo.relativenumber = false
  wo.signcolumn = "no"
  wo.foldcolumn = "0"
  wo.spell = false
  wo.list = false
  wo.wrap = true
  wo.linebreak = true
  wo.foldenable = false
  wo.conceallevel = 0
  vim.bo[buf].filetype = kind == "results" and "vimquire" or ("vimquire_" .. kind)
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      M.kinds[buf] = nil
    end,
  })
  return buf
end

function M.is_ours(buf, kind)
  local k = M.kinds[buf]
  return k ~= nil and (kind == nil or k == kind)
end

function M.width(buf)
  local win = vim.fn.bufwinid(buf)
  local w = win ~= -1 and vim.api.nvim_win_get_width(win) or 80
  return math.max(30, math.min(require("vimquire.config").options.width, w - 2))
end

--- Replace the buffer's text. hl entries are {lnum, group} for whole lines or
--- {lnum, group, scol, ecol} for a byte range (0-based columns).
function M.set_lines(buf, lines, hl)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  for _, h in ipairs(hl or {}) do
    local lnum, group, scol, ecol = h[1], h[2], h[3], h[4]
    local text = lines[lnum]
    if text then
      pcall(vim.api.nvim_buf_set_extmark, buf, M.ns, lnum - 1, scol or 0, {
        end_col = ecol or #text,
        hl_group = group,
      })
    end
  end
end

function M.map(buf, lhs, fn, desc)
  vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true, desc = desc })
end

--- Wipe our buffers that no window shows. Nothing from a session is kept.
function M.cleanup()
  for buf in pairs(M.kinds) do
    if vim.api.nvim_buf_is_valid(buf) and vim.fn.bufwinid(buf) == -1 then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
end

--- Go back to where this buffer was opened from and wipe it.
function M.close(buf)
  local back = vim.b[buf].vimquire_back
  if back and vim.api.nvim_buf_is_valid(back) then
    vim.api.nvim_win_set_buf(0, back)
  else
    vim.cmd("enew")
  end
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
  if not M.is_ours(vim.api.nvim_get_current_buf()) then
    M.cleanup()
  end
end

return M
