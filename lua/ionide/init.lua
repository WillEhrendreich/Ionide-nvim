--  www.github.com/willehrendreich/ionide-vim

local validate = vim.validate
local api = vim.api
local uc = vim.api.nvim_create_user_command
local lsp = vim.lsp
local autocmd = vim.api.nvim_create_autocmd
local grp = vim.api.nvim_create_augroup
-- local plenary = require("plenary")

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
local neotree = tryRequire("neotree.nvim")

local neoconf = tryRequire("neoconf.plugins")
if neoconf == nil then
  ---@class SettingsPlugin
  ---@field name string
  ---@field setup fun()|nil
  ---@field on_update fun(event)|nil
  ---@field on_schema fun(schema: Schema)
  --construct a fake one to "register" the schema without it giving an error.
  ---@type  SettingsPlugin
  local fakeNeoConfRegisterOpts = {
    on_schema = function(schema) end,
  }

  neoconf = {
    ---comment
    ---@param plugin SettingsPlugin
    register = function(plugin) end,
  }
end

---@class PackageReference
---@field FullPath string
---@field Name string
---@field Version string

---@class ProjectReference
---@field ProjectFileName string
---@field RelativePath string

---@class ProjectInfo.Item
-- The full FilePath
---@field FilePath string
---Metadata
---@field Metadata table
---Name = "Compile",
---@field Name string
---VirtualPath = "DebuggingTp/Shared.fs"
---@field VirtualPath string

---@class ProjectInfo.Info.RunCmd
---@field Arguments string
---@field Command string

---@class ProjectInfo.Info
--   Configuration = "Debug","Release"
---@field Configuration string
--   IsPackable = true,
---@field IsPackable boolean
--   IsPublishable = true,
---@field IsPublishable boolean
--   IsTestProject = false,
---@field IsTestProject boolean
--   RestoreSuccess = true,
---@field RestoreSuccess boolean
--   RunCmd = vim.NIL,
---@field RunCmd ProjectInfo.Info.RunCmd|nil
--   TargetFramework = "netstandard2.0",
---@field TargetFramework string
--   TargetFrameworkIdentifier = ".NETStandard",
---@field TargetFrameworkIdentifier string
--   TargetFrameworkVersion = "v2.0",
---@field TargetFrameworkVersion string
--   TargetFrameworks = { "netstandard2.0" }
---@field TargetFrameworks  string[]

---@class ProjectInfo
---@field AdditionalInfo table
---@field Files string[]
---@field Info ProjectInfo.Info
---@field Items ProjectInfo.Item[]
-- full Output file path, usually with things like bin/debug/{TargetFramework}/{AssemblyName}.dll
---@field Output string
-- OutputType = "lib", "exe"
---@field OutputType string
-- PackageReferences = all the nuget package references
---@field PackageReferences PackageReference[]
-- Project path, absolute, not  relative.
---@field Project string
-- ProjectReferences - all the other projects this project references.
---@field ProjectReferences ProjectReference[]
-- References - all the dll's this project references.
---@field References string[]

---@class ProjectDataTable
---@field Configurations table

---@class ProjectKind
---@field Data ProjectDataTable
---@field Kind string -- likely should always be "msbuildformat"

---@class Project
---@field Guid string
---@field Kind ProjectKind
---@field Name string -- the FilePath

---@class SolutionData
---@field Configurations table
---@field Items Project[]
---@field Path string

---@class Solution
---@field Data SolutionData
---@field Type string --should only ever be "solution"

--- for calling "fsharp/workspaceLoad" -
--- accepts WorkspaceLoadParms, loads given list of projects in the background,
--- partial result notified by fsharp/notifyWorkspace notification
--- original FSharp Type Definition:
--- type WorkspaceLoadParms =
---   {
---     /// Project files to load
---     TextDocuments: TextDocumentIdentifier[]
---   }
---@class FSharpWorkspaceLoadParams
---@field TextDocuments lsp.TextDocumentIdentifier[]

--- for calling "fsharp/workspacePeek" - accepts WorkspacePeekRequest,
--- returns list of possible workspaces (resolved solution files,
--- or list of projects if there are no solution files)
--- original FSharp Type Definition:
--- type WorkspacePeekRequest =
---   { Directory: string
---     Deep: int
---     ExcludedDirs: string array }
---@class FSharpWorkspacePeekRequest
---@field Directory string
---@field Deep integer
---@field ExcludedDirs string[]

-- type PlainNotification = { Content: string }
---@class PlainNotification
---@field Content string

-- type TestAdapterEntry<'range> =
--   { Name: string
--     Range: 'range
--     Childs: ResizeArray<TestAdapterEntry<'range>>
--     Id: int
--     List: bool
--     ModuleType: string
--     Type: string }
---@class TestAdapterEntry<Range>
---@field Name string
---@field Range Range
---@field Childs TestAdapterEntry<Range>[]
---@field Id integer
---@field List boolean
---@field ModuleType string
---@field Type string -- usually "Expecto"|"XUnit"|"NUnit"

-- /// Notification when a `TextDocument` is completely analyzed:
-- /// F# Compiler checked file & all Analyzers (like `UnusedOpensAnalyzer`) are done.
-- ///
-- /// Used to signal all Diagnostics for this `TextDocument` are collected and sent.
-- /// -> For tests to get all Diagnostics of `TextDocument`
-- type DocumentAnalyzedNotification =
--   { TextDocument: VersionedTextDocumentIdentifier }
---@class DocumentAnalyzedNotification
-- -@field TextDocument VersionedTextDocumentIdentifier
---@field TextDocument lsp.TextDocumentIdentifier
---
-- type TestDetectedNotification =
--   { File: string
--     Tests: TestAdapter.TestAdapterEntry<Range> array }
---@class TestDetectedNotification
---@field File string
---@field Tests TestAdapterEntry<Range>[]

-- type ProjectParms =
--   {
--     /// Project file to compile
--     Project: TextDocumentIdentifier
--   }
---@class FSharpProjectParams
---@field Project lsp.TextDocumentIdentifier

-- type HighlightingRequest =
--   { TextDocument: TextDocumentIdentifier }
---@class HighlightingRequest
---@field TextDocument lsp.TextDocumentIdentifier

-- type LineLensConfig = { Enabled: string; Prefix: string }
---@class LineLensConfig
---@field Enabled string
---@field Prefix string

-- type FsdnRequest = { Query: string }
---@class FsdnRequest
---@field Query string

-- type DotnetNewListRequest = { Query: string }
---@class DotnetNewListRequest
---@field Query string

-- type DotnetNewRunRequest =
--   { Template: string
--     Output: string option
--     Name: string option }
---@class DotnetNewRunRequest
---@field Template string
---@field Output string?
---@field Name string?

-- type DotnetProjectRequest = { Target: string; Reference: string }
---@class DotnetProjectRequest
---@field Target string
---@field Reference string

-- type DotnetFileRequest =
--   { FsProj: string
--     FileVirtualPath: string }
---@class DotnetFileRequest
---@field FsProj string
---@field FileVirtualPath string

-- type DotnetFile2Request =
--   { FsProj: string
--     FileVirtualPath: string
--     NewFile: string }
---@class DotnetFile2Request
---@field FsProj string
---@field FileVirtualPath string
---@field NewFile string

-- type DotnetRenameFileRequest =
--   { FsProj: string
--     OldFileVirtualPath: string
--     NewFileName: string }
---@class DotnetRenameFileRequest
---@field FsProj string
---@field OldFileVirtualPath string
---@field NewFileName string

-- type FSharpLiterateRequest =
--   { TextDocument: TextDocumentIdentifier }
---@class FSharpLiterateRequest
---@field TextDocument lsp.TextDocumentIdentifier

-- type FSharpPipelineHintRequest =
--   { TextDocument: TextDocumentIdentifier }
---@class FSharpPipelineHintRequest
---@field TextDocument lsp.TextDocumentIdentifier

---@class AutocmdEvent

---@class IonideNvimSettings
--- the CLI command to start Ionide's Lsp server, FsAutocomplete.
--- usually this is something like {"fsautocomplete"} if your fsautocomplete
--- server is installed globally and accessable on your PATH Environment variable.
--- if installed with Mason.nvim, this would be supplied automatically by Mason, and should be something like
--- Windows {"C:/Users/[YourUsernameHere]/AppData/local/nvim/nvim-data/mason/bin/fsautocomplete.cmd"}
--- Linux {"~/.local/share/nvim-data/mason/bin/fsautocomplete"}
--- Mac {"[however the nvim-data dir looks on mac, I'm sorry I don't have one]/mason/bin/fsautocomplete"}
---@field FsautocompleteCommand string[]
---not currently really used, but the thought is to shut off any and customization to the server config,
---and just run what is here by default. honestly not that important,
---as you can simply not send anything to the setup function
---(require("ionide").setup())
---and it will give you the defaults as they are.
---@field UseRecommendedServerConfig boolean
---@field AutomaticWorkspaceInit boolean
---@field AutomaticReloadWorkspace boolean
---@field AutomaticCodeLensRefresh boolean
---@field ShowSignatureOnCursorMove boolean
---@field FsiCommand string
---@field FsiKeymap string
---@field FsiWindowCommand string
---@field FsiFocusOnSend boolean
--- used in the case that lspconfig is not present, and Ionide has to set up it's own per root manager..
--- It's recommended to have lspconfig installed, and not rely on this plugin's implementation of this functionality.
--- defaults to false.
---@field LspAutoSetup boolean
--- Whether or not to apply a recommended color scheme for diagnostics and CodeLenses
---@field LspRecommendedColorScheme boolean
---@field FsiVscodeKeymaps boolean
---@field StatusLine string
---@field AutocmdEvents table<string>
---@field EnableFsiStdOutTeeToFile boolean
---@field FsiStdOutFileName string
---@field FsiKeymapSend string
---@field FsiKeymapToggle string

---@class IonideOptions: lspconfig.options.fsautocomplete
---@field IonideNvimSettings IonideNvimSettings

-- lspconfig.fsautocomplete = {
--   ---@param options lspconfig.options.fsautocomplete
--   setup = function(options) end,
-- }

---determines if input string ends with the suffix given.
---@param s string
---@param suffix string
---@return boolean
local function stringEndsWith(s, suffix)
  return s:sub(-#suffix) == suffix
end

local M = {}

function M.notify(msg, level, opts)
  local safeMessage = "[Ionide] - "
  if type(msg) == "string" then
    safeMessage = safeMessage .. msg
  else
    safeMessage = safeMessage .. vim.inspect(msg)
  end
  vim.notify(safeMessage, level, opts)
end

---wholesale taken from  https://github.com/folke/edgy.nvim/blob/main/lua/edgy/util.lua
---@generic F: fun()
---@param fn F
---@param max_retries? number
---@return F
function M.with_retry(fn, max_retries)
  max_retries = max_retries or 3
  local retries = 0
  local function try()
    local ok, ret = pcall(fn)
    if ok then
      retries = 0
    else
      if retries >= max_retries or require("edgy.config").debug then
        M.error(ret)
      end
      if retries < max_retries then
        return vim.schedule(try)
      end
    end
  end
  return try
end

---@generic F: fun()
---@param fn F
---@return F
function M.noautocmd(fn)
  return function(...)
    vim.o.eventignore = "all"
    local ok, ret = pcall(fn, ...)
    vim.o.eventignore = ""
    if not ok then
      error(ret)
    end
    return ret
  end
end

--- @generic F: function
--- @param fn F
--- @param ms? number
--- @return F
function M.throttle(fn, ms)
  ms = ms or 200
  local timer = assert(vim.loop.new_timer())
  local waiting = 0
  return function()
    if timer:is_active() then
      waiting = waiting + 1
      return
    end
    waiting = 0
    fn() -- first call, execute immediately
    timer:start(ms, 0, function()
      if waiting > 1 then
        vim.schedule(fn) -- only execute if there are calls waiting
      end
    end)
  end
end

--- @generic F: function
--- @param fn F
--- @param ms? number
--- @return F
function M.debounce(fn, ms)
  ms = ms or 50
  local timer = assert(vim.loop.new_timer())
  local waiting = 0
  return function()
    if timer:is_active() then
      waiting = waiting + 1
    else
      waiting = 0
      fn()
    end
    timer:start(ms, 0, function()
      if waiting then
        vim.schedule(fn) -- only execute if there are calls waiting
      end
    end)
  end
end

M.getIonideClientAttachedToCurrentBufferOrFirstInActiveClients = function()
  local bufnr = vim.api.nvim_get_current_buf()
  -- local bufname = vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr))
  -- local projectRoot = vim.fs.normalize(M.GitFirstRootDir(bufname))
  local ionideClientsList = vim.lsp.get_active_clients({ name = "ionide" })
  if ionideClientsList then
    if #ionideClientsList > 1 then
      for _, client in ipairs(ionideClientsList) do
        if vim.list_contains(vim.tbl_keys(client.attached_buffers), bufnr) then
          return client
        end
        -- local root = client.config.root_dir or ""
        -- if vim.fs.normalize(root) == projectRoot then
        --   return client
        -- end
      end
    else
      if ionideClientsList[1] then
        return ionideClientsList[1]
      end
      return nil
    end
  else
    return nil
  end
end

M.getIonideClientConfigRootDirOrCwd = function()
  local ionide = M.getIonideClientAttachedToCurrentBufferOrFirstInActiveClients()
  if ionide then
    return vim.fs.normalize(ionide.config.root_dir or "")
  else
    return vim.fs.normalize(vim.fn.getcwd())
  end
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
  --   { AutomaticWorkspaceInit: bool option AutomaticWorkspaceInit = false
  --     WorkspaceModePeekDeepLevel: int option WorkspaceModePeekDeepLevel = 2
  workspaceModePeekDeepLevel = 4,

  fsac = {
    attachDebugger = false,
    -- cachedTypeCheckCount = 200,
    conserveMemory = true,
    silencedLogs = {},
    parallelReferenceResolution = true,
    -- "FSharp.fsac.sourceTextImplementation": {
    --        "default": "NamedText",
    --    "description": "EXPERIMENTAL. Enables the use of a new source text implementation. This may have better memory characteristics. Requires restart.",
    --      "enum": [
    --        "NamedText",
    --        "RoslynSourceText"
    --      ]
    --    },
    sourceTextImplementation = "RoslynSourceText",
    dotnetArgs = {},
    -- netCoreDllPath = "",
  },

  enableAdaptiveLspServer = true,
  --     ExcludeProjectDirectories: string[] option = [||]
  excludeProjectDirectories = { "paket-files", ".fable", "packages", "node_modules" },
  --     KeywordsAutocomplete: bool option false
  keywordsAutocomplete = true,
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
  lineLens = { enabled = "always", prefix = "ll//" },

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

  --     InlayHints: InlayHintDto option
  --type InlayHintsConfig =
  -- { typeAnnotations: bool
  -- parameterNames: bool
  -- disableLongTooltip: bool }
  -- static member Default =
  --   { typeAnnotations = true
  --     parameterNames = true
  --     disableLongTooltip = true }
  inlayHints = {
    --do these really annoy anyone? why not have em on?
    enabled = true,
    typeAnnotations = true,
    -- Defaults to false, the more info the better, right?
    disableLongTooltip = false,
    parameterNames = true,
  },
  --     Debug: DebugDto option }
  --   type DebugConfig =
  -- { DontCheckRelatedFiles: bool
  --   CheckFileDebouncerTimeout: int
  --   LogDurationBetweenCheckFiles: bool
  --   LogCheckFileDuration: bool }
  --
  -- static member Default =
  --   { DontCheckRelatedFiles = false
  --     CheckFileDebouncerTimeout = 250
  --     LogDurationBetweenCheckFiles = false
  --     LogCheckFileDuration = false }
  --       }
  debug = {
    dontCheckRelatedFiles = false,
    checkFileDebouncerTimeout = 250,
    logDurationBetweenCheckFiles = false,
    logCheckFileDuration = false,
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
  AutomaticReloadWorkspace = true,
  AutomaticCodeLensRefresh = true,
  ShowSignatureOnCursorMove = true,
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
    "BufEnter",
    "BufWritePost",
    "CursorHold",
    "CursorHoldI",
    "InsertEnter",
    "InsertLeave",
  },
  FsiKeymapSend = "<M-cr>",
  FsiKeymapToggle = "<M-@>",
}

function M.GitFirstRootDir(n)
  local root
  root = util.find_git_ancestor(n)
  root = root or util.root_pattern("*.sln")(n)
  root = root or util.root_pattern("*.fsproj")(n)
  root = root or util.root_pattern("*.fsx")(n)
  return root
end

local function split_lines(value)
  value = string.gsub(value, "\r\n?", "\n")
  return vim.split(value, "\n", { trimempty = true })
end

---matches a document signature command request originally meant for vscode's commands
---@param s string
---@return string|nil, string|nil
local function matchFsharpDocSigRequest(s)
  local link_pattern = "<a href='command:(.-)%?(.-)'>"
  return string.match(s, link_pattern)
end
local function returnFuncNameToCallFromCapture(s)
  local result = ((s or ""):gsub("%.", "/")) -- print("funcName match result : " .. result)
  result = string.gsub(result, "showDocumentation", "documentationSymbol")

  return result
end
---comment
---@param input string
---@return string
local function unHtmlify(input)
  input = input or ""
  -- print("unHtmlify input: " .. input)
  local result
  if #input > 2 then
    result = input:gsub("%%%x%x", function(entity)
      entity = entity or ""
      if #entity > 2 then
        return string.char(tonumber(entity:sub(2), 16))
      else
        return entity
      end
    end)
  else
    result = input
  end

  -- print("unHtmlify result: " .. result)
  return result
end
--- gets the various parts given by hover request and returns them
---@param input_string string
---function name
---@return string
---escapedHtml
---@return string
---DocumentationForSymbolRequest
---@return FSharpDocumentationForSymbolRequest
---label
---@return string
local function parse_string(input_string)
  local function_capture, json_capture = matchFsharpDocSigRequest(input_string)
  if function_capture then
    M.notify(function_capture)
    if json_capture then
      M.notify(json_capture)
      local function_name = returnFuncNameToCallFromCapture(function_capture)
      local unHtml = unHtmlify(json_capture)
      unHtml = unHtml
      -- print("unHtml :", unHtml)
      local decoded = (vim.json.decode(unHtml) or {
        {
          XmlDocSig = "NoProperSigGiven",
          AssemblyName = "NoProperAssemblyGiven",
        },
      })[1]
      -- M.notify("after decode: " .. vim.inspect(decoded))
      ---@type FSharpDocumentationForSymbolRequest
      local decoded_json = M.DocumentationForSymbolRequest(decoded.XmlDocSig, decoded.AssemblyName)
      M.notify({ "as symbolrequest: ", decoded_json })
      local label_text = input_string:match(">(.-)<")
      return function_name, unHtml, decoded_json, label_text
    else
      return input_string, "", M.DocumentationForSymbolRequest("NoProperSigGiven", "NoProperAssemblyGiven"), ""
    end
    return input_string, "", M.DocumentationForSymbolRequest("NoProperSigGiven", "NoProperAssemblyGiven"), ""
  end
  return input_string, "", M.DocumentationForSymbolRequest("NoProperSigGiven", "NoProperAssemblyGiven"), ""
end

function M.ParseAndReformatShowDocumentationFromHoverResponseContentLines(input, contents)
  -- -- value = string.gsub(value, "\r\n?", "\n")
  -- local thisIonide = vim.lsp.get_active_clients({ name = "ionide" })[1]
  local result
  contents = contents or {}

  if type(input) == "string" then
    -- local lines = vim.split(value, "\n", { trimempty = true })
    local parsedOrFunctionName, escapedHtml, decodedJsonTable, labelText = parse_string(input)
    if input == parsedOrFunctionName then
      -- print("no Match for line " .. line)
      result = input
    else
      if decodedJsonTable then
        -- result = ""
        --   .. " "
        --   .. "FunctionToCall: "
        --   .. parsedOrFunctionName
        --   .. " WithParams: "
        --   .. vim.inspect(decodedJsonTable)
        -- if not line == parsedOrFunctionName then
        -- print("decoded json looks like : " .. vim.inspect(decodedJsonTable))
        -- print(decodedJsonTable.XmlDocSig, decodedJsonTable.AssemblyName)
        -- if thisIonide then
        -- M.DocumentationForSymbolRequest(decodedJsonTable.XmlDocSig, decodedJsonTable.AssemblyName)
        vim.schedule_wrap(function()
          vim.lsp.buf_request(0, parsedOrFunctionName, decodedJsonTable, function(e, r)
            result = vim.inspect(e) .. vim.inspect(r)
            M.notify("results from request " .. vim.inspect(parsedOrFunctionName) .. ":" .. result)
            table.insert(contents, result)
          end)
        end)
        -- else
        -- print("noActiveIonide.. probably testing ")
        -- end
      else
        print("no decoded json")
      end
    end
  else
    -- MarkupContent
    if input.kind then
      -- The kind can be either plaintext or markdown.
      -- If it's plaintext, then wrap it in a <text></text> block

      -- Some servers send input.value as empty, so let's ignore this :(
      local value = input.value or ""

      if input.kind == "plaintext" then
        -- wrap this in a <text></text> block so that stylize_markdown
        -- can properly process it as plaintext
        value = string.format("<text>\n%s\n</text>", value)
      end

      -- assert(type(value) == 'string')
      vim.list_extend(contents, split_lines(value))
      -- MarkupString variation 2
    elseif input.language then
      -- Some servers send input.value as empty, so let's ignore this :(
      -- assert(type(input.value) == 'string')
      table.insert(contents, "```" .. input.language)
      vim.list_extend(contents, split_lines(input.value or ""))
      table.insert(contents, "```")
      -- By deduction, this must be MarkedString[]
    else
      for _, marked_string in ipairs(input) do
        M.ParseAndReformatShowDocumentationFromHoverResponseContentLines(marked_string, contents)
      end
    end
    if (contents[1] == "" or contents[1] == nil) and #contents == 1 then
      return {}
    end
  end
  return contents
end

-- print(vim.inspect(parselinesForfsharpDocs({
--   "this line should be left alone ",
--   "<a href='command:fsharp.showDocumentation?%5B%7B%20%22XmlDocSig%22%3A%20%22T%3AFabload.Main.CLIArguments%22%2C%20%22AssemblyName%22%3A%20%22main%22%20%7D%5D'>Open the documentation</a>",
--   "this line should be left alone after the thingy ",
-- })))
--
--- Handlers ---

--see: https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_documentHighlight
M["textDocument/documentHighlight"] = function(error, result, context, config)
  if not error then
    vim.lsp.handlers["textDocument/documentHighlight"](error, result, context, config)
  end
end

M["textDocument/hover"] = function(error, result, context, config)
  M.notify(
    "handling "
      .. "textDocument/hover"
      .. " | "
      .. "result is: \n"
      .. vim.inspect({ error or "", result or "", context or "", config or "" })
  )
  if result then
    if result.content then
    end
  end
  vim.lsp.handlers.hover(error or {}, result or {}, context or {}, config or {})
end

M["fsharp/documentationSymbol"] = function(error, result, context, config)
  M.notify(
    "handling "
      .. "fsharp/documentationSymbol"
      .. " | "
      .. "result is: \n"
      .. vim.inspect({ error or "", result or "", context or "", config or "" })
  )
  if result then
    if result.content then
    end
  end
end

M["fsharp/notifyWorkspace"] = function(payload)
  -- M.notify("handling notifyWorkspace")
  local content = vim.json.decode(payload.content)
  -- M.notify("notifyWorkspace Decoded content is : \n"..vim.inspect(content))
  if content then
    if content.Kind == "projectLoading" then
      M.notify("Loading " .. vim.fs.normalize(content.Data.Project))
      -- M.notify("now calling AddOrUpdateThenSort on table  " .. vim.inspect(Workspace))
      --
      -- table.insert( M.Projects, content.Data.Project)
      -- -- local dir = vim.fs.dirname(content.Data.Project)
      -- M.notify("after attempting to reassign table value it looks like this : " .. vim.inspect(Workspace))
    elseif content.Kind == "project" then
      local k = content.Data.Project
      local projInfo = {}
      projInfo[k] = content.Data

      M.Projects = vim.tbl_deep_extend("force", M.Projects, projInfo)
    elseif content.Kind == "workspaceLoad" and content.Data.Status == "finished" then
      -- M.notify("calling updateServerConfig ... ")
      -- M.notify("before calling updateServerconfig, workspace looks like:   " .. vim.inspect(Workspace))

      for proj, projInfoData in pairs(M.Projects) do
        local dir = vim.fs.dirname(proj)
        if vim.tbl_contains(M.projectFolders, dir) then
        else
          table.insert(M.projectFolders, dir)
        end
      end
      -- M.notify("after calling updateServerconfig, workspace looks like:   " .. vim.inspect(Workspace))
      local projectCount = vim.tbl_count(M.Projects)
      if projectCount > 0 then
        local util = require("vim.lsp.util")
        local projNames = util.convert_input_to_markdown_lines(vim.tbl_map(function(s)
          return vim.fn.fnamemodify(s, ":P:.")
        end, vim.tbl_keys(M.Projects)))
        if projectCount > 1 then
          M.notify("Loaded " .. projectCount .. " projects:")
        else
          M.notify("Loaded 1 project:")
        end
        for _, projName in pairs(projNames) do
          M.notify("Loaded " .. vim.fs.normalize(vim.inspect(projName)))
        end
      else
        M.notify("Workspace is empty! Something went wrong. ")
      end
      local deleteMeFiles = vim.fs.find(function(name, _)
        return name:match(".*TempFileForProjectInitDeleteMe.fs$")
      end, { type = "file" })
      if deleteMeFiles then
        for _, file in ipairs(deleteMeFiles) do
          pcall(os.remove, file)
        end
      end
    end
  end
end

M["fsharp/workspaceLoad"] = function(result)
  M.notify(
    "handling workspaceLoad response\n"
      .. "result is: \n"
      .. vim.inspect(result or "result could not be read correctly")
  )
  if result then
    local resultContent = result.content
    if resultContent ~= nil then
      local content = vim.json.decode(resultContent)
      M.notify("json decode of payload content : " .. vim.inspect(content or "not decoded"))
      if content then
        -- M.notify( "Ionide Workspace Load Status: "
        --  ..  vim.inspect(content.Status or "result.content could not be read correctly")
        -- )
      end
    end
  end
end

M["fsharp/workspacePeek"] = function(error, result, context, config)
  if result then
    local resultContent = result.content
    -- M.notify(
    --   "handling workspacePeek response\n"
    --     .. "result is: \n"
    --     .. vim.inspect(resultContent or "result.content could not be read correctly")
    -- )
    ---@type Solution []
    local solutions = {}
    local directory
    if resultContent ~= nil then
      local content = vim.json.decode(resultContent)
      -- M.notify("json decode of payload content : ".. vim.inspect(content or "not decoded"))
      if content then
        -- M.notify("json decode of payload content successful")
        local kind = content.Kind
        if kind and kind == "workspacePeek" then
          -- M.notify("workspace peek is content kind")
          local data = content.Data
          if data ~= nil then
            -- M.notify("Data not null")
            local found = data.Found
            if found ~= nil then
              -- M.notify("data.Found not null")

              ---@type Project[]
              local projects = {}
              for _, item in ipairs(found) do
                if item.Type == "solution" then
                  table.insert(solutions, item)
                elseif item.Type == "directory" then
                  directory = vim.fs.normalize(item.Data.Directory)
                elseif item.Kind.Kind == "msbuildformat" then
                  table.insert(projects, item)
                else -- else left in case I want some other type to be dealt with..
                  M.notify("Unaccounted for item type in workspacePeek handler, " .. item.Type)
                end
              end
              local cwd = vim.fs.normalize(vim.fn.getcwd())
              if directory == cwd then
                -- M.notify("WorkspacePeek directory \n"
                --   ..
                --   directory
                --   ..
                --   "\nEquals current working directory\n"
                --   .. cwd
                -- )
              else
                M.notify(
                  "WorkspacePeek directory \n" .. directory .. "Does not equal current working directory\n" .. cwd
                )
              end
              -- local solutionToLoad
              local finalChoice
              if #solutions > 0 then
                -- M.notify(vim.inspect(#solutions) .. " solutions found in workspace")
                if #solutions > 1 then
                  -- M.notify("More than one solution found in workspace!")
                  vim.ui.select(solutions, {
                    prompt = "More than one solution found in workspace. Please pick one to load:",

                    format_item = function(item)
                      return vim.fn.fnamemodify(vim.fs.normalize(item.Data.Path), ":p:.")
                    end,
                  }, function(_, index)
                    finalChoice = solutions[index]
                  end)
                else
                  finalChoice = solutions[1]
                end

                finalChoice = finalChoice
                  or {
                    Data = {
                      Path = vim.fn.getcwd(),
                      Items = {
                        Name = vim.fs.find(function(name, _)
                          return name:match(".*%.[cf]sproj$")
                        end, { type = "file" }),
                      },
                    },
                  }
                local finalPath = vim.fs.normalize(finalChoice.Data.Path)
                M.notify("Loading solution : " .. vim.fn.fnamemodify(vim.fs.normalize(finalPath), ":p:."))

                ---@type string[]
                local pathsToLoad = {}
                local projects = finalChoice.Data.Items
                for _, project in ipairs(projects) do
                  if project.Name:match("sproj") then
                    table.insert(pathsToLoad, vim.fs.normalize(project.Name))
                  end
                end

                M.notify("Going to ask FsAutoComplete to load these project paths.. " .. vim.inspect(pathsToLoad))
                local projectParams = {}
                for _, path in ipairs(pathsToLoad) do
                  table.insert(projectParams, M.CreateFSharpProjectParams(path))
                end
                M.CallFSharpWorkspaceLoad(pathsToLoad)
                for _, proj in ipairs(projectParams) do
                  vim.lsp.buf_request(0, "fsharp/project", { proj }, function(payload)
                    -- M.notify("fsharp/project load request has a payload of :  " .. vim.inspect( payload or "No Result from Server"))
                  end)
                end

                -- if solutionToLoad ~= nil then
                --   M.notify("solutionToLoad is set to " ..
                --     solutionToLoad .. " \nthough currently that doesn't do anything..")
                -- else
                --   M.notify("for some reason solution to load was null. .... why?")
                -- end
              else
                M.notify("Only one solution in workspace path, projects should be loaded already. ")
              end
            else
              -- M.notify("for some reason data.Found was null. .... why?")
            end
          else
            -- M.notify("for some reason content.Data was null. .... why?")
          end
        else
          -- M.notify("content.Type wasn't workspace peek.. that should be impossible.. .... why?")
        end
      else
        -- M.notify("no content from Json decode? but it isn't null.... why?")
      end
    else
      -- M.notify("no content from Json decode? but it isn't null.... why?")
    end
    -- else
    --   M.notify("no result from workspace peek! WHY??!")
  end
end

M["fsharp/compilerLocation"] = function(error, result, context, config)
  M.notify(
    "handling compilerLocation response\n"
      .. "result is: \n"
      .. vim.inspect({ error or "", result or "", context or "", config or "" })
  )
end

M["workspace/workspaceFolders"] = function(error, result, context, config)
  if result then
    M.notify(
      "handling workspace/workspaceFolders response\n"
        .. "result is: \n"
        .. vim.inspect({ error or "", result or "", context or "", config or "" })
    )
  end
  local client_id = context.client_id
  local client = vim.lsp.get_client_by_id(client_id)
  if not client then
    -- vim.err_message("LSP[id=", client_id, "] client has shut down after sending the message")
    return
  end
  return client.workspace_folders or vim.NIL
end

M["fsharp/signature"] = function(error, result, context, config)
  if result then
    if result.result then
      if result.result.content then
        local content = vim.json.decode(result.result.content)
        if content then
          if content.Data then
            -- Using gsub() instead of substitute() in Lua
            -- and % instead of :
            M.notify(content.Data:gsub("\n+$", " "))
          end
        end
      end
    end
  end
end

function M.CreateHandlers()
  local h = {
    "fsharp/notifyWorkspace",
    "fsharp/documentationSymbol",
    "fsharp/workspacePeek",
    "fsharp/workspaceLoad",
    "fsharp/compilerLocation",
    "fsharp/signature",
    "textDocument/hover",
    "textDocument/documentHighlight",
  }
  local r = {}
  for _, method in ipairs(h) do
    r[method] = function(err, params, ctx, config)
      if method == "fsharp/compilerLocation" then
        M[method](err or "No Error", params or "No Params", ctx or "No Context", config or "No Configs")
      elseif method == "fsharp/documentationSymbol" then
        M[method](err or "No Error", params or "No Params", ctx or "No Context", config or "No Configs")
      else
        M[method](params)
      end
    end
  end
  M.Handlers = vim.tbl_deep_extend("force", M.Handlers, r)
  return r
end

---@type IonideOptions
M.DefaultLspConfig = {
  IonideNvimSettings = M.DefaultNvimSettings,
  filetypes = { "fsharp" },
  name = "ionide",
  cmd = M.DefaultNvimSettings.FsautocompleteCommand,
  -- cmd_env = M.DefaultNvimSettings.FsautocompleteCommand,
  autostart = true,
  handlers = M.CreateHandlers(),
  init_options = { AutomaticWorkspaceInit = M.DefaultNvimSettings.AutomaticWorkspaceInit },
  -- on_attach = function(client, bufnr)
  -- local isProjFile = vim.bo[bufnr].filetype == "fsharp_project"
  -- if isProjFile then
  --   if lspconfig_is_present then
  --     local lspconfig = require("lspconfig")
  --   end
  -- else
  --   return
  -- end

  -- end,
  -- on_new_config = M.Initialize,
  on_init = function()
    M.Initialize()
  end,
  settings = { FSharp = M.DefaultServerSettings },
  root_dir = M.GitFirstRootDir,
  log_level = lsp.protocol.MessageType.Warning,
  message_level = lsp.protocol.MessageType.Warning,
  capabilities = lsp.protocol.make_client_capabilities(),
}

neoconf.register({
  on_schema = function(schema)
    if schema then
      ---@diagnostic disable-next-line
      if schema.import then
        ---@diagnostic disable-next-line
        schema:import("ionide", M.DefaultLspConfig)
      end
    end
  end,
})
---@type IonideOptions
M.PassedInConfig = { settings = { FSharp = {} } }

M.Manager = nil

---@param content any
---@returns PlainNotification
function M.PlainNotification(content)
  -- return vim.cmd("return 'Content': a:" .. content .. " }")
  return { Content = content }
end

---creates a textDocumentIdentifier from a string path
---@param path string
---@return lsp.TextDocumentIdentifier
function M.TextDocumentIdentifier(path)
  local usr_ss_opt = vim.o.shellslash
  vim.o.shellslash = true
  local uri = vim.fn.fnamemodify(path, ":p")
  if string.sub(uri, 1, 1) == "/" then
    uri = "file://" .. uri
  else
    uri = "file:///" .. uri
  end
  vim.o.shellslash = usr_ss_opt

  ---@type lsp.TextDocumentIdentifier
  return { Uri = uri }
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
  return {
    Project = M.TextDocumentIdentifier(projectUri),
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

---Calls the Lsp server endpoint with the method name, parameters
---@param method (string) LSP method name
---@param params table|nil Parameters to send to the server
---@param handler function|nil optional handler to use instead of the default method.
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
  ---@type lsp-handler
  handler = handler or M.Handlers[method]
  return lsp.buf_request(0, method, params, handler)
end

function M.CallLspNotify(method, params)
  lsp.buf_notify(0, method, params)
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

function M.CallFSharpLineLens(projectPath, handler)
  return M.Call("fsharp/lineLens", M.CreateFSharpProjectParams(projectPath), handler)
end

function M.CallFSharpCompilerLocation(handler)
  return M.Call("fsharp/compilerLocation", {}, handler)
end

---Calls "fsharp/compile" on the given project file
---@param projectPath string
---@return nil
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
---@return nil
---@return table<integer, integer>, fun() 2-tuple:
---  - Map of client-id:request-id pairs for all successful requests.
---  - Function which can be used to cancel all the requests. You could instead
---    iterate all clients and call their `cancel_request()` methods.
function M.CallFSharpWorkspacePeek(directoryPath, depth, excludedDirs, handler)
  return M.Call("fsharp/workspacePeek", M.CreateFSharpWorkspacePeekRequest(directoryPath, depth, excludedDirs), handler)
end

---Call to "fsharp/workspaceLoad"
---@param projectFiles string[]  a string list of project files.
---@return nil
---@return table<integer, integer>, fun() 2-tuple:
---  - Map of client-id:request-id pairs for all successful requests.
---  - Function which can be used to cancel all the requests. You could instead
---    iterate all clients and call their `cancel_request()` methods.
function M.CallFSharpWorkspaceLoad(projectFiles, handler)
  return M.Call("fsharp/workspaceLoad", M.CreateFSharpWorkspaceLoadParams(projectFiles), handler)
end

---call to "fsharp/project" - which, after using projectPath to create an FSharpProjectParms, loads given project
---@param projectPath string
---@return nil
---@return table<integer, integer>, fun() 2-tuple:
---  - Map of client-id:request-id pairs for all successful requests.
---  - Function which can be used to cancel all the requests. You could instead
---    iterate all clients and call their `cancel_request()` methods.
function M.CallFSharpProject(projectPath, handler)
  return M.Call("fsharp/project", M.CreateFSharpProjectParams(projectPath), handler)
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
---@return nil
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
---@return nil
---@return table<integer, integer>, fun() 2-tuple:
---  - Map of client-id:request-id pairs for all successful requests.
---  - Function which can be used to cancel all the requests. You could instead
---    iterate all clients and call their `cancel_request()` methods.
function M.CallFSharpDocumentationSymbol(xmlSig, assembly, handler)
  return M.Call("fsharp/documentationSymbol", M.DocumentationForSymbolRequest(xmlSig, assembly), handler)
end

---this should take the settings.FSharp table
---@param newSettingsTable _.lspconfig.settings.fsautocomplete.FSharp
function M.UpdateServerConfig(newSettingsTable)
  -- local input = vim.fn.input({ prompt = "Attach your debugger, to process " .. vim.inspect(vim.fn.getpid()) })
  M.CallLspNotify("workspace/didChangeConfiguration", newSettingsTable)
end

---Loads the given projects list.
---@param projects string[] -- projects only
---@return table<integer, integer>, fun() 2-tuple:
---  - Map of client-id:request-id pairs for all successful requests.
---  - Function which can be used to cancel all the requests. You could instead
---    iterate all clients and call their `cancel_request()` methods.
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
  for proj, projInfo in pairs(M.Projects) do
    M.notify("- " .. vim.fs.normalize(proj))
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

function M.ShowIonideClientWorkspaceFolders()
  ---@type lsp.Client|nil
  local client = M.getIonideClientAttachedToCurrentBufferOrFirstInActiveClients()
  if client then
    local folders = client.workspace_folders or {}
    M.notify("WorkspaceFolders: \n" .. vim.inspect(folders))
  else
    M.notify("No ionide client found, no workspace folders to show! \n")
  end
end

function M.ShowNvimSettings()
  M.notify("NvimSettings: \n" .. vim.inspect(M.MergedConfig.IonideNvimSettings))
end

function M.ShowConfigs()
  -- M.notify("Last passed in Config: \n" .. vim.inspect(M.PassedInConfig))
  M.notify("Last final merged Config: \n" .. vim.inspect(M.MergedConfig))
  M.ShowIonideClientWorkspaceFolders()
end

---applies a recommended color scheme for diagnostics and CodeLenses
function M.ApplyRecommendedColorscheme()
  vim.cmd([[
    highlight! LspDiagnosticsDefaultError ctermbg=Red ctermfg=White
    highlight! LspDiagnosticsDefaultWarning ctermbg=Yellow ctermfg=Black
    highlight! LspDiagnosticsDefaultInformation ctermbg=LightBlue ctermfg=Black
    highlight! LspDiagnosticsDefaultHint ctermbg=Green ctermfg=White
    highlight! default link LspCodeLens Comment
]])
end

function M.RegisterAutocmds()
  autocmd({ "LspAttach" }, {
    desc = "FSharp clear code lens on attach ",
    group = grp("FSharp_ClearCodeLens", { clear = true }),
    pattern = "*.fs,*.fsi,*.fsx",
    callback = function(args)
      local codelensConfig = {
        references = { enabled = false },
        signature = { enabled = false },
      }
      if M.MergedConfig.settings and M.MergedConfig.settings.FSharp and M.MergedConfig.settings.FSharp.codeLenses then
        codelensConfig = M.MergedConfig.settings.FSharp.codeLenses
      end
      if codelensConfig.references.enabled == true or codelensConfig.signature.enabled == true then
        vim.defer_fn(function()
          vim.lsp.codelens.clear()
          vim.lsp.codelens.refresh()
          vim.lsp.codelens.refresh()
          -- M.notify("lsp codelens refreshing")
        end, 7000)
      end
    end,
  })

  autocmd({ "LspAttach" }, {
    desc = "FSharp enable inlayHint on attach ",
    group = grp("FSharp_enableInlayHint", { clear = true }),
    pattern = "*.fs,*.fsi,*.fsx",
    callback = function(args)
      -- args.data.client_id
      if M.MergedConfig.settings.FSharp.inlayHints.enabled == true then
        vim.defer_fn(function()
          -- M.notify("enabling lsp inlayHint")
          vim.lsp.buf.inlay_hint(args.buf, true)
        end, 2000)
      else
        -- M.notify("lsp inlayHints are not enabled.")
      end
    end,
  })

  autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
    desc = "FSharp Auto refresh code lens ",
    group = grp("IonideAutomaticCodeLensRefresh", { clear = true }),
    pattern = "*.fs,*.fsi,*.fsx",
    callback = function(arg)
      if
        M.MergedConfig.settings.FSharp.codeLenses.references.enabled == true
        or M.MergedConfig.settings.FSharp.codeLenses.references.enabled == true
      then
        if M.MergedConfig.IonideNvimSettings.AutomaticCodeLensRefresh == true then
          vim.defer_fn(function()
            vim.lsp.codelens.refresh()
            -- M.notify("lsp codelens refreshing")
          end, 2000)
        end
      end
    end,
  })

  autocmd({ "CursorHold,InsertLeave" }, {
    desc = "Ionide Show Signature on cursor move or hold",
    group = grp("FSharp_ShowSignatureOnCursorMoveOrHold", { clear = true }),
    pattern = "*.fs,*.fsi,*.fsx",
    callback = function()
      if M.MergedConfig.IonideNvimSettings.ShowSignatureOnCursorMove == true then
        vim.defer_fn(function()
          local pos = vim.inspect_pos(
            vim.api.nvim_get_current_buf(),
            nil,
            nil,
            ---@type InspectorFilter
            {
              extmarks = false,
              syntax = false,
              semantic_tokens = false,
              treesitter = false,
            }
          )
          M.CallFSharpSignature(vim.uri_from_bufnr(pos.buffer), pos.col, pos.row)
        end, 1000)
      end
    end,
  })

  autocmd({ "BufReadPost" }, {
    desc = "Apply Recommended Colorscheme to Lsp Diagnostic and Code lenses.",
    group = grp("FSharp_ApplyRecommendedColorScheme", { clear = true }),
    pattern = "*.fs,*.fsi,*.fsx",
    callback = function()
      if M.MergedConfig.IonideNvimSettings.LspRecommendedColorScheme == true then
        M.ApplyRecommendedColorscheme()
      end
    end,
  })
end

function M.Initialize()
  if not vim.fn.has("nvim") then
    M.notify("WARNING - This version of Ionide is only for NeoVim. please try Ionide/Ionide-Vim instead. ")
    return
  end

  M.notify("Initializing")

  M.notify("Calling updateServerConfig...")
  M.UpdateServerConfig(M.MergedConfig.settings.FSharp)

  M.notify("Setting Keymaps...")
  M.SetKeymaps()
  M.notify("Registering Autocommands...")
  M.RegisterAutocmds()
  local thisBufnr = vim.api.nvim_get_current_buf()
  local thisBufname = vim.api.nvim_buf_get_name(thisBufnr)
  ---@type lsp.Client
  local thisIonide = vim.lsp.get_active_clients({ bufnr = thisBufnr, name = "ionide" })[1]
    or { workspace_folders = { { vim.fn.getcwd() } } }

  local thisBufIonideRootDir = thisIonide.workspace_folders[1][1] -- or vim.fn.getcwd()
  M.CallFSharpWorkspacePeek(
    thisBufIonideRootDir,
    M.MergedConfig.settings.FSharp.workspaceModePeekDeepLevel,
    M.MergedConfig.settings.FSharp.excludeProjectDirectories
  )
  M.notify("Fully Initialized!")
end

-- M.Manager = nil
function M.AutoStartIfNeeded(config)
  local auto_setup = (M.MergedConfig.IonideNvimSettings.LspAutoSetup == true)
  if auto_setup and not (config.autostart == false) then
    M.Autostart()
  end
end

function M.DelegateToLspConfig(config)
  -- M.notify("calling DelegateToLspConfig")
  local lspconfig = require("lspconfig")
  local configs = require("lspconfig.configs")
  if not configs["ionide"] then
    -- M.notify("creating entry in lspconfig configs for ionide ")
    configs["ionide"] = {
      default_config = config,
      docs = {
        description = [[
          WARNING: This version of ionide is a fork,
          and absolutely useless to anyone not runnning Neovim.
          I will not be maintaining support for regular vim.
          In fact, it shouldn't even run, it should just direct you to
          the community maintained official one. This is
          my version that I've sunk stupid amounts of time into,
          and it's meant to be a better alternative.
          https://github.com/willehrendreich/Ionide-vim ]],
      },
    }
  end

  lspconfig.ionide.setup(config)

  -- M.notify("calling lspconfig setup for ionide ")
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
          -- vim.bo[bufnr].comments = "<!--,e:-->"
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
          -- comment settings
          vim.bo[bufnr].formatoptions = "croql"
          -- vim.bo[bufnr].commentstring = "(*%s*)"
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
          -- vim.bo[bufnr].commentstring = "(*%s*)"
          vim.bo[bufnr].comments = [[s0:*\ -,m0:*\ \ ,ex0:*),s1:(*,mb:*,ex:*),:\/\/\/,:\/\/]]
        end
    end,
  },
})

autocmd("BufWritePost", {
  pattern = "*.fsproj",
  desc = "FSharp Auto refresh on project save",
  group = vim.api.nvim_create_augroup("FSProjRefreshOnProjectSave", { clear = true }),
  callback = function()
    M.OnFSProjSave()
  end,
})

autocmd({ "BufReadPost" }, {
  desc = "FSharp start Ionide on fsharp_project load",
  group = grp("FSProjStartIonide", { clear = true }),
  pattern = "*.fsproj",
  callback = function()
    local bufnr = vim.api.nvim_get_current_buf()
    local bufname = vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr))
    local projectRoot = vim.fs.normalize(M.GitFirstRootDir(bufname))

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
    local ionideClientsList = vim.lsp.get_active_clients({ name = "ionide" })
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

---Create Ionide Manager
---@param config IonideOptions
local function create_manager(config)
  validate({
    cmd = { config.cmd, "t", true },
    root_dir = { config.root_dir, "f", true },
    filetypes = { config.filetypes, "t", true },
    on_attach = { config.on_attach, "f", true },
    on_new_config = { config.on_new_config, "f", true },
  })

  config = vim.tbl_deep_extend("keep", config, M.DefaultLspConfig)

  local _
  if config.filetypes then
    _ = "FileType " .. table.concat(config.filetypes, ",")
  else
    _ = "BufReadPost *"
  end

  local get_root_dir = config.root_dir

  function M.Autostart()
    ---@type string
    local root_dir = vim.fs.normalize(
      get_root_dir(api.nvim_buf_get_name(0), api.nvim_get_current_buf())
        or util.path.dirname(vim.fn.fnamemodify("%", ":p"))
        or vim.fn.getcwd()
    )
    api.nvim_command(
      string.format("autocmd %s lua require'ionide'.manager.try_add_wrapper()", "BufReadPost " .. root_dir .. "/*")
    )
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      local buf_dir = api.nvim_buf_get_name(bufnr)
      if buf_dir:sub(1, root_dir:len()) == root_dir then
        M.Manager.try_add_wrapper(bufnr)
      end
    end
  end

  local reload = false
  if M.Manager then
    for _, client in ipairs(M.Manager.clients()) do
      client.stop(true)
    end
    reload = true
    M.Manager = nil
  end

  function M.MakeConfig(_root_dir)
    ---@type lspconfig.options.fsautocomplete
    local new_config = vim.tbl_deep_extend("keep", vim.empty_dict(), config)
    new_config = vim.tbl_deep_extend("keep", new_config, M.DefaultLspConfig)
    new_config.capabilities = new_config.capabilities or lsp.protocol.make_client_capabilities()
    new_config.capabilities = vim.tbl_deep_extend("keep", new_config.capabilities, {
      workspace = {
        configuration = true,
      },
    })
    if config.on_new_config then
      pcall(config.on_new_config, new_config, _root_dir)
    end
    new_config.on_init = util.add_hook_after(new_config.on_init, function(client, _)
      function client.workspace_did_change_configuration(settings)
        if not settings then
          return
        end
        if vim.tbl_isempty(settings) then
          settings = { [vim.type_idx] = vim.types.dictionary }
        end
        local settingsInspected = vim.inspect(settings)
        M.notify("Settings being sent to LSP server are: " .. settingsInspected)
        return client.notify("workspace/didChangeConfiguration", {
          settings = settings,
        })
      end

      if not vim.tbl_isempty(new_config.settings) then
        local settingsInspected = vim.inspect(new_config.settings)
        M.notify("Settings being sent to LSP server are: " .. settingsInspected)
        client.workspace_did_change_configuration(new_config.settings)
      end
    end)
    new_config._on_attach = new_config.on_attach
    new_config.on_attach = vim.schedule_wrap(function(client, bufnr)
      if bufnr == api.nvim_get_current_buf() then
        M._setup_buffer(client.id, bufnr)
      else
        api.nvim_command(
          string.format(
            "autocmd BufEnter <buffer=%d> ++once lua require'ionide'._setup_buffer(%d,%d)",
            bufnr,
            client.id,
            bufnr
          )
        )
      end
    end)
    new_config.root_dir = _root_dir
    return new_config
  end

  local manager = util.server_per_root_dir_manager(function(_root_dir)
    return M.MakeConfig(_root_dir)
  end)

  function manager.try_add(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    ---@diagnostic disable-next-line
    if api.nvim_buf_get_option(bufnr, "buftype") == "nofile" then
      return
    end
    local root_dir = get_root_dir(api.nvim_buf_get_name(bufnr), bufnr)
    local id = manager.add(root_dir)
    if id then
      lsp.buf_attach_client(bufnr, id)
    end
  end

  function manager.try_add_wrapper(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    ---@diagnostic disable-next-line
    local buftype = api.nvim_buf_get_option(bufnr, "filetype")
    if buftype == "fsharp" then
      manager.try_add(bufnr)
      return
    end
  end

  M.Manager = manager
  if reload and not (config.autostart == false) then
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      manager.try_add_wrapper(bufnr)
    end
  else
    M.AutoStartIfNeeded(config)
  end
end

-- partially adopted from neovim/nvim-lspconfig, see lspconfig.LICENSE.md
function M._setup_buffer(client_id, bufnr)
  local client = lsp.get_client_by_id(client_id)
  if not client then
    return
  end
  if client.config._on_attach then
    client.config._on_attach(client, bufnr)
  end
end

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

function M.setup(config)
  M.PassedInConfig = config or {}
  -- M.notify("entered setup for ionide: passed in config is  " .. vim.inspect(M.PassedInConfig))
  M.MergedConfig = vim.tbl_deep_extend("force", M.DefaultLspConfig, M.PassedInConfig)
  -- M.notify("entered setup for ionide: passed in config merged with defaults gives us " .. vim.inspect(M.MergedConfig))
  M.UpdateServerConfig(M.MergedConfig.settings.FSharp)
  M.InitializeDefaultFsiKeymapSettings()

  if lspconfig_is_present then
    return M.DelegateToLspConfig(M.MergedConfig)
  end
  return create_manager(M.MergedConfig)
end

function M.status()
  if lspconfig_is_present then
    -- print("* LSP server: handled by nvim-lspconfig")

    -- local ionide = lsp.buf.inlay_hint(0, true)
    vim.inspect(lsp.buf.list_workspace_folders())
  elseif M.Manager ~= nil then
    if next(M.Manager.clients()) == nil then
      print("* LSP server: not started")
    else
      print("* LSP server: started")
    end
  else
    print("* LSP server: not initialized")
  end
end

FsiBuffer = -1
local fsiJob = -1
local fsiWidth = 0
local fsiHeight = 0

uc("IonideResetIonideBufferNumber", function()
  FsiBuffer = -1
  vim.notify("Fsi buffer is now set to number " .. vim.inspect(FsiBuffer))
end, {
  desc = "Resets the current buffer that fsi is assigned to back to the invalid number -1, so that Ionide knows to recreate it.",
})

--"
--" function! s:win_gotoid_safe(winid)
--"     function! s:vimReturnFocus(window)
--"         call win_gotoid(a:window)
--"         redraw!
--"     endfunction
--"     if has('nvim')
--"         call win_gotoid(a:winid)
--"     else
--"         call timer_start(1, { -> s:vimReturnFocus(a:winid) })
--"     endif
--" endfunction
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

--"
--" function! s:get_fsi_command()
--"     let cmd = g:fsharp#fsi_command
--"     for prm in g:fsharp#fsi_extra_parameters
--"         let cmd = cmd . " " . prm
--"     endfor
--"     return cmd
--" endfunction

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
  then
    if M.MergedConfig.IonideNvimSettings and M.MergedConfig.IonideNvimSettings.FsiStdOutFileName then
      if M.MergedConfig.IonideNvimSettings.FsiStdOutFileName ~= "" then
        cmd = cmd .. " | tee '" .. (M.MergedConfig.IonideNvimSettings.FsiStdOutFileName or "./fsiOutputFile.txt") .. "'"
      else
        cmd = cmd .. " | tee '" .. "./fsiOutputFile.txt" .. "'"
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

-- function M.OpenFsi(returnFocus)
--   M.notify("OpenFsi got return focus as " .. vim.inspect(returnFocus))
--   local isNeovim = vim.fn.has('nvim')
--   if not isNeovim then
--     M.notify("This version of ionide is for Neovim only. please try www.github.com/ionide/ionide-vim")
--   end
--     if vim.fn.exists('*termopen') == true or vim.fn.exists('*term_start') then
--       --"             let current_win = win_getid()
--       local currentWin = vim.fn.win_getid()
--     M.notify("OpenFsi currentWin = " .. vim.inspect(currentWin))
--       --"             execute g:fsharp#fsi_window_command
--       vim.fn.execute(M.FsiWindowCommand or 'botright 10new')
--       -- "             if s:fsi_width  > 0 | execute 'vertical resize' s:fsi_width | endif
--       if fsiWidth > 0 then vim.fn.execute('vertical resize ' .. fsiWidth) end
--       --"             if s:fsi_height > 0 | execute 'resize' s:fsi_height | endif
--       if fsiHeight > 0 then vim.fn.execute('resize ' .. fsiHeight) end
--       --"             " if window is closed but FSI is still alive then reuse it
--       --"             if s:fsi_buffer >= 0 && bufexists(str2nr(s:fsi_buffer))
--       if FsiBuffer >= 0 and vim.fn.bufexists(FsiBuffer) then
--         --"                 exec 'b' s:fsi_buffer
--         vim.cmd('b' .. tostring(FsiBuffer))
--         --"                 normal G
--
--         vim.cmd("normal G")
--         --"                 if a:returnFocus | call s:win_gotoid_safe(current_win) | endif
--         if returnFocus then winGoToIdSafe(currentWin) end
--         --"             " open FSI: Neovim
--         --"             elseif has('nvim')
--   local bufWinid = vim.fn.bufwinid(FsiBuffer) or -1
--   M.notify("OpenFsi bufWinid = " .. vim.inspect(bufWinid))
--   if bufWinid <= 0 then
--     local cmd = getFsiCommand()
--     if isNeovim then
--       fsiJob = vim.fn.termopen(cmd)
--       M.notify("OpenFsi fsiJob is now  = " .. vim.inspect(fsiJob))
--       if fsiJob > 0 then
--         FsiBuffer = vim.fn.bufnr(vim.api.nvim_get_current_buf())
--       else
--         vim.cmd.close()
--         M.notify("failed to open FSI")
--         return -1
--       end
--     end
--   end
--   M.notify("This version of ionide is for Neovim only. please try www.github.com/ionide/ionide-vim")
--   if returnFocus then winGoToIdSafe(currentWin) end
--   return FsiBuffer
-- end
--
--"
--" function! fsharp#toggleFsi()
--"     let fsiWindowId = bufwinid(s:fsi_buffer)
--"     if fsiWindowId > 0
--"         let current_win = win_getid()
--"         call win_gotoid(fsiWindowId)
--"         let s:fsi_width = winwidth('%')
--"         let s:fsi_height = winheight('%')
--"         close
--"         call win_gotoid(current_win)
--"     else
--"         call fsharp#openFsi(0)
--"     endif
--" endfunction

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

--"
--" function! fsharp#quitFsi()
--"     if s:fsi_buffer >= 0 && bufexists(str2nr(s:fsi_buffer))
--"         if has('nvim')
--"             let winid = bufwinid(s:fsi_buffer)
--"             if winid > 0 | execute "close " . winid | endif
--"             call jobstop(s:fsi_job)
--"         else
--"             call job_stop(s:fsi_job, "term")
--"         endif
--"         let s:fsi_buffer = -1
--"         let s:fsi_job = -1
--"     endif
--" endfunction
--

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

--" function! fsharp#resetFsi()
--"     call fsharp#quitFsi()
--"     return fsharp#openFsi(1)
--" endfunction
--"
function M.ResetFsi()
  M.QuitFsi()
  M.OpenFsi(false)
end

--" function! fsharp#sendFsi(text)
--"     if fsharp#openFsi(!g:fsharp#fsi_focus_on_send) > 0
--"         " Neovim
--"         if has('nvim')
--"             call chansend(s:fsi_job, a:text . "\n" . ";;". "\n")
--"         " Vim 8
--"         else
--"             call term_sendkeys(s:fsi_buffer, a:text . "\<cr>" . ";;" . "\<cr>")
--"             call term_wait(s:fsi_buffer)
--"         endif
--"     endif
--" endfunction
-- "

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
  -- vim.cmd(':normal' .. vim.fn.len(lines) .. 'j')
  local lines = M.GetVisualSelection()

  -- vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<esc>", true, false, true), 'x', true)
  -- vim.cmd(':normal' .. ' j')
  -- vim.cmd('normal' .. vim.fn.len(lines) .. 'j')
  -- local text = vim.fn.join(lines, "\n")
  -- M.notify("fsi send selection " .. text)
  M.SendFsi(lines)

  -- local line_end, _ = unpack(vim.fn.getpos("'>"), 2)

  -- vim.cmd 'normal j'

  -- vim.cmd(':normal' .. ' j')
  -- vim.api.nvim_win_set_cursor(0, { line_end + 1, 0 })

  -- vim.cmd(':normal' .. vim.fn.len(lines) .. 'j')
end

function M.SendLineToFsi()
  local text = vim.api.nvim_get_current_line()
  local line, _ = unpack(vim.fn.getpos("."), 2)
  local lastline = vim.fn.line("w$")
  if line > lastline then
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

-- Parameters: ~
--   • {name}     Name of the new user command. Must begin with an uppercase
--                letter.
--   • {command}  Replacement command to execute when this user command is
--                executed. When called from Lua, the command can also be a
--                Lua function. The function is called with a single table
--                argument that contains the following keys:
--                • name: (string) Command name
--                • args: (string) The args passed to the command, if any
--                  |<args>|
--                • fargs: (table) The args split by unescaped whitespace
--                  (when more than one argument is allowed), if any
--                  |<f-args>|
--                • bang: (boolean) "true" if the command was executed with a
--                  ! modifier |<bang>|
--                • line1: (number) The starting line of the command range
--                  |<line1>|
--                • line2: (number) The final line of the command range
--                  |<line2>|
--                • range: (number) The number of items in the command range:
--                  0, 1, or 2 |<range>|
--                • count: (number) Any count supplied |<count>|
--                • reg: (string) The optional register, if specified |<reg>|
--                • mods: (string) Command modifiers, if any |<mods>|
--                • smods: (table) Command modifiers in a structured format.
--                  Has the same structure as the "mods" key of
--                  |nvim_parse_cmd()|.
--   • {opts}     Optional command attributes. See |command-attributes| for
--                more details. To use boolean attributes (such as
--                |:command-bang| or |:command-bar|) set the value to "true".
--                In addition to the string options listed in
--                |:command-complete|, the "complete" key also accepts a Lua
--                function which works like the "customlist" completion mode
--                |:command-completion-customlist|. Additional parameters:
--                • desc: (string) Used for listing the command when a Lua
--                  function is used for {command}.
--                • force: (boolean, default true) Override any previous
--                  definition.
--                • preview: (function) Preview callback for 'inccommand'
--                  |:command-preview|

-- uc("IonideUpdateServerConfiguration", function(opts)
--   -- if type(opts.fargs) == "string" then
--   -- elseif type(opts.fargs) == "table" then
--
--   -- M.notify("entered setup for ionide: passed in config is  " .. vim.inspect(M.PassedInConfig))
--   M.MergedConfig = vim.tbl_deep_extend("force", M.DefaultLspConfig, M.PassedInConfig)
--   -- M.notify("entered setup for ionide: passed in config merged with defaults gives us " .. vim.inspect(M.MergedConfig))
--   if M.MergedConfig.settings and M.MergedConfig.settings and M.MergedConfig.settings.FSharp then
--     M.UpdateServerConfig(M.MergedConfig.settings.FSharp)
--   else
--     M.UpdateServerConfig(M.DefaultServerSettings)
--   end
-- end, { desc = "Notify FSAC of the settings in merged settings table" })

uc("IonideTestDocumentationForSymbolRequestParsing", function()
  M.CallFSharpDocumentationSymbol("T:System.String.Trim", "netstandard")
end, { desc = "testing out the call to the symbol request from a hover" })
uc("IonideSendCurrentLineToFSI", M.SendLineToFsi, { desc = "Ionide - Send Current line's text to FSharp Interactive" })
uc("IonideSendWholeBufferToFSI", M.SendAllToFsi, { desc = "Ionide - Send Current buffer's text to FSharp Interactive" })
uc("IonideToggleFSI", M.ToggleFsi, { desc = "Ionide - Toggle FSharp Interactive" })
uc("IonideQuitFSI", M.QuitFsi, { desc = "Ionide - Quit FSharp Interactive" })
uc("IonideResetFSI", M.ResetFsi, { desc = "Ionide - Reset FSharp Interactive" })

uc("IonideShowConfigs", M.ShowConfigs, { desc = "Shows the merged config." })
uc("IonideShowWorkspaceFolders", M.ShowIonideClientWorkspaceFolders, {})
uc("IonideLoadProjects", function(opts)
  if type(opts.fargs) == "string" then
    local projTable = { opts.fargs }
    M.LoadProjects(projTable)
  elseif type(opts.fargs) == "table" then
    local projects = opts.fargs
    M.LoadProjects(projects)
  elseif opts.nargs > 1 then
    local projects = {}
    for _, proj in ipairs(opts.fargs) do
      table.insert(projects, proj)
    end
    M.LoadProjects(projects)
  else
    M.notify(opts)
  end
end, {})

uc("IonideShowLoadedProjects", M.ShowLoadedProjects, { desc = "Shows just the project names that have been loaded." })
uc("IonideShowNvimSettings", M.ShowNvimSettings, {})
uc("IonideShowAllLoadedProjectInfo", function()
  M.notify(M.Projects)
end, { desc = "Show all currently loaded Project Info" })
uc("IonideShowAllLoadedProjectFolders", function()
  M.notify(table.concat(M.projectFolders, "\n"))
end, { desc = "Show all currently loaded project folders" })
uc("IonideWorkspacePeek", function()
  local settingsFSharp = M.DefaultServerSettings
  if M.MergedConfig.settings and M.MergedConfig.settings.FSharp then
    settingsFSharp = M.MergedConfig.settings.FSharp
  end
  M.CallFSharpWorkspacePeek(
    M.getIonideClientConfigRootDirOrCwd(),
    settingsFSharp.workspaceModePeekDeepLevel or 3,
    settingsFSharp.excludeProjectDirectories or {}
  )
end, { desc = "Request a workspace peek from Lsp" })

return M

--
-- (function()
--   local function determineFsiPath(useNetCore, ifNetFXUseAnyCpu)
--     local pf, exe, arg, fsiExe
--     if useNetCore == true then
--       pf = os.getenv("ProgramW6432")
--       if pf == nil or pf == "" then
--         pf = os.getenv("ProgramFiles")
--       end
--       exe = pf .. "/dotnet/dotnet.exe"
--       arg = "fsi"
--       if not os.rename(exe, exe) then
--         M.notify("Could Not Find fsi.exe: " .. exe)
--       end
--       return exe .. " " .. arg
--     else
--       local function fsiExeName()
--         local any = ifNetFXUseAnyCpu or true
--         if any then
--           return "fsiAnyCpu.exe"
--           -- elseif runtime.architecture == "Arm64" then
--           --   return "fsiArm64.exe"
--         else
--           return "fsi.exe"
--         end
--       end
--
--       -- - path (string): Path to begin searching from. If
--       --        omitted, the |current-directory| is used.
--       -- - upward (boolean, default false): If true, search
--       --          upward through parent directories. Otherwise,
--       --          search through child directories
--       --          (recursively).
--       -- - stop (string): Stop searching when this directory is
--       --        reached. The directory itself is not searched.
--       -- - type (string): Find only files ("file") or
--       --        directories ("directory"). If omitted, both
--       --        files and directories that match {names} are
--       --        included.
--       -- - limit (number, default 1): Stop the search after
--       --         finding this many matches. Use `math.huge` to
--       --         place no limit on the number of matches.
--
--       local function determineFsiRelativePath(name)
--         local find = vim.fs.find({ name },
--                 { path = vim.fn.getcwd(), upward = false, type = "file", limit = 1 })
--         if vim.tbl_isempty(find) or find[1] == nil then
--           return ""
--         else
--           return find[1]
--         end
--       end
--
--       local name = fsiExeName()
--       local path = determineFsiRelativePath(name)
--       if not path == "" then
--         fsiExe = path
--       else
--         local fsbin = os.getenv("FSharpBinFolder")
--         if fsbin == nil or fsbin == "" then
--           local lastDitchEffortPath =
--               vim.fs.find({ name },
--                   {
--                       path = "C:/Program Files (x86)/Microsoft Visual Studio/",
--                       upward = false,
--                       type = "file",
--                       limit = 1
--                   })
--           if not lastDitchEffortPath then
--             fsiExe = "Could not find FSI"
--           else
--             fsiExe = lastDitchEffortPath
--           end
--         else
--           fsiExe = fsbin .. "/Tools/" .. name
--         end
--       end
--       return fsiExe
--     end
--   end
--
--   local function shouldUseAnyCpu()
--     local uname = vim.api.nvim_call_function("system", { "uname -m" })
--     local architecture = uname:gsub("\n", "")
--     if architecture == "" then
--       local output = vim.api.nvim_call_function("system", { "cmd /c echo %PROCESSOR_ARCHITECTURE%" })
--       architecture = output:gsub("\n", "")
--     end
--     if string.match(architecture, "64") then
--       return true
--     else
--       return false
--     end
--   end
--
--   local useSdkScripts = false
--   if M.DefaultServerSettings then
--     local ds = M.DefaultServerSettings
--     if ds.useSdkScripts then
--       useSdkScripts = ds.useSdkScripts
--     end
--   end
--   if not M.PassedInConfig then
--     M["PassedInConfig"] = {}
--   end
--   if M.PassedInConfig.settings then
--     if M.PassedInConfig.settings.FSharp then
--       if M.PassedInConfig.settings.FSharp.useSdkScripts then
--         useSdkScripts = M.PassedInConfig.settings.FSharp.useSdkScripts
--       end
--     end
--   end
--
--   local useAnyCpu = shouldUseAnyCpu()
--   return determineFsiPath(useSdkScripts, useAnyCpu)
-- end)(),
