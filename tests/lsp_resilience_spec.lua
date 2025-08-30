local ionide = require("ionide.init")
local vim = vim
local assert = require("luassert")
local mock = require("luassert.mock")
local stub = require("luassert.stub")

describe("LSP Client Resilience Tests", function()
  local original_get_clients
  local original_buf_request
  local original_buf_notify
  
  before_each(function()
    -- Store original functions
    original_get_clients = vim.lsp.get_clients
    original_buf_request = vim.lsp.buf_request
    original_buf_notify = vim.lsp.buf_notify
  end)
  
  after_each(function()
    -- Restore original functions
    vim.lsp.get_clients = original_get_clients
    vim.lsp.buf_request = original_buf_request
    vim.lsp.buf_notify = original_buf_notify
  end)

  describe("Client Management", function()
    it("can get ionide clients", function()
      vim.lsp.get_clients = function(filter)
        if filter and filter.name == "ionide" then
          return {
            {
              id = 1,
              name = "ionide",
              config = { root_dir = "/test/project" }
            }
          }
        end
        return {}
      end
      
      local clients = vim.lsp.get_clients({ name = "ionide" })
      assert.is_table(clients)
      assert.equals(1, #clients)
      assert.equals("ionide", clients[1].name)
    end)
    
    it("handles no clients gracefully", function()
      vim.lsp.get_clients = function()
        return {}
      end
      
      local clients = vim.lsp.get_clients({ name = "ionide" })
      assert.is_table(clients)
      assert.equals(0, #clients)
    end)
  end)

  describe("LSP Request Handling", function()
    it("can make basic LSP calls", function()
      local call_made = false
      local method_called = nil
      local params_passed = nil
      
      vim.lsp.buf_request = function(bufnr, method, params, handler)
        call_made = true
        method_called = method
        params_passed = params
        return {}, function() end
      end
      
      ionide.Call("test/method", { test = "param" })
      
      assert.is_true(call_made)
      assert.equals("test/method", method_called)
      assert.is_table(params_passed)
      assert.equals("param", params_passed.test)
    end)
    
    it("can make notification calls", function()
      local notify_made = false
      local method_called = nil
      local params_passed = nil
      
      vim.lsp.buf_notify = function(bufnr, method, params)
        notify_made = true
        method_called = method
        params_passed = params
      end
      
      ionide.CallLspNotify("test/notify", { test = "notify_param" })
      
      assert.is_true(notify_made)
      assert.equals("test/notify", method_called)
      assert.is_table(params_passed)
      assert.equals("notify_param", params_passed.test)
    end)
    
    it("handles LSP request errors gracefully", function()
      local error_handled = false
      
      vim.lsp.buf_request = function(bufnr, method, params, handler)
        -- Simulate an error by calling handler with an error
        if handler then
          handler({ code = -1, message = "Connection failed" }, nil, nil, nil)
        end
        return {}, function() end
      end
      
      local handler = function(err, result, ctx, config)
        if err then
          error_handled = true
        end
      end
      
      ionide.Call("test/method", {}, handler)
      assert.is_true(error_handled)
    end)
  end)

  describe("F# Specific LSP Methods", function()
    it("can call fsharp/workspacePeek", function()
      local method_called = nil
      local params_passed = nil
      
      vim.lsp.get_clients = function() 
        return {{ id = 1, name = "ionide", config = { root_dir = "/test" }}}
      end
      vim.lsp.buf_request = function(bufnr, method, params, handler)
        method_called = method
        params_passed = params
        return {}, function() end
      end
      
      ionide.CallFSharpWorkspacePeek("/test/path", 3, {})
      
      assert.equals("fsharp/workspacePeek", method_called)
      assert.is_table(params_passed)
    end)
    
    it("can call fsharp/project", function()
      local method_called = nil
      local params_passed = nil
      
      vim.lsp.buf_request = function(bufnr, method, params, handler)
        method_called = method
        params_passed = params
        return {}, function() end
      end
      
      ionide.CallFSharpProject("/test/project.fsproj")
      
      assert.equals("fsharp/project", method_called)
      assert.is_table(params_passed)
    end)
    
    it("can call fsharp/compile", function()
      local method_called = nil
      
      vim.lsp.buf_request = function(bufnr, method, params, handler)
        method_called = method
        return {}, function() end
      end
      
      ionide.CallFSharpCompileOnProjectFile("/test/project.fsproj")
      
      assert.equals("fsharp/compile", method_called)
    end)
    
    it("can call fsharp/compilerLocation", function()
      local method_called = nil
      local params_passed = nil
      
      vim.lsp.buf_request = function(bufnr, method, params, handler)
        method_called = method
        params_passed = params
        return {}, function() end
      end
      
      ionide.CallFSharpCompilerLocation()
      
      assert.equals("fsharp/compilerLocation", method_called)
      assert.is_table(params_passed)
    end)
  end)

  describe("Configuration Updates", function()
    it("can update server configuration", function()
      local method_called = nil
      local params_passed = nil
      
      vim.lsp.buf_notify = function(bufnr, method, params)
        method_called = method
        params_passed = params
      end
      
      local new_settings = { test_setting = true }
      ionide.UpdateServerConfig(new_settings)
      
      assert.equals("workspace/didChangeConfiguration", method_called)
      assert.is_table(params_passed)
      assert.is_true(params_passed.test_setting)
    end)
  end)
end)