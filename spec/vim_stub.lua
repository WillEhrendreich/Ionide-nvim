-- Minimal but stateful vim API stub for busted unit tests

local vim = {}

local function deepcopy(value)
  if type(value) ~= "table" then
    return value
  end
  local result = {}
  for k, v in pairs(value) do
    result[k] = deepcopy(v)
  end
  return result
end

vim.__test = {}

function vim.__test.reset()
  vim.__test.notifications = {}
  vim.__test.user_commands = {}
  vim.__test.autocmds = {}
  vim.__test.augroups = {}
  vim.__test.keymaps = {}
  vim.__test.buf_requests = {}
  vim.__test.buf_notifies = {}
  vim.__test.inlay_hints = {}
  vim.__test.codelens_refreshes = {}
  vim.__test.codelens_displays = {}
  vim.__test.lsp_buf_calls = {
    document_highlight = 0,
    clear_references = 0,
    signature_help = 0,
  }
  vim.__test.clients = {}
  vim.__test.client_requests = {}
  vim.__test.buffers_by_client_id = {}
  vim.__test.current_buf = 1
  vim.__test.cursor = { 1, 0 }
  vim.__test.buffer_names = { [1] = "" }
  vim.__test.buffer_lines = { [1] = {} }
  vim.__test.deferred = {}
  vim.__test.env = {}
  vim.__test.floating_previews = {}
  vim.__test.diagnostics = {}
  vim.__test.jobstops = {}
  -- buf_keymaps[mode][lhs] = rhs  — set in tests to simulate pre-existing buffer maps
  vim.__test.buf_keymaps = {}
  vim.__test.fs_renames = {}   -- records {old, new} pairs from uv.fs_rename calls
  vim.__test.fs_rename_should_fail = false
end

function vim.__test.run_autocmd(event, opts)
  opts = opts or {}
  local bufnr = opts.buffer or vim.__test.current_buf
  for _, autocmd in ipairs(vim.__test.autocmds) do
    local matches_event = false
    if type(autocmd.event) == "table" then
      for _, e in ipairs(autocmd.event) do
        if e == event then
          matches_event = true
          break
        end
      end
    else
      matches_event = autocmd.event == event
    end

    local matches_buffer = autocmd.opts.buffer == nil or autocmd.opts.buffer == bufnr
    if matches_event and matches_buffer and type(autocmd.opts.callback) == "function" then
      autocmd.opts.callback({ buf = bufnr, event = event, data = opts.data })
    end
  end
end

vim.__test.reset()

-- Basic table utilities
vim.tbl_deep_extend = function(behavior, ...)
  local result = {}
  for _, t in ipairs({ ... }) do
    if type(t) == "table" then
      for k, v in pairs(t) do
        if type(v) == "table" and type(result[k]) == "table" then
          result[k] = vim.tbl_deep_extend(behavior, result[k], v)
        else
          result[k] = deepcopy(v)
        end
      end
    end
  end
  return result
end

vim.tbl_extend = function(behavior, ...)
  local result = {}
  for _, t in ipairs({ ... }) do
    if type(t) == "table" then
      for k, v in pairs(t) do
        result[k] = v
      end
    end
  end
  return result
end

vim.tbl_contains = function(list, item)
  if type(list) ~= "table" then
    return false
  end
  for _, value in ipairs(list) do
    if value == item then
      return true
    end
  end
  return false
end

vim.tbl_isempty = function(t)
  return next(t) == nil
end

vim.tbl_get = function(t, ...)
  local value = t
  for i = 1, select("#", ...) do
    if type(value) ~= "table" then
      return nil
    end
    value = value[select(i, ...)]
  end
  return value
end

vim.tbl_flatten = function(list)
  local result = {}
  local function flatten(value)
    if type(value) == "table" then
      for _, item in ipairs(value) do
        flatten(item)
      end
    else
      table.insert(result, value)
    end
  end
  flatten(list)
  return result
end

vim.split = function(str, sep)
  local parts = {}
  if sep == "[-.]" then
    for part in str:gmatch("[^%-.]+") do
      table.insert(parts, part)
    end
  else
    for part in str:gmatch("[^" .. sep .. "]+") do
      table.insert(parts, part)
    end
  end
  return parts
end

vim.list_extend = function(dst, src)
  for _, v in ipairs(src) do
    table.insert(dst, v)
  end
  return dst
end

vim.inspect = function(val)
  if type(val) == "string" then
    return '"' .. val .. '"'
  elseif type(val) == "table" then
    local parts = {}
    for k, v in pairs(val) do
      table.insert(parts, tostring(k) .. " = " .. vim.inspect(v))
    end
    table.sort(parts)
    return "{ " .. table.concat(parts, ", ") .. " }"
  else
    return tostring(val)
  end
end

vim.notify = function(msg, level, opts)
  table.insert(vim.__test.notifications, { msg = msg, level = level, opts = opts })
end

vim.log = { levels = { WARN = 2, ERROR = 4, INFO = 1 } }
vim.v = { shell_error = 0 }

vim.fn = {
  has = function() return 1 end,
  system = function() return "8.0.100" end,
  fnamemodify = function(path, _) return path end,
  win_gotoid = function() end,
  executable = function() return 1 end,
  glob = function() return {} end,
  join = function(list, sep) return table.concat(list, sep) end,
  bufadd = function() return 2 end,
  bufexists = function() return 1 end,
  bufwinid = function() return -1 end,
  win_getid = function() return 1 end,
  execute = function() end,
  getpos = function() return { 0, 1, 1, 0 } end,
  visualmode = function() return "v" end,
  line = function() return 1 end,
  expand = function() return "1" end,
  winwidth = function() return 80 end,
  winheight = function() return 20 end,
  jobstart = function() return 1 end,
  jobstop = function(job_id)
    -- Record that jobstop was called; tests can inspect vim.__test.jobstops
    table.insert(vim.__test.jobstops or {}, job_id)
    vim.__test.jobstops = vim.__test.jobstops or {}
    table.insert(vim.__test.jobstops, job_id)
  end,
  chansend = function() end,
  writefile = function() end,
  -- maparg: simulate buffer-local keymap lookup.
  -- Returns a table with buffer=true when the lhs is in vim.__test.buf_keymaps[mode],
  -- otherwise returns an empty string (Neovim's behaviour when no map exists).
  maparg = function(lhs, mode, abbr, dict)
    if not dict then return "" end
    local buf_maps = vim.__test.buf_keymaps and vim.__test.buf_keymaps[mode] or {}
    if buf_maps[lhs] then
      return { lhs = lhs, rhs = buf_maps[lhs], buffer = true }
    end
    return {}
  end,
  json_decode = function(str)
    if str:match('"XmlDocSig"') then
      return {
        {
          XmlDocSig = str:match('"XmlDocSig"%s*:%s*"(.-)"'),
          AssemblyName = str:match('"AssemblyName"%s*:%s*"(.-)"'),
        },
      }
    end
    if str:match('"Kind"%s*:%s*"help"') then
      local data = str:match('"Data"%s*:%s*"(.-)"') or ""
      data = data:gsub('\\n', '\n')
      return {
        Kind = "help",
        Data = data,
      }
    end
    if str:match('"Kind"%s*:%s*"formattedDocumentation"') then
      local signature = str:match('"Signature"%s*:%s*"(.-)"') or ""
      local comment = str:match('"Comment"%s*:%s*"(.-)"') or ""
      comment = comment:gsub('\\n', '\n')
      local footer = {}
      for item in str:gmatch('"FooterLines"%s*:%s*%[(.-)%]') do
        for value in item:gmatch('"(.-)"') do
          table.insert(footer, value)
        end
      end
      return {
        Kind = "formattedDocumentation",
        Data = {
          Signature = signature,
          Comment = comment,
          FooterLines = footer,
        },
      }
    end
    return nil
  end,
}

vim.fs = {
  normalize = function(path) return path end,
  dirname = function(path) return path:match("(.+)/") or path end,
  find = function() return {} end,
  -- relpath: return the relative path from base to target (Neovim 0.10+).
  -- Used by IonideRenameFileInteractive to build the virtual path.
  relpath = function(base, target)
    -- strip trailing separator from base
    base = base:gsub("[/\\]+$", "")
    if target:sub(1, #base + 1) == base .. "/" then
      return target:sub(#base + 2)
    end
    return target
  end,
}

vim.o = { shellslash = false }
vim.bo = setmetatable({}, { __index = function() return {} end })
vim.b = setmetatable({}, { __index = function() return {} end })
vim.g = { selection = "inclusive" }
vim.w = setmetatable({}, { __index = function() return {} end })

vim.api = {
  nvim_get_current_buf = function() return vim.__test.current_buf end,
  nvim_buf_get_name = function(bufnr) return vim.__test.buffer_names[bufnr or vim.__test.current_buf] or "" end,
  nvim_get_current_line = function()
    local lines = vim.__test.buffer_lines[vim.__test.current_buf] or {}
    return lines[1] or ""
  end,
  nvim_buf_get_lines = function(bufnr, start, end_, strict)
    local lines = vim.__test.buffer_lines[bufnr or vim.__test.current_buf] or {}
    if end_ == -1 then
      end_ = #lines
    end
    local result = {}
    for i = start + 1, end_ do
      if lines[i] ~= nil then
        table.insert(result, lines[i])
      end
    end
    return result
  end,
  nvim_buf_is_valid = function() return true end,
  nvim_create_user_command = function(name, callback, opts)
    vim.__test.user_commands[name] = { callback = callback, opts = opts or {} }
  end,
  nvim_create_autocmd = function(event, opts)
    table.insert(vim.__test.autocmds, { event = event, opts = opts or {} })
    return #vim.__test.autocmds
  end,
  nvim_create_augroup = function(name, opts)
    local id = #vim.__test.augroups + 1
    vim.__test.augroups[id] = { name = name, opts = opts or {} }
    return id
  end,
  nvim_win_close = function() end,
  nvim_call_function = function() return 0 end,
  nvim_replace_termcodes = function(s) return s end,
  nvim_feedkeys = function() end,
  nvim_win_set_cursor = function() end,
  nvim_win_get_cursor = function() return vim.__test.cursor end,
}

vim.opt_local = {}
vim.cmd = setmetatable({}, { __index = function() return function() end end })
vim.keymap = {
  set = function(mode, lhs, rhs, opts)
    table.insert(vim.__test.keymaps, { mode = mode, lhs = lhs, rhs = rhs, opts = opts or {} })
  end,
}

local function client_matches_filter(client, filter)
  if not filter then
    return true
  end
  if filter.name and client.name ~= filter.name then
    return false
  end
  if filter.bufnr then
    local bufs = vim.__test.buffers_by_client_id[client.id] or {}
    for _, buf in ipairs(bufs) do
      if buf == filter.bufnr then
        return true
      end
    end
    return false
  end
  return true
end

vim.lsp = {
  get_clients = function(filter)
    local result = {}
    for _, client in ipairs(vim.__test.clients) do
      if client_matches_filter(client, filter) then
        table.insert(result, client)
      end
    end
    return result
  end,
  buf_request = function(bufnr, method, params, handler, on_unsupported)
    table.insert(vim.__test.buf_requests, {
      bufnr = bufnr,
      method = method,
      params = params,
      handler = handler,
      on_unsupported = on_unsupported,
    })
    return {}, function() end
  end,
  buf_request_all = function(bufnr, method, params, callback)
    table.insert(vim.__test.buf_requests, {
      bufnr = bufnr,
      method = method,
      params = params,
      is_all = true,
      callback = callback,
    })
  end,
  buf_notify = function(bufnr, method, params)
    table.insert(vim.__test.buf_notifies, { bufnr = bufnr, method = method, params = params })
  end,
  protocol = {
    MessageType = { Warning = 2 },
    make_client_capabilities = function() return {} end,
  },
  start = function() end,
  get_buffers_by_client_id = function(client_id)
    return vim.__test.buffers_by_client_id[client_id] or {}
  end,
  get_client_by_id = function(client_id)
    for _, client in ipairs(vim.__test.clients) do
      if client.id == client_id then
        return client
      end
    end
  end,
  codelens = {
    refresh = function(opts)
      table.insert(vim.__test.codelens_refreshes, opts or {})
    end,
    display = function(lenses, bufnr, client_id)
      table.insert(vim.__test.codelens_displays, { lenses = lenses, bufnr = bufnr, client_id = client_id })
    end,
  },
  inlay_hint = {
    enable = function(enabled, opts)
      table.insert(vim.__test.inlay_hints, { enabled = enabled, opts = opts or {} })
    end,
  },
  buf = {
    document_highlight = function()
      vim.__test.lsp_buf_calls.document_highlight = vim.__test.lsp_buf_calls.document_highlight + 1
    end,
    clear_references = function()
      vim.__test.lsp_buf_calls.clear_references = vim.__test.lsp_buf_calls.clear_references + 1
    end,
    signature_help = function()
      vim.__test.lsp_buf_calls.signature_help = vim.__test.lsp_buf_calls.signature_help + 1
    end,
  },
}

local client_mt = {
  __index = {
    request = function(self, method, params, handler, bufnr)
      local request_id = #(vim.__test.client_requests[self.id] or {}) + 1
      vim.__test.client_requests[self.id] = vim.__test.client_requests[self.id] or {}
      table.insert(vim.__test.client_requests[self.id], {
        method = method,
        params = params,
        handler = handler,
        bufnr = bufnr,
        request_id = request_id,
      })
      return request_id
    end,
    cancel_request = function(self, request_id)
      return true
    end,
  },
}

function vim.__test.with_client_methods(client)
  return setmetatable(client, client_mt)
end

vim.lsp.util = {
  open_floating_preview = function(contents, syntax, opts)
    table.insert(vim.__test.floating_previews, { contents = contents, syntax = syntax, opts = opts or {} })
    return 1, 1
  end,
}

vim.diagnostic = {
  severity = { ERROR = 1, WARN = 2, INFO = 3, HINT = 4 },
  get = function(bufnr, opts)
    local diagnostics = vim.__test.diagnostics[bufnr or vim.__test.current_buf] or {}
    if not opts or opts.lnum == nil then
      return diagnostics
    end
    local result = {}
    for _, diagnostic in ipairs(diagnostics) do
      if diagnostic.lnum == opts.lnum then
        table.insert(result, diagnostic)
      end
    end
    return result
  end,
}

vim.validate = function() end
vim.uv = {
  os_setenv = function(name, value)
    vim.__test.env[name] = value
  end,
  -- Return a Linux-style uname so that ionide/util.lua uses "/" as path_sep.
  -- This makes iterate_parents terminate correctly on Unix-style test paths.
  os_uname = function() return { version = "Linux" } end,
  fs_realpath = function(path) return path end,
  fs_stat = function() return { type = "directory" } end,
  -- fs_rename: record the rename and return success/nil depending on test config.
  -- Default is success (true). Tests can set vim.__test.fs_rename_should_fail = true
  -- to simulate a disk error.
  fs_rename = function(old, new)
    table.insert(vim.__test.fs_renames, { old = old, new = new })
    if vim.__test.fs_rename_should_fail then
      return nil, "simulated rename error"
    end
    return true
  end,
}
vim.loop = vim.uv

vim.filetype = { add = function() end }
vim.opt = setmetatable({}, {
  __index = function()
    return { get = function() return "" end }
  end,
})

vim.defer_fn = function(fn, ms)
  table.insert(vim.__test.deferred, { fn = fn, ms = ms })
  if type(fn) == "function" then
    fn()
  end
end

vim.uri_decode = function(str)
  return (str:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

-- vim.uri_from_fname: convert a file path to a file:// URI.
-- Mirrors the real Neovim implementation used by TextDocumentIdentifier.
vim.uri_from_fname = function(path)
  -- Normalise backslashes → forward slashes
  local p = path:gsub("\\", "/")
  -- Windows drive letter: C:/foo → file:///C:/foo
  -- Unix absolute: /foo → file:///foo
  if p:match("^%a:/") then
    return "file:///" .. p
  elseif p:match("^/") then
    return "file://" .. p
  else
    return "file:///" .. p
  end
end

vim.schedule = function(fn)
  if type(fn) == "function" then
    fn()
  end
end

vim.uri_to_bufnr = function(uri)
  for bufnr, name in pairs(vim.__test.buffer_names) do
    if uri == name or uri == ("file:///" .. name) or uri == ("file://" .. name) then
      return bufnr
    end
  end
  return vim.__test.current_buf
end

_G.vim = vim

return vim
