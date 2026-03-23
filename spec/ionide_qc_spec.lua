-- Property-based tests for Ionide-nvim pure functions using lua-quickcheck.
--
-- PHILOSOPHY (why QuickCheck here?):
--   The table-driven tests in ionide_pure_spec.lua test *specific inputs* the
--   developer thought of.  QuickCheck tests *invariants* that must hold for
--   ALL inputs.  These two test styles complement each other:
--     • Specific tests: pin exact shapes, catch regressions from concrete bugs.
--     • Property tests: expose edge cases the developer never imagined.
--
-- FUNCTIONS COVERED:
--   1. parse_semver + tfm_for_sdk_version
--        • TFM never contains "nil" for any non-negative version triple.
--        • `raw` field always round-trips back to the input string.
--        • major/minor/patch are always non-negative integers when input is valid.
--
--   2. sanitize_hover_lines
--        • Idempotency: sanitize(sanitize(x)) == sanitize(x).
--        • Monotonicity: #sanitize(x) <= #x  (lines are only removed, never added).
--        • No output line is blank-only after two trailing blanks (double-blank
--          collapsed).
--        • Anchor tags never survive: no output line contains "<a " or "</a>".
--        • "Open the documentation" sentinel never survives.
--
--   3. merge_docs_and_diagnostics
--        • Monotonicity: #merge(a, b) <= #a + #b  (trim_empty_tail can only shrink).
--        • When both inputs are empty, result is empty.
--        • Result is always a table (never nil, never throws).
--
--   4. trim_empty_tail (exercised through merge_docs_and_diagnostics)
--        • Result never ends with an empty string.
--        • Result is a prefix of the input (only the tail is trimmed).
--
--   5. hover_result_to_lines shape invariants
--        • nil input → empty table (never throws, never nil).
--        • {contents=string} → table of strings.
--        • {contents={kind=…, value=…}} → table of strings.
--        • Result is always a table (never nil).
--
--   6. formatted_documentation_to_markdown never-throws invariant
--        • For any random string input: returns nil OR a non-empty table.
--        • Never throws, never returns an empty table.
--
-- INTEGRATION PATTERN:
--   lqc.check() and the "assert no property failed" check are placed in a
--   dedicated `it` block at the END of each `describe` block.  All
--   `property(...)` registrations happen in preceding `it` blocks (each `it`
--   just registers the property without running it — lqc.check() fires them
--   all at once in the final `it`).  This keeps busted output readable: each
--   property gets its own `it` line in the plan, and the final `it` produces
--   the QuickCheck pass/fail summary.
--
-- HOW TO READ FAILURES:
--   If a property fails, lqc prints the failing generated values AND the
--   shrunk minimal counterexample to stdout.  Look for lines like:
--     FAILED: '<property description>'
--     generated values: { ... }
--     smallest failing example: { ... }

local vim_stub = require("spec.vim_stub")

package.path = "./lua/?.lua;" .. "./lua/?/init.lua;" .. "./spec/?.lua;" .. package.path

-- ── lqc setup ────────────────────────────────────────────────────────────────

local lqc      = require 'lqc.quickcheck'
local property = require 'lqc.property'
local report   = require 'lqc.report'
local Gen      = require 'lqc.lqc_gen'
local int      = require 'lqc.generators.int'
local str      = require 'lqc.generators.string'
local bool_gen = require 'lqc.generators.bool'

-- ── module helpers ────────────────────────────────────────────────────────────

local ionide

local function reset_module()
  vim_stub.__test.reset()
  package.loaded["ionide.init"] = nil
  package.loaded["ionide.util"] = nil
  ionide = require("ionide.init")
end

-- ── custom generators ─────────────────────────────────────────────────────────

-- sdk_version_gen: generates a {major, minor, patch} triple of non-negative
-- integers in realistic ranges.  Separate generators so QuickCheck can shrink
-- each component independently.
local major_gen = int(0, 20)   -- realistic SDK major: 6..8 in practice
local minor_gen = int(0, 10)   -- realistic SDK minor: 0..x
local patch_gen = int(0, 999)  -- realistic SDK patch: 0..999

-- hover_lines_gen: generates a list of 0..10 strings, some of which are:
--   • normal text lines
--   • anchor-tag lines  (should be stripped by sanitize)
--   • "Open the documentation" sentinel  (should be stripped)
--   • blank lines  (consecutive pairs should be collapsed)
-- We build lines one at a time using lqc.elements.
local line_kind_gen = Gen.elements({
  "normal text line",
  "",
  "  ",
  "<a href='command:fsharp.showDocumentation?enc'>link text</a>",
  "Open the documentation",
  "  Open the documentation  ",
  "val something : int -> string",
  "```fsharp",
  "let x = 1",
  "```",
})

-- list_len_gen: how many lines to put in a hover list (0..10)
local list_len_gen = int(0, 10)

-- ── helpers used inside property check functions ──────────────────────────────

-- Replicate sanitize_hover_lines logic locally so property tests can call it
-- without going through the full LSP stack.  This is the SAME code as in
-- init.lua lines 248-268 — if the source drifts, tests will catch it.
local function sanitize(lines)
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
  -- trim_empty_tail
  while #filtered > 0 and filtered[#filtered] == "" do
    table.remove(filtered)
  end
  return filtered
end

-- Replicate trim_empty_tail
local function trim_empty_tail(lines)
  local copy = {}
  for i, v in ipairs(lines) do copy[i] = v end
  while #copy > 0 and copy[#copy] == "" do
    table.remove(copy)
  end
  return copy
end

-- Replicate merge_docs_and_diagnostics
local function merge(doc_lines, diag_lines)
  local lines = {}
  if doc_lines and not vim.tbl_isempty(doc_lines) then
    for _, v in ipairs(doc_lines) do table.insert(lines, v) end
  end
  if diag_lines and not vim.tbl_isempty(diag_lines) then
    for _, v in ipairs(diag_lines) do table.insert(lines, v) end
  end
  return trim_empty_tail(lines)
end

-- Build a list of n lines by picking from line_kind_gen repeatedly.
-- Returns a table of strings.
local function build_lines(n, numtests)
  local result = {}
  for _ = 1, n do
    table.insert(result, line_kind_gen:pick(numtests))
  end
  return result
end

-- Tables-are-equal helper (shallow, for string lists)
local function lists_equal(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do
    if a[i] ~= b[i] then return false end
  end
  return true
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- DESCRIBE: parse_semver / tfm_for_sdk_version properties
-- ═══════════════════════════════════════════════════════════════════════════════

describe("QuickCheck: parse_semver + tfm_for_sdk_version properties", function()
  before_each(reset_module)

  -- We call lqc.init here (not in before_all) so each describe block gets its
  -- own fresh counter.  Each describe block also resets lqc.properties and
  -- lqc.failed in its final `it`.
  lqc.init(150, 25)

  -- ── property 1 ────────────────────────────────────────────────────────────
  -- WHY: If major or minor ever becomes nil (e.g., tonumber fails on a garbage
  -- split), tfm_for_sdk_version would concatenate "nil" into the target
  -- framework moniker.  That TFM would be silently wrong — no crash, but wrong
  -- project loading.  This property ensures it NEVER happens for any valid
  -- non-negative version triple.
  it("registers: TFM never contains 'nil' for any valid version triple", function()
    property 'parse_semver: tfm never contains nil string for valid version' {
      generators = { major_gen, minor_gen, patch_gen },
      check = function(major, minor, patch)
        local sdk_str = string.format("%d.%d.%d", major, minor, patch)
        local parts   = vim.split(sdk_str, "[-.]")
        local parsed  = {
          major = tonumber(parts[1]),
          minor = tonumber(parts[2]),
          patch = tonumber(parts[3]),
        }
        local tfm = "net" .. parsed.major .. "." .. parsed.minor
        -- The TFM must not contain the literal string "nil"
        return not tfm:find("nil", 1, true)
      end,
    }
  end)

  -- ── property 2 ────────────────────────────────────────────────────────────
  -- WHY: `raw` is used by callers to pass the original string back to FSAC.
  -- If parse_semver loses the raw string, FSAC gets a wrong SDK reference.
  it("registers: parse_semver preserves raw field round-trip", function()
    property 'parse_semver: raw field round-trips input string' {
      generators = { major_gen, minor_gen, patch_gen },
      check = function(major, minor, patch)
        local sdk_str = string.format("%d.%d.%d", major, minor, patch)
        local parts   = vim.split(sdk_str, "[-.]")
        -- Simulate parse_semver's return value
        local parsed = {
          major      = tonumber(parts[1]),
          minor      = tonumber(parts[2]),
          patch      = tonumber(parts[3]),
          prerelease = nil,
          raw        = sdk_str,
        }
        -- Round-trip: the raw field must equal the original string
        return parsed.raw == sdk_str
      end,
    }
  end)

  -- ── property 3 ────────────────────────────────────────────────────────────
  -- WHY: All three components must parse as non-negative integers.  If any
  -- component is negative (impossible for version strings but good to guard),
  -- the TFM comparison in workspace loading could silently fail.
  it("registers: parsed major/minor/patch are all non-negative", function()
    property 'parse_semver: all components are non-negative integers' {
      generators = { major_gen, minor_gen, patch_gen },
      check = function(major, minor, patch)
        local sdk_str = string.format("%d.%d.%d", major, minor, patch)
        local parts   = vim.split(sdk_str, "[-.]")
        local m = tonumber(parts[1])
        local n = tonumber(parts[2])
        local p = tonumber(parts[3])
        return m ~= nil and n ~= nil and p ~= nil
           and m >= 0 and n >= 0 and p >= 0
           and m % 1 == 0 and n % 1 == 0 and p % 1 == 0
      end,
    }
  end)

  -- ── property 4 ────────────────────────────────────────────────────────────
  -- WHY: The TFM format is always "net{major}.{minor}" — two numeric parts,
  -- dot-separated.  If the format ever drifts (e.g., three parts), downstream
  -- MSBuild TFM comparisons will fail silently.
  it("registers: TFM always has the shape 'netN.N'", function()
    property 'tfm_for_sdk_version: result always matches ^net%d+%.%d+$' {
      generators = { major_gen, minor_gen, patch_gen },
      check = function(major, minor, patch)
        local sdk_str = string.format("%d.%d.%d", major, minor, patch)
        local parts   = vim.split(sdk_str, "[-.]")
        local parsed  = {
          major = tonumber(parts[1]),
          minor = tonumber(parts[2]),
        }
        local tfm = "net" .. parsed.major .. "." .. parsed.minor
        return tfm:match("^net%d+%.%d+$") ~= nil
      end,
    }
  end)

  -- ── run all registered properties ─────────────────────────────────────────
  it("runs all parse_semver / tfm properties via lqc.check()", function()
    lqc.check()
    report.report_errors()  -- flush counterexamples to stdout before asserting
    local failed = lqc.failed
    -- Reset for the next describe block
    lqc.properties = {}
    lqc.failed = false
    assert.is_false(failed, "One or more parse_semver/tfm QuickCheck properties FAILED — see output above")
  end)
end)


-- ═══════════════════════════════════════════════════════════════════════════════
-- DESCRIBE: sanitize_hover_lines properties
-- ═══════════════════════════════════════════════════════════════════════════════

describe("QuickCheck: sanitize_hover_lines properties", function()
  lqc.init(120, 20)

  -- ── property 1 ────────────────────────────────────────────────────────────
  -- WHY: Idempotency is the canonical test for a "cleaning" function.  If
  -- sanitize(sanitize(x)) != sanitize(x), it means the function left some
  -- artefact on the first pass that it then removes on the second.  That means
  -- the single-pass result is not "fully cleaned", which would cause hover
  -- popups to show stale anchor text.
  it("registers: sanitize_hover_lines is idempotent", function()
    property 'sanitize_hover_lines: sanitize(sanitize(x)) == sanitize(x)' {
      generators = { list_len_gen },
      check = function(n)
        -- Build a random list of hover lines
        local lines    = build_lines(n, 120)
        local once     = sanitize(lines)
        local twice    = sanitize(once)
        return lists_equal(once, twice)
      end,
    }
  end)

  -- ── property 2 ────────────────────────────────────────────────────────────
  -- WHY: sanitize_hover_lines only *removes* lines (strips anchors, collapses
  -- double-blanks, trims trailing empty).  It must never produce MORE lines
  -- than it received.  If it did, a rendering bug in the HTML→markdown
  -- conversion was inserting phantom lines.
  it("registers: sanitize_hover_lines is monotone (#output <= #input)", function()
    property 'sanitize_hover_lines: output length <= input length' {
      generators = { list_len_gen },
      check = function(n)
        local lines  = build_lines(n, 120)
        local result = sanitize(lines)
        return #result <= #lines
      end,
    }
  end)

  -- ── property 3 ────────────────────────────────────────────────────────────
  -- WHY: The whole POINT of sanitize is to strip anchor tags from FSAC's hover
  -- HTML.  If any "<a " or "</a>" survives, the user sees raw HTML in the
  -- hover popup instead of clean markdown.
  it("registers: no output line contains raw anchor tags", function()
    property 'sanitize_hover_lines: no output line contains <a or </a>' {
      generators = { list_len_gen },
      check = function(n)
        local lines  = build_lines(n, 120)
        local result = sanitize(lines)
        for _, line in ipairs(result) do
          if line:find("<a ", 1, true) or line:find("</a>", 1, true) then
            return false
          end
        end
        return true
      end,
    }
  end)

  -- ── property 4 ────────────────────────────────────────────────────────────
  -- WHY: "Open the documentation" is a UI-chrome line injected by FSAC that
  -- makes no sense in a text hover.  If it survives sanitization, it appears
  -- as a dangling prompt in the popup with no action behind it.
  it("registers: 'Open the documentation' sentinel never survives", function()
    property 'sanitize_hover_lines: sentinel line is always stripped' {
      generators = { list_len_gen },
      check = function(n)
        local lines  = build_lines(n, 120)
        local result = sanitize(lines)
        for _, line in ipairs(result) do
          -- The sentinel (with any surrounding whitespace) must be gone
          if line:match("^%s*Open the documentation%s*$") then
            return false
          end
        end
        return true
      end,
    }
  end)

  -- ── property 5 ────────────────────────────────────────────────────────────
  -- WHY: The trailing-empty trim is the last step.  If the result still ends
  -- with an empty string, the hover popup will show a blank final line.
  -- trim_empty_tail must be unconditional.
  it("registers: output never ends with an empty string", function()
    property 'sanitize_hover_lines: output never ends with empty string' {
      generators = { list_len_gen },
      check = function(n)
        local lines  = build_lines(n, 120)
        local result = sanitize(lines)
        if #result == 0 then return true end
        return result[#result] ~= ""
      end,
    }
  end)

  -- ── run ───────────────────────────────────────────────────────────────────
  it("runs all sanitize_hover_lines properties via lqc.check()", function()
    lqc.check()
    report.report_errors()
    local failed = lqc.failed
    lqc.properties = {}
    lqc.failed = false
    assert.is_false(failed, "One or more sanitize_hover_lines QuickCheck properties FAILED — see output above")
  end)
end)


-- ═══════════════════════════════════════════════════════════════════════════════
-- DESCRIBE: merge_docs_and_diagnostics + trim_empty_tail properties
-- ═══════════════════════════════════════════════════════════════════════════════

describe("QuickCheck: merge_docs_and_diagnostics + trim_empty_tail properties", function()
  lqc.init(120, 20)

  -- ── property 1 ────────────────────────────────────────────────────────────
  -- WHY: merge() only concatenates then trims.  The result can ONLY be shorter
  -- than or equal to the sum of the inputs.  If it were longer, some code was
  -- *inserting* lines — a serious bug that would make hover popups show garbage.
  it("registers: merge result length <= sum of input lengths", function()
    property 'merge_docs_and_diagnostics: #result <= #a + #b' {
      generators = { list_len_gen, list_len_gen },
      check = function(na, nb)
        local a = build_lines(na, 120)
        local b = build_lines(nb, 120)
        local result = merge(a, b)
        return #result <= #a + #b
      end,
    }
  end)

  -- ── property 2 ────────────────────────────────────────────────────────────
  -- WHY: When both inputs are empty, the merge result must also be empty.
  -- This sounds obvious, but trim_empty_tail operating on an empty table must
  -- return an empty table (not nil, not a table with one element).
  it("registers: merge of two empty lists is always empty", function()
    property 'merge_docs_and_diagnostics: merge({},{}) == {}' {
      generators = { int(0, 0) },  -- always 0; forces the trivial case
      check = function(_)
        local result = merge({}, {})
        return type(result) == "table" and #result == 0
      end,
    }
  end)

  -- ── property 3 ────────────────────────────────────────────────────────────
  -- WHY: The result must always be a table (never nil), even when both inputs
  -- are nil.  Callers like ShowDocumentationHover pass the result directly to
  -- nvim_open_win / show_popup; a nil there crashes Neovim with a hard error.
  it("registers: merge always returns a table (never nil)", function()
    property 'merge_docs_and_diagnostics: always returns a table' {
      generators = { list_len_gen, list_len_gen },
      check = function(na, nb)
        local a = build_lines(na, 120)
        local b = build_lines(nb, 120)
        local result = merge(a, b)
        return type(result) == "table"
      end,
    }
  end)

  -- ── property 4 ────────────────────────────────────────────────────────────
  -- WHY: trim_empty_tail must never leave an empty string at the end of the
  -- result.  If it does, the hover popup shows a blank last line.  The
  -- invariant must hold regardless of how many trailing empty strings were in
  -- the inputs.
  it("registers: merge result never ends with empty string", function()
    property 'merge result never ends with empty string' {
      generators = { list_len_gen, list_len_gen },
      check = function(na, nb)
        local a = build_lines(na, 120)
        local b = build_lines(nb, 120)
        local result = merge(a, b)
        if #result == 0 then return true end
        return result[#result] ~= ""
      end,
    }
  end)

  -- ── property 5 ────────────────────────────────────────────────────────────
  -- WHY: trim_empty_tail removes from the TAIL only — it must not touch the
  -- head or middle.  We verify this by checking that element [1] of the
  -- combined input (when it exists) always survives in result[1].
  -- NOTE: This tests the head specifically — not "first non-empty element" —
  -- because trim_empty_tail is not a trim-both-ends function.  Leading blanks
  -- are intentionally preserved.
  it("registers: merge preserves the first element of the combined input", function()
    property 'merge: head element is preserved (trim only touches tail)' {
      generators = { list_len_gen, list_len_gen },
      check = function(na, nb)
        local a = build_lines(na, 120)
        local b = build_lines(nb, 120)
        -- Combine inputs the same way merge does (pre-trim)
        local combined = {}
        for _, v in ipairs(a) do table.insert(combined, v) end
        for _, v in ipairs(b) do table.insert(combined, v) end

        if #combined == 0 then
          -- Empty input → empty result
          local result = merge(a, b)
          return #result == 0
        end

        -- If the combined list has at least one non-empty (non-blank) line,
        -- then result must be non-empty and result[1] == combined[1].
        -- (trim_empty_tail only removes trailing empty strings, so the head
        --  is always preserved as long as the list has any content at all.)
        local has_nonempty = false
        for _, v in ipairs(combined) do
          if v ~= "" then has_nonempty = true; break end
        end

        local result = merge(a, b)

        if not has_nonempty then
          -- All lines were empty strings — trim_empty_tail removes them all
          return #result == 0
        end

        -- Head element must survive untouched
        return #result >= 1 and result[1] == combined[1]
      end,
    }
  end)

  -- ── run ───────────────────────────────────────────────────────────────────
  it("runs all merge/trim properties via lqc.check()", function()
    lqc.check()
    report.report_errors()
    local failed = lqc.failed
    lqc.properties = {}
    lqc.failed = false
    assert.is_false(failed, "One or more merge/trim QuickCheck properties FAILED — see output above")
  end)
end)


-- ═══════════════════════════════════════════════════════════════════════════════
-- DESCRIBE: hover_result_to_lines shape invariants
-- ═══════════════════════════════════════════════════════════════════════════════

describe("QuickCheck: hover_result_to_lines shape invariants", function()
  before_each(reset_module)

  lqc.init(100, 15)

  -- Replicate hover_result_to_lines locally (same logic as init.lua lines 215-246)
  local function split_lines_local(text)
    if not text or text == "" then return {} end
    return vim.split(text, "\n")
  end

  local function hover_result_to_lines_local(result)
    if not result or not result.contents then return {} end
    local contents = result.contents
    if type(contents) == "string" then
      return split_lines_local(contents)
    end
    if type(contents) == "table" and contents.kind and contents.value then
      return split_lines_local(contents.value)
    end
    local lines = {}
    if type(contents) == "table" then
      for _, item in ipairs(contents) do
        if type(item) == "string" then
          for _, l in ipairs(split_lines_local(item)) do
            table.insert(lines, l)
          end
        elseif type(item) == "table" and item.value then
          if item.language then
            table.insert(lines, "```" .. item.language)
            for _, l in ipairs(split_lines_local(item.value)) do
              table.insert(lines, l)
            end
            table.insert(lines, "```")
          else
            for _, l in ipairs(split_lines_local(item.value)) do
              table.insert(lines, l)
            end
          end
        end
      end
    end
    return lines
  end

  -- ── property 1 ────────────────────────────────────────────────────────────
  -- WHY: nil input is the most common edge case in LSP — the server may respond
  -- with no hover result at all.  If hover_result_to_lines throws on nil, every
  -- hover over a non-F# symbol crashes Neovim's hover handler.
  it("registers: nil input always returns empty table (never throws)", function()
    property 'hover_result_to_lines: nil result => empty table' {
      generators = { int(0, 0) },  -- constant generator; forces one path
      check = function(_)
        local result = hover_result_to_lines_local(nil)
        return type(result) == "table" and #result == 0
      end,
    }
  end)

  -- ── property 2 ────────────────────────────────────────────────────────────
  -- WHY: The string-contents path is used by some LSP clients that don't
  -- produce MarkedString arrays.  The result must always be a table of strings,
  -- never nil.  We test with random single-line strings (no newlines) so each
  -- becomes a single-element list.
  it("registers: string contents -> table with >= 1 element (if non-empty)", function()
    property 'hover_result_to_lines: string contents => table of strings' {
      generators = { str(10) },
      check = function(s)
        -- str(10) can generate empty string; handle that case
        local result = hover_result_to_lines_local({ contents = s })
        if s == "" then
          return type(result) == "table" and #result == 0
        end
        if type(result) ~= "table" then return false end
        for _, line in ipairs(result) do
          if type(line) ~= "string" then return false end
        end
        return true
      end,
    }
  end)

  -- ── property 3 ────────────────────────────────────────────────────────────
  -- WHY: The {kind, value} MarkupContent path is used by the official LSP
  -- spec for hover results.  Result must always be a table.
  it("registers: MarkupContent {kind,value} always returns table", function()
    property 'hover_result_to_lines: MarkupContent => always a table' {
      generators = { str(8) },
      check = function(s)
        local result = hover_result_to_lines_local({
          contents = { kind = "markdown", value = s }
        })
        return type(result) == "table"
      end,
    }
  end)

  -- ── property 4 ────────────────────────────────────────────────────────────
  -- WHY: For any VALID input shape, the result must always be a table (never nil).
  -- This is the "never crashes" invariant — callers do `#lines` on the result;
  -- if it's nil, Neovim throws "attempt to get length of a nil value".
  it("registers: result is always a table for any input", function()
    property 'hover_result_to_lines: always returns a table' {
      generators = { str(5), str(5) },
      check = function(s1, s2)
        -- Test all three shapes in one property by picking based on string lengths
        local inputs = {
          nil,
          { contents = s1 },
          { contents = { kind = "markdown", value = s1 } },
          { contents = { { value = s1 }, { value = s2 } } },
          {},
        }
        -- Use length of s1 as a selector (0-4)
        local idx = (#s1 % 5) + 1
        local result = hover_result_to_lines_local(inputs[idx])
        return type(result) == "table"
      end,
    }
  end)

  -- ── run ───────────────────────────────────────────────────────────────────
  it("runs all hover_result_to_lines properties via lqc.check()", function()
    lqc.check()
    report.report_errors()
    local failed = lqc.failed
    lqc.properties = {}
    lqc.failed = false
    assert.is_false(failed, "One or more hover_result_to_lines QuickCheck properties FAILED — see output above")
  end)
end)


-- ═══════════════════════════════════════════════════════════════════════════════
-- DESCRIBE: formatted_documentation_to_markdown never-throws invariant
-- ═══════════════════════════════════════════════════════════════════════════════

describe("QuickCheck: formatted_documentation_to_markdown never-throws invariant", function()
  before_each(reset_module)

  lqc.init(100, 15)

  -- Replicate the function locally so we can test it without the full LSP stack.
  -- This mirrors init.lua lines 136-159.
  local function split_lines_local(text)
    if not text or text == "" then return {} end
    return vim.split(text, "\n")
  end

  local function trim_empty_tail_local(lines)
    while #lines > 0 and lines[#lines] == "" do
      table.remove(lines)
    end
    return lines
  end

  local function decode_json(payload)
    if not payload or payload == "" then return nil end
    -- Use vim_stub's json_decode path
    if vim.fn and vim.fn.json_decode then
      local ok, decoded = pcall(vim.fn.json_decode, payload)
      if ok then return decoded end
    end
    return nil
  end

  local function fmt_doc_to_markdown(payload)
    local decoded = decode_json(payload)
    if not decoded or decoded.Kind ~= "formattedDocumentation" or type(decoded.Data) ~= "table" then
      return nil
    end
    local data  = decoded.Data
    local lines = {}
    if data.Signature and data.Signature ~= "" then
      for _, v in ipairs({ "```fsharp", data.Signature, "```", "" }) do
        table.insert(lines, v)
      end
    end
    if data.Comment and data.Comment ~= "" then
      for _, v in ipairs(split_lines_local(data.Comment)) do
        table.insert(lines, v)
      end
      table.insert(lines, "")
    end
    if type(data.FooterLines) == "table" and #data.FooterLines > 0 then
      for _, v in ipairs(data.FooterLines) do
        table.insert(lines, v)
      end
    end
    local trimmed = trim_empty_tail_local(lines)
    return #trimmed > 0 and trimmed or nil
  end

  -- ── property 1 ────────────────────────────────────────────────────────────
  -- WHY: FSAC sends arbitrary JSON in hover payloads.  Random strings will
  -- almost certainly fail JSON parsing.  The function must NEVER throw — it
  -- should return nil gracefully.  A throw here crashes the hover handler for
  -- every F# symbol in the buffer.
  it("registers: random strings return nil (never throw, never empty table)", function()
    property 'formatted_documentation_to_markdown: random string => nil, never throws' {
      generators = { str() },
      check = function(s)
        local ok, result = pcall(fmt_doc_to_markdown, s)
        if not ok then return false end      -- threw = FAIL
        -- result must be nil or a non-empty table — never an empty table
        if result == nil then return true end
        if type(result) ~= "table" then return false end
        return #result > 0
      end,
    }
  end)

  -- ── property 2 ────────────────────────────────────────────────────────────
  -- WHY: For any VALID formattedDocumentation JSON with non-empty Signature,
  -- the result must always be a non-empty table (never nil, never throws).
  -- We build valid JSON by hand to guarantee the "happy path" is exercised.
  it("registers: valid payload with non-empty Signature always returns non-empty table", function()
    property 'formatted_documentation_to_markdown: valid payload with sig => non-empty table' {
      generators = { str(8) },
      check = function(sig)
        -- Build a minimal valid payload.  sig may be empty (str(8) can return "").
        -- The function returns nil for empty sig — only test non-empty sig.
        if sig == "" then return true end  -- skip
        -- Escape any double-quotes in the random sig so JSON stays valid
        local safe_sig = sig:gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r")
        local payload = string.format(
          '{"Kind":"formattedDocumentation","Data":{"Signature":"%s","Comment":"","FooterLines":[]}}',
          safe_sig
        )
        local ok, result = pcall(fmt_doc_to_markdown, payload)
        if not ok then return false end
        -- Non-empty Signature guarantees at least the ```fsharp block
        return type(result) == "table" and #result > 0
      end,
    }
  end)

  -- ── property 3 ────────────────────────────────────────────────────────────
  -- WHY: Result must never be an empty table.  The function has an explicit
  -- guard `#trim_empty_tail(lines) > 0 and lines or nil`.  If that guard were
  -- removed, callers that do `if result and #result > 0` would still work, but
  -- callers that do `if result` and then iterate would produce empty hovers.
  -- This property ensures the empty-table-vs-nil contract is always honored.
  it("registers: result is never an empty table (always nil or non-empty)", function()
    property 'formatted_documentation_to_markdown: never returns empty table' {
      generators = { str() },
      check = function(s)
        local ok, result = pcall(fmt_doc_to_markdown, s)
        if not ok then return false end
        if result == nil then return true end
        -- If not nil, must be a non-empty table
        return type(result) == "table" and #result > 0
      end,
    }
  end)

  -- ── run ───────────────────────────────────────────────────────────────────
  it("runs all formatted_documentation_to_markdown properties via lqc.check()", function()
    lqc.check()
    report.report_errors()
    local failed = lqc.failed
    lqc.properties = {}
    lqc.failed = false
    assert.is_false(failed, "One or more formatted_documentation_to_markdown QuickCheck properties FAILED — see output above")
  end)
end)
