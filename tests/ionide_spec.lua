local p = require("plenary")
local pb = require("plenary.busted")
local ph = require("plenary.test_harness")
local i = require("ionide")
local mock = require("luassert.mock")
local stub = require("luassert.stub")
local assert = require("luassert")
local vim = vim

describe("Test example", function()
	it("Test can access vim namespace", function()
		assert.are.same(vim.trim("  a "), "a")
	end)
end)

describe("Ionide basic functionality", function()
	it("can require ionide module", function()
		assert.is_not_nil(i)
		assert.is_table(i)
	end)
	
	it("has setup function", function()
		assert.is_function(i.setup)
	end)
	
	it("can show config", function()
		assert.is_function(i.show_config)
	end)
end)
