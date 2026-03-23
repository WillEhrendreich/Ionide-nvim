-- Tests for Ionide-Nvim behavior
-- Run with: busted spec/ionide_spec.lua

local vim = require("spec.vim_stub")

package.path = "./lua/?.lua;" .. "./lua/?/init.lua;" .. "./spec/?.lua;" .. package.path

describe("ionide.init", function()
  local ionide

  local function reset_module()
    vim.__test.reset()
    package.loaded["ionide.init"] = nil
    ionide = require("ionide.init")
  end

  local function make_client(overrides)
    local client = vim.tbl_deep_extend("force", {
      id = 1,
      name = "ionide",
      config = { root_dir = "/workspace" },
      server_capabilities = {},
      supports_method = function(self, method)
        return self.__supported_methods and self.__supported_methods[method] == true or false
      end,
      stop = function() end,
    }, overrides or {})
    return vim.__test.with_client_methods(client)
  end

  local function find_autocmd(event, bufnr)
    for _, autocmd in ipairs(vim.__test.autocmds) do
      local matches_event = autocmd.event == event
      if type(autocmd.event) == "table" then
        matches_event = vim.tbl_contains(autocmd.event, event)
      end
      local matches_buf = not bufnr or autocmd.opts.buffer == bufnr
      if matches_event and matches_buf then
        return autocmd
      end
    end
    return nil
  end

  before_each(function()
    reset_module()
    local client = make_client({ id = 1, name = "ionide" })
    vim.__test.clients = { client }
    vim.__test.buffers_by_client_id[1] = { 1 }
  end)

  describe("request object builders", function()
    it("Given DotnetFile2Request, when called, then it returns named keys not an array", function()
      local result = ionide.DotnetFile2Request("/path/to/project.fsproj", "Src/Existing.fs", "Src/New.fs")
      assert.is_table(result)
      assert.equals("/path/to/project.fsproj", result.FsProj)
      assert.equals("Src/Existing.fs", result.FileVirtualPath)
      assert.equals("Src/New.fs", result.NewFile)
      assert.is_nil(result[1])
    end)

    it("Given DotnetFileRequest, when called, then it returns FsProj and FileVirtualPath", function()
      local result = ionide.DotnetFileRequest("/path/to/project.fsproj", "Src/File.fs")
      assert.equals("/path/to/project.fsproj", result.FsProj)
      assert.equals("Src/File.fs", result.FileVirtualPath)
    end)

    it("Given DotnetRenameFileRequest, when called, then it returns FsProj, OldFileVirtualPath, and NewFileName", function()
      local result = ionide.DotnetRenameFileRequest("/path/to/project.fsproj", "Src/Old.fs", "New.fs")
      assert.equals("/path/to/project.fsproj", result.FsProj)
      assert.equals("Src/Old.fs", result.OldFileVirtualPath)
      assert.equals("New.fs", result.NewFileName)
    end)

    it("Given DotnetProjectRequest, when called, then it returns Target and Reference", function()
      local result = ionide.DotnetProjectRequest("Target.sln", "Project.fsproj")
      assert.equals("Target.sln", result.Target)
      assert.equals("Project.fsproj", result.Reference)
    end)

    it("Given DotnetNewRunRequest, when called, then it returns Template, Output, and Name", function()
      local result = ionide.DotnetNewRunRequest("console", "./out", "MyApp")
      assert.equals("console", result.Template)
      assert.equals("./out", result.Output)
      assert.equals("MyApp", result.Name)
    end)

    it("Given TestRunRequest, when called, then it returns AttachDebugger and optional filters", function()
      local result = ionide.TestRunRequest({ "/a.fsproj" }, "MyTests", true)
      assert.same({ "/a.fsproj" }, result.LimitToProjects)
      assert.equals("MyTests", result.TestCaseFilter)
      assert.is_true(result.AttachDebugger)
    end)
  end)

  describe("pure helper values", function()
    it("Given PlainNotification, when called, then it wraps content", function()
      local result = ionide.PlainNotification("hello world")
      assert.equals("hello world", result.Content)
    end)

    it("Given Position, when called, then it creates Line and Character", function()
      local result = ionide.Position(10, 5)
      assert.equals(10, result.Line)
      assert.equals(5, result.Character)
    end)

    it("Given CreateFSharpWorkspacePeekRequest, when called, then it creates the expected shape", function()
      local result = ionide.CreateFSharpWorkspacePeekRequest("/workspace", 4, { "node_modules" })
      assert.equals("/workspace", result.Directory)
      assert.equals(4, result.Deep)
      assert.same({ "node_modules" }, result.ExcludedDirs)
    end)

    it("Given CreateFSharpWorkspaceLoadParams, when called, then it creates TextDocuments", function()
      local result = ionide.CreateFSharpWorkspaceLoadParams({ "/path/a.fsproj", "/path/b.fsproj" })
      assert.equals(2, #result.TextDocuments)
    end)
  end)

  describe("default config truth", function()
    it("Given DefaultServerSettings, when inspected, then core analyzers are enabled", function()
      local s = ionide.DefaultServerSettings
      assert.is_true(s.unusedOpensAnalyzer)
      assert.is_true(s.unusedDeclarationsAnalyzer)
      assert.is_true(s.simplifyNameAnalyzer)
      assert.is_true(s.resolveNamespaces)
      assert.is_true(s.enableAnalyzers)
    end)

    it("Given DefaultServerSettings, when inspected, then code lenses are enabled by default", function()
      assert.is_true(ionide.DefaultServerSettings.codeLenses.signature.enabled)
      assert.is_true(ionide.DefaultServerSettings.codeLenses.references.enabled)
    end)

    it("Given DefaultNvimSettings, when inspected, then automatic attach niceties are off by default", function()
      assert.is_false(ionide.DefaultNvimSettings.AutomaticCodeLensRefresh)
      assert.is_false(ionide.DefaultNvimSettings.ShowSignatureOnCursorMove)
      assert.is_false(ionide.DefaultNvimSettings.UseIonideDocumentationHover)
      assert.is_false(ionide.DefaultNvimSettings.AutomaticReloadWorkspace)
      assert.is_true(ionide.DefaultNvimSettings.AutomaticWorkspaceInit)
    end)
  end)

  describe("FSAC custom request wrappers", function()
    local function assert_last_request(method)
      local requests = vim.__test.client_requests[1]
      local req = requests and requests[#requests] or nil
      assert.is_not_nil(req)
      assert.equals(method, req.method)
      return req
    end

    it("Given CallFSharpPipelineHint, when invoked, then it uses fsharp/pipelineHint", function()
      ionide.CallFSharpPipelineHint("/path/to/file.fs")
      local req = assert_last_request("fsharp/pipelineHint")
      assert.equals("file:///path/to/file.fs", req.params.TextDocument.uri)
    end)

    it("Given CallFSharpDocumentationGenerator, when invoked, then it uses fsharp/documentationGenerator", function()
      ionide.CallFSharpDocumentationGenerator("/path/to/file.fs", 4, 7)
      assert_last_request("fsharp/documentationGenerator")
    end)

    it("Given CallFSharpDotnetNewList, when invoked, then it uses fsharp/dotnetnewlist", function()
      ionide.CallFSharpDotnetNewList("console")
      local req = assert_last_request("fsharp/dotnetnewlist")
      assert.equals("console", req.params.Query)
    end)

    it("Given CallFSharpDotnetNewRun, when invoked, then it uses fsharp/dotnetnewrun", function()
      ionide.CallFSharpDotnetNewRun("console", "./out", "App")
      local req = assert_last_request("fsharp/dotnetnewrun")
      assert.equals("console", req.params.Template)
      assert.equals("./out", req.params.Output)
      assert.equals("App", req.params.Name)
    end)

    it("Given CallFSharpDotnetAddProject, when invoked, then it uses fsharp/dotnetaddproject", function()
      ionide.CallFSharpDotnetAddProject("Demo.sln", "src/App/App.fsproj")
      local req = assert_last_request("fsharp/dotnetaddproject")
      assert.equals("Demo.sln", req.params.Target)
      assert.equals("src/App/App.fsproj", req.params.Reference)
    end)

    it("Given CallFSharpDotnetRemoveProject, when invoked, then it uses fsharp/dotnetremoveproject", function()
      ionide.CallFSharpDotnetRemoveProject("Demo.sln", "src/App/App.fsproj")
      assert_last_request("fsharp/dotnetremoveproject")
    end)

    it("Given CallFSharpDotnetSlnAdd, when invoked, then it uses fsharp/dotnetaddsln", function()
      ionide.CallFSharpDotnetSlnAdd("Demo.sln", "src/App/App.fsproj")
      assert_last_request("fsharp/dotnetaddsln")
    end)

    it("Given CallFSharpLoadAnalyzers, when invoked, then it uses fsharp/loadAnalyzers", function()
      ionide.CallFSharpLoadAnalyzers({ Trigger = "manual" })
      assert_last_request("fsharp/loadAnalyzers")
    end)

    it("Given CallTestDiscoverTests, when invoked, then it uses test/discoverTests", function()
      ionide.CallTestDiscoverTests()
      assert_last_request("test/discoverTests")
    end)

    it("Given CallTestRunTests, when invoked, then it uses test/runTests", function()
      ionide.CallTestRunTests({ "/a.fsproj" }, "MyTests", false)
      local req = assert_last_request("test/runTests")
      assert.same({ "/a.fsproj" }, req.params.LimitToProjects)
      assert.equals("MyTests", req.params.TestCaseFilter)
      assert.is_false(req.params.AttachDebugger)
    end)

    it("Given fsautocomplete and copilot are attached, when ionide sends a custom request, then only fsautocomplete receives it", function()
      local fsac = make_client({ id = 30, name = "fsautocomplete" })
      local copilot = vim.__test.with_client_methods(make_client({ id = 31, name = "copilot" }))
      vim.__test.clients = { fsac, copilot }
      vim.__test.buffers_by_client_id[30] = { 1 }
      vim.__test.buffers_by_client_id[31] = { 1 }

      ionide.CallFSharpWorkspacePeek("/workspace", 4, {})

      assert.equals("fsharp/workspacePeek", vim.__test.client_requests[30][1].method)
      assert.is_nil(vim.__test.client_requests[31])
    end)
  end)

  describe("LSP attach behavior", function()
    it("Given code lens is supported and auto refresh is enabled, when ionide attaches, then codelens refresh occurs and autocmds are registered", function()
      local client = make_client({
        id = 11,
        server_capabilities = { CodeLensProvider = { ResolveProvider = true } },
        __supported_methods = { ["textDocument/codeLens"] = true },
      })
      ionide.MergedConfig = vim.tbl_deep_extend("force", ionide.DefaultLspConfig, {
        IonideNvimSettings = { AutomaticCodeLensRefresh = true },
      })

      ionide.OnLspAttach(client, 8)

      assert.is_true(#vim.__test.codelens_refreshes >= 1)
      assert.is_not_nil(find_autocmd("BufEnter", 8))
      assert.is_not_nil(find_autocmd("InsertLeave", 8))
      assert.is_not_nil(find_autocmd("BufWritePost", 8))
    end)

    it("Given document highlight is supported, when ionide attaches, then highlight autocmds are registered and call vim.lsp.buf helpers", function()
      local client = make_client({
        id = 12,
        server_capabilities = { DocumentHighlightProvider = true },
        __supported_methods = { ["textDocument/documentHighlight"] = true },
      })

      ionide.OnLspAttach(client, 9)

      assert.is_not_nil(find_autocmd("CursorHold", 9))
      assert.is_not_nil(find_autocmd("CursorMoved", 9))

      vim.__test.run_autocmd("CursorHold", { buffer = 9 })
      vim.__test.run_autocmd("CursorMoved", { buffer = 9 })

      assert.equals(1, vim.__test.lsp_buf_calls.document_highlight)
      assert.equals(1, vim.__test.lsp_buf_calls.clear_references)
    end)

    it("Given ShowSignatureOnCursorMove is enabled and signature help is supported, when ionide attaches, then cursor move requests signature help", function()
      local client = make_client({
        id = 13,
        server_capabilities = { SignatureHelpProvider = { TriggerCharacters = { "(" } } },
        __supported_methods = { ["textDocument/signatureHelp"] = true },
      })
      ionide.MergedConfig = vim.tbl_deep_extend("force", ionide.DefaultLspConfig, {
        IonideNvimSettings = { ShowSignatureOnCursorMove = true },
      })

      ionide.OnLspAttach(client, 10)

      assert.is_not_nil(find_autocmd("CursorMovedI", 10))
      vim.__test.run_autocmd("CursorMovedI", { buffer = 10 })
      assert.equals(1, vim.__test.lsp_buf_calls.signature_help)
    end)

    it("Given code lens auto refresh is disabled, when ionide attaches, then no codelens autocmds are created", function()
      local client = make_client({
        id = 14,
        server_capabilities = { CodeLensProvider = { ResolveProvider = true } },
        __supported_methods = { ["textDocument/codeLens"] = true },
      })

      ionide.OnLspAttach(client, 11)

      assert.is_nil(find_autocmd("BufEnter", 11))
      assert.is_nil(find_autocmd("InsertLeave", 11))
      assert.is_nil(find_autocmd("BufWritePost", 11))
    end)

    it("Given UseIonideDocumentationHover is enabled, when ionide attaches, then buffer-local K is mapped to documentation hover", function()
      local client = make_client({ id = 15 })
      ionide.MergedConfig = vim.tbl_deep_extend("force", ionide.DefaultLspConfig, {
        IonideNvimSettings = { UseIonideDocumentationHover = true },
      })

      ionide.OnLspAttach(client, 12)

      -- Find the K mapping by lhs rather than by position — registration order
      -- is not part of the contract and can change when new keymaps are added.
      local k_map = nil
      for _, km in ipairs(vim.__test.keymaps) do
        if km.lhs == "K" and km.opts.buffer == 12 then
          k_map = km
          break
        end
      end
      assert.is_not_nil(k_map, "expected a buffer-local K keymap to be registered")
      assert.equals("n", k_map.mode)
      assert.equals(12, k_map.opts.buffer)
      assert.truthy(k_map.opts.desc:match("formatted F# documentation"))
    end)
  end)

  describe("custom notifications", function()
    it("Given fsharp/documentAnalyzed, when handled, then codelens refreshes when enabled", function()
      ionide.MergedConfig = vim.tbl_deep_extend("force", ionide.DefaultLspConfig, {
        IonideNvimSettings = { AutomaticCodeLensRefresh = true },
      })
      vim.__test.buffer_names[21] = "/workspace/File.fs"

      ionide.Handlers["fsharp/documentAnalyzed"](nil, {
        TextDocument = { uri = "/workspace/File.fs", version = 1 },
      }, {}, {})

      assert.equals(1, #vim.__test.codelens_refreshes)
      assert.equals(21, vim.__test.codelens_refreshes[1].bufnr)
    end)

    it("Given fsharp/notifyWorkspace, when handled, then ionide notifies the user", function()
      ionide.Handlers["fsharp/notifyWorkspace"](nil, { Content = "workspace loaded" }, {}, {})
      assert.is_true(#vim.__test.notifications >= 1)
      assert.truthy(vim.__test.notifications[#vim.__test.notifications].msg:match("workspace loaded"))
    end)

    it("Given fsharp/testDetected, when handled, then ionide stores the detected tests", function()
      ionide.Handlers["fsharp/testDetected"](nil, {
        File = "/workspace/Tests.fs",
        Tests = { { Name = "My test" } },
      }, {}, {})

      assert.is_table(ionide.State.test_detection["/workspace/Tests.fs"])
      assert.equals("My test", ionide.State.test_detection["/workspace/Tests.fs"][1].Name)
    end)
  end)

  describe("client resolution", function()
    it("Given a client named fsautocomplete, when ionide resolves clients, then it is accepted", function()
      local client = make_client({ id = 20, name = "fsautocomplete" })
      vim.__test.clients = { client }
      vim.__test.buffers_by_client_id[20] = { 1 }

      local clients = ionide.GetIonideClients({ bufnr = 1 })

      assert.equals(1, #clients)
      assert.equals("fsautocomplete", clients[1].name)
    end)

    it("Given a client named ionide, when ionide resolves clients, then it is accepted", function()
      local client = make_client({ id = 21, name = "ionide" })
      vim.__test.clients = { client }
      vim.__test.buffers_by_client_id[21] = { 1 }

      local clients = ionide.GetIonideClients({ bufnr = 1 })

      assert.equals(1, #clients)
      assert.equals("ionide", clients[1].name)
    end)

    it("Given a client without the usual fsac name but with fsac custom methods, when ionide resolves clients, then it is accepted", function()
      local client = make_client({
        id = 22,
        name = "custom-fsharp-client",
        __supported_methods = {
          ["fsharp/documentation"] = true,
        },
      })
      vim.__test.clients = { client }
      vim.__test.buffers_by_client_id[22] = { 1 }

      local clients = ionide.GetIonideClients({ bufnr = 1 })

      assert.equals(1, #clients)
      assert.equals("custom-fsharp-client", clients[1].name)
    end)
  end)

  describe("commands and setup", function()
    it("Given setup, when invoked, then missing fsproj and test commands are created", function()
      ionide.setup({})

      assert.is_table(vim.__test.user_commands.IonideFsprojAddFile)
      assert.is_table(vim.__test.user_commands.IonideFsprojAddExistingFile)
      assert.is_table(vim.__test.user_commands.IonideFsprojAddFileAbove)
      assert.is_table(vim.__test.user_commands.IonideFsprojAddFileBelow)
      assert.is_table(vim.__test.user_commands.IonideTestDiscover)
      assert.is_table(vim.__test.user_commands.IonideTestRun)
      assert.is_table(vim.__test.user_commands.IonideDocumentation)
    end)

    it("Given a custom FsautocompleteCommand, when setup is invoked, then the LSP cmd uses that command", function()
      local cfg = ionide.setup({
        IonideNvimSettings = {
          FsautocompleteCommand = { "dotnet", "C:/custom/fsautocomplete.dll" },
        },
      })

      assert.same({ "dotnet", "C:/custom/fsautocomplete.dll" }, cfg.cmd)
    end)

    it("Given AutomaticWorkspaceInit is enabled, when LspAttach fires, then workspace peek is requested", function()
      ionide.setup({})
      local client = make_client({ id = 22, name = "ionide", config = { root_dir = "/workspace" } })
      vim.__test.clients = { client }
      vim.__test.buffers_by_client_id[22] = { 1 }

      vim.__test.run_autocmd("LspAttach", { buffer = 1 })

      local req = vim.__test.client_requests[22][#vim.__test.client_requests[22]]
      assert.is_not_nil(req)
      assert.equals("fsharp/workspacePeek", req.method)
    end)
  end)

  describe("legacy surfaces", function()
    it("Given Fsdn, when invoked, then it returns empty results and a cancel function", function()
      local requests, cancel = ionide.Fsdn("test query")
      assert.is_table(requests)
      assert.is_function(cancel)
    end)

    it("Given notify, when invoked with string or table, then it does not error", function()
      assert.has_no.errors(function()
        ionide.notify("test message")
        ionide.notify({ key = "value" })
      end)
    end)
  end)

  describe("documentation-first hover", function()
    it("Given fsharp/documentation and documentationSymbol are available, when ShowDocumentationHover is invoked, then symbol docs and current-line diagnostics are shown", function()
      vim.__test.buffer_names[1] = "/workspace/File.fs"
      vim.__test.cursor = { 3, 4 }
      vim.__test.diagnostics[1] = {
        { lnum = 2, severity = vim.diagnostic.severity.WARN, source = "FSAC", message = "Unused open" },
        { lnum = 1, severity = vim.diagnostic.severity.ERROR, source = "FSAC", message = "Other line" },
      }

      ionide.CallFSharpDocumentation = function(file, line, character, handler)
        handler(nil, {
          Content = [[{"Kind":"formattedDocumentation","Data":{"Signature":"val map : ('a -> 'b) -> 'a list -> 'b list","Comment":"Applies a function to each element","FooterLines":["From module List"]}}]],
        }, {}, {})
      end

      ionide.CallFSharpDocumentationSymbol = function(xmlSig, assembly, handler)
        assert.equals("T:Microsoft.FSharp.Collections.ListModule", xmlSig)
        assert.equals("FSharp.Core", assembly)
        handler(nil, {
          Content = [[{"Kind":"formattedDocumentation","Data":{"Signature":"val map<'T,'U> : ('T -> 'U) -> 'T list -> 'U list","Comment":"Mapped symbol docs","FooterLines":["External docs footer"]}}]],
        }, {}, {})
      end

      ionide.F1Help = function(file, line, character, handler)
        handler(nil, { Content = [[{"Kind":"help","Data":"List.map help text"}]] }, {}, {})
      end

      local hover_req_count = #vim.__test.buf_requests

      ionide.ShowDocumentationHover()

      local hover_req = vim.__test.buf_requests[hover_req_count + 1]
      assert.equals("textDocument/hover", hover_req.method)
      hover_req.callback({
        [1] = {
          result = {
            contents = {
              { language = "fsharp", value = "val map" },
              "<a href='command:fsharp.showDocumentation?%5B%7B%20%22XmlDocSig%22%3A%20%22T%3AMicrosoft.FSharp.Collections.ListModule%22%2C%20%22AssemblyName%22%3A%20%22FSharp.Core%22%20%7D%5D'>Open the documentation</a>",
            },
          },
        },
      })

      local preview = vim.__test.floating_previews[#vim.__test.floating_previews]
      assert.is_not_nil(preview)
      assert.equals("markdown", preview.syntax)
      assert.same({
        "```fsharp",
        "val map<'T,'U> : ('T -> 'U) -> 'T list -> 'U list",
        "```",
        "",
        "Mapped symbol docs",
        "",
        "External docs footer",
        "",
        "List.map help text",
        "",
        "### Diagnostics",
        "- **WARN** [FSAC]: Unused open",
      }, preview.contents)
    end)

    it("Given external docs cannot be resolved, when ShowDocumentationHover is invoked, then it combines fallback help, hover metadata, and diagnostics", function()
      local hover_calls = 0
      vim.lsp.buf.hover = function()
        hover_calls = hover_calls + 1
      end
      vim.__test.buffer_names[1] = "/workspace/File.fs"
      vim.__test.cursor = { 3, 4 }
      vim.__test.diagnostics[1] = {
        { lnum = 2, severity = vim.diagnostic.severity.ERROR, source = "FSAC", message = "Type mismatch" },
      }

      ionide.CallFSharpDocumentation = function(file, line, character, handler)
        handler(nil, {
          Content = [[{"Kind":"formattedDocumentation","Data":{"Signature":"val ctx : HttpContext","Comment":"","FooterLines":["From assembly Microsoft.AspNetCore.Http"]}}]],
        }, {}, {})
      end

      ionide.CallFSharpDocumentationSymbol = function(xmlSig, assembly, handler)
        handler(nil, {
          Content = [[{"Kind":"formattedDocumentation","Data":{"Signature":"val ctx : HttpContext","Comment":"","FooterLines":["From assembly Microsoft.AspNetCore.Http"]}}]],
        }, {}, {})
      end

      ionide.F1Help = function(file, line, character, handler)
        handler(nil, {
          Content = [[{"Kind":"help","Data":"ASP.NET Core request context value."}]],
        }, {}, {})
      end

      local hover_req_count = #vim.__test.buf_requests

      ionide.ShowDocumentationHover()

      local hover_req = vim.__test.buf_requests[hover_req_count + 1]
      hover_req.callback({
        [1] = {
          result = {
            contents = {
              { language = "fsharp", value = "val ctx : HttpContext" },
              "<a href='command:fsharp.showDocumentation?%5B%7B%20%22XmlDocSig%22%3A%20%22%22%2C%20%22AssemblyName%22%3A%20%22HarmonyServer%22%20%7D%5D'>Open the documentation</a>",
              "Full name: HarmonyServer.handleDashboard",
            },
          },
        },
      })

      local preview = vim.__test.floating_previews[#vim.__test.floating_previews]
      assert.is_not_nil(preview)
      assert.same({
        "```fsharp",
        "val ctx : HttpContext",
        "```",
        "",
        "From assembly Microsoft.AspNetCore.Http",
        "",
        "ASP.NET Core request context value.",
        "Full name: HarmonyServer.handleDashboard",
        "",
        "",
        "_FsAutoComplete could not resolve external XML documentation for this symbol._",
        "",
        "### Diagnostics",
        "- **ERROR** [FSAC]: Type mismatch",
      }, preview.contents)
      assert.equals(0, hover_calls)
    end)
  end)
end)
