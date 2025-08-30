local ionide = require("ionide.init")
local vim = vim
local assert = require("luassert")
local mock = require("luassert.mock")
local stub = require("luassert.stub")

describe("Hover Documentation Link Replacement Tests", function()
  local original_buf_definition
  local original_notify
  
  before_each(function()
    -- Store original functions
    original_buf_definition = vim.lsp.buf.definition
    original_notify = ionide.notify
    
    -- Mock functions
    vim.lsp.buf.definition = function() end
    ionide.notify = function() end
  end)
  
  after_each(function()
    -- Restore original functions
    vim.lsp.buf.definition = original_buf_definition
    ionide.notify = original_notify
  end)

  describe("Documentation Link Parsing", function()
    it("should parse VSCode documentation command links correctly", function()
      local test_html = "<a href='command:fsharp.showDocumentation?%5B%7B%20%22XmlDocSig%22%3A%20%22P%3AProgram.server%22%2C%20%22AssemblyName%22%3A%20%22AppHost%22%20%7D%5D'>Open the documentation</a>"
      
      -- Call the internal parsing function (we'll need to expose this for testing)
      local function_name, unhtml_text, decoded_json, label_text = ionide._parse_documentation_string(test_html)
      
      assert.is_string(function_name)
      assert.is_string(unhtml_text)
      assert.is_table(decoded_json)
      assert.equals("P:Program.server", decoded_json.XmlSig)
      assert.equals("AppHost", decoded_json.Assembly)
      assert.equals("Open the documentation", label_text)
    end)
    
    it("should handle URL decoding correctly", function()
      local encoded_json = "%5B%7B%20%22XmlDocSig%22%3A%20%22P%3AProgram.server%22%2C%20%22AssemblyName%22%3A%20%22AppHost%22%20%7D%5D"
      
      local decoded = ionide._unHtmlify(encoded_json)
      
      assert.is_string(decoded)
      assert.is_true(decoded:find("XmlDocSig") ~= nil)
      assert.is_true(decoded:find("Program.server") ~= nil)
    end)
  end)

  describe("Documentation Link Replacement", function()
    it("should replace VSCode command links with neovim-compatible navigation", function()
      local test_input = "<a href='command:fsharp.showDocumentation?%5B%7B%20%22XmlDocSig%22%3A%20%22P%3AProgram.server%22%2C%20%22AssemblyName%22%3A%20%22AppHost%22%20%7D%5D'>Open the documentation</a>"
      
      local result = ionide._replace_documentation_links(test_input)
      
      -- Should not contain VSCode-specific command
      assert.is_false(result:find("command:fsharp.showDocumentation") ~= nil)
      
      -- Should contain helpful neovim navigation instructions
      assert.is_true(result:find("Go to definition") ~= nil)
      assert.is_true(result:find("gd") ~= nil or result:find("<C-]>") ~= nil)
    end)
    
    it("should preserve non-documentation content unchanged", function()
      local test_input = "This is regular text that should be preserved."
      
      local result = ionide._replace_documentation_links(test_input)
      
      assert.equals(test_input, result)
    end)
    
    it("should handle mixed content with documentation links", function()
      local test_input = [[
val server: IResourceBuilder<ProjectResource>

<a href='command:fsharp.showDocumentation?%5B%7B%20%22XmlDocSig%22%3A%20%22P%3AProgram.server%22%2C%20%22AssemblyName%22%3A%20%22AppHost%22%20%7D%5D'>Open the documentation</a>
*Full name: Program.server*
*Assembly: AppHost*
]]
      
      local result = ionide._replace_documentation_links(test_input)
      
      -- Should preserve type signature and metadata
      assert.is_true(result:find("val server:") ~= nil)
      assert.is_true(result:find("Full name: Program.server") ~= nil)
      assert.is_true(result:find("Assembly: AppHost") ~= nil)
      
      -- Should not contain VSCode command
      assert.is_false(result:find("command:fsharp.showDocumentation") ~= nil)
      
      -- Should contain helpful navigation instructions
      assert.is_true(result:find("Go to definition") ~= nil)
    end)
  end)

  describe("Hover Handler Integration", function()
    it("should process hover responses and replace documentation links", function()
      local test_hover_result = {
        content = {
          value = [[
```fsharp
val server: IResourceBuilder<ProjectResource>
```

<a href='command:fsharp.showDocumentation?%5B%7B%20%22XmlDocSig%22%3A%20%22P%3AProgram.server%22%2C%20%22AssemblyName%22%3A%20%22AppHost%22%20%7D%5D'>Open the documentation</a>
*Full name: Program.server*
*Assembly: AppHost*
]]
        }
      }
      
      -- Mock the hover handler
      local processed_result = nil
      local mock_hover_handler = function(error, result, context, config)
        processed_result = result
      end
      
      -- Override the hover handler temporarily
      local original_hover_handler = vim.lsp.handlers.hover
      vim.lsp.handlers.hover = mock_hover_handler
      
      -- Call our hover handler
      ionide["textDocument/hover"](nil, test_hover_result, {}, {})
      
      -- Restore original handler
      vim.lsp.handlers.hover = original_hover_handler
      
      -- Verify the result was processed
      assert.is_not_nil(processed_result)
      assert.is_not_nil(processed_result.content)
      assert.is_not_nil(processed_result.content.value)
      
      -- Should not contain VSCode command
      assert.is_false(processed_result.content.value:find("command:fsharp.showDocumentation") ~= nil)
    end)
  end)
end)