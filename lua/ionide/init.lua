local M = {}

M.State = {
  test_detection = {},
}

---@class InternalIonideNvimConfig
---@field exe? string|string[]
---@field config vim.lsp.ClientConfig
---@field choose_sln? fun(solutions: string[]): string?
---@field broad_search boolean

---@class IonideNvimConfig
---@field exe? string|string[]
---@field config? vim.lsp.ClientConfig
---@field choose_sln? fun(solutions: string[]): string?
---@field broad_search? boolean

local function tryRequire(...)
  local status, lib = pcall(require, ...)
  if status then
    return lib
  end
  return nil
end

local lspconfig_is_present = true
local util = tryRequire("lspconfig.util")
if util == nil then
  lspconfig_is_present = false
  util = require("ionide.util")
end

local function run_dotnet_version(root)
  local cmd = "dotnet --version"
  if root and root ~= "" then
    cmd = 'cd "' .. root .. '" && ' .. cmd
  end
  local output = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    return nil, output
  end
  return output:gsub("%s+$", ""), nil
end

local function parse_semver(version_str)
  local parts = vim.split(version_str, "[-.]")
  local major = tonumber(parts[1])
  local minor = tonumber(parts[2])
  local patch = tonumber(parts[3])
  local prerelease = nil
  if #parts > 3 then
    prerelease = table.concat(parts, ".", 4)
  end
  return {
    major = major,
    minor = minor,
    patch = patch,
    prerelease = prerelease,
    raw = version_str,
  }
end

local function tfm_for_sdk_version(sdk_version)
  return "net" .. sdk_version.major .. "." .. sdk_version.minor
end

---determines if input string ends with the suffix given.
---@param s string
---@param suffix string
---@return boolean
local function stringEndsWith(s, suffix)
  return s:sub(-#suffix) == suffix
end

local function notify_content(level)
  return function(err, rs, ctx, config)
    if rs and rs.Content then
      M.notify(rs.Content, level)
    end
  end
end

local function create_buf_autocmd(events, group_name, bufnr, callback)
  local group = vim.api.nvim_create_augroup(group_name .. bufnr, { clear = true })
  vim.api.nvim_create_autocmd(events, {
    group = group,
    buffer = bufnr,
    callback = callback,
  })
end

local function register_fsproj_command(name, usage, desc, argc, callback)
  vim.api.nvim_create_user_command(name, function(opts)
    if #opts.fargs < argc then
      M.notify("Usage: " .. usage, vim.log.levels.ERROR)
      return
    end
    callback(opts.fargs)
  end, { nargs = "+", desc = desc })
end

local function split_lines(text)
  if not text or text == "" then
    return {}
  end
  return vim.split(text, "\n")
end

local function trim_empty_tail(lines)
  while #lines > 0 and lines[#lines] == "" do
    table.remove(lines)
  end
  return lines
end

local function decode_json_payload(content)
  if not content or content == "" then
    return nil
  end
  if vim.json and vim.json.decode then
    local ok, decoded = pcall(vim.json.decode, content)
    if ok then
      return decoded
    end
  end
  if vim.fn and vim.fn.json_decode then
    local ok, decoded = pcall(vim.fn.json_decode, content)
    if ok then
      return decoded
    end
  end
  return nil
end

local function formatted_documentation_to_markdown(payload)
  local decoded = decode_json_payload(payload)
  if not decoded or decoded.Kind ~= "formattedDocumentation" or type(decoded.Data) ~= "table" then
    return nil
  end

  local data = decoded.Data
  local lines = {}

  if data.Signature and data.Signature ~= "" then
    vim.list_extend(lines, { "```fsharp", data.Signature, "```", "" })
  end

  if data.Comment and data.Comment ~= "" then
    vim.list_extend(lines, split_lines(data.Comment))
    table.insert(lines, "")
  end

  if type(data.FooterLines) == "table" and #data.FooterLines > 0 then
    vim.list_extend(lines, data.FooterLines)
  end

  return #trim_empty_tail(lines) > 0 and lines or nil
end

local function formatted_documentation_metadata(payload)
  local decoded = decode_json_payload(payload)
  if not decoded or decoded.Kind ~= "formattedDocumentation" or type(decoded.Data) ~= "table" then
    return nil
  end
  return decoded.Data
end

local function help_payload_to_markdown(payload)
  local decoded = decode_json_payload(payload)
  if not decoded or decoded.Kind ~= "help" then
    return nil
  end
  if type(decoded.Data) ~= "string" or decoded.Data == "" then
    return nil
  end
  return split_lines(decoded.Data)
end

local function unresolved_external_doc_note(symbolRequest)
  if not symbolRequest then
    return nil
  end
  local lines = {
    "_FsAutoComplete could not resolve external XML documentation for this symbol._",
  }
  if symbolRequest.Assembly and symbolRequest.Assembly ~= "" then
    table.insert(lines, "Assembly: `" .. symbolRequest.Assembly .. "`")
  end
  if symbolRequest.XmlSig and symbolRequest.XmlSig ~= "" then
    table.insert(lines, "XmlDocSig: `" .. symbolRequest.XmlSig .. "`")
  end
  return lines
end

local function extract_documentation_symbol_request(markdown_lines)
  local text = table.concat(markdown_lines or {}, "\n")
  local encoded = text:match("command:fsharp%.showDocumentation%?([^'%)%s>]+)")
  if not encoded then
    return nil
  end

  local decoded = vim.fn.json_decode(vim.uri_decode(encoded))
  local first = type(decoded) == "table" and decoded[1] or nil
  if not first or not first.XmlDocSig or first.XmlDocSig == "" or not first.AssemblyName or first.AssemblyName == "" then
    return nil
  end

  return {
    XmlSig = first.XmlDocSig,
    Assembly = first.AssemblyName,
  }
end

local function hover_result_to_lines(result)
  if not result or not result.contents then
    return {}
  end

  local contents = result.contents
  if type(contents) == "string" then
    return split_lines(contents)
  end

  if type(contents) == "table" and contents.kind and contents.value then
    return split_lines(contents.value)
  end

  local lines = {}
  if type(contents) == "table" then
    for _, item in ipairs(contents) do
      if type(item) == "string" then
        vim.list_extend(lines, split_lines(item))
      elseif type(item) == "table" and item.value then
        if item.language then
          vim.list_extend(lines, { "```" .. item.language })
          vim.list_extend(lines, split_lines(item.value))
          vim.list_extend(lines, { "```" })
        else
          vim.list_extend(lines, split_lines(item.value))
        end
      end
    end
  end
  return lines
end

local function sanitize_hover_lines(lines)
  local sanitized = {}
  for _, line in ipairs(lines or {}) do
    local cleaned = line
      :gsub("<a href='command:fsharp%.showDocumentation%?[^']*'>", "")
      :gsub("</a>", "")
      :gsub("^%s*Open the documentation%s*$", "")
    if cleaned ~= "" then
      table.insert(sanitized, cleaned)
    end
  end
  local filtered = {}
  local previous_blank = false
  for _, line in ipairs(sanitized) do
    local is_blank = line:match("^%s*$") ~= nil
    if not (is_blank and previous_blank) then
      table.insert(filtered, line)
    end
    previous_blank = is_blank
  end
  return trim_empty_tail(filtered)
end

local function strip_redundant_signature_block(hover_lines)
  if not hover_lines or vim.tbl_isempty(hover_lines) then
    return hover_lines
  end

  local result = {}
  local i = 1
  while i <= #hover_lines do
    if hover_lines[i]:match("^```") then
      i = i + 1
      while i <= #hover_lines and not hover_lines[i]:match("^```") do
        i = i + 1
      end
      if i <= #hover_lines and hover_lines[i]:match("^```") then
        i = i + 1
      end
    else
      table.insert(result, hover_lines[i])
      i = i + 1
    end
  end
  return trim_empty_tail(result)
end

local function has_nonempty_line(lines)
  for _, line in ipairs(lines or {}) do
    if line and line:match("%S") then
      return true
    end
  end
  return false
end

local function diagnostic_severity_label(severity)
  if not vim.diagnostic or not vim.diagnostic.severity then
    return "INFO"
  end
  for name, value in pairs(vim.diagnostic.severity) do
    if value == severity then
      return name
    end
  end
  return "INFO"
end

local function diagnostics_to_markdown(bufnr, line)
  if not vim.diagnostic or not vim.diagnostic.get then
    return {}
  end

  local diagnostics = vim.diagnostic.get(bufnr, { lnum = line })
  if not diagnostics or vim.tbl_isempty(diagnostics) then
    return {}
  end

  local lines = { "", "### Diagnostics" }
  for _, diagnostic in ipairs(diagnostics) do
    local severity = diagnostic_severity_label(diagnostic.severity)
    local source = diagnostic.source and (" [" .. diagnostic.source .. "]") or ""
    table.insert(lines, string.format("- **%s**%s: %s", severity, source, diagnostic.message or ""))
  end
  return lines
end

local function merge_docs_and_diagnostics(doc_lines, diagnostic_lines)
  local lines = {}
  if doc_lines and not vim.tbl_isempty(doc_lines) then
    vim.list_extend(lines, doc_lines)
  end
  if diagnostic_lines and not vim.tbl_isempty(diagnostic_lines) then
    vim.list_extend(lines, diagnostic_lines)
  end
  return trim_empty_tail(lines)
end

local function current_position_params()
  local line, col = unpack(vim.api.nvim_win_get_cursor(0))
  local file = vim.api.nvim_buf_get_name(0)
  return file, line - 1, col
end

function M.notify(msg, level, opts)
  local safeMessage = "[Ionide] - "
  if type(msg) == "string" then
    safeMessage = safeMessage .. msg
  else
    safeMessage = safeMessage .. vim.inspect(msg)
  end
  vim.notify(safeMessage, level, opts)
end

function M.GetRoot(n)
  local root
  root = root or util.root_pattern("*.slnx")(n)
  if root then
    return root
  end
  root = root or util.root_pattern("*.sln")(n)
  if root then
    return root
  end
  root = root or util.root_pattern("*.fsproj")(n)
  if root then
    return root
  end
  root = root or util.root_pattern("*.fsx")(n)
  if root then
    return root
  end
  root = util.find_git_ancestor(n)
  if root then
    return root
  end
  return root
end

---@return table<string []>
M.GetDefaultEnvVarsForRoot = function(root)
  local output, err = run_dotnet_version(root)
  if not output then
    -- Error running dotnet --version, return empty args
    return {}
  end

  local sdk_version = parse_semver(output)
  local sdk_tfm = tfm_for_sdk_version(sdk_version)
  local fsac_tfm = sdk_tfm -- Assume FSAC TFM matches SDK TFM
  local should_apply_implicit_roll_forward = sdk_tfm ~= fsac_tfm
  local envs = {}
  -- Set environment variables if needed
  if should_apply_implicit_roll_forward or sdk_version.prerelease then
    if should_apply_implicit_roll_forward then
      vim.list_extend(envs, { { "DOTNET_ROLL_FORWARD", "LatestMajor" } })
    end
    if sdk_version.prerelease then
      vim.list_extend(envs, { { "DOTNET_ROLL_FORWARD_TO_PRERELEASE", "1" } })
    end
  end

  return envs
end

---@return string []
M.GetDefaultDotnetArgsForRoot = function(root)
  local output, err = run_dotnet_version(root)
  if not output then
    -- Error running dotnet --version, return empty args
    return {}
  end

  local sdk_version = parse_semver(output)
  local sdk_tfm = tfm_for_sdk_version(sdk_version)
  local fsac_tfm = sdk_tfm -- Assume FSAC TFM matches SDK TFM
  local should_apply_implicit_roll_forward = sdk_tfm ~= fsac_tfm

  local args = {}
  if should_apply_implicit_roll_forward then
    table.insert(args, "--roll-forward")
    table.insert(args, "LatestMajor")
  end
  if sdk_version.prerelease then
    table.insert(args, "--roll-forward-to-prerelease")
    table.insert(args, "1")
  end
  return args
end

---@table<string,function>
M.Handlers = {
  [""] = function(err, rs, ctx, config)
    M.notify("if you're seeing this called, something went wrong, it's key is literally an empty string.  ")
  end,
  ["fsharp/notifyWorkspace"] = notify_content(vim.log.levels.DEBUG),
  ["fsharp/notifyWorkspacePeek"] = notify_content(vim.log.levels.DEBUG),
  ["fsharp/notifyCancel"] = notify_content(vim.log.levels.DEBUG),
  ["fsharp/fileParsed"] = notify_content(vim.log.levels.DEBUG),
  ["fsharp/documentAnalyzed"] = function(err, rs, ctx, config)
    if not (M.MergedConfig and M.MergedConfig.IonideNvimSettings and M.MergedConfig.IonideNvimSettings.AutomaticCodeLensRefresh) then
      return
    end

    local textDocument = rs and rs.TextDocument
    local uri = textDocument and (textDocument.uri or textDocument.Uri)
    if not uri then
      return
    end

    local bufnr = vim.uri_to_bufnr and vim.uri_to_bufnr(uri) or 0
    vim.lsp.codelens.refresh({ bufnr = bufnr })
  end,
  ["fsharp/testDetected"] = function(err, rs, ctx, config)
    if rs and rs.File then
      M.State.test_detection[rs.File] = rs.Tests or {}
    end
  end,
}

---@type IonideOptions
M.MergedConfig = {}

---@type _.lspconfig.settings.fsautocomplete.FSharp
M.DefaultServerSettings = {

  -- `addFsiWatcher`,
  addFsiWatcher = false,
  -- `addPrivateAccessModifier`,
  addPrivateAccessModifier = false,
  -- `autoRevealInExplorer`,
  autoRevealInExplorer = "sameAsFileExplorer",
  -- `disableFailedProjectNotifications`,
  disableFailedProjectNotifications = false,
  -- `enableMSBuildProjectGraph`,
  enableMSBuildProjectGraph = true,
  -- `enableReferenceCodeLens`,
  enableReferenceCodeLens = true,
  -- `enableTouchBar`,
  enableTouchBar = true,
  -- `enableTreeView`,
  enableTreeView = true,
  -- `fsiSdkFilePath`,
  fsiSdkFilePath = "",
  -- `infoPanelReplaceHover`,
  --  Not relevant to Neovim, currently
  --  if there's a big demand I'll consider making one.
  infoPanelReplaceHover = false,
  -- `infoPanelShowOnStartup`,
  infoPanelShowOnStartup = false,
  -- `infoPanelStartLocked`,
  infoPanelStartLocked = false,
  -- `infoPanelUpdate`,
  infoPanelUpdate = "never",
  -- `inlineValues`, https://github.com/ionide/ionide-vscode-fsharp/issues/1963   https://github.com/ionide/FsAutoComplete/issues/1214
  inlineValues = { enabled = false, prefix = "  // " },
  --includeAnalyzers
  includeAnalyzers = {},
  --excludeAnalyzers
  excludeAnalyzers = {},
  unnecessaryParenthesesAnalyzer = true,
  -- `msbuildAutoshow`,
  --  Not relevant to Neovim, currently
  msbuildAutoshow = false,
  -- `notifications`,
  -- notifications = { trace = false, traceNamespaces = { "BoundModel.TypeCheck", "BackgroundCompiler." } },
  -- `openTelemetry`,
  -- openTelemetry = { enabled = false },
  -- `pipelineHints`,
  -- pipelineHints = { enabled = true, prefix = "  // " },
  -- `saveOnSendLastSelection`,
  saveOnSendLastSelection = false,
  -- `showExplorerOnStartup`,
  --  Not relevant to Neovim, currently
  showExplorerOnStartup = false,
  -- `showProjectExplorerIn`,
  --  Not relevant to Neovim, currently
  showProjectExplorerIn = "fsharp",
  -- `simplifyNameAnalyzerExclusions`,
  --  Not relevant to Neovim, currently
  simplifyNameAnalyzerExclusions = { ".*\\.g\\.fs", ".*\\.cg\\.fs" },
  -- `smartIndent`,
  --  Not relevant to Neovim, currently
  smartIndent = true,
  -- `suggestGitignore`,
  suggestGitignore = true,
  -- `trace`,
  trace = { server = "off" },
  -- `unusedDeclarationsAnalyzerExclusions`,
  unusedDeclarationsAnalyzerExclusions = { ".*\\.g\\.fs", ".*\\.cg\\.fs" },
  -- `unusedOpensAnalyzerExclusions`,
  unusedOpensAnalyzerExclusions = { ".*\\.g\\.fs", ".*\\.cg\\.fs" },
  -- `verboseLogging`,
  verboseLogging = false,
  -- `workspacePath`
  workspacePath = "",
  -- `TestExplorer` = "",
  --  Not relevant to Neovim, currently
  TestExplorer = { AutoDiscoverTestsOnLoad = true },

  --   { AutomaticWorkspaceInit: bool option AutomaticWorkspaceInit = false
  --     WorkspaceModePeekDeepLevel: int option WorkspaceModePeekDeepLevel = 2
  workspaceModePeekDeepLevel = 4,
  fcs = { transparentCompiler = { enabled = true } },
  fsac = {
    attachDebugger = false,
    -- cachedTypeCheckCount = 200,
    conserveMemory = true,
    silencedLogs = {},
  },

  enableAdaptiveLspServer = true,
  --     ExcludeProjectDirectories: string[] option = [||]
  excludeProjectDirectories = { "paket-files", ".fable", "packages", "node_modules" },
  --     KeywordsAutocomplete: bool option false
  keywordsAutocomplete = true,
  --     fullNameExternalAutocomplete: bool option false
  fullNameExternalAutocomplete = false,
  --     ExternalAutocomplete: bool option false
  externalAutocomplete = false,
  --     Linter: bool option false
  linter = true,
  --     IndentationSize: int option 4
  indentationSize = 2,
  --     UnionCaseStubGeneration: bool option false
  unionCaseStubGeneration = true,
  --     UnionCaseStubGenerationBody: string option """failwith "Not Implemented" """
  unionCaseStubGenerationBody = 'failwith "Not Implemented"',
  --     RecordStubGeneration: bool option false
  recordStubGeneration = true,
  --     RecordStubGenerationBody: string option "failwith \"Not Implemented\""
  recordStubGenerationBody = 'failwith "Not Implemented"',
  --     InterfaceStubGeneration: bool option false
  interfaceStubGeneration = true,
  --     InterfaceStubGenerationObjectIdentifier: string option "this"
  interfaceStubGenerationObjectIdentifier = "this",
  --     InterfaceStubGenerationMethodBody: string option "failwith \"Not Implemented\""
  interfaceStubGenerationMethodBody = 'failwith "Not Implemented"',
  --     UnusedOpensAnalyzer: bool option false
  unusedOpensAnalyzer = true,
  --     UnusedDeclarationsAnalyzer: bool option false
  unusedDeclarationsAnalyzer = true,
  --     SimplifyNameAnalyzer: bool option false
  simplifyNameAnalyzer = true,
  --     ResolveNamespaces: bool option false
  resolveNamespaces = true,
  --     EnableAnalyzers: bool option false
  enableAnalyzers = true,
  --     AnalyzersPath: string[] option
  analyzersPath = { "packages/Analyzers", "analyzers" },
  --     DisableInMemoryProjectReferences: bool option false|
  -- disableInMemoryProjectReferences = false,

  -- LineLens: LineLensConfig option
  -- lineLens = { enabled = "always", prefix = "ll//" },

  -- enables the use of .Net Core SDKs for script file type-checking and evaluation,
  -- otherwise the .Net Framework reference lists will be used.
  -- Recommended default value: `true`.
  --
  useSdkScripts = true,

  suggestSdkScripts = true,
  -- DotNetRoot - the path to the dotnet sdk. usually best left alone, the compiler searches for this on it's own,
  dotnetRoot = "",

  -- FSIExtraParameters: string[]
  -- an array of additional runtime arguments that are passed to FSI.
  -- These are used when typechecking scripts to ensure that typechecking has the same context as your FSI instances.
  -- An example would be to set the following parameters to enable Preview features (like opening static classes) for typechecking.
  -- defaults to {}
  fsiExtraParameters = {},

  -- FSICompilerToolLocations: string[]|nil
  -- passes along this list of locations to compiler tools for FSI to the FSharpCompilerServiceChecker
  -- to this function in fsautocomplete
  -- https://github.com/fsharp/FsAutoComplete/blob/main/src/FsAutoComplete/LspServers/AdaptiveFSharpLspServer.fs#L99
  -- which effectively just prepends "--compilertool:" to each entry and tells the FSharpCompilerServiceChecker about it and the fsiExtraParameters
  fsiCompilerToolLocations = {},

  -- TooltipMode: string option
  -- TooltipMode can be one of the following:
  -- "full" ->  this provides the most verbose output
  -- "summary" -> this is a slimmed down version of the tooltip
  -- "" or nil -> this is the old or default way, and calls TipFormatter.FormatCommentStyle.Legacy on the lsp server... *shrug*
  tooltipMode = "full",

  -- GenerateBinlog
  -- if true, binary logs will be generated and placed in the directory specified. They will have names of the form `{directory}/{project_name}.binlog`
  -- defaults to false
  generateBinlog = false,
  abstractClassStubGeneration = true,
  abstractClassStubGenerationObjectIdentifier = "this",
  abstractClassStubGenerationMethodBody = 'failwith "Not Implemented"',

  -- configures which parts of the CodeLens are enabled, if any
  -- defaults to both signature and references being true
  codeLenses = {
    signature = { enabled = true },
    references = { enabled = true },
  },
}

-- used for "fsharp/documentationSymbol" - accepts DocumentationForSymbolReuqest,
-- returns documentation data about given symbol from given assembly, used for InfoPanel
-- original fsharp type declaration :
-- type DocumentationForSymbolReuqest = { XmlSig: string; Assembly: string }
---@class FSharpDocumentationForSymbolRequest
---@field XmlSig string
---@field Assembly string

---Creates a DocumentationForSymbolRequest from the xmlSig and assembly strings
---@param xmlSig string
---@param assembly string
---@return FSharpDocumentationForSymbolRequest
function M.DocumentationForSymbolRequest(xmlSig, assembly)
  ---@type FSharpDocumentationForSymbolRequest
  local result = {
    XmlSig = xmlSig,
    Assembly = assembly,
  }
  return result
end

---@type IonideNvimSettings
M.DefaultNvimSettings = {
  FsautocompleteCommand = { "fsautocomplete" },
  UseRecommendedServerConfig = false,
  AutomaticWorkspaceInit = true,
  AutomaticReloadWorkspace = false,
  AutomaticCodeLensRefresh = false,
  ShowSignatureOnCursorMove = false,
  UseIonideDocumentationHover = false,
  FsiCommand = "dotnet fsi",
  FsiKeymap = "vscode",
  FsiWindowCommand = "botright 10new",
  FsiFocusOnSend = false,
  EnableFsiStdOutTeeToFile = false,
  LspAutoSetup = false,
  LspRecommendedColorScheme = false,
  FsiVscodeKeymaps = true,
  FsiStdOutFileName = "",
  StatusLine = "Ionide",
  AutocmdEvents = {
    "LspAttach",
  },
  FsiKeymapSend = "<M-cr>",
  FsiKeymapToggle = "<M-@>",
  AddFSharpKeymaps = true,
}

---@type IonideOptions
M.DefaultLspConfig = {
  IonideNvimSettings = M.DefaultNvimSettings,
  filetypes = { "fsharp", "fsharp_project" },
  name = "ionide",
  cmd = M.DefaultNvimSettings.FsautocompleteCommand,

  root_dir = function(bufnr, on_dir)
    -- NOTE: do NOT shadow `bufnr` — it is the correct buffer passed by Neovim 0.10+.
    -- The old `local bufnr = vim.api.nvim_get_current_buf()` introduced a race
    -- when multiple files were opened simultaneously (wrong buffer's root was used).
    local bufname = vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr))
    local root = M.GetRoot(bufname)

    return on_dir(root)
  end,
  -- root_markers = { "*.slnx", "*.sln", "*.fsproj", ".git" },
  -- autostart = true,
  settings = { FSharp = M.DefaultServerSettings },
  log_level = vim.lsp.protocol.MessageType.Warning,
  message_level = vim.lsp.protocol.MessageType.Warning,
  handlers = M.Handlers,
  capabilities = vim.lsp.protocol.make_client_capabilities(),
}

---@type IonideOptions
M.PassedInConfig = { settings = { FSharp = {} } }

M.Manager = nil

---@param content any
---@returns PlainNotification
function M.PlainNotification(content)
  return { Content = content }
end

---creates a textDocumentIdentifier from a string path
---@param path string
---@return lsp.TextDocumentIdentifier
function M.TextDocumentIdentifier(path)
  -- vim.uri_from_fname handles Windows drive letters, forward/backslash normalisation,
  -- and URI percent-encoding correctly — including on Windows with or without shellslash.
  -- This replaces the previous hand-rolled implementation that temporarily mutated
  -- vim.o.shellslash (a global side effect that could be left permanently changed if
  -- the code inside errored before restoring the original value).
  ---@type lsp.TextDocumentIdentifier
  return { uri = vim.uri_from_fname(vim.fs.normalize(path)) }
end

---Creates an lsp.Position from a line and character number
---@param line integer
---@param character integer
---@return lsp.Position
function M.Position(line, character)
  return { Line = line, Character = character }
end

---Creates a TextDocumentPositionParams from a documentUri , line number and character number
---@param documentUri string
---@param line integer
---@param character integer
---@return lsp.TextDocumentPositionParams
function M.TextDocumentPositionParams(documentUri, line, character)
  return {
    TextDocument = M.TextDocumentIdentifier(documentUri),
    Position = M.Position(line, character),
  }
end

---creates a ProjectParms for fsharp/project call
---@param projectUri string
---@return FSharpProjectParams
function M.CreateFSharpProjectParams(projectUri)
  local tdi = M.TextDocumentIdentifier(projectUri)
  M.notify("projectUri: " .. vim.inspect(tdi), vim.log.levels.DEBUG)
  return {

    Project = tdi,
  }
end

---Creates an FSharpWorkspacePeekRequest from a directory string path, the workspaceModePeekDeepLevel integer and excludedDirs list
---@param directory string
---@param deep integer
---@param excludedDirs string[]
---@return FSharpWorkspacePeekRequest
function M.CreateFSharpWorkspacePeekRequest(directory, deep, excludedDirs)
  return {
    Directory = vim.fs.normalize(directory),
    Deep = deep,
    ExcludedDirs = excludedDirs,
  }
end

---creates an fsdn request
---NOTE: FSAC docs indicate this service is no longer available.
---@deprecated Use online F# documentation search instead.
---@param query string
---@return FsdnRequest
function M.FsdnRequest(query)
  return { Query = query }
end

---Creates FSharpWorkspaceLoadParams from the string list of Project files to load given.
---@param files string[] -- project files only..
---@return FSharpWorkspaceLoadParams
function M.CreateFSharpWorkspaceLoadParams(files)
  local prm = {}
  for _, file in ipairs(files) do
    -- if stringEndsWith(file,"proj") then
    table.insert(prm, M.TextDocumentIdentifier(file))
    -- end
  end
  return { TextDocuments = prm }
end

--- if nil then it will try to use the method of the same name
--- in M.Handlers from Ionide, if it exists.
--- if that returns nil, then the vim.lsp.buf_notify() request
--- should fallback to the normal built in
--- vim.lsp.handlers\[["some/lspMethodNameHere"]\] general execution strategy
---
---@return table<integer, integer>, fun() 2-tuple:
---  - Map of client-id:request-id pairs for all successful requests.
---  - Function which can be used to cancel all the requests. You could instead
---    iterate all clients and call their `cancel_request()` methods.
function M.Call(method, params, handler)
  local bufnr = vim.api.nvim_get_current_buf()
  local clients = M.GetIonideClients({ bufnr = bufnr })
  if #clients == 0 then
    M.notify("LSP method " .. method .. " is not supported by any ionide LSP client", vim.log.levels.WARN)
    return {}, function() end
  end

  local request_ids = {}
  local function cancel_all()
    for client_id, request_id in pairs(request_ids) do
      local client = vim.lsp.get_client_by_id(client_id)
      if client and client.cancel_request then
        pcall(client.cancel_request, client, request_id)
      end
    end
  end

  for _, client in ipairs(clients) do
    local ok, request_id = pcall(function()
      return client:request(method, params, handler, bufnr)
    end)
    if ok and request_id ~= nil then
      request_ids[client.id] = request_id
    end
  end

  if vim.tbl_isempty(request_ids) then
    M.notify("LSP method " .. method .. " is not supported by any ionide LSP client", vim.log.levels.WARN)
  end

  return request_ids, cancel_all
end

function M.ShowDocumentationHover(opts)
  local config = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()
  -- Bail out silently if no Ionide (FSAC) client is attached to this buffer.
  -- Prevents "Method not found: fsharp/documentation" errors and
  -- "fsharp/f1Help is not supported" warnings when K is pressed in non-F# buffers.
  if vim.tbl_isempty(M.GetIonideClients({ bufnr = bufnr })) then
    vim.lsp.buf.hover(config)
    return
  end
  local filePath, line, character = current_position_params()
  local debug_hover = config.debug == true
  local function trace(...)
    if not debug_hover then
      return
    end
    local parts = { "[Ionide hover]" }
    for i = 1, select("#", ...) do
      table.insert(parts, tostring(select(i, ...)))
    end
    vim.notify(table.concat(parts, " "))
  end

  local function show_lines(doc_lines)
    if not has_nonempty_line(doc_lines) then
      trace("show_lines", "skipped-empty")
      return false
    end
    local merged = merge_docs_and_diagnostics(doc_lines or {}, diagnostics_to_markdown(bufnr, line))
    if not vim.tbl_isempty(merged) then
      trace("show_lines", "opening-float", #merged)
      vim.lsp.util.open_floating_preview(merged, "markdown", {
        border = config.border,
        focus_id = "ionide/fsharp/documentation",
      })
      return true
    end
    trace("show_lines", "merged-empty")
    return false
  end

  local function fallback_hover()
    trace("fallback_hover")
    vim.lsp.buf.hover(config)
  end

  local function show_sanitized_hover(results)
    local hover_lines = {}
    for _, resp in pairs(results or {}) do
      if resp and resp.result then
        vim.list_extend(hover_lines, sanitize_hover_lines(hover_result_to_lines(resp.result)))
      end
    end
    if not has_nonempty_line(hover_lines) then
      return false
    end
    return show_lines(hover_lines)
  end

  local function sanitized_hover_lines(results)
    local hover_lines = {}
    for _, resp in pairs(results or {}) do
      if resp and resp.result then
        vim.list_extend(hover_lines, sanitize_hover_lines(hover_result_to_lines(resp.result)))
      end
    end
    if not has_nonempty_line(hover_lines) then
      return nil
    end
    return hover_lines
  end

  local function show_combined_lines(primary_lines, secondary_lines, extra_lines)
    local merged = {}
    if primary_lines and not vim.tbl_isempty(primary_lines) then
      vim.list_extend(merged, primary_lines)
    end
    if secondary_lines and not vim.tbl_isempty(secondary_lines) then
      if has_nonempty_line(merged) and has_nonempty_line(secondary_lines) then
        table.insert(merged, "")
      end
      vim.list_extend(merged, secondary_lines)
    end
    if extra_lines and not vim.tbl_isempty(extra_lines) then
      if has_nonempty_line(merged) and has_nonempty_line(extra_lines) then
        table.insert(merged, "")
      end
      vim.list_extend(merged, extra_lines)
    end
    return show_lines(merged)
  end

  return M.CallFSharpDocumentation(filePath, line, character, function(err, result, ctx, lsp_config)
    trace("documentation", err and "error" or "ok", result and result.Content and "has-content" or "no-content")
    if err then
      if config.silent ~= true then
        M.notify(err.message or "Failed to fetch F# documentation", vim.log.levels.ERROR)
      end
      return
    end

    local lines = result and result.Content and formatted_documentation_to_markdown(result.Content)
    local documentationMetadata = result and result.Content and formatted_documentation_metadata(result.Content)
    trace("documentation-lines", has_nonempty_line(lines) and "yes" or "no")

    return vim.lsp.buf_request_all(0, "textDocument/hover", M.TextDocumentPositionParams(filePath, line, character), function(results)
      trace("hover-results", results and "received" or "nil")
      local symbolRequest = nil
      for _, resp in pairs(results or {}) do
        if resp and resp.result then
          symbolRequest = extract_documentation_symbol_request(hover_result_to_lines(resp.result)) or symbolRequest
        end
      end
      trace("symbol-request", symbolRequest and (symbolRequest.XmlSig .. " @ " .. symbolRequest.Assembly) or "none")

      if symbolRequest then
        return M.CallFSharpDocumentationSymbol(symbolRequest.XmlSig, symbolRequest.Assembly, function(symbolErr, symbolResult)
          trace("documentationSymbol", symbolErr and "error" or "ok", symbolResult and symbolResult.Content and "has-content" or "no-content")
          local symbolLines = symbolResult and symbolResult.Content and formatted_documentation_to_markdown(symbolResult.Content)
          local symbolMetadata = symbolResult and symbolResult.Content and formatted_documentation_metadata(symbolResult.Content)
          local unresolvedNote = nil
          if not has_nonempty_line(symbolLines) or (symbolMetadata and symbolMetadata.Comment == "") then
            unresolvedNote = unresolved_external_doc_note(symbolRequest)
          end

          return M.F1Help(filePath, line, character, function(helpErr, helpResult)
            trace("f1help", helpErr and "error" or "ok", helpResult and helpResult.Content and "has-content" or "no-content")
            local helpLines = helpResult and helpResult.Content and help_payload_to_markdown(helpResult.Content)
            local hoverLines = strip_redundant_signature_block(sanitized_hover_lines(results))
            local extra = {}
            if helpLines and not vim.tbl_isempty(helpLines) then
              vim.list_extend(extra, helpLines)
            end
            if hoverLines and not vim.tbl_isempty(hoverLines) then
              vim.list_extend(extra, hoverLines)
            end
            if unresolvedNote and not vim.tbl_isempty(unresolvedNote) then
              if has_nonempty_line(extra) then
                table.insert(extra, "")
              end
              vim.list_extend(extra, unresolvedNote)
            end

            if show_combined_lines(symbolLines or lines, nil, extra) then
              trace("final", "combined-symbol-success")
              return
            end
            trace("final", "combined-symbol-failed")
            fallback_hover()
          end)
        end)
      end

      return M.F1Help(filePath, line, character, function(helpErr, helpResult)
        trace("f1help", helpErr and "error" or "ok", helpResult and helpResult.Content and "has-content" or "no-content")
        local helpLines = helpResult and helpResult.Content and help_payload_to_markdown(helpResult.Content)
        local hoverLines = strip_redundant_signature_block(sanitized_hover_lines(results))
        local unresolved = documentationMetadata and documentationMetadata.Comment == "" and { "", "_FsAutoComplete could not resolve external XML documentation for this symbol._" } or nil
        local extra = {}
        if helpLines and not vim.tbl_isempty(helpLines) then
          vim.list_extend(extra, helpLines)
        end
        if hoverLines and not vim.tbl_isempty(hoverLines) then
          vim.list_extend(extra, hoverLines)
        end
        if unresolved and not vim.tbl_isempty(unresolved) then
          if has_nonempty_line(extra) then
            table.insert(extra, "")
          end
          vim.list_extend(extra, unresolved)
        end

        if show_combined_lines(lines, nil, extra) then
          trace("final", "combined-doc-success")
          return
        end
        trace("final", "combined-doc-failed")
        fallback_hover()
      end)
    end)
  end)
end

---Returns true if the given LSP client is an Ionide / fsautocomplete client.
---@param client vim.lsp.Client
---@return boolean
function M.IsIonideClient(client)
  if not client then return false end
  return client.name == "ionide" or client.name == "fsautocomplete"
end

function M.GetIonideClients(filter)
  local candidates = vim.lsp.get_clients(filter or {})
  local results = {}
  for _, client in ipairs(candidates) do
    if M.IsIonideClient(client) then
      table.insert(results, client)
    end
  end
  return results
end

function M.CallLspNotify(method, params)
  -- Check if any ionide clients are available (with safety check for test environment)
  if vim.lsp and vim.lsp.get_clients then
    local clients = M.GetIonideClients({ bufnr = vim.api.nvim_get_current_buf() })
    if #clients == 0 then
      M.notify("No ionide LSP clients available for notification: " .. method, vim.log.levels.WARN)
      return
    end
  end

  -- Wrap in pcall for error safety
  local ok, err = pcall(vim.lsp.buf_notify, 0, method, params)
  if not ok then
    M.notify("Failed to send LSP notification " .. method .. ": " .. (err or "unknown error"), vim.log.levels.ERROR)
  end
end

function M.DotnetFile2Request(projectPath, currentVirtualPath, newFileVirtualPath)
  return {
    FsProj = projectPath,
    FileVirtualPath = currentVirtualPath,
    NewFile = newFileVirtualPath,
  }
end

---Creates a DotnetFileRequest for fsproj single-file operations
---@param projectPath string
---@param fileVirtualPath string
---@return DotnetFileRequest
function M.DotnetFileRequest(projectPath, fileVirtualPath)
  return {
    FsProj = projectPath,
    FileVirtualPath = fileVirtualPath,
  }
end

---Creates a DotnetRenameFileRequest
---@param projectPath string
---@param oldFileVirtualPath string
---@param newFileName string
---@return DotnetRenameFileRequest
function M.DotnetRenameFileRequest(projectPath, oldFileVirtualPath, newFileName)
  return {
    FsProj = projectPath,
    OldFileVirtualPath = oldFileVirtualPath,
    NewFileName = newFileName,
  }
end

function M.DotnetProjectRequest(target, reference)
  return {
    Target = target,
    Reference = reference,
  }
end

function M.DotnetNewListRequest(query)
  return {
    Query = query,
  }
end

function M.DotnetNewRunRequest(template, output, name)
  return {
    Template = template,
    Output = output,
    Name = name,
  }
end

function M.FSharpPipelineHintRequest(filePath)
  return {
    TextDocument = M.TextDocumentIdentifier(filePath),
  }
end

function M.OptionallyVersionedTextDocumentPositionParams(filePath, line, character, version)
  return {
    TextDocument = {
      uri = M.TextDocumentIdentifier(filePath).uri,
      version = version,
    },
    Position = M.Position(line, character),
  }
end

function M.TestRunRequest(limitToProjects, testCaseFilter, attachDebugger)
  return {
    LimitToProjects = limitToProjects,
    TestCaseFilter = testCaseFilter,
    AttachDebugger = attachDebugger == true,
  }
end

function M.CallFSharpAddFileAbove(projectPath, currentVirtualPath, newFileVirtualPath, handler)
  return M.Call(
    "fsproj/addFileAbove",
    M.DotnetFile2Request(projectPath, currentVirtualPath, newFileVirtualPath),
    handler
  )
end

---Adds a file below the specified file in the fsproj
---@param projectPath string
---@param currentVirtualPath string
---@param newFileVirtualPath string
---@param handler? fun(err: any, result: any, ctx: any, config: any)
function M.CallFSharpAddFileBelow(projectPath, currentVirtualPath, newFileVirtualPath, handler)
  return M.Call(
    "fsproj/addFileBelow",
    M.DotnetFile2Request(projectPath, currentVirtualPath, newFileVirtualPath),
    handler
  )
end

---Adds a new file to the fsproj
---@param projectPath string
---@param fileVirtualPath string
---@param handler? fun(err: any, result: any, ctx: any, config: any)
function M.CallFSharpAddFile(projectPath, fileVirtualPath, handler)
  return M.Call(
    "fsproj/addFile",
    M.DotnetFileRequest(projectPath, fileVirtualPath),
    handler
  )
end

---Adds an existing file to the fsproj
---@param projectPath string
---@param fileVirtualPath string
---@param handler? fun(err: any, result: any, ctx: any, config: any)
function M.CallFSharpAddExistingFile(projectPath, fileVirtualPath, handler)
  return M.Call(
    "fsproj/addExistingFile",
    M.DotnetFileRequest(projectPath, fileVirtualPath),
    handler
  )
end

---Removes a file from the fsproj
---@param projectPath string
---@param fileVirtualPath string
---@param handler? fun(err: any, result: any, ctx: any, config: any)
function M.CallFSharpRemoveFile(projectPath, fileVirtualPath, handler)
  return M.Call(
    "fsproj/removeFile",
    M.DotnetFileRequest(projectPath, fileVirtualPath),
    handler
  )
end

---Moves a file up in the fsproj compile order
---@param projectPath string
---@param fileVirtualPath string
---@param handler? fun(err: any, result: any, ctx: any, config: any)
function M.CallFSharpMoveFileUp(projectPath, fileVirtualPath, handler)
  return M.Call(
    "fsproj/moveFileUp",
    M.DotnetFileRequest(projectPath, fileVirtualPath),
    handler
  )
end

---Moves a file down in the fsproj compile order
---@param projectPath string
---@param fileVirtualPath string
---@param handler? fun(err: any, result: any, ctx: any, config: any)
function M.CallFSharpMoveFileDown(projectPath, fileVirtualPath, handler)
  return M.Call(
    "fsproj/moveFileDown",
    M.DotnetFileRequest(projectPath, fileVirtualPath),
    handler
  )
end

---Renames a file in the fsproj
---@param projectPath string
---@param oldFileVirtualPath string
---@param newFileName string
---@param handler? fun(err: any, result: any, ctx: any, config: any)
function M.CallFSharpRenameFile(projectPath, oldFileVirtualPath, newFileName, handler)
  return M.Call(
    "fsproj/renameFile",
    M.DotnetRenameFileRequest(projectPath, oldFileVirtualPath, newFileName),
    handler
  )
end

function M.CallFSharpDocumentationGenerator(filePath, line, character, handler)
  return M.Call(
    "fsharp/documentationGenerator",
    M.OptionallyVersionedTextDocumentPositionParams(filePath, line, character),
    handler
  )
end

function M.CallFSharpSignature(filePath, line, character, handler)
  return M.Call("fsharp/signature", M.TextDocumentPositionParams(filePath, line, character), handler)
end

function M.CallFSharpSignatureData(filePath, line, character, handler)
  return M.Call("fsharp/signatureData", M.TextDocumentPositionParams(filePath, line, character), handler)
end

-- deprecated
function M.CallFSharpLineLens(projectPath, handler)
  return M.Call("fsharp/lineLens", M.CreateFSharpProjectParams(projectPath), handler)
end

-- deprecated
function M.CallFSharpCompilerLocation(handler)
  return M.Call("fsharp/compilerLocation", {}, handler)
end

---Calls "fsharp/compile" on the given project file
---@param projectPath string
---@return table<integer, integer>, fun() 2-tuple:
---  - Map of client-id:request-id pairs for all successful requests.
---  - Function which can be used to cancel all the requests. You could instead
---    iterate all clients and call their `cancel_request()` methods.
function M.CallFSharpCompileOnProjectFile(projectPath, handler)
  return M.Call("fsharp/compile", M.CreateFSharpProjectParams(projectPath), handler)
end

---Calls "fsharp/workspacePeek" Lsp Endpoint of FsAutoComplete
---@param directoryPath string
---@param depth integer
---@param excludedDirs string[]
---@return table<integer, integer>, fun() 2-tuple:
---  - Map of client-id:request-id pairs for all successful requests.
---  - Function which can be used to cancel all the requests. You could instead
---    iterate all clients and call their `cancel_request()` methods.
function M.CallFSharpWorkspacePeek(directoryPath, depth, excludedDirs, handler)
  return M.Call("fsharp/workspacePeek", M.CreateFSharpWorkspacePeekRequest(directoryPath, depth, excludedDirs), handler)
end

---Call to "fsharp/workspaceLoad"
---@param projectFiles string[]  a string list of project files.
---@return table<integer, integer>, fun() 2-tuple:
---  - Map of client-id:request-id pairs for all successful requests.
---  - Function which can be used to cancel all the requests. You could instead
---    iterate all clients and call their `cancel_request()` methods.
function M.CallFSharpWorkspaceLoad(projectFiles, handler)
  M.notify("Loading workspace " .. vim.inspect(projectFiles), vim.log.levels.DEBUG)
  return M.Call("fsharp/workspaceLoad", M.CreateFSharpWorkspaceLoadParams(projectFiles), handler)
end

---call to "fsharp/project" - which, after using projectPath to create an FSharpProjectParms, loads given project
---@param projectPath string
---@return table<integer, integer>, fun() 2-tuple:
---  - Map of client-id:request-id pairs for all successful requests.
---  - Function which can be used to cancel all the requests. You could instead
---    iterate all clients and call their `cancel_request()` methods.
function M.CallFSharpProject(projectPath, handler)
  M.notify("Loading project " .. vim.inspect(projectPath), vim.log.levels.DEBUG)
  local p = M.CreateFSharpProjectParams(projectPath)
  return M.Call("fsharp/project", p, handler)
end

---@deprecated FSAC docs indicate the FSDN service is no longer available.
---@return table<integer, integer>, fun()
function M.Fsdn(signature, handler)
  M.notify("fsharp/fsdn is no longer available — the FSDN service is offline", vim.log.levels.WARN)
  return {}, function() end
end

---@return table<integer, integer>, fun() 2-tuple:
---  - Map of client-id:request-id pairs for all successful requests.
---  - Function which can be used to cancel all the requests. You could instead
---    iterate all clients and call their `cancel_request()` methods.
function M.F1Help(filePath, line, character, handler)
  return M.Call("fsharp/f1Help", M.TextDocumentPositionParams(filePath, line, character), handler)
end

--- call to "fsharp/documentation"
--- first creates a TextDocumentPositionParams,
--- requests data about symbol at given position, used for InfoPanel
---@param filePath string
---@param line integer
---@param character integer
---@return table<integer, integer>, fun() 2-tuple:
---  - Map of client-id:request-id pairs for all successful requests.
---  - Function which can be used to cancel all the requests. You could instead
---    iterate all clients and call their `cancel_request()` methods.
function M.CallFSharpDocumentation(filePath, line, character, handler)
  return M.Call("fsharp/documentation", M.TextDocumentPositionParams(filePath, line, character), handler)
end

---Calls "fsharp/documentationSymbol" Lsp endpoint on FsAutoComplete
---creates a DocumentationForSymbolRequest then sends that request to FSAC
---@param xmlSig string
---@param assembly string
---@return table<integer, integer>, fun() 2-tuple:
---  - Map of client-id:request-id pairs for all successful requests.
---  - Function which can be used to cancel all the requests. You could instead
---    iterate all clients and call their `cancel_request()` methods.
function M.CallFSharpDocumentationSymbol(xmlSig, assembly, handler)
  return M.Call("fsharp/documentationSymbol", M.DocumentationForSymbolRequest(xmlSig, assembly), handler)
end

function M.CallFSharpPipelineHint(filePath, handler)
  return M.Call("fsharp/pipelineHint", M.FSharpPipelineHintRequest(filePath), handler)
end

function M.CallFSharpDotnetNewList(query, handler)
  return M.Call("fsharp/dotnetnewlist", M.DotnetNewListRequest(query), handler)
end

function M.CallFSharpDotnetNewRun(template, output, name, handler)
  return M.Call("fsharp/dotnetnewrun", M.DotnetNewRunRequest(template, output, name), handler)
end

function M.CallFSharpDotnetAddProject(target, reference, handler)
  return M.Call("fsharp/dotnetaddproject", M.DotnetProjectRequest(target, reference), handler)
end

function M.CallFSharpDotnetRemoveProject(target, reference, handler)
  return M.Call("fsharp/dotnetremoveproject", M.DotnetProjectRequest(target, reference), handler)
end

function M.CallFSharpDotnetSlnAdd(target, reference, handler)
  return M.Call("fsharp/dotnetaddsln", M.DotnetProjectRequest(target, reference), handler)
end

function M.CallFSharpLoadAnalyzers(payload, handler)
  return M.Call("fsharp/loadAnalyzers", payload or {}, handler)
end

function M.CallTestDiscoverTests(handler)
  return M.Call("test/discoverTests", {}, handler)
end

function M.CallTestRunTests(limitToProjects, testCaseFilter, attachDebugger, handler)
  return M.Call("test/runTests", M.TestRunRequest(limitToProjects, testCaseFilter, attachDebugger), handler)
end

---Loads the given projects list.
---@param projects string[] -- projects only
function M.LoadProjects(projects)
  if projects then
    for _, proj in ipairs(projects) do
      if proj then
        M.CallFSharpProject(proj)
      end
    end
  end
end

---Reloads all loaded projects by requesting workspace load again.
function M.ReloadProjects()
  local clients = M.GetIonideClients()
  if #clients == 0 then
    M.notify("No ionide LSP clients available for reload", vim.log.levels.WARN)
    return
  end
  for _, client in ipairs(clients) do
    local root = client.config.root_dir
    if root then
      M.notify("Reloading workspace at " .. root)
      M.CallFSharpWorkspacePeek(root, M.MergedConfig.settings.FSharp.workspaceModePeekDeepLevel or 4, M.MergedConfig.settings.FSharp.excludeProjectDirectories or {})
    end
  end
end

local function supports_method(client, method, capability_key)
  if client == nil then
    return false
  end
  if client.supports_method and client:supports_method(method) then
    return true
  end
  if client.server_capabilities and capability_key then
    if client.server_capabilities[capability_key] ~= nil then
      return true
    end
    local lower = capability_key:sub(1, 1):lower() .. capability_key:sub(2)
    if client.server_capabilities[lower] ~= nil then
      return true
    end
  end
  return false
end

---Interactively rename the current F# source file on disk and update its .fsproj entry.
---Prompts for a new filename (pre-filled with the current name), renames the file on
---disk, updates the .fsproj via FSAC's fsproj/renameFile endpoint, and switches the
---current buffer to the new path.
---
---This is wired to <leader>cR in F# buffers to override the generic Snacks file-rename
---which calls workspace/willRenameFiles — a FSAC stub that does nothing.
function M.IonideRenameFileInteractive()
  local bufnr = vim.api.nvim_get_current_buf()
  local old_full_path = vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr))
  if old_full_path == "" then
    vim.notify("Ionide: buffer has no file path", vim.log.levels.WARN)
    return
  end

  local ext = old_full_path:match("%.([^./\\]+)$")
  if ext ~= "fs" and ext ~= "fsi" then
    vim.notify("Ionide: not an F# source file (" .. (ext or "no ext") .. ")", vim.log.levels.WARN)
    return
  end

  -- Find the nearest .fsproj directory
  local fsproj_dir = util.root_pattern("*.fsproj")(old_full_path)
  if not fsproj_dir then
    vim.notify("Ionide: could not find a .fsproj above " .. old_full_path, vim.log.levels.WARN)
    return
  end
  fsproj_dir = vim.fs.normalize(fsproj_dir)

  -- Glob for .fsproj files in that directory
  local fsproj_files = vim.fn.glob(fsproj_dir .. "/*.fsproj", false, true)
  if not fsproj_files or #fsproj_files == 0 then
    vim.notify("Ionide: no .fsproj found in " .. fsproj_dir, vim.log.levels.WARN)
    return
  end
  -- Use the first fsproj if there are multiple (edge case — single fsproj dirs are normal)
  local fsproj_path = vim.fs.normalize(fsproj_files[1])

  -- Virtual path = path of the file relative to the fsproj directory.
  -- e.g. fsproj_dir = "/repo/MyProject", old_full_path = "/repo/MyProject/src/Game.fs"
  -- → virtual_path = "src/Game.fs"
  --
  -- vim.fs.normalize() returns paths WITHOUT a trailing separator, so fsproj_dir is
  -- e.g. "/repo/MyProject" (no trailing "/"). We need to skip exactly one separator
  -- character (+1), not +2 which would eat the first character of the relative path.
  -- Use vim.fs.relpath when available (Neovim 0.10+); fall back to the substring
  -- arithmetic on older versions.
  local virtual_path
  if vim.fs.relpath then
    virtual_path = vim.fs.relpath(fsproj_dir, old_full_path)
  else
    -- fsproj_dir has no trailing separator (vim.fs.normalize guarantee), so skip
    -- exactly len+1 characters to consume the one "/" that separates dir from file.
    virtual_path = old_full_path:sub(#fsproj_dir + 1 + 1) -- +1 for separator
  end

  local old_filename = vim.fn.fnamemodify(old_full_path, ":t")
  local old_dir = vim.fn.fnamemodify(old_full_path, ":h")

  vim.ui.input(
    { prompt = "Rename F# file to: ", default = old_filename },
    function(new_name)
      if not new_name or new_name == "" or new_name == old_filename then
        return
      end

      local new_ext = new_name:match("%.([^./\\]+)$")
      if new_ext ~= "fs" and new_ext ~= "fsi" then
        vim.notify("Ionide: new name must have .fs or .fsi extension", vim.log.levels.WARN)
        return
      end

      local new_full_path = old_dir .. "/" .. new_name

      -- Step 1: update the .fsproj via FSAC FIRST.
      -- If FSAC fails we abort before touching the disk — keeping the project consistent.
      -- (Old order was disk-first, which left a renamed file with a stale .fsproj entry
      -- when FSAC returned an error.)
      M.CallFSharpRenameFile(fsproj_path, virtual_path, new_name, function(rename_err, _)
        if rename_err then
          vim.notify("Ionide: fsproj rename failed — disk file NOT renamed: " .. vim.inspect(rename_err), vim.log.levels.ERROR)
          return
        end

        -- Step 2: rename on disk (only reached when FSAC succeeded)
        local ok, err = vim.uv.fs_rename(old_full_path, new_full_path)
        if not ok then
          vim.notify(
            "Ionide: disk rename failed (WARNING: .fsproj was already updated): " .. (err or "unknown error"),
            vim.log.levels.ERROR
          )
          return
        end

        -- Step 3: point the buffer at the new path and reload.
        -- Scheduled so the LSP detach/reattach cycle doesn't race with the rename.
        vim.schedule(function()
          vim.api.nvim_buf_set_name(bufnr, new_full_path)
          vim.cmd("edit")
          M.notify("Renamed " .. old_filename .. " → " .. new_name, vim.log.levels.INFO)
        end)
      end)
    end
  )
end

function M.OnLspAttach(client, bufnr)
  local settings = (M.MergedConfig and M.MergedConfig.IonideNvimSettings) or M.DefaultNvimSettings

  if settings.UseIonideDocumentationHover == true then
    vim.keymap.set("n", "K", function()
      M.ShowDocumentationHover()
    end, { buffer = bufnr, desc = "Ionide - Show formatted F# documentation" })
  end

  if settings.AutomaticCodeLensRefresh == true and supports_method(client, "textDocument/codeLens", "CodeLensProvider") then
    vim.lsp.codelens.refresh({ bufnr = bufnr })
    create_buf_autocmd({ "BufEnter", "InsertLeave", "BufWritePost" }, "IonideCodeLens", bufnr, function()
      vim.lsp.codelens.refresh({ bufnr = bufnr })
    end)
  end

  if supports_method(client, "textDocument/documentHighlight", "DocumentHighlightProvider") then
    create_buf_autocmd({ "CursorHold", "CursorHoldI" }, "IonideDocumentHighlightHold", bufnr, function()
      vim.lsp.buf.document_highlight()
    end)
    create_buf_autocmd({ "CursorMoved", "CursorMovedI" }, "IonideDocumentHighlightMove", bufnr, function()
      vim.lsp.buf.clear_references()
    end)
  end

  if settings.ShowSignatureOnCursorMove == true and supports_method(client, "textDocument/signatureHelp", "SignatureHelpProvider") then
    create_buf_autocmd({ "CursorMovedI" }, "IonideSignatureHelp", bufnr, function()
      vim.lsp.buf.signature_help()
    end)
  end

  -- Buffer-local keymaps for F#-specific LSP actions.
  -- Only registered when AddFSharpKeymaps is not explicitly false, giving users
  -- a clean opt-out if they prefer their own bindings.
  if settings.AddFSharpKeymaps ~= false then
    -- Helper: returns true when no buffer-local keymap for `lhs` exists in `mode` yet.
    -- This prevents Ionide from silently overwriting a map already set by LazyVim
    -- (or another plugin) in its own LspAttach handler, depending on handler order.
    local function no_buf_map(mode, lhs)
      local existing = vim.fn.maparg(lhs, mode, false, true)
      -- maparg returns a table when a mapping exists; an empty string when it doesn't.
      -- For buffer-local maps, the table will have buffer=true (or a buffer number).
      if type(existing) == "table" and existing.buffer and existing.buffer ~= 0 then
        return false
      end
      return true
    end

    -- Symbol rename — available workspace-wide via FSAC's renameProvider
    if supports_method(client, "textDocument/rename", "RenameProvider") and no_buf_map("n", "<leader>cr") then
      vim.keymap.set("n", "<leader>cr", vim.lsp.buf.rename, {
        buffer = bufnr,
        desc = "Rename F# symbol (workspace-wide)",
      })
    end

    -- Code actions — exposes all 40+ FSAC code fixes (implement interface,
    -- generate union cases, add explicit type annotation, remove unused opens, …)
    -- Works in both normal and visual mode; visual mode passes the selection range.
    if supports_method(client, "textDocument/codeAction", "CodeActionProvider") then
      if no_buf_map("n", "<leader>ca") then
        vim.keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, {
          buffer = bufnr,
          desc = "F# code actions (fixes & refactors)",
        })
      end
    end

    -- File rename — renames the .fs file on disk AND updates the .fsproj entry.
    -- Overrides the generic Snacks file-rename which calls workspace/willRenameFiles
    -- (a FSAC stub that does nothing).
    -- <leader>cR is Ionide-specific — always set it; it's intentionally more capable
    -- than any generic file-rename that might be registered.
    vim.keymap.set("n", "<leader>cR", function()
      M.IonideRenameFileInteractive()
    end, {
      buffer = bufnr,
      desc = "Rename F# file (updates .fsproj)",
    })
  end
end

function M.OnNativeLspAttach(args)
  local bufnr = args.buf or vim.api.nvim_get_current_buf()
  -- Only act when an Ionide/fsautocomplete client is the one attaching.
  -- If a non-Ionide client (e.g. copilot, lua_ls) fires LspAttach on this
  -- buffer, ignore it — we don't want to re-run workspace init for every
  -- client that happens to attach.
  local attaching_client = args.data and args.data.client_id and vim.lsp.get_client_by_id(args.data.client_id)
  local clients
  if attaching_client then
    -- A specific client triggered this event: only proceed if it's Ionide.
    if not M.IsIonideClient(attaching_client) then return end
    clients = { attaching_client }
  else
    -- No client_id in args (legacy/manual call): fall back to all Ionide clients.
    clients = M.GetIonideClients({ bufnr = bufnr })
  end
  for _, client in ipairs(clients) do
    M.OnLspAttach(client, bufnr)
    if M.MergedConfig.IonideNvimSettings and M.MergedConfig.IonideNvimSettings.AutomaticWorkspaceInit ~= false then
      local root = client.config and client.config.root_dir or M.GetRoot(vim.api.nvim_buf_get_name(bufnr))
      if root then
        -- Send workspacePeek directly on the known client+bufnr to avoid
        -- M.Call re-querying nvim_get_current_buf(), which is wrong at LspAttach
        -- time and causes "fsharp/workspacePeek is not supported" warnings.
        local params = M.CreateFSharpWorkspacePeekRequest(
          root,
          M.MergedConfig.settings.FSharp.workspaceModePeekDeepLevel or 4,
          M.MergedConfig.settings.FSharp.excludeProjectDirectories or {}
        )
        pcall(function()
          client:request("fsharp/workspacePeek", params, nil, bufnr)
        end)
      end
    end
  end
end

function M.OnFSProjSave()
  if
    vim.bo.ft == "fsharp_project"
    and M.MergedConfig.IonideNvimSettings
    and M.MergedConfig.IonideNvimSettings.AutomaticReloadWorkspace == true
  then
    M.notify("fsharp project saved, reloading...")
    M.ReloadProjects()
  end
end

function M.RegisterAutocmds()
  -- vim.notify("Registering Ionide FSharp autocmds...")
  vim.api.nvim_create_autocmd("BufWritePost", {
    pattern = "*.fsproj",
    desc = "FSharp Auto refresh on project save",
    group = vim.api.nvim_create_augroup("FSProjRefreshOnProjectSave", { clear = true }),
    callback = function()
      M.OnFSProjSave()
    end,
  })

  vim.api.nvim_create_autocmd({ "BufReadPost" }, {
    desc = "FSharp start Ionide on fsharp_project load",
    group = vim.api.nvim_create_augroup("FSProjStartIonide", { clear = true }),
    pattern = "*.fsproj",
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      local bufname = vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr))
      local projectRoot = vim.fs.normalize(M.GetRoot(bufname))

      -- M.notify("Searching for Ionide client already started for root path of " .. projectRoot )
      local parentDir = vim.fs.normalize(vim.fs.dirname(bufname))
      local closestFsFile = vim.fs.find(function(name, path)
        return name:match(".*%.fs$")
      end, { limit = 1, type = "file", upward = true, path = parentDir, stop = projectRoot })[1]

      -- If no .fs file exists nearby, FSAC will still attach via fsharp_project filetype — no need to create a temp file.
      if not closestFsFile then
        return
      end

      -- M.notify("closest fs file is  " .. closestFsFile )
      ---@type integer
      local closestFileBufNumber = vim.fn.bufadd(closestFsFile)
       local ionideClientsList = M.GetIonideClients()
      local isAleadyStarted = false
      if ionideClientsList then
        for _, client in ipairs(ionideClientsList) do
          local root = client.config.root_dir or ""
          if vim.fs.normalize(root) == projectRoot then
            -- M.notify("Ionide already started for root path of " .. projectRoot .. " \nClient Id: " .. vim.inspect(client.id))
            isAleadyStarted = true
            break
          end
        end
      else
      end
      if not isAleadyStarted then
        vim.defer_fn(function()
          vim.cmd.tcd(projectRoot)
          vim.cmd.e(closestFsFile)
          vim.cmd.b(bufnr)
          vim.cmd.bd(closestFileBufNumber)
        end, 100)
      end
      end,
  })

  vim.api.nvim_create_autocmd(M.MergedConfig.IonideNvimSettings.AutocmdEvents or { "LspAttach" }, {
    desc = "Ionide attach-time LSP integrations",
    group = vim.api.nvim_create_augroup("IonideNativeLspAttach", { clear = true }),
    callback = function(args)
      M.OnNativeLspAttach(args)
    end,
  })
end

--- ftplugin section ---
vim.filetype.add({
  extension = {
    fsproj = function(_, _)
      return "fsharp_project",
        function(bufnr)
          vim.bo[bufnr].syn = "xml"
          vim.bo[bufnr].ro = false
          vim.b[bufnr].readonly = false
          vim.bo[bufnr].commentstring = "<!--%s-->"
          vim.opt_local.foldlevelstart = 99
          vim.w.fdm = "syntax"
        end
    end,
  },
})

vim.filetype.add({
  extension = {
    fs = function(path, bufnr)
      return "fsharp",
        function(bufnr)
          if not vim.g.filetype_fs then
            vim.g["filetype_fs"] = "fsharp"
          end
          if not vim.g.filetype_fs == "fsharp" then
            vim.g["filetype_fs"] = "fsharp"
          end
          vim.w.fdm = "syntax"
          vim.bo[bufnr].formatoptions = "croql"
          vim.bo[bufnr].commentstring = "//%s"
          vim.bo[bufnr].comments = [[s0:*\ -,m0:*\ \ ,ex0:*),s1:(*,mb:*,ex:*),:\/\/\/,:\/\/]]
        end
    end,
    fsx = function(path, bufnr)
      return "fsharp",
        function(bufnr)
          if not vim.g.filetype_fs then
            vim.g["filetype_fsx"] = "fsharp"
          end
          if not vim.g.filetype_fs == "fsharp" then
            vim.g["filetype_fsx"] = "fsharp"
          end
          vim.w.fdm = "syntax"
          -- comment settings
          vim.bo[bufnr].formatoptions = "croql"
          vim.bo[bufnr].commentstring = "//%s"
          vim.bo[bufnr].comments = [[s0:*\ -,m0:*\ \ ,ex0:*),s1:(*,mb:*,ex:*),:\/\/\/,:\/\/]]
        end
    end,
    fsi = function(path, bufnr)
      return "fsharp",
        function(bufnr)
          vim.w.fdm = "syntax"
          vim.bo[bufnr].formatoptions = "croql"
          vim.bo[bufnr].commentstring = "//%s"
          vim.bo[bufnr].comments = [[s0:*\ -,m0:*\ \ ,ex0:*),s1:(*,mb:*,ex:*),:\/\/\/,:\/\/]]
        end
    end,
  },
})

function M.InitializeDefaultFsiKeymapSettings()
  if not M.MergedConfig.IonideNvimSettings.FsiKeymap then
    M.MergedConfig.IonideNvimSettings.FsiKeymap = "vscode"
  end
  if M.MergedConfig.IonideNvimSettings.FsiKeymap == "vscode" then
    M.MergedConfig.IonideNvimSettings.FsiKeymapSend = "<M-cr>"
    M.MergedConfig.IonideNvimSettings.FsiKeymapToggle = "<M-@>"
  elseif M.MergedConfig.IonideNvimSettings.FsiKeymap == "vim-fsharp" then
    M.MergedConfig.IonideNvimSettings.FsiKeymapSend = "<leader>i"
    M.MergedConfig.IonideNvimSettings.FsiKeymapToggle = "<leader>e"
  elseif M.MergedConfig.IonideNvimSettings.FsiKeymap == "custom" then
    M.MergedConfig.IonideNvimSettings.FsiKeymap = "none"
    if not M.MergedConfig.IonideNvimSettings.FsiKeymapSend then
      M.notify("FsiKeymapSend not set", vim.log.levels.WARN)
    elseif not M.MergedConfig.IonideNvimSettings.FsiKeymapToggle then
      M.notify("FsiKeymapToggle not set", vim.log.levels.WARN)
    else
      M.MergedConfig.IonideNvimSettings.FsiKeymap = "custom"
    end
  end
end

local FsiBuffer = -1
local fsiJob = -1
local fsiWidth = 0
local fsiHeight = 0

vim.api.nvim_create_user_command("IonideResetIonideBufferNumber", function()
  -- Stop the existing FSI job before clearing the buffer reference.
  -- Previously only FsiBuffer was reset to -1, leaving fsiJob pointing at
  -- a live (leaked) terminal job. The next OpenFsi call would start a NEW job
  -- while the old one kept running in the background.
  if fsiJob > 0 then
    pcall(vim.fn.jobstop, fsiJob)
    fsiJob = -1
  end
  FsiBuffer = -1
  vim.notify("Fsi buffer is now set to number " .. vim.inspect(FsiBuffer))
end, {
  desc = "Resets the current buffer that fsi is assigned to back to the invalid number -1, so that Ionide knows to recreate it.",
})

---Restarts all Ionide LSP clients
---@return boolean success
function M.RestartLspClient()
  local clients = M.GetIonideClients()
  if #clients == 0 then
    M.notify("No ionide LSP clients found to restart", vim.log.levels.WARN)
    return false
  end
  for _, client in ipairs(clients) do
    local bufs = vim.lsp.get_buffers_by_client_id(client.id)
    client:stop()
    vim.defer_fn(function()
      for _, buf in ipairs(bufs) do
        if vim.api.nvim_buf_is_valid(buf) then
          vim.lsp.start(M.MergedConfig, { bufnr = buf })
        end
      end
    end, 500)
  end
  return true
end

vim.api.nvim_create_user_command("IonideRestartLspClient", function()
  local success = M.RestartLspClient()
  if success then
    vim.notify("LSP client restart initiated", vim.log.levels.INFO)
  else
    vim.notify("Failed to restart LSP client", vim.log.levels.ERROR)
  end
end, { desc = "Ionide - Restart LSP Client" })

local function vimReturnFocus(window)
  vim.fn.win_gotoid(window)
  vim.cmd.redraw("!")
end

local function winGoToIdSafe(id)
  vim.fn.win_gotoid(id)
end

local function getFsiCommand()
  local cmd = "dotnet fsi"
  if M.MergedConfig.IonideNvimSettings and M.MergedConfig.IonideNvimSettings.FsiCommand then
    cmd = M.MergedConfig.IonideNvimSettings.FsiCommand or "dotnet fsi"
  end
  local ep = {}
  if
    M.MergedConfig.settings
    and M.MergedConfig.settings.FSharp
    and M.MergedConfig.settings.FSharp.fsiExtraParameters
  then
    ep = M.MergedConfig.settings.FSharp.fsiExtraParameters or {}
  end
  if #ep > 0 then
    cmd = cmd .. " " .. vim.fn.join(ep, " ")
  end
  if
    M.MergedConfig.IonideNvimSettings
    and M.MergedConfig.IonideNvimSettings.EnableFsiStdOutTeeToFile
    and M.MergedConfig.IonideNvimSettings.EnableFsiStdOutTeeToFile == true
    and vim.opt.shell:get():match("powershell") ~= nil
  then
    local teeToInvoke = " *>&1 | tee '"
    local teeToTry = [[
$Path = "$pshome\types.ps1xml";
[IO.StreamReader]$reader = [System.IO.StreamReader]::new($Path)
# embed loop in scriptblock:
& {
    while (-not $reader.EndOfStream)
    {
        # read current line
        $reader.ReadLine()

        # add artificial delay to pretend this was a HUGE file
        Start-Sleep -Milliseconds 10
    }
# process results in real-time as they become available:
} | Out-GridView

# close and dispose the streamreader properly:
$reader.Close()
$reader.Dispose()

    ]]
    -- local teeToInvoke = [[ | ForEach-Object { tee $_ $_ } | tee ']]
    local defaultOutputName = "./fsiOutputFile.txt"
    if M.MergedConfig.IonideNvimSettings and M.MergedConfig.IonideNvimSettings.FsiStdOutFileName then
      if M.MergedConfig.IonideNvimSettings.FsiStdOutFileName ~= "" then
        cmd = cmd .. teeToInvoke .. (M.MergedConfig.IonideNvimSettings.FsiStdOutFileName or defaultOutputName) .. "'"
      else
        cmd = cmd .. teeToInvoke .. defaultOutputName .. "'"
      end
    end
  end

  return cmd
end

local function getFsiWindowCommand()
  local cmd = "botright 10new"
  if M.MergedConfig.IonideNvimSettings and M.MergedConfig.IonideNvimSettings.FsiWindowCommand then
    cmd = M.MergedConfig.IonideNvimSettings.FsiWindowCommand or "botright 10new"
  end
  return cmd
end

function M.OpenFsi(returnFocus)
  if vim.fn.bufwinid(FsiBuffer) <= 0 then
    local cmd = getFsiCommand()
    local currentWin = vim.fn.win_getid()
    vim.fn.execute(getFsiWindowCommand())
    if fsiWidth > 0 then
      vim.fn.execute("vertical resize " .. fsiWidth)
    end
    if fsiHeight > 0 then
      vim.fn.execute("resize " .. fsiHeight)
    end
    if FsiBuffer >= 0 and vim.fn.bufexists(FsiBuffer) == 1 then
      vim.cmd.b(string.format("%i", FsiBuffer))
      vim.cmd.normal("G")
      if returnFocus then
        winGoToIdSafe(currentWin)
      end
    else
      fsiJob = vim.fn.jobstart(cmd, { term = true }) or 0
      if fsiJob > 0 then
        FsiBuffer = vim.fn.bufnr(vim.api.nvim_get_current_buf())
      else
        vim.cmd.close()
        M.notify("failed to open FSI")
        return -1
      end
    end
    vim.opt_local.bufhidden = "hide"
    vim.cmd.normal("G")
    if returnFocus then
      winGoToIdSafe(currentWin)
    end
    return FsiBuffer
  end
  return FsiBuffer
end

function M.ToggleFsi()
  local w = vim.fn.bufwinid(FsiBuffer)
  if w > 0 then
    local curWin = vim.fn.win_getid()
    winGoToIdSafe(w)
    fsiWidth = vim.fn.winwidth(tonumber(vim.fn.expand("%")) or 0)
    fsiHeight = vim.fn.winheight(tonumber(vim.fn.expand("%")) or 0)
    vim.cmd.close()
    vim.fn.win_gotoid(curWin)
  else
    M.OpenFsi()
  end
end

function M.GetVisualSelection(keepSelectionIfNotInBlockMode, advanceCursorOneLine, debugNotify)
  local line_start, column_start
  local line_end, column_end
  -- if debugNotify is true, use M.notify to show debug info.
  debugNotify = debugNotify or false
  -- keep selection defaults to false, but if true the selection will
  -- be reinstated after it's cleared to set '> and '<
  -- only relevant in visual or visual line mode, block always keeps selection.
  keepSelectionIfNotInBlockMode = keepSelectionIfNotInBlockMode or false
  -- advance cursor one line defaults to true, but is turned off for
  -- visual block mode regardless.
  -- NOTE: `advanceCursorOneLine or true` is a Lua boolean trap: if the caller passes
  -- `false` the expression still evaluates to `true` because `false or true == true`.
  -- Use an explicit nil-check instead.
  advanceCursorOneLine = (function()
    if keepSelectionIfNotInBlockMode == true then
      return false
    else
      if advanceCursorOneLine == nil then
        return true
      end
      return advanceCursorOneLine
    end
  end)()

  if vim.fn.visualmode() == "\22" then
    line_start, column_start = unpack(vim.fn.getpos("v"), 2)
    line_end, column_end = unpack(vim.fn.getpos("."), 2)
  else
    -- if not in visual block mode then i want to escape to normal mode.
    -- if this isn't done here, then the '< and '> do not get set,
    -- and the selection will only be whatever was LAST selected.
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<esc>", true, false, true), "x", true)
    line_start, column_start = unpack(vim.fn.getpos("'<"), 2)
    line_end, column_end = unpack(vim.fn.getpos("'>"), 2)
  end
  if column_start > column_end then
    column_start, column_end = column_end, column_start
    if debugNotify == true then
      M.notify(
        "switching column start and end, \nWas "
          .. column_end
          .. ","
          .. column_start
          .. "\nNow "
          .. column_start
          .. ","
          .. column_end
      )
    end
  end
  if line_start > line_end then
    line_start, line_end = line_end, line_start
    if debugNotify == true then
      M.notify(
        "switching line start and end, \nWas "
          .. line_end
          .. ","
          .. line_start
          .. "\nNow "
          .. line_start
          .. ","
          .. line_end
      )
    end
  end
  if vim.g.selection == "exclusive" then
    column_end = column_end - 1 -- Needed to remove the last character to make it match the visual selection
  end
  if debugNotify == true then
    M.notify(
      "vim.fn.visualmode(): "
        .. vim.fn.visualmode()
        .. "\nsel start "
        .. vim.inspect(line_start)
        .. " "
        .. vim.inspect(column_start)
        .. "\nSel end "
        .. vim.inspect(line_end)
        .. " "
        .. vim.inspect(column_end)
    )
  end
  local n_lines = math.abs(line_end - line_start) + 1
  local lines = vim.api.nvim_buf_get_lines(0, line_start - 1, line_end, false)
  if #lines == 0 then
    return { "" }
  end
  if vim.fn.visualmode() == "\22" then
    -- this is what actually sets the lines to only what is found between start and end columns
    for i = 1, #lines do
      lines[i] = string.sub(lines[i], column_start, column_end)
    end
  else
    lines[1] = string.sub(lines[1], column_start, -1)
    if n_lines == 1 then
      lines[n_lines] = string.sub(lines[n_lines], 1, column_end - column_start + 1)
    else
      lines[n_lines] = string.sub(lines[n_lines], 1, column_end)
    end
    -- if advanceCursorOneLine == true, then i do want the cursor to advance once.
    if advanceCursorOneLine == true then
      if debugNotify == true then
        M.notify("advancing cursor one line past the end of the selection to line " .. vim.inspect(line_end + 1))
      end

      local lastline = vim.fn.line("w$")
      if line_end > lastline then
        vim.api.nvim_win_set_cursor(0, { line_end + 1, 0 })
      end
    end

    if keepSelectionIfNotInBlockMode then
      vim.api.nvim_feedkeys("gv", "n", true)
    end
  end
  if debugNotify == true then
    M.notify(vim.fn.join(lines, "\n") .. "\n")
    -- M.notify(table.concat(lines, "\n"))
  end
  return lines -- use this return if you want an array of text lines
  -- return table.concat(lines, "\n") -- use this return instead if you need a text block
end

---Quit current fsi
function M.QuitFsi()
  if vim.api.nvim_buf_is_valid(FsiBuffer) then
    local winid = vim.api.nvim_call_function("bufwinid", { FsiBuffer })
    if winid > 0 then
      vim.api.nvim_win_close(winid, true)
    end
    vim.api.nvim_call_function("jobstop", { fsiJob })
    FsiBuffer = -1
    fsiJob = -1
  end
end

function M.ResetFsi()
  M.QuitFsi()
  M.OpenFsi(false)
end

---sends lines to FSI
---@param lines string[]
function M.SendFsi(lines)
  local focusOnSend = false
  if M.MergedConfig.IonideNvimSettings and M.MergedConfig.IonideNvimSettings.FsiFocusOnSend then
    focusOnSend = M.MergedConfig.IonideNvimSettings.FsiFocusOnSend or false
  end
  local openResult = M.OpenFsi(focusOnSend)
  if not openResult then
    openResult = 1
  end

  if openResult > 0 then
    local toBeSent = vim.list_extend(lines, { "", ";;", "" })
    -- M.notify("Text being sent to FSI:\n" .. vim.inspect(toBeSent))
    vim.fn.chansend(fsiJob, toBeSent)
  end
end

function M.GetCompleteBuffer()
  return vim.api.nvim_buf_get_lines(vim.api.nvim_get_current_buf(), 0, -1, false)
end

function M.SendSelectionToFsi()
  local lines = M.GetVisualSelection()
  M.SendFsi(lines)
end

function M.SendLineToFsi()
  local text = vim.api.nvim_get_current_line()
  local line, _ = unpack(vim.fn.getpos("."), 2)
  local lastline = vim.fn.line("w$")
  if line < lastline then
    vim.api.nvim_win_set_cursor(0, { line + 1, 0 })
  end
  -- M.notify("fsi send line " .. text)
  M.SendFsi({ text })
  -- vim.cmd 'normal j'
end

function M.SendAllToFsi()
  -- M.notify("fsi send all ")
  local text = M.GetCompleteBuffer()
  return M.SendFsi(text)
end

function M.SetKeymaps()
  -- vim.notify("Setting up FSI keymaps")
  local send = M.MergedConfig.IonideNvimSettings.FsiKeymapSend or "<M-CR>"
  local toggle = M.MergedConfig.IonideNvimSettings.FsiKeymapToggle or "<M-@>"
  vim.keymap.set("v", send, function()
    M.SendSelectionToFsi()
  end, { silent = false })
  vim.keymap.set("n", send, function()
    M.SendLineToFsi()
  end, { silent = false })
  vim.keymap.set("n", toggle, function()
    M.ToggleFsi()
  end, { silent = false })
  vim.keymap.set("t", toggle, function()
    M.ToggleFsi()
  end, { silent = false })
end

vim.api.nvim_create_user_command(
  "IonideSendCurrentLineToFSI",
  M.SendLineToFsi,
  { desc = "Ionide - Send Current line's text to FSharp Interactive" }
)
vim.api.nvim_create_user_command(
  "IonideSendWholeBufferToFSI",
  M.SendAllToFsi,
  { desc = "Ionide - Send Current buffer's text to FSharp Interactive" }
)
vim.api.nvim_create_user_command("IonideToggleFSI", M.ToggleFsi, { desc = "Ionide - Toggle FSharp Interactive" })
vim.api.nvim_create_user_command("IonideQuitFSI", M.QuitFsi, { desc = "Ionide - Quit FSharp Interactive" })
vim.api.nvim_create_user_command("IonideResetFSI", M.ResetFsi, { desc = "Ionide - Reset FSharp Interactive" })
vim.api.nvim_create_user_command("IonideReloadProjects", function()
  M.ReloadProjects()
end, { desc = "Ionide - Reload workspace projects" })

-- fsproj file operation commands
register_fsproj_command(
  "IonideFsprojMoveFileUp",
  "IonideFsprojMoveFileUp <fsproj> <fileVirtualPath>",
  "Ionide - Move file up in fsproj compile order",
  2,
  function(args) M.CallFSharpMoveFileUp(args[1], args[2]) end
)

register_fsproj_command(
  "IonideFsprojMoveFileDown",
  "IonideFsprojMoveFileDown <fsproj> <fileVirtualPath>",
  "Ionide - Move file down in fsproj compile order",
  2,
  function(args) M.CallFSharpMoveFileDown(args[1], args[2]) end
)

register_fsproj_command(
  "IonideFsprojAddFile",
  "IonideFsprojAddFile <fsproj> <fileVirtualPath>",
  "Ionide - Add file to fsproj",
  2,
  function(args) M.CallFSharpAddFile(args[1], args[2]) end
)

register_fsproj_command(
  "IonideFsprojAddExistingFile",
  "IonideFsprojAddExistingFile <fsproj> <fileVirtualPath>",
  "Ionide - Add existing file to fsproj",
  2,
  function(args) M.CallFSharpAddExistingFile(args[1], args[2]) end
)

register_fsproj_command(
  "IonideFsprojAddFileAbove",
  "IonideFsprojAddFileAbove <fsproj> <currentFileVirtualPath> <newFileVirtualPath>",
  "Ionide - Add file above another file in fsproj",
  3,
  function(args) M.CallFSharpAddFileAbove(args[1], args[2], args[3]) end
)

register_fsproj_command(
  "IonideFsprojAddFileBelow",
  "IonideFsprojAddFileBelow <fsproj> <currentFileVirtualPath> <newFileVirtualPath>",
  "Ionide - Add file below another file in fsproj",
  3,
  function(args) M.CallFSharpAddFileBelow(args[1], args[2], args[3]) end
)

register_fsproj_command(
  "IonideFsprojRemoveFile",
  "IonideFsprojRemoveFile <fsproj> <fileVirtualPath>",
  "Ionide - Remove file from fsproj",
  2,
  function(args) M.CallFSharpRemoveFile(args[1], args[2]) end
)

register_fsproj_command(
  "IonideFsprojRenameFile",
  "IonideFsprojRenameFile <fsproj> <oldFileVirtualPath> <newFileName>",
  "Ionide - Rename file in fsproj",
  3,
  function(args) M.CallFSharpRenameFile(args[1], args[2], args[3]) end
)

vim.api.nvim_create_user_command("IonideTestDiscover", function()
  M.CallTestDiscoverTests()
end, { desc = "Ionide - Discover tests through FsAutoComplete" })

vim.api.nvim_create_user_command("IonideTestRun", function(opts)
  local testCaseFilter = opts.fargs[1]
  M.CallTestRunTests(nil, testCaseFilter, false)
end, { nargs = "?", desc = "Ionide - Run tests through FsAutoComplete" })

vim.api.nvim_create_user_command("IonideDocumentation", function()
  M.ShowDocumentationHover()
end, { desc = "Ionide - Show formatted F# documentation hover" })

function M.setup(config)
  M.PassedInConfig = config or {}
  -- M.notify("entered setup for ionide: passed in config is  " .. vim.inspect(M.PassedInConfig))
  M.MergedConfig = vim.tbl_deep_extend("force", M.DefaultLspConfig, M.PassedInConfig)
  M.MergedConfig.cmd = M.MergedConfig.IonideNvimSettings.FsautocompleteCommand
  M.MergedConfig.handlers = vim.tbl_deep_extend("force", M.Handlers, M.MergedConfig.handlers or {})
  -- M.notify("Initializing")

  vim.validate({
    cmd = { M.MergedConfig.cmd, "table", true },
    root_dir = { M.MergedConfig.root_dir, "function", true },
    filetypes = { M.MergedConfig.filetypes, "table", true },
    on_attach = { M.MergedConfig.on_attach, "function", true },
  })

  local bufnr = vim.api.nvim_get_current_buf()
  local bufname = vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr))
  local envs = M.GetDefaultEnvVarsForRoot(M.GetRoot(bufname))
  -- M.notify("setting environment variables: \n" .. vim.inspect(envs))
  for i, env in ipairs(envs) do
    local name = env[1]
    local value = env[2]
    vim.uv.os_setenv(name, value)
  end

  M.InitializeDefaultFsiKeymapSettings()
  M.SetKeymaps()
  M.RegisterAutocmds()

  return M.MergedConfig
end

return M
