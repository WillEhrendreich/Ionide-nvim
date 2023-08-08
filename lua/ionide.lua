local util = require("ionide.util")
local vim = vim
local validate = vim.validate
local api = vim.api
local uc = vim.api.nvim_create_user_command
local lsp = vim.lsp
-- local log = require('vim.lsp.log')
-- local protocol = require('vim.lsp.protocol')
local tbl_extend = vim.tbl_extend
local autocmd = vim.api.nvim_create_autocmd
local grp = vim.api.nvim_create_augroup

local M = {}
---@type lspconfig.options.fsautocomplete
M.DefaultConfig = {}
---@type lspconfig.options.fsautocomplete
M.MergedConfig = {}
---@type lspconfig.options.fsautocomplete
M.PassedInConfig = {}
---this is the setup for ionide.nvim.
---@param config
M.setup = function(config)
  M.PassedInConfig = config
  M.MergedConfig = vim.tbl_deep_extend("force", M.DefaultConfig, M.PassedInConfig or {})
end

function M.show_config()
  vim.notify("Config is:\n" .. vim.inspect(M.MergedConfig))
end

return M
