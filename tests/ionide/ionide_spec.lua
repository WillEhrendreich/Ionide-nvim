local plugin = require("ionide")

describe("setup", function()
  it("works with default", function()
    -- Test that the plugin loads without error
    assert.is_not_nil(plugin)
    assert.is_function(plugin.setup)
  end)

  it("works with custom config", function()
    -- Test that setup function works with custom config
    local config = { AutomaticWorkspaceInit = false }
    plugin.setup({ IonideNvimSettings = config })
    assert.is_not_nil(plugin)
  end)
end)
