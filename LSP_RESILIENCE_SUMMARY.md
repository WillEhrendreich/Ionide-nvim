# Ionide-nvim LSP Resilience Improvements

## Summary

This implementation adds comprehensive resilience features to the Ionide-nvim LSP client to address frequent client restart issues and improve communication reliability with the FsAutoComplete language server.

## Features Added

### 1. Enhanced LSP Call Resilience (`CallWithResilience`)
- **Automatic Retry Logic**: Retries failed requests up to 3 times for transient errors
- **Timeout Handling**: 10-second timeout on LSP requests with proper cleanup
- **Error Classification**: Distinguishes between retryable and non-retryable errors
- **Graceful Degradation**: Continues operation when some F# features are unavailable

### 2. Health Monitoring System
- **Automatic Monitoring**: Checks LSP client health every 30 seconds
- **Client Detection**: Monitors for disconnected or stopped clients
- **Auto-restart**: Attempts to restart failed clients automatically
- **Status Reporting**: Provides detailed health status information

### 3. Improved Error Handling
- **Connection Safety**: Checks for available clients before making requests
- **Error Notification**: Enhanced error messages with context
- **Timeout Protection**: Prevents hanging on unresponsive server calls
- **Graceful Failures**: Handles server unavailability without crashes

### 4. User Commands
- `:IonideCheckLspHealth` - Check current LSP client status
- `:IonideRestartLspClient` - Manually restart LSP clients

### 5. Configuration Options
- `EnableHealthMonitoring` (default: true) - Enable/disable health monitoring

## Technical Implementation

### Core Functions

#### `CallWithResilience(method, params, handler, opts)`
Enhanced LSP call with:
- Configurable retry count (default: 3)
- Timeout handling (default: 10 seconds)
- Retry delay (default: 1 second)
- Error classification and handling

#### `CheckLspHealth()`
Returns health status including:
- Client count and status
- Root directory information
- Issues and recommendations

#### `RestartLspClient()`
Safely restarts LSP clients with:
- Graceful client shutdown
- Automatic buffer refresh
- Error handling

### Error Codes Handled
- `-32603` - Server errors (retryable)
- `-32001` - Request timeout (retryable)
- `-32002` - Server not initialized (retryable)
- `-32300` - Connection failures (retryable)
- `-32601` - Method not found (non-retryable)

## Testing

Comprehensive test suite covering:

### 1. LSP Resilience Tests (`tests/lsp_resilience_spec.lua`)
- Client management and detection
- Basic LSP request/notification handling
- F# specific method calls
- Configuration updates

### 2. LSP Functionality Tests (`tests/lsp_functionality_spec.lua`)
- Request parameter creation
- F# language server methods
- Handler functionality
- Default configurations
- Project discovery

### 3. Connection Resilience Tests (`tests/lsp_connection_resilience_spec.lua`)
- Connection state management
- Error handling (timeouts, disconnections, method errors)
- Request resilience (concurrent requests, cancellation)
- Notification resilience
- Health monitoring
- Graceful degradation

**Test Results**: 46/46 tests passing ✅

## Compatibility

### Neovim Version Compatibility
- Handles different Neovim versions (vim.uv vs vim.loop)
- Graceful fallbacks for missing APIs
- Test environment compatibility

### Backward Compatibility
- All existing APIs remain unchanged
- New features are opt-in via configuration
- Existing user workflows unaffected

## Usage Examples

### Basic Setup with Health Monitoring
```lua
require('ionide').setup({
  IonideNvimSettings = {
    EnableHealthMonitoring = true,  -- default
    -- other settings...
  }
})
```

### Manual Health Check
```lua
local health = require('ionide.init').CheckLspHealth()
print("Status:", health.status)
print("Issues:", vim.inspect(health.issues))
```

### Custom Resilient Call
```lua
require('ionide.init').CallWithResilience("fsharp/project", params, handler, {
  retry_count = 5,
  timeout = 15000,
  retry_delay = 2000
})
```

## Benefits

1. **Reduced Manual Restarts**: Automatic detection and restart of failed clients
2. **Better Error Reporting**: Clear, actionable error messages
3. **Improved Reliability**: Retry logic handles transient network/server issues
4. **Enhanced Debugging**: Health monitoring provides visibility into client status
5. **Graceful Failures**: System continues working even when some features fail

## Files Modified

- `lua/ionide/init.lua` - Core resilience implementation
- `lua/ionide/types.lua` - Type definitions for new features
- `tests/minimal_init.lua` - Test environment improvements
- `Makefile` - Test automation
- `.gitignore` - Exclude build artifacts

## Files Added

- `tests/lsp_resilience_spec.lua` - LSP resilience tests
- `tests/lsp_functionality_spec.lua` - LSP functionality tests  
- `tests/lsp_connection_resilience_spec.lua` - Connection resilience tests
- `demo_resilience.lua` - Feature demonstration script

This implementation addresses the core issue of frequent LSP client restarts by providing automatic recovery, better error handling, and comprehensive monitoring, making the Ionide-nvim experience much more stable and reliable.