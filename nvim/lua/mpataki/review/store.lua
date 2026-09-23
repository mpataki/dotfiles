-- Pending review comments as a markdown file. The file is the source of truth
-- for the local draft; the capture float and push/pull read and write it.
-- Format:
--   <!-- review: owner/repo#N head=<sha> pushed=<fingerprint> -->
--   ## path:line          (or ## path:start-end)
--   body until next "## "
local M = {}

function M.path(common_dir, number)
  return common_dir .. '/reviews/' .. tostring(number) .. '.md'
end

function M.remote_path(common_dir, number)
  return common_dir .. '/reviews/' .. tostring(number) .. '.remote.json'
end

function M.key(entry)
  if entry.start_line then
    return ('%s:%d-%d'):format(entry.path, entry.start_line, entry.line)
  end
  return ('%s:%d'):format(entry.path, entry.line)
end

local function parse_header(line)
  local repo, head, pushed = line:match('^<!%-%- review: (%S+) head=(%S*) pushed=(%S*) %-%->')
  if not repo then return {} end
  return { repo = repo, head = head ~= '' and head or nil, pushed = pushed ~= '' and pushed or nil }
end

local function parse_heading(line)
  local path, a, b = line:match('^## (.-):(%d+)%-(%d+)$')
  if path then return { path = path, start_line = tonumber(a), line = tonumber(b) } end
  path, a = line:match('^## (.-):(%d+)$')
  if path then return { path = path, line = tonumber(a) } end
  return nil
end

function M.parse(text)
  local doc = { header = {}, entries = {} }
  local current, body = nil, {}

  local function flush()
    if current then
      current.body = vim.trim(table.concat(body, '\n'))
      table.insert(doc.entries, current)
    end
    current, body = nil, {}
  end

  for line in (text .. '\n'):gmatch('(.-)\n') do
    local heading = parse_heading(line)
    if heading then
      flush()
      current = heading
    elseif not current and line:match('^<!%-%- review:') then
      doc.header = parse_header(line)
    elseif current then
      table.insert(body, line)
    end
  end
  flush()
  return doc
end

function M.serialize(doc)
  local h = doc.header or {}
  local out = {
    ('<!-- review: %s head=%s pushed=%s -->'):format(h.repo or '', h.head or '', h.pushed or ''),
    '',
  }
  for _, e in ipairs(doc.entries) do
    table.insert(out, '## ' .. M.key(e))
    table.insert(out, '')
    table.insert(out, e.body)
    table.insert(out, '')
  end
  return table.concat(out, '\n') .. '\n'
end

function M.read(file)
  if vim.fn.filereadable(file) ~= 1 then
    return { header = {}, entries = {} }
  end
  return M.parse(table.concat(vim.fn.readfile(file), '\n'))
end

function M.write(file, doc)
  vim.fn.mkdir(vim.fn.fnamemodify(file, ':h'), 'p')
  vim.fn.writefile(vim.split(M.serialize(doc), '\n'), file)
end

function M.find(doc, path, line, start_line)
  local want = M.key({ path = path, line = line, start_line = start_line })
  for i, e in ipairs(doc.entries) do
    if M.key(e) == want then return e, i end
  end
  return nil, nil
end

function M.remove(doc, path, line, start_line)
  local _, i = M.find(doc, path, line, start_line)
  if i then table.remove(doc.entries, i) end
end

function M.upsert(doc, entry)
  local body = vim.trim(entry.body or '')
  local _, i = M.find(doc, entry.path, entry.line, entry.start_line)
  if body == '' then
    if i then table.remove(doc.entries, i) end
    return
  end
  local e = { path = entry.path, line = entry.line, start_line = entry.start_line, body = body }
  if i then doc.entries[i] = e else table.insert(doc.entries, e) end
end

function M.fingerprint(entries)
  local parts = {}
  for _, e in ipairs(entries) do
    table.insert(parts, M.key(e) .. ':' .. vim.trim(e.body or ''))
  end
  table.sort(parts)
  return vim.fn.sha256(table.concat(parts, '\n'))
end

return M
