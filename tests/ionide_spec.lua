-- local p = require("plenary")
local p = require("plenary")
local pb = require("plenary.busted")
-- pb.
local ph = require("plenary.test_harness")
local i = require("ionide")
-- import the luassert.mock module
local mock = require("luassert.mock")
local stub = require("luassert.stub")
local assert = require("luassert")
local vim = vim
-- function M.AddThenSort(value, tbl)
-- 	if not vim.tbl_contains(tbl, value) then
-- 		table.insert(tbl, value)
-- 		-- table.sort(tbl)
-- 	end
-- 	-- print("after sorting table, it now looks like this : " .. vim.inspect(tbl))
-- 	return tbl
-- end

-- ph._run_path("busted", vim.fn.expand("%:p"))

describe("Test example", function()
	it("Test cat access vim namespace", function()
		assert.are.same(vim.trim("  a "), "a")
	end)
end)

describe("AddThenSort", function()
	it("correctly adds a value", function()
		local t = {}
		local val = "some/path"
		i.AddThenSort(val, t)
		assert(false, "table did not contain the value " .. val)
		-- assert(t.tbl_contains(val), "table did not contain the value " .. val)
	end)
end)
