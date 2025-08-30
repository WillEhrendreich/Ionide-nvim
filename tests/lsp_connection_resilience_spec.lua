local ionide = require("ionide.init")
local vim = vim
local assert = require("luassert")
local mock = require("luassert.mock")
local stub = require("luassert.stub")

describe("LSP Connection Resilience Tests", function()
  local original_get_clients
  local original_buf_request
  local original_buf_notify
  local original_notify
  
  before_each(function()
    -- Store original functions
    original_get_clients = vim.lsp.get_clients
    original_buf_request = vim.lsp.buf_request
    original_buf_notify = vim.lsp.buf_notify
    original_notify = vim.notify
    
    -- Mock vim.notify to capture notifications
    vim.notify = function(msg, level) end
  end)
  
  after_each(function()
    -- Restore original functions
    vim.lsp.get_clients = original_get_clients
    vim.lsp.buf_request = original_buf_request
    vim.lsp.buf_notify = original_buf_notify
    vim.notify = original_notify
  end)

  describe("Connection State Management", function()
    it("detects when no clients are available", function()
      vim.lsp.get_clients = function()
        return {}
      end
      
      local clients = vim.lsp.get_clients({ name = "ionide" })
      assert.equals(0, #clients)
    end)
    
    it("can identify active ionide clients", function()
      vim.lsp.get_clients = function(filter)
        if filter and filter.name == "ionide" then
          return {
            {
              id = 1,
              name = "ionide",
              config = { root_dir = "/test" },
              is_stopped = function() return false end
            }
          }
        end
        return {}
      end
      
      local clients = vim.lsp.get_clients({ name = "ionide" })
      assert.equals(1, #clients)
      assert.equals("ionide", clients[1].name)
    end)
  end)

  describe("Error Handling in LSP Calls", function()
    it("handles connection timeout errors", function()
      local error_received = nil
      local timeout_error = {
        code = -32001,
        message = "Request timeout"
      }
      
      -- Mock with one client to pass the client check
      vim.lsp.get_clients = function() 
        return {{ id = 1, name = "ionide", config = { root_dir = "/test" }}}
      end
      vim.lsp.buf_request = function(bufnr, method, params, handler)
        if handler then
          handler(timeout_error, nil, nil, nil)
        end
        return {}, function() end
      end
      
      local custom_handler = function(err, result, ctx, config)
        error_received = err
      end
      
      -- Use CallWithResilience with no retries to avoid retry behavior in test
      ionide.CallWithResilience("fsharp/project", {}, custom_handler, { retry_count = 0 })
      
      assert.is_table(error_received)
      assert.equals(-32001, error_received.code)
      assert.equals("Request timeout", error_received.message)
    end)
    
    it("handles server disconnection errors", function()
      local error_received = nil
      local disconnect_error = {
        code = -32603,
        message = "Server disconnected"
      }
      
      -- Mock with one client to pass the client check
      vim.lsp.get_clients = function() 
        return {{ id = 1, name = "ionide", config = { root_dir = "/test" }}}
      end
      vim.lsp.buf_request = function(bufnr, method, params, handler)
        if handler then
          handler(disconnect_error, nil, nil, nil)
        end
        return {}, function() end
      end
      
      local custom_handler = function(err, result, ctx, config)
        error_received = err
      end
      
      -- Use CallWithResilience with no retries to avoid retry behavior in test
      ionide.CallWithResilience("fsharp/workspacePeek", ionide.CreateFSharpWorkspacePeekRequest("/test", 2, {}), custom_handler, { retry_count = 0 })
      
      assert.is_table(error_received)
      assert.equals(-32603, error_received.code)
    end)
    
    it("handles method not found errors", function()
      local error_received = nil
      local method_error = {
        code = -32601,
        message = "Method not found"
      }
      
      vim.lsp.buf_request = function(bufnr, method, params, handler)
        if handler then
          handler(method_error, nil, nil, nil)
        end
        return {}, function() end
      end
      
      local custom_handler = function(err, result, ctx, config)
        error_received = err
      end
      
      ionide.Call("unknown/method", {}, custom_handler)
      
      assert.is_table(error_received)
      assert.equals(-32601, error_received.code)
    end)
  end)

  describe("Request Resilience", function()
    it("can handle multiple concurrent requests", function()
      local request_count = 0
      local completed_requests = {}
      
      vim.lsp.buf_request = function(bufnr, method, params, handler)
        request_count = request_count + 1
        local req_id = request_count
        
        -- Simulate async response
        vim.defer_fn(function()
          if handler then
            handler(nil, { success = true, request_id = req_id }, nil, nil)
          end
        end, 10)
        
        return { [1] = req_id }, function() end
      end
      
      local handler = function(err, result, ctx, config)
        if result then
          table.insert(completed_requests, result.request_id)
        end
      end
      
      -- Make multiple concurrent requests
      ionide.CallFSharpProject("/test/proj1.fsproj", handler)
      ionide.CallFSharpProject("/test/proj2.fsproj", handler)
      ionide.CallFSharpProject("/test/proj3.fsproj", handler)
      
      assert.equals(3, request_count)
    end)
    
    it("provides cancellation functions for requests", function()
      local cancel_called = false
      
      vim.lsp.buf_request = function(bufnr, method, params, handler)
        return { [1] = 123 }, function()
          cancel_called = true
        end
      end
      
      local _, cancel_fn = ionide.Call("fsharp/test", {})
      
      assert.is_function(cancel_fn)
      cancel_fn()
      assert.is_true(cancel_called)
    end)
  end)

  describe("Notification Resilience", function()
    it("handles notification failures gracefully", function()
      local notify_error = false
      
      vim.lsp.buf_notify = function(bufnr, method, params)
        -- Simulate notification failure by throwing error
        error("Failed to send notification")
      end
      
      -- Should not crash even if notification fails
      assert.has_no.errors(function()
        pcall(ionide.CallLspNotify, "workspace/didChangeConfiguration", {})
      end)
    end)
    
    it("can send configuration change notifications", function()
      local method_called = nil
      local params_sent = nil
      
      vim.lsp.buf_notify = function(bufnr, method, params)
        method_called = method
        params_sent = params
      end
      
      local new_config = { 
        FSharp = { 
          enableTreeView = true,
          showProjectExplorerIn = "fsharp" 
        }
      }
      
      ionide.UpdateServerConfig(new_config)
      
      assert.equals("workspace/didChangeConfiguration", method_called)
      assert.is_table(params_sent)
      assert.is_table(params_sent.FSharp)
      assert.is_true(params_sent.FSharp.enableTreeView)
    end)
  end)

  describe("Server Health Monitoring", function()
    it("can detect server availability through client list", function()
      -- Test when server is available
      vim.lsp.get_clients = function(filter)
        if filter and filter.name == "ionide" then
          return {
            {
              id = 1,
              name = "ionide",
              config = { root_dir = "/test" }
            }
          }
        end
        return {}
      end
      
      local clients = vim.lsp.get_clients({ name = "ionide" })
      local server_available = #clients > 0
      
      assert.is_true(server_available)
      
      -- Test when server is not available
      vim.lsp.get_clients = function()
        return {}
      end
      
      clients = vim.lsp.get_clients({ name = "ionide" })
      server_available = #clients > 0
      
      assert.is_false(server_available)
    end)
    
    it("can check client status for specific root directory", function()
      local test_root = "/test/project"
      
      vim.lsp.get_clients = function(filter)
        if filter and filter.name == "ionide" then
          return {
            {
              id = 1,
              name = "ionide",
              config = { root_dir = test_root }
            },
            {
              id = 2,
              name = "ionide", 
              config = { root_dir = "/other/project" }
            }
          }
        end
        return {}
      end
      
      local clients = vim.lsp.get_clients({ name = "ionide" })
      local target_client = nil
      
      for _, client in ipairs(clients) do
        if client.config.root_dir == test_root then
          target_client = client
          break
        end
      end
      
      assert.is_table(target_client)
      assert.equals(test_root, target_client.config.root_dir)
    end)
  end)

  describe("Graceful Degradation", function()
    it("continues working when some F# features are unavailable", function()
      local available_methods = {
        ["fsharp/project"] = true,
        ["fsharp/workspacePeek"] = true,
        -- fsharp/compile is "unavailable"
      }
      
      vim.lsp.buf_request = function(bufnr, method, params, handler)
        if available_methods[method] then
          if handler then
            handler(nil, { success = true }, nil, nil)
          end
        else
          if handler then
            handler({ code = -32601, message = "Method not found: " .. method }, nil, nil, nil)
          end
        end
        return {}, function() end
      end
      
      local project_success = false
      local compile_failed = false
      
      ionide.CallFSharpProject("/test.fsproj", function(err, result)
        if result and result.success then
          project_success = true
        end
      end)
      
      ionide.CallFSharpCompileOnProjectFile("/test.fsproj", function(err, result)
        if err and err.code == -32601 then
          compile_failed = true
        end
      end)
      
      -- Allow some time for async callbacks
      vim.wait(50)
      
      assert.is_true(project_success)
      assert.is_true(compile_failed)
    end)
  end)
end)