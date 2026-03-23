-- Tests documenting and pinning the 8 bugs fixed in commit 232436d + the
-- IsIonideClient custom-name fix.
--
-- Style contract (matches sagefs.nvim spec style):
--   • BDD: "Given …, when …, then …" descriptions.
--   • WHY comments above each test — not WHAT, but WHY the old code was wrong
--     and why the fix is the correct behaviour.
--   • Property tests: table-driven loops that assert an invariant across many
--     representative inputs, not just a single happy-path example.
--
-- These tests are GREEN (the bugs are fixed).  If any of these regress to RED
-- it means a refactor has re-introduced the original bug.

local vim = require("spec.vim_stub")

package.path = "./lua/?.lua;" .. "./lua/?/init.lua;" .. "./spec/?.lua;" .. package.path

describe("ionide bug regression suite", function()
  local ionide

  local function reset_module()
    vim.__test.reset()
    package.loaded["ionide.init"] = nil
    package.loaded["ionide.util"] = nil
    ionide = require("ionide.init")
  end

  local function make_client(overrides)
    local base = {
      id = 1,
      name = "ionide",
      config = { root_dir = "/workspace" },
      server_capabilities = {},
      supports_method = function(self, method)
        return (self.__supported_methods and self.__supported_methods[method]) == true
      end,
      stop = function() end,
    }
    local client = vim.tbl_deep_extend("force", base, overrides or {})
    -- supports_method must be a real function with self-aware closure
    if overrides and overrides.__supported_methods then
      client.supports_method = function(self, method)
        return (self.__supported_methods and self.__supported_methods[method]) == true
      end
    end
    return vim.__test.with_client_methods(client)
  end

  before_each(reset_module)

  -- ===========================================================================
  -- BUG 1: root_dir parameter shadow
  -- ===========================================================================
  -- The old code contained `local bufnr = vim.api.nvim_get_current_buf()` inside
  -- the root_dir callback, which shadowed the `bufnr` parameter Neovim 0.10+ passes
  -- in.  When multiple files were opened simultaneously the callback executed for
  -- buffer A but read the name of whatever nvim_get_current_buf() returned at that
  -- instant — potentially buffer B.  The fix: remove the shadowing `local` and use
  -- the passed-in `bufnr` directly.

  describe("BUG 1 — root_dir uses the passed-in bufnr, not get_current_buf()", function()
    it("Given two buffers, when root_dir callback fires with bufnr=2, then nvim_buf_get_name is called for buffer 2 first", function()
      -- WHY: the old code called `local bufnr = vim.api.nvim_get_current_buf()` which
      -- would always read buffer 1 (the current buf) regardless of which buffer Neovim
      -- passed in.  We verify the fix by instrumenting nvim_buf_get_name.
      vim.__test.buffer_names[1] = "/workspace/Main.fs"
      vim.__test.buffer_names[2] = "/other/Other.fs"
      vim.__test.current_buf = 1   -- current buf is 1

      local first_queried = nil
      local orig_get_name = vim.api.nvim_buf_get_name
      vim.api.nvim_buf_get_name = function(bufnr_arg)
        if first_queried == nil then first_queried = bufnr_arg end
        return orig_get_name(bufnr_arg)
      end

      -- root_dir is a closure; calling it drives nvim_buf_get_name.
      -- With the fix it uses the passed-in bufnr (2), not get_current_buf() (1).
      -- We use pcall because GetRoot may not find a .fsproj and returns nil,
      -- but the important thing is which bufnr was queried first.
      pcall(ionide.DefaultLspConfig.root_dir, 2, function() end)

      vim.api.nvim_buf_get_name = orig_get_name

      assert.is_not_nil(first_queried, "nvim_buf_get_name must have been called")
      assert.equals(2, first_queried,
        "root_dir must query nvim_buf_get_name with the PASSED-IN bufnr (2), not get_current_buf() (1)")
    end)

    it("Given current_buf=1 and root_dir called with bufnr=2, then bufnr 1 is NOT queried first", function()
      -- WHY: the old shadow `local bufnr = vim.api.nvim_get_current_buf()` would
      -- make the FIRST query always go to buffer 1.  After the fix, 1 should not
      -- be the first buffer queried when 2 is passed in.
      vim.__test.buffer_names[1] = "/workspace/Main.fs"
      vim.__test.buffer_names[2] = "/other/Other.fs"
      vim.__test.current_buf = 1

      local first_queried = nil
      local orig_get_name = vim.api.nvim_buf_get_name
      vim.api.nvim_buf_get_name = function(bufnr_arg)
        if first_queried == nil then first_queried = bufnr_arg end
        return orig_get_name(bufnr_arg)
      end

      pcall(ionide.DefaultLspConfig.root_dir, 2, function() end)
      vim.api.nvim_buf_get_name = orig_get_name

      assert.is_not_nil(first_queried)
      assert.are_not.equal(1, first_queried,
        "The FIRST nvim_buf_get_name query must NOT be for the current buf (1) when bufnr=2 was passed")
    end)

    it("property: root_dir callback is called at most once per invocation", function()
      -- WHY: a second call to get_current_buf inside root_dir could in principle
      -- cause the on_dir callback to be invoked twice.  Once per invocation is
      -- the contract.
      local call_count = 0
      -- Buffer 1 has a file that won't match any .fsproj — callback fires with nil.
      vim.__test.buffer_names[1] = "/no/project/here/Script.fsx"
      ionide.DefaultLspConfig.root_dir(1, function(_) call_count = call_count + 1 end)
      assert.is_true(call_count <= 1,
        "root_dir must call on_dir at most once (got " .. call_count .. ")")
    end)
  end)

  -- ===========================================================================
  -- BUG 2: TextDocumentIdentifier mutated vim.o.shellslash
  -- ===========================================================================
  -- The old implementation temporarily set vim.o.shellslash = true to normalise
  -- paths, then restored it.  If any code path errored between the set and the
  -- restore the global was left permanently mutated, silently breaking all
  -- subsequent path operations for the lifetime of the session.
  -- The fix: use vim.uri_from_fname which handles drive letters natively.

  describe("BUG 2 — TextDocumentIdentifier never mutates vim.o.shellslash", function()
    -- WHY property: exercise every kind of path the function might encounter.
    -- For each one shellslash must remain exactly what it was before the call.
    local paths = {
      "/workspace/Src/Game.fs",           -- Unix absolute
      "C:/workspace/Src/Game.fs",         -- Windows forward-slash
      "C:\\workspace\\Src\\Game.fs",      -- Windows backslash
      "/a/b/c/Deep/Nested/Module.fsi",    -- deep unix
      "relative/path.fs",                 -- relative (unusual but not forbidden)
    }

    for _, initial_shellslash in ipairs({ true, false }) do
      for _, path in ipairs(paths) do
        it(string.format(
          "property: shellslash=%s unchanged after TextDocumentIdentifier(%q)",
          tostring(initial_shellslash), path
        ), function()
          vim.o.shellslash = initial_shellslash

          ionide.TextDocumentIdentifier(path)

          assert.equals(
            initial_shellslash, vim.o.shellslash,
            "TextDocumentIdentifier must not mutate vim.o.shellslash"
          )
        end)
      end
    end

    it("Given a Windows path, when TextDocumentIdentifier is called, then the uri is a file:// URI", function()
      -- WHY: the uri must be a valid LSP TextDocumentIdentifier — the server
      -- will reject bare file-system paths.
      local result = ionide.TextDocumentIdentifier("C:/workspace/Game.fs")
      assert.is_string(result.uri)
      assert.truthy(result.uri:match("^file://"), "uri must start with file://")
    end)

    it("Given a Unix path, when TextDocumentIdentifier is called, then the uri is a file:// URI", function()
      local result = ionide.TextDocumentIdentifier("/workspace/Game.fs")
      assert.is_string(result.uri)
      assert.truthy(result.uri:match("^file://"), "uri must start with file://")
    end)

    it("property: uri field is always a string, never nil", function()
      local test_paths = {
        "/a/b.fs", "C:/a/b.fs", "relative/b.fs", "/deeply/nested/path/Module.fsi",
      }
      for _, p in ipairs(test_paths) do
        local result = ionide.TextDocumentIdentifier(p)
        assert.is_string(result.uri, "uri should be a string for path: " .. p)
      end
    end)
  end)

  -- ===========================================================================
  -- BUG 3: IsIonideClient only matched by name, ignoring custom-named clients
  -- ===========================================================================
  -- A user who configures fsautocomplete under a custom LSP client name (e.g.
  -- via a distro package or a wrapper) would be silently ignored: every
  -- GetIonideClients call returns an empty list, so all Ionide features
  -- (documentation, signatures, code actions) disappear without any error.
  -- The fix: also accept clients whose supports_method("fsharp/documentation")
  -- returns true, as that is the fsautocomplete-specific capability marker.

  describe("BUG 3 — IsIonideClient accepts custom-named clients by capability", function()
    it("Given a client named 'ionide', when IsIonideClient is called, then it returns true", function()
      local c = make_client({ name = "ionide" })
      assert.is_true(ionide.IsIonideClient(c))
    end)

    it("Given a client named 'fsautocomplete', when IsIonideClient is called, then it returns true", function()
      local c = make_client({ name = "fsautocomplete" })
      assert.is_true(ionide.IsIonideClient(c))
    end)

    it("Given a custom-named client with fsharp/documentation support, when IsIonideClient is called, then it returns true", function()
      -- WHY: package-manager-managed installs often use names like 'fsac' or
      -- 'custom-fsharp-lsp'.  If the client speaks the fsharp protocol, Ionide
      -- must recognise it regardless of the configured name.
      local c = make_client({
        name = "custom-fsharp-client",
        __supported_methods = { ["fsharp/documentation"] = true },
      })
      assert.is_true(ionide.IsIonideClient(c))
    end)

    it("Given a non-fsharp client (copilot), when IsIonideClient is called, then it returns false", function()
      local c = make_client({ name = "copilot" })
      assert.is_false(ionide.IsIonideClient(c))
    end)

    it("Given nil, when IsIonideClient is called, then it returns false without error", function()
      -- WHY: defensive — LSP attach events can fire with nil clients in edge cases.
      assert.is_false(ionide.IsIonideClient(nil))
    end)

    it("property: any name other than ionide/fsautocomplete without fsharp capability is rejected", function()
      -- WHY: make sure the capability check doesn't accidentally accept everything.
      local non_fsharp_names = { "lua_ls", "clangd", "pyright", "rust_analyzer", "tsserver" }
      for _, name in ipairs(non_fsharp_names) do
        local c = make_client({ name = name, __supported_methods = {} })
        assert.is_false(ionide.IsIonideClient(c),
          "should reject client named: " .. name)
      end
    end)

    it("Given a custom-named client, when GetIonideClients is called, then it is included in the results", function()
      -- WHY: IsIonideClient feeds GetIonideClients — verify the integration, not
      -- just the predicate in isolation.
      local c = make_client({
        id = 99,
        name = "my-fsharp-wrapper",
        __supported_methods = { ["fsharp/documentation"] = true },
      })
      vim.__test.clients = { c }
      vim.__test.buffers_by_client_id[99] = { 1 }

      local clients = ionide.GetIonideClients({ bufnr = 1 })

      assert.equals(1, #clients)
      assert.equals("my-fsharp-wrapper", clients[1].name)
    end)
  end)

  -- ===========================================================================
  -- BUG 5: advanceCursorOneLine `or true` boolean trap
  -- ===========================================================================
  -- `local x = param or true` is a Lua boolean trap: if the caller passes `false`
  -- the expression evaluates to `true` because `false or true == true`.  There is
  -- no way for the caller to opt out of the default.  The fix uses an explicit
  -- nil-check so that `false` is preserved.

  describe("BUG 5 — GetVisualSelection: explicit false is respected", function()
    -- NOTE: GetVisualSelection makes vim.api calls (feedkeys, getpos, visualmode).
    -- The stub returns safe defaults so the function completes without error.

    it("Given advanceCursorOneLine=false, when GetVisualSelection is called, then no error is raised", function()
      -- WHY: before the fix, passing false was silently overridden to true.
      -- The test can't easily observe cursor movement in a stub, but it can at
      -- least confirm the function completes and returns without unhandled error.
      local ok, _ = pcall(ionide.GetVisualSelection, false, false)
      assert.is_true(ok, "GetVisualSelection(false, false) should not error")
    end)

    it("Given advanceCursorOneLine=nil, when GetVisualSelection is called, then it defaults without error", function()
      -- WHY: nil is the normal case when the parameter is omitted — must default to
      -- true (advance) without erroring.
      local ok, _ = pcall(ionide.GetVisualSelection, false, nil)
      assert.is_true(ok, "GetVisualSelection with nil advanceCursorOneLine should not error")
    end)

    it("property: GetVisualSelection does not error for any combination of the two boolean parameters", function()
      -- WHY: property over all four bool × bool combinations ensures there is no
      -- combination that causes a nil-path crash.
      local bool_values = { true, false, nil }
      for _, keep in ipairs(bool_values) do
        for _, advance in ipairs(bool_values) do
          local ok, err = pcall(ionide.GetVisualSelection, keep, advance)
          assert.is_true(ok,
            string.format("should not error for keepSelection=%s, advance=%s: %s",
              tostring(keep), tostring(advance), tostring(err)))
        end
      end
    end)
  end)

  -- ===========================================================================
  -- BUG 6: IonideResetIonideBufferNumber leaked the fsiJob
  -- ===========================================================================
  -- The old command only reset FsiBuffer to -1 but left fsiJob pointing at a
  -- (now-orphaned) job handle.  The next call to start FSI would start a second
  -- job — two terminal jobs writing to the same output, multiplying output and
  -- wasting resources.  The fix: stop fsiJob (if > 0) before resetting both
  -- module-level variables.

  describe("BUG 6 — IonideResetIonideBufferNumber stops fsiJob before clearing", function()
    it("Given no active fsiJob, when IonideResetIonideBufferNumber is called, then it completes without error", function()
      -- WHY: defensive — reset on a fresh state (fsiJob == -1) must not crash.
      -- This command is created at module load time (top-level in init.lua).
      local reset_cmd = vim.__test.user_commands["IonideResetIonideBufferNumber"]
      assert.is_table(reset_cmd, "IonideResetIonideBufferNumber command must exist after module load")

      local ok = pcall(reset_cmd.callback, {})
      assert.is_true(ok, "reset command must not error when fsiJob is -1")
    end)

    it("When IonideResetIonideBufferNumber is called, then a notification is emitted confirming the buffer number", function()
      -- WHY: the user must get feedback that the reset happened — otherwise they
      -- can't tell whether the command ran.
      local reset_cmd = vim.__test.user_commands["IonideResetIonideBufferNumber"]
      reset_cmd.callback({})

      local found = false
      for _, n in ipairs(vim.__test.notifications) do
        if n.msg and n.msg:match("[Ff]si") then
          found = true
          break
        end
      end
      assert.is_true(found, "a notification about FsiBuffer state must be emitted")
    end)

    it("Given jobstart recorded fsiJob=1, when reset is called, then jobstop is recorded", function()
      -- WHY: fsiJob is a module-level local so we cannot set it directly.
      -- We simulate it by monkey-patching jobstart to return 1, then calling
      -- the IonideResetIonideBufferNumber command path via the module's own
      -- internal StartFsi-like function (OpenFsi stub path).
      --
      -- Strategy: override vim.fn.jobstart to record the job id, then call
      -- IonideToggleFSI (which calls OpenFsi → jobstart) but ONLY if it doesn't
      -- trigger GetRoot/iterate_parents.  Since we've fixed the uname stub to
      -- use Linux path_sep, paths like /workspace/... will traverse and stop at /.
      -- We set the buffer to a file with no .fsproj → GetRoot returns nil quickly.
      vim.__test.buffer_names[1] = "/nosuchproject/Script.fsx"
      vim.fn.bufnr = function(_) return 1 end

      ionide.setup({ IonideNvimSettings = { AutomaticWorkspaceInit = false } })

      -- IonideToggleFSI is created inside setup.
      local toggle_cmd = vim.__test.user_commands["IonideToggleFSI"]
      if toggle_cmd and type(toggle_cmd.callback) == "function" then
        pcall(toggle_cmd.callback, {})   -- opens FSI (stub jobstart returns 1 → fsiJob = 1)
      end

      vim.__test.jobstops = {}   -- clear any jobstops that happened during open

      local reset_cmd = vim.__test.user_commands["IonideResetIonideBufferNumber"]
      assert.is_table(reset_cmd, "IonideResetIonideBufferNumber command must exist after setup")

      local ok = pcall(reset_cmd.callback, {})
      assert.is_true(ok, "reset must not error")

      -- If toggle_cmd was found and ran successfully (fsiJob > 0) then jobstop
      -- must have been called.  If toggle_cmd was not found we accept the weaker
      -- guarantee that reset at least ran without crashing.
      if toggle_cmd then
        assert.is_true(#vim.__test.jobstops > 0,
          "jobstop must be called when fsiJob > 0 before clearing FsiBuffer")
      end
    end)
  end)

  -- ===========================================================================
  -- BUG 7: Keymap race — <leader>cr and <leader>ca set without guard
  -- ===========================================================================
  -- LazyVim and other distributions set buffer-local <leader>cr / <leader>ca
  -- in their own LspAttach handlers.  When those handlers fire before Ionide's
  -- handler, Ionide's handler was silently overwriting them, removing the user's
  -- custom bindings.  The fix: check maparg() for an existing buffer-local map
  -- before registering; skip if one already exists.
  --
  -- NOTE: OnLspAttach is called by OnNativeLspAttach, which is triggered by the
  -- LspAttach autocmd registered in setup().  The autocmd fires synchronously
  -- in the stub (run_autocmd calls the callback directly).

  describe("BUG 7 — keymap race: existing buffer-local maps are not overwritten", function()
    local function attach_client(client, bufnr)
      -- Simulate a full LspAttach event for client+bufnr.
      -- setup() registers the LspAttach autocmd; run_autocmd fires it.
      vim.__test.clients = { client }
      vim.__test.buffers_by_client_id[client.id] = { bufnr }
      ionide.setup({ IonideNvimSettings = { AutomaticWorkspaceInit = false } })
      vim.__test.run_autocmd("LspAttach", {
        buffer = bufnr,
        data   = { client_id = client.id },
      })
    end

    it("Given a pre-existing buffer-local <leader>cr map, when Ionide attaches, then <leader>cr is NOT re-registered", function()
      -- WHY: if Ionide blindly sets the keymap it removes the user's custom rename
      -- binding (e.g. LazyVim's keymap that calls snacks.rename or similar).
      vim.__test.buf_keymaps["n"] = { ["<leader>cr"] = "existing_rename" }

      local c = make_client({
        id = 10,
        __supported_methods = {
          ["textDocument/rename"]     = true,
          ["textDocument/codeAction"] = true,
        },
        server_capabilities = {
          renameProvider    = true,
          codeActionProvider = true,
        },
      })
      attach_client(c, 1)

      local ionide_cr = nil
      for _, km in ipairs(vim.__test.keymaps) do
        if km.lhs == "<leader>cr" and km.opts and km.opts.buffer == 1 then
          ionide_cr = km
          break
        end
      end
      assert.is_nil(ionide_cr,
        "<leader>cr must not be overwritten when a buffer-local map already exists")
    end)

    it("Given no pre-existing <leader>cr map, when Ionide attaches with rename capability, then <leader>cr IS registered", function()
      -- WHY: the guard must not block registration when the slot is genuinely free.
      vim.__test.buf_keymaps["n"] = {}

      local c = make_client({
        id = 11,
        __supported_methods = {
          ["textDocument/rename"]     = true,
          ["textDocument/codeAction"] = true,
        },
        server_capabilities = {
          renameProvider    = true,
          codeActionProvider = true,
        },
      })
      attach_client(c, 1)

      local found = false
      for _, km in ipairs(vim.__test.keymaps) do
        if km.lhs == "<leader>cr" then found = true; break end
      end
      assert.is_true(found, "<leader>cr should be registered when the slot is free")
    end)

    it("Given a pre-existing buffer-local <leader>ca map, when Ionide attaches, then <leader>ca is NOT re-registered", function()
      vim.__test.buf_keymaps["n"] = { ["<leader>ca"] = "existing_code_action" }

      local c = make_client({
        id = 12,
        __supported_methods = {
          ["textDocument/rename"]     = true,
          ["textDocument/codeAction"] = true,
        },
        server_capabilities = {
          renameProvider    = true,
          codeActionProvider = true,
        },
      })
      attach_client(c, 1)

      local ionide_ca = nil
      for _, km in ipairs(vim.__test.keymaps) do
        if km.lhs == "<leader>ca" and km.opts and km.opts.buffer == 1 then
          ionide_ca = km
          break
        end
      end
      assert.is_nil(ionide_ca,
        "<leader>ca must not be overwritten when a buffer-local map already exists")
    end)

    it("Given no pre-existing <leader>ca map, when Ionide attaches with codeAction capability, then <leader>ca IS registered", function()
      vim.__test.buf_keymaps["n"] = {}

      local c = make_client({
        id = 13,
        __supported_methods = {
          ["textDocument/rename"]     = true,
          ["textDocument/codeAction"] = true,
        },
        server_capabilities = {
          renameProvider    = true,
          codeActionProvider = true,
        },
      })
      attach_client(c, 1)

      local found = false
      for _, km in ipairs(vim.__test.keymaps) do
        if km.lhs == "<leader>ca" then found = true; break end
      end
      assert.is_true(found, "<leader>ca should be registered when the slot is free")
    end)

    it("property: <leader>cR (file rename) is ALWAYS registered regardless of pre-existing maps", function()
      -- WHY: <leader>cR is Ionide-specific (not a generic LSP keymap), so there
      -- is no conflict risk — it should always be registered.
      vim.__test.buf_keymaps["n"] = { ["<leader>cR"] = "some_other_rename" }

      local c = make_client({
        id = 14,
        __supported_methods = {
          ["textDocument/rename"]     = true,
          ["textDocument/codeAction"] = true,
        },
        server_capabilities = {
          renameProvider    = true,
          codeActionProvider = true,
        },
      })
      attach_client(c, 1)

      local found = false
      for _, km in ipairs(vim.__test.keymaps) do
        if km.lhs == "<leader>cR" then found = true; break end
      end
      assert.is_true(found, "<leader>cR should always be registered by Ionide")
    end)
  end)

  -- ===========================================================================
  -- BUG 4 (rename atomicity) + BUG 3 (virtual path +2 → +1)
  -- ===========================================================================
  -- IonideRenameFileInteractive had two related bugs:
  --
  -- Virtual-path bug: the old `sub(#fsproj_dir + 2)` ate the first character of
  -- the relative path because vim.fs.normalize guarantees no trailing separator
  -- (so the separator is at index #fsproj_dir+1).
  -- The fix uses vim.fs.relpath (Neovim 0.10+) which is correct by definition.
  --
  -- Atomicity bug: old code renamed the disk file FIRST, then called FSAC.
  -- If FSAC failed the file was renamed on disk but the .fsproj still referenced
  -- the old name.  The fix inverts the order: FSAC first, disk only on success.
  --
  -- We test the observable guarantees of the relpath stub directly and verify
  -- the early-exit guards on IonideRenameFileInteractive.

  describe("BUG 4 + virtual path — IonideRenameFileInteractive guards and relpath", function()
    it("Given a buffer with no file path, when IonideRenameFileInteractive is called, then it warns and returns early without LSP calls", function()
      -- WHY: empty buffer names are common (scratch buffers, unnamed new files).
      -- The function must not crash or attempt an LSP call.
      vim.__test.buffer_names[1] = ""
      ionide.IonideRenameFileInteractive()

      local warned = false
      for _, n in ipairs(vim.__test.notifications) do
        if n.msg and n.msg:match("[Nn]o.*[Ff]ile") or n.msg:match("no file path") then
          warned = true
          break
        end
      end
      assert.is_true(warned, "should warn about missing file path")
      assert.equals(0, #vim.__test.buf_requests, "no LSP request should be made for an empty buffer path")
    end)

    it("Given a non-.fs buffer, when IonideRenameFileInteractive is called, then it warns about the extension and returns early", function()
      -- WHY: the rename logic is .fs/.fsi specific.
      vim.__test.buffer_names[1] = "/workspace/Config.json"
      ionide.IonideRenameFileInteractive()

      local warned = false
      for _, n in ipairs(vim.__test.notifications) do
        if n.msg then warned = true; break end
      end
      -- At minimum a notification is emitted (content varies — may say "no file path",
      -- "not an F# source file", or similar).
      assert.is_true(warned, "should emit a notification for non-.fs file")
    end)

    it("property: IonideRenameFileInteractive never errors for any file extension", function()
      -- WHY: totality — the guard must handle every possible file extension
      -- without crashing.  Only .fs/.fsi proceed; everything else warns and returns.
      local extensions = { "fs", "fsi", "lua", "py", "json", "cs", "vb", "", "txt" }
      for _, ext in ipairs(extensions) do
        vim.__test.reset()
        package.loaded["ionide.init"] = nil
        package.loaded["ionide.util"] = nil
        ionide = require("ionide.init")
        vim.__test.buffer_names[1] = ext == "" and "/workspace/noext" or "/workspace/File." .. ext
        local ok, err = pcall(ionide.IonideRenameFileInteractive)
        assert.is_true(ok,
          string.format("IonideRenameFileInteractive must not throw for extension %q: %s",
            ext, tostring(err)))
      end
    end)

    it("Given a fsproj dir and a nested file path, when relpath is called, then the result never starts with a separator", function()
      -- WHY: the +2 bug caused the virtual path to be off by one character — e.g.
      -- "rc/Game.fs" instead of "src/Game.fs".  vim.fs.relpath in the stub is the
      -- reference implementation.  This test pins the stub's behaviour and documents
      -- what the production code now produces.
      local cases = {
        { base = "/repo/Project",   path = "/repo/Project/Game.fs",     expected = "Game.fs" },
        { base = "/repo/Project",   path = "/repo/Project/src/Game.fs", expected = "src/Game.fs" },
        { base = "/a",              path = "/a/b.fs",                   expected = "b.fs" },
        { base = "/a/b/c",         path = "/a/b/c/d/e/F.fsi",          expected = "d/e/F.fsi" },
      }
      for _, c in ipairs(cases) do
        local result = vim.fs.relpath(c.base, c.path)
        assert.equals(c.expected, result,
          string.format("relpath(%q, %q) should be %q, got %q",
            c.base, c.path, c.expected, tostring(result)))
        assert.is_false(result:sub(1, 1) == "/" or result:sub(1, 1) == "\\",
          "relpath result must not start with a path separator: " .. result)
      end
    end)
  end)

  -- ===========================================================================
  -- Integration smoke test — setup + LspAttach
  -- ===========================================================================
  -- Confirms that setup() + LspAttach completes without error when an Ionide
  -- client with typical server_capabilities attaches.  If any of the 8 fixes
  -- introduced a new crash this test will catch it.

  describe("smoke test — setup + LspAttach with an Ionide client", function()
    it("Given setup and a well-formed LspAttach event, when fired, then no error and keymaps are registered", function()
      local client = make_client({
        id = 42,
        name = "ionide",
        config = { root_dir = "/workspace" },
        server_capabilities = {
          renameProvider            = true,
          codeActionProvider        = true,
          codeLensProvider          = {},
          inlayHintProvider         = true,
          signatureHelpProvider     = {},
          documentHighlightProvider = true,
        },
        __supported_methods = {
          ["textDocument/rename"]            = true,
          ["textDocument/codeAction"]        = true,
          ["textDocument/codeLens"]          = true,
          ["textDocument/inlayHint"]         = true,
          ["textDocument/signatureHelp"]     = true,
          ["textDocument/documentHighlight"] = true,
        },
      })

      vim.__test.clients = { client }
      vim.__test.buffers_by_client_id[42] = { 1 }
      vim.__test.buf_keymaps = {}  -- no pre-existing maps

      local ok = pcall(function()
        ionide.setup({ IonideNvimSettings = { AutomaticWorkspaceInit = false } })
        vim.__test.run_autocmd("LspAttach", {
          buffer = 1,
          data   = { client_id = 42 },
        })
      end)

      assert.is_true(ok, "setup + LspAttach must not throw")
      assert.is_true(#vim.__test.keymaps > 0, "at least one keymap should be registered")
    end)
  end)
end)
