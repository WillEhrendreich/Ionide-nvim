local vim = require("spec.vim_stub")

package.path = "./lua/?.lua;./lua/?/init.lua;./spec/?.lua;" .. package.path

describe("FSAC config contract", function()
  local ionide
  local fsac_lsp_helpers = "C:/Code/Repos/fsautocomplete/src/FsAutoComplete/LspHelpers.fs"

  local function reset_module()
    vim.__test.reset()
    package.loaded["ionide.init"] = nil
    package.loaded["ionide.util"] = nil
    ionide = require("ionide.init")
  end

  local function read_all(path)
    local f = assert(io.open(path, "r"), "failed to open " .. path)
    local content = f:read("*a")
    f:close()
    return content
  end

  local function extract_record_fields(source, type_name)
    -- Parse a top-level F# record declaration line-by-line.
    -- This deliberately ignores nested anonymous record bodies like {| Enabled: ... |}
    -- and extracts only the top-level field names for the named DTO.
    -- If FSAC materially changes formatting or the DTO stops being a record,
    -- we WANT this to fail loudly.
    local lines = {}
    for line in source:gmatch("([^\r\n]+)") do
      table.insert(lines, line)
    end

    local start_idx = nil
    for i, line in ipairs(lines) do
      if line:match("^type%s+" .. type_name .. "%s*=") then
        start_idx = i + 1
        break
      end
    end

    assert.is_not_nil(start_idx, "Could not find type " .. type_name .. " in FSAC source")

    local fields = {}
    for i = start_idx, #lines do
      local line = lines[i]
      if line:match("^type%s+") then break end
      local field = line:match("^%s*{%s*([%a_][%w_]*)%s*:") or line:match("^%s+([%a_][%w_]*)%s*:")
      if field then
        fields[field] = true
      end
      if line:match("^%s*}%s*$") then break end
    end

    assert.is_true(next(fields) ~= nil, "Could not extract any fields for " .. type_name .. " from FSAC source")
    return fields
  end

  local function assert_has_fields(actual, expected, owner)
    for _, field in ipairs(expected) do
      assert.is_true(
        actual[field] == true,
        string.format("FSAC contract changed: expected %s.%s to exist upstream", owner, field)
      )
    end
  end

  before_each(reset_module)

  it("Given Ionide depends on specific FSAC config fields, when upstream DTO changes, then this contract test fails loudly", function()
    -- Why: Ionide passes settings = { FSharp = ... } to FSAC. If FSAC renames or
    -- removes fields like WorkspaceModePeekDeepLevel or FSIExtraParameters, Ionide
    -- may silently stop configuring behavior correctly. We want that to break tests
    -- immediately, not drift in production.
    local source = read_all(fsac_lsp_helpers)

    local fsharp = extract_record_fields(source, "FSharpConfigDto")
    local code_lens = extract_record_fields(source, "CodeLensConfigDto")
    local inlay_hint = extract_record_fields(source, "InlayHintDto")
    local inline_value = extract_record_fields(source, "InlineValueDto")
    local notifications = extract_record_fields(source, "NotificationsDto")
    local fsac = extract_record_fields(source, "FSACDto")

    -- Top-level FSAC config fields Ionide currently depends on or documents as supported.
    assert_has_fields(fsharp, {
      "AutomaticWorkspaceInit",
      "WorkspaceModePeekDeepLevel",
      "ExcludeProjectDirectories",
      "KeywordsAutocomplete",
      "ExternalAutocomplete",
      "FullNameExternalAutocomplete",
      "Linter",
      "IndentationSize",
      "UnionCaseStubGeneration",
      "UnionCaseStubGenerationBody",
      "RecordStubGeneration",
      "RecordStubGenerationBody",
      "InterfaceStubGeneration",
      "InterfaceStubGenerationObjectIdentifier",
      "InterfaceStubGenerationMethodBody",
      "UnusedOpensAnalyzer",
      "UnusedDeclarationsAnalyzer",
      "SimplifyNameAnalyzer",
      "ResolveNamespaces",
      "EnableAnalyzers",
      "AnalyzersPath",
      "UseSdkScripts",
      "DotNetRoot",
      "FSIExtraParameters",
      "FSICompilerToolLocations",
      "TooltipMode",
      "GenerateBinlog",
      "AbstractClassStubGeneration",
      "AbstractClassStubGenerationObjectIdentifier",
      "AbstractClassStubGenerationMethodBody",
      "CodeLenses",
      "PipelineHints",
      "InlayHints",
      "Fsac",
      "Notifications",
    }, "FSharpConfigDto")

    -- Nested DTOs Ionide either configures now or has commented/documented support for.
    assert_has_fields(code_lens, { "Signature", "References" }, "CodeLensConfigDto")
    assert_has_fields(inlay_hint, { "typeAnnotations", "parameterNames", "disableLongTooltip" }, "InlayHintDto")
    assert_has_fields(inline_value, { "Enabled", "Prefix" }, "InlineValueDto")
    assert_has_fields(notifications, { "Trace", "TraceNamespaces", "BackgroundServiceProgress" }, "NotificationsDto")
    assert_has_fields(fsac, { "CachedTypeCheckCount", "ParallelReferenceResolution" }, "FSACDto")
  end)

  it("Given Ionide default server settings, when mapped to FSAC names, then the upstream DTO still contains those names", function()
    -- Why: this protects the subset of fields actually present in DefaultServerSettings,
    -- not just the broader documented/configurable surface. If one of these gets renamed
    -- upstream, Ionide's defaults become stale immediately.
    local source = read_all(fsac_lsp_helpers)
    local fsharp = extract_record_fields(source, "FSharpConfigDto")

    local ionide_to_fsac = {
      workspaceModePeekDeepLevel = "WorkspaceModePeekDeepLevel",
      excludeProjectDirectories = "ExcludeProjectDirectories",
      keywordsAutocomplete = "KeywordsAutocomplete",
      fullNameExternalAutocomplete = "FullNameExternalAutocomplete",
      externalAutocomplete = "ExternalAutocomplete",
      linter = "Linter",
      indentationSize = "IndentationSize",
      unionCaseStubGeneration = "UnionCaseStubGeneration",
      unionCaseStubGenerationBody = "UnionCaseStubGenerationBody",
      recordStubGeneration = "RecordStubGeneration",
      recordStubGenerationBody = "RecordStubGenerationBody",
      interfaceStubGeneration = "InterfaceStubGeneration",
      interfaceStubGenerationObjectIdentifier = "InterfaceStubGenerationObjectIdentifier",
      interfaceStubGenerationMethodBody = "InterfaceStubGenerationMethodBody",
      unusedOpensAnalyzer = "UnusedOpensAnalyzer",
      unusedDeclarationsAnalyzer = "UnusedDeclarationsAnalyzer",
      simplifyNameAnalyzer = "SimplifyNameAnalyzer",
      resolveNamespaces = "ResolveNamespaces",
      enableAnalyzers = "EnableAnalyzers",
      analyzersPath = "AnalyzersPath",
      useSdkScripts = "UseSdkScripts",
      dotnetRoot = "DotNetRoot",
      fsiExtraParameters = "FSIExtraParameters",
      fsiCompilerToolLocations = "FSICompilerToolLocations",
      tooltipMode = "TooltipMode",
      generateBinlog = "GenerateBinlog",
      abstractClassStubGeneration = "AbstractClassStubGeneration",
      abstractClassStubGenerationObjectIdentifier = "AbstractClassStubGenerationObjectIdentifier",
      abstractClassStubGenerationMethodBody = "AbstractClassStubGenerationMethodBody",
      codeLenses = "CodeLenses",
      fsac = "Fsac",
    }

    for ionide_key, fsac_key in pairs(ionide_to_fsac) do
      assert.is_not_nil(ionide.DefaultServerSettings[ionide_key], "Expected Ionide default setting " .. ionide_key .. " to exist")
      assert.is_true(
        fsharp[fsac_key] == true,
        string.format(
          "FSAC contract changed: Ionide DefaultServerSettings.%s maps to missing upstream field FSharpConfigDto.%s",
          ionide_key,
          fsac_key
        )
      )
    end
  end)
end)
