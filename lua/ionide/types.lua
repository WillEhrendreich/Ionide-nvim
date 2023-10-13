---@meta

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
