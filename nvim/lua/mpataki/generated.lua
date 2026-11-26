-- Files .gitattributes marks `linguist-generated` (the attribute GitHub uses to
-- collapse them in diffs). Diff views tag them "(gen)" and render them in muted
-- variants of their usual highlights — duller, still red/green, never the grey
-- of hidden files — so hand-written files stand out for careful review.
local M = {}

-- Fraction of the original fg kept when blending toward the background.
local KEEP = 0.55

-- Set (path -> true) of the given repo-relative paths that are generated. One
-- `git check-attr` for the whole list; a git failure marks nothing generated,
-- which is the safe direction (everything looks hand-written).
function M.set(root, paths)
  local gen = {}
  if #paths == 0 then return gen end
  local res = vim.system(
    { 'git', '-C', root, 'check-attr', '-z', '--stdin', 'linguist-generated' },
    { stdin = table.concat(paths, '\0') .. '\0', text = true }
  ):wait(10000)
  if res.code ~= 0 then return gen end
  -- -z output: path NUL attr NUL value NUL, repeated.
  local f = vim.split(res.stdout, '\0', { plain = true })
  for i = 1, #f - 2, 3 do
    local v = f[i + 2]
    if v == 'set' or v == 'true' then gen[f[i]] = true end
  end
  return gen
end

local function blend(fg, bg)
  local function ch(c, s) return math.floor(bit.band(bit.rshift(c, s), 0xff)) end
  local out = 0
  for _, s in ipairs({ 16, 8, 0 }) do
    out = out + bit.lshift(math.floor(ch(fg, s) * KEEP + ch(bg, s) * (1 - KEEP) + 0.5), s)
  end
  return out
end

local made = {}
vim.api.nvim_create_autocmd('ColorScheme', { callback = function() made = {} end })

-- Name of a muted copy of highlight `group`, created on first use and rebuilt
-- after a colorscheme change.
function M.muted(group)
  local name = 'Generated_' .. group:gsub('[^%w_]', '_')
  if made[name] then return name end
  local hl = vim.api.nvim_get_hl(0, { name = group, link = false })
  local normal = vim.api.nvim_get_hl(0, { name = 'Normal', link = false })
  local bg = normal.bg or (vim.o.background == 'light' and 0xffffff or 0x000000)
  local fg = hl.fg or normal.fg or (vim.o.background == 'light' and 0x000000 or 0xffffff)
  vim.api.nvim_set_hl(0, name, { fg = blend(fg, bg), italic = hl.italic, bold = hl.bold })
  made[name] = true
  return name
end

M.TAG = '(gen)'

return M
