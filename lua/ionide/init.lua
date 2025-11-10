local M = {}

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

M.projectFolders = {}

---@type table<string,ProjectInfo>
M.Projects = {}

---@table<string,function>
M.Handlers = {
  [""] = function(err, rs, ctx, config)
    M.notify("if you're seeing this called, something went wrong, it's key is literally an empty string.  ")
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
}

---@type IonideOptions
M.DefaultLspConfig = {
  IonideNvimSettings = M.DefaultNvimSettings,
  filetypes = { "fsharp", "fsharp_project" },
  name = "ionide",
  cmd = M.DefaultNvimSettings.FsautocompleteCommand,

  root_dir = function(bufnr, on_dir)
    local bufnr = vim.api.nvim_get_current_buf()
    local bufname = vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr))
    local root = M.GetRoot(bufname)

    return on_dir(root)
  end,
  -- root_markers = { "*.slnx", "*.sln", "*.fsproj", ".git" },
  -- autostart = true,
  settings = { FSharp = M.DefaultServerSettings },
  log_level = vim.lsp.protocol.MessageType.Warning,
  message_level = vim.lsp.protocol.MessageType.Warning,
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
  -- Handle compatibility with different Neovim versions
  local uv = vim.uv or vim.loop
  local is_windows = false

  if uv and uv.os_uname then
    is_windows = uv.os_uname().version:match("Windows") ~= nil
  else
    -- Fallback detection for test environments
    is_windows = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
  end

  local usr_ss_opt
  if is_windows then
    usr_ss_opt = vim.o.shellslash
    vim.o.shellslash = true
  end

  local uri = vim.fn.fnamemodify(vim.fs.normalize(path), ":p")

  if string.sub(uri, 1, 1) == "/" then
    uri = "file://" .. uri
  else
    uri = "file:///" .. uri
  end
  if is_windows then
    vim.o.shellslash = usr_ss_opt
  end
  ---
  ---@type lsp.TextDocumentIdentifier
  return {
    uri = uri,
  }
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
  vim.notify("projectUri: " .. vim.inspect(tdi))
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

---creates an fsdn request.. probabably useless now..
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
  local function on_unsupported()
    M.notify("LSP method " .. method .. " is not supported by any ionide LSP client", vim.log.levels.WARN)
  end
  return vim.lsp.buf_request(0, method, params, handler, on_unsupported)
end

function M.CallLspNotify(method, params)
  -- Check if any ionide clients are available (with safety check for test environment)
  if vim.lsp and vim.lsp.get_clients then
    local clients = vim.lsp.get_clients({ name = "ionide" })
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
    projectPath,
    currentVirtualPath,
    newFileVirtualPath,
  }
end

function M.CallFSharpAddFileAbove(projectPath, currentVirtualPath, newFileVirtualPath, handler)
  return M.Call(
    "fsharp/addFileAbove",
    M.DotnetFile2Request(projectPath, currentVirtualPath, newFileVirtualPath),
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
  ---@type vim.lsp.get_clients.Filter
  local lspFilter = {
    name = "ionide",
  }

  ---@type vim.lsp.Client
  local i = vim.lsp.get_clients(lspFilter)
  -- vim.notify("Lsp peek client " .. vim.inspect(i))
  -- i.

  return M.Call("fsharp/workspacePeek", M.CreateFSharpWorkspacePeekRequest(directoryPath, depth, excludedDirs), handler)
end

---Call to "fsharp/workspaceLoad"
---@param projectFiles string[]  a string list of project files.
---@return table<integer, integer>, fun() 2-tuple:
---  - Map of client-id:request-id pairs for all successful requests.
---  - Function which can be used to cancel all the requests. You could instead
---    iterate all clients and call their `cancel_request()` methods.
function M.CallFSharpWorkspaceLoad(projectFiles, handler)
  vim.notify("Loading workspace " .. vim.inspect(projectFiles))
  return M.Call("fsharp/workspaceLoad", M.CreateFSharpWorkspaceLoadParams(projectFiles), handler)
end

---call to "fsharp/project" - which, after using projectPath to create an FSharpProjectParms, loads given project
---@param projectPath string
---@return table<integer, integer>, fun() 2-tuple:
---  - Map of client-id:request-id pairs for all successful requests.
---  - Function which can be used to cancel all the requests. You could instead
---    iterate all clients and call their `cancel_request()` methods.
function M.CallFSharpProject(projectPath, handler)
  vim.notify("Loading project " .. vim.inspect(projectPath))
  local p = M.CreateFSharpProjectParams(projectPath)
  return M.Call("fsharp/project", p, handler)
end

---@return table<integer, integer>, fun() 2-tuple:
---  - Map of client-id:request-id pairs for all successful requests.
---  - Function which can be used to cancel all the requests. You could instead
---    iterate all clients and call their `cancel_request()` methods.
function M.Fsdn(signature, handler)
  return M.Call("fsharp/fsdn", M.FsdnRequest(signature), handler)
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

function M.ShowLoadedProjects()
  M.notify("Loaded Projects:")
  for proj, projInfo in pairs(M.Projects) do
    M.notify("- " .. vim.fs.normalize(vim.inspect(projInfo)))
  end
end

function M.ReloadProjects()
  M.notify("Reloading Projects")
  local foldersCount = #M.projectFolders
  if foldersCount > 0 then
    M.CallFSharpWorkspaceLoad(M.projectFolders)
  else
    M.notify("Workspace is empty")
  end
end

function M.OnFSProjSave()
  if
    vim.bo.ft == "fsharp_project"
    and M.MergedConfig.IonideNvimSettings.AutomaticReloadWorkspace
    and M.MergedConfig.IonideNvimSettings.AutomaticReloadWorkspace == true
  then
    M.notify("fsharp project saved, reloading...")
    local parentDir = vim.fs.normalize(vim.fs.dirname(vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())))

    if not vim.tbl_contains(M.projectFolders, parentDir) then
      table.insert(M.projectFolders, parentDir)
    end
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
      end, { limit = 1, type = "file", upward = true, path = parentDir, stop = projectRoot })[1] or (function()
        local newFile = parentDir .. "/" .. vim.inspect(os.time()) .. "TempFileForProjectInitDeleteMe.fs"
        vim.fn.writefile({}, newFile)
        return newFile
      end)()

      -- M.notify("closest fs file is  " .. closestFsFile )
      ---@type integer
      local closestFileBufNumber = vim.fn.bufadd(closestFsFile)
      local ionideClientsList = vim.lsp.get_clients({ name = "ionide" })
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
  },
})

function M.InitializeDefaultFsiKeymapSettings()
  if not M.MergedConfig.IonideNvimSettings.FsiKeymap then
    M.MergedConfig.IonideNvimSettings.FsiKeymap = "vscode"
  end
  if vim.fn.has("nvim") then
    if M.MergedConfig.IonideNvimSettings.FsiKeymap == "vscode" then
      M.MergedConfig.IonideNvimSettings.FsiKeymapSend = "<M-cr>"
      M.MergedConfig.IonideNvimSettings.FsiKeymapToggle = "<M-@>"
    elseif M.MergedConfig.IonideNvimSettings.FsiKeymap == "vim-fsharp" then
      M.MergedConfig.IonideNvimSettings.FsiKeymapSend = "<leader>i"
      M.MergedConfig.IonideNvimSettings.FsiKeymapToggle = "<leader>e"
    elseif M.MergedConfig.IonideNvimSettings.FsiKeymap == "custom" then
      M.MergedConfig.IonideNvimSettings.FsiKeymap = "none"
      if not M.MergedConfig.IonideNvimSettings.FsiKeymapSend then
        vim.cmd.echoerr("FsiKeymapSend not set. good luck with that I dont have a nice way to change it yet. sorry. ")
      elseif not M.MergedConfig.IonideNvimSettings.FsiKeymapToggle then
        vim.cmd.echoerr("FsiKeymapToggle not set. good luck with that I dont have a nice way to change it yet. sorry. ")
      else
        M.MergedConfig.IonideNvimSettings.FsiKeymap = "custom"
      end
    end
  else
    M.notify("I'm sorry I don't support regular vim, try ionide/ionide-vim instead")
  end
end

FsiBuffer = -1
local fsiJob = -1
local fsiWidth = 0
local fsiHeight = 0

vim.api.nvim_create_user_command("IonideResetIonideBufferNumber", function()
  FsiBuffer = -1
  vim.notify("Fsi buffer is now set to number " .. vim.inspect(FsiBuffer))
end, {
  desc = "Resets the current buffer that fsi is assigned to back to the invalid number -1, so that Ionide knows to recreate it.",
})

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
  if vim.fn.has("nvim") then
    vim.fn.win_gotoid(id)
  else
    vim.fn.timer_start(1, function()
      vimReturnFocus(id)
    end, {})
  end
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
      fsiJob = vim.fn.termopen(cmd) or 0
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
    M.winGoToId(w)
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
  advanceCursorOneLine = (function()
    if keepSelectionIfNotInBlockMode == true then
      return false
    else
      return advanceCursorOneLine or true
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
  return vim.api.nvim_buf_get_lines(vim.api.nvim_get_current_buf(), 1, -1, false)
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

function M.setup(config)
  M.PassedInConfig = config or {}
  -- M.notify("entered setup for ionide: passed in config is  " .. vim.inspect(M.PassedInConfig))
  M.MergedConfig = vim.tbl_deep_extend("force", M.DefaultLspConfig, M.PassedInConfig)
  -- M.notify("Initializing")

  vim.validate({
    cmd = { M.MergedConfig.cmd, "table", true },
    root_dir = { M.MergedConfig.root_dir, "function", true },
    filetypes = { M.MergedConfig.filetypes, "table", true },
    on_attach = { M.MergedConfig.on_attach, "function", true },
  })

  M.SetKeymaps()
  M.RegisterAutocmds()

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

  return M.MergedConfig
end

return M
