local plenary_dir = os.getenv("PLENARY_DIR") or "/tmp/plenary.nvim"
local is_not_a_directory = vim.fn.isdirectory(plenary_dir) == 0
if is_not_a_directory then
  vim.fn.system({"git", "clone", "https://github.com/nvim-lua/plenary.nvim", plenary_dir})
end

vim.opt.rtp:append(".")
vim.opt.rtp:append(plenary_dir)

-- Mock vim.uv for older neovim versions or test environment
if not vim.uv then
  vim.uv = vim.loop or {
    os_uname = function()
      return { version = "Linux" }
    end
  }
end

-- Mock defer_fn for testing
if not vim.defer_fn then
  vim.defer_fn = function(fn, ms)
    fn()
  end
end

-- Mock wait for testing
if not vim.wait then
  vim.wait = function(ms, fn)
    if fn then
      return fn()
    end
    return true
  end
end

vim.cmd("runtime plugin/plenary.vim")
require("plenary.busted")
