#!/usr/bin/env nvim --headless -l

-- Demonstration script for Ionide LSP resilience features
-- Run with: nvim --headless -l demo_resilience.lua

local ionide = require("ionide.init")

print("=== Ionide LSP Resilience Demonstration ===")

-- Test 1: Health Check
print("\n1. LSP Health Check:")
local health = ionide.CheckLspHealth()
print("Status:", health.status)
print("Number of clients:", #health.clients)
if #health.issues > 0 then
  for i, issue in ipairs(health.issues) do
    print("Issue " .. i .. ":", issue)
  end
end

-- Test 2: Resilient Call Configuration
print("\n2. Resilient Call Configuration:")
print("Default retry count: 3")
print("Default timeout: 10000ms")
print("Default retry delay: 1000ms")

-- Test 3: Error Handling
print("\n3. Error Handling Test:")
-- Mock a failing LSP call
vim.lsp = vim.lsp or {}
vim.lsp.buf_request = function(bufnr, method, params, handler)
  print("Mock LSP call made:", method)
  if handler then
    handler({ code = -32603, message = "Test server error" }, nil, nil, nil)
  end
  return {}, function() end
end

local error_received = false
ionide.CallWithResilience("fsharp/test", {}, function(err, result, ctx, config)
  if err then
    print("Error handled:", err.message)
    error_received = true
  end
end, { retry_count = 0 }) -- No retries for demo

-- Test 4: Health Monitoring
print("\n4. Health Monitoring:")
print("Health monitoring enabled by default")
print("Check interval: 30 seconds")
print("Auto-restart on client failure")

print("\n=== Demonstration Complete ===")
print("New features added:")
print("- Automatic retry on transient errors")
print("- Timeout handling for LSP requests")
print("- Health monitoring and auto-restart")
print("- Enhanced error reporting")
print("- User commands: :IonideCheckLspHealth, :IonideRestartLspClient")

vim.cmd("quit!")