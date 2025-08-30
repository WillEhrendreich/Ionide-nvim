local ionide = require("ionide.init")
local vim = vim
local assert = require("luassert")
local mock = require("luassert.mock")
local stub = require("luassert.stub")

describe("LSP Basic Functionality Tests", function()
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

  describe("Request Parameter Creation", function()
    it("creates TextDocumentPositionParams correctly", function()
      local params = ionide.TextDocumentPositionParams("/test/file.fs", 10, 5)
      
      assert.is_table(params)
      assert.is_table(params.TextDocument)
      assert.equals("file:///test/file.fs", params.TextDocument.uri)
      assert.is_table(params.Position)
      assert.equals(10, params.Position.Line)
      assert.equals(5, params.Position.Character)
    end)
    
    it("creates FSharpProjectParams correctly", function()
      local params = ionide.CreateFSharpProjectParams("/test/project.fsproj")
      
      assert.is_table(params)
      assert.is_table(params.Project)
      assert.equals("file:///test/project.fsproj", params.Project.uri)
    end)
    
    it("creates WorkspacePeekRequest correctly", function()
      local params = ionide.CreateFSharpWorkspacePeekRequest("/test/dir", 3, { "bin", "obj" })
      
      assert.is_table(params)
      assert.equals("/test/dir", params.Directory)
      assert.equals(3, params.Deep)
      assert.is_table(params.ExcludedDirs)
      assert.equals(2, #params.ExcludedDirs)
    end)
    
    it("creates DocumentationForSymbolRequest correctly", function()
      local params = ionide.DocumentationForSymbolRequest("test.xml.sig", "test.assembly")
      
      assert.is_table(params)
      assert.equals("test.xml.sig", params.XmlSig)
      assert.equals("test.assembly", params.Assembly)
    end)
  end)

  describe("F# Language Server Methods", function()
    before_each(function()
      vim.lsp.buf_request = function(bufnr, method, params, handler)
        return {}, function() end
      end
    end)
    
    it("supports F# signature requests", function()
      local method_called = nil
      
      vim.lsp.buf_request = function(bufnr, method, params, handler)
        method_called = method
        return {}, function() end
      end
      
      ionide.CallFSharpSignature("/test/file.fs", 10, 5)
      assert.equals("fsharp/signature", method_called)
    end)
    
    it("supports F# signature data requests", function()
      local method_called = nil
      
      vim.lsp.buf_request = function(bufnr, method, params, handler)
        method_called = method
        return {}, function() end
      end
      
      ionide.CallFSharpSignatureData("/test/file.fs", 10, 5)
      assert.equals("fsharp/signatureData", method_called)
    end)
    
    it("supports F# documentation requests", function()
      local method_called = nil
      
      vim.lsp.buf_request = function(bufnr, method, params, handler)
        method_called = method
        return {}, function() end
      end
      
      ionide.CallFSharpDocumentation("/test/file.fs", 10, 5)
      assert.equals("fsharp/documentation", method_called)
    end)
    
    it("supports F# documentation symbol requests", function()
      local method_called = nil
      
      vim.lsp.buf_request = function(bufnr, method, params, handler)
        method_called = method
        return {}, function() end
      end
      
      ionide.CallFSharpDocumentationSymbol("test.xml", "test.dll")
      assert.equals("fsharp/documentationSymbol", method_called)
    end)
    
    it("supports F# line lens requests", function()
      local method_called = nil
      
      vim.lsp.buf_request = function(bufnr, method, params, handler)
        method_called = method
        return {}, function() end
      end
      
      ionide.CallFSharpLineLens("/test/project.fsproj")
      assert.equals("fsharp/lineLens", method_called)
    end)
    
    it("supports F# workspace load requests", function()
      local method_called = nil
      local params_passed = nil
      
      vim.lsp.buf_request = function(bufnr, method, params, handler)
        method_called = method
        params_passed = params
        return {}, function() end
      end
      
      ionide.CallFSharpWorkspaceLoad({ "/test/proj1.fsproj", "/test/proj2.fsproj" })
      
      assert.equals("fsharp/workspaceLoad", method_called)
      assert.is_table(params_passed)
      assert.is_table(params_passed.TextDocuments)
      assert.equals(2, #params_passed.TextDocuments)
    end)
    
    it("supports FSDN requests", function()
      local method_called = nil
      
      vim.lsp.buf_request = function(bufnr, method, params, handler)
        method_called = method
        return {}, function() end
      end
      
      ionide.Fsdn("test signature")
      assert.equals("fsharp/fsdn", method_called)
    end)
    
    it("supports F1 help requests", function()
      local method_called = nil
      
      vim.lsp.buf_request = function(bufnr, method, params, handler)
        method_called = method
        return {}, function() end
      end
      
      ionide.F1Help("/test/file.fs", 10, 5)
      assert.equals("fsharp/f1Help", method_called)
    end)
  end)

  describe("Handler Functionality", function()
    it("has proper handlers setup", function()
      local handlers = ionide.CreateHandlers()
      
      assert.is_table(handlers)
      assert.is_function(handlers["fsharp/compilerLocation"])
      assert.is_function(handlers["fsharp/workspacePeek"])
      assert.is_function(handlers["fsharp/workspaceLoad"])
      assert.is_function(handlers["fsharp/project"])
      assert.is_function(handlers["fsharp/documentationSymbol"])
      assert.is_function(handlers["textDocument/hover"])
    end)
    
    it("handlers can be called without errors", function()
      local handlers = ionide.CreateHandlers()
      
      -- Test that handlers can be called without throwing errors
      assert.has_no.errors(function()
        handlers["fsharp/compilerLocation"](nil, {}, {}, {})
      end)
      
      assert.has_no.errors(function()
        handlers["fsharp/workspacePeek"](nil, {}, {}, {})
      end)
      
      assert.has_no.errors(function()
        handlers["fsharp/project"](nil, {}, {}, {})
      end)
    end)
  end)

  describe("Default Configuration", function()
    it("has valid default LSP config", function()
      local config = ionide.DefaultLspConfig
      
      assert.is_table(config)
      assert.is_table(config.IonideNvimSettings)
      assert.is_table(config.filetypes)
      assert.equals("ionide", config.name)
      assert.is_table(config.cmd)
      assert.is_true(config.autostart)
      assert.is_table(config.handlers)
      assert.is_table(config.init_options)
      assert.is_table(config.settings)
    end)
    
    it("has valid default nvim settings", function()
      local settings = ionide.DefaultNvimSettings
      
      assert.is_table(settings)
      assert.is_table(settings.FsautocompleteCommand)
      assert.is_boolean(settings.UseRecommendedServerConfig)
      assert.is_boolean(settings.AutomaticWorkspaceInit)
      assert.is_boolean(settings.AutomaticReloadWorkspace)
      assert.is_boolean(settings.AutomaticCodeLensRefresh)
      assert.is_boolean(settings.ShowSignatureOnCursorMove)
      assert.is_string(settings.FsiCommand)
      assert.is_string(settings.FsiKeymap)
    end)
    
    it("has valid default server settings", function()
      local settings = ionide.DefaultServerSettings
      
      assert.is_table(settings)
      assert.is_boolean(settings.addFsiWatcher)
      assert.is_boolean(settings.addPrivateAccessModifier)
      assert.is_string(settings.autoRevealInExplorer)
    end)
  end)

  describe("Project Discovery", function()
    it("can get project files info", function()
      -- Mock file system functions
      local original_fs_root = vim.fs.root
      local original_fs_find = vim.fs.find
      
      vim.fs.root = function(source, names)
        return "/test/project"
      end
      
      vim.fs.find = function(names, opts)
        return { "/test/project/test.fsproj", "/test/project/lib/lib.fsproj" }
      end
      
      local project_info = ionide.get_project_files(0)
      
      assert.is_table(project_info)
      assert.equals("/test/project", project_info.directory)
      assert.is_table(project_info.files)
      assert.equals(2, #project_info.files)
      
      -- Restore
      vim.fs.root = original_fs_root
      vim.fs.find = original_fs_find
    end)
  end)
end)