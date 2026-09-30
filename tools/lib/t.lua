-- tools/lib/t.lua -- the suite boilerplate, once (T57, P13, review Q9).
--
-- Every suite used to carry its own check(), its own footer, its own ASCII /
-- no-bare-pipe test (seven of them, which disagreed about "\n") and its own
-- colour stripping. New suites take them from here; old ones keep theirs until
-- a task touches them anyway (no mass migration).
--
--   local here = arg[0]:match("^(.*)/[^/]+$")
--   local T = dofile(here .. "/lib/t.lua")      -- a fresh counter per dofile
--   local check = T.check
--   T.section("the clock")
--   check("a name", cond, "detail when it fails")
--   ...
--   T.done()                                     -- the footer, then exit 0 / 1
--
-- The footer is the one tools/check.sh reads: "<n> ok, <m> failed" on a line of
-- its own, then one "  FAIL <name>" line per failure, exit 1 when m > 0.
--
-- Run on its own (tools/run.sh tools/lib/t.lua) it tests itself; tools/check.sh
-- runs it that way.
local T = {}

local ok, fails = 0, {}
local width = 72

-- One assertion: printed as "<name padded> ok|FAIL[ - detail]", counted.
function T.check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. tostring(detail)) or "") end
    print(string.format("%-" .. width .. "s %s%s", name, cond and "ok" or "FAIL",
        detail and (" - " .. tostring(detail)) or ""))
    return cond and true or false
end

-- A heading between groups of checks; counts nothing.
function T.section(title)
    print("")
    print("-- " .. tostring(title))
end

-- The counts so far, for a suite that decides something from them.
function T.counts() return ok, #fails end

-- The footer and the exit code. `noExit` returns the failure count instead of
-- leaving (for a caller that has more to do after).
function T.done(noExit)
    print(string.format("\n%d ok, %d failed", ok, #fails))
    for _, f in ipairs(fails) do print("  FAIL " .. f) end
    if noExit then return #fails end
    os.exit(#fails == 0 and 0 or 1)
end

-- Colour codes out: |cAARRGGBB and |r. An escaped pipe (||) is left as it is.
function T.Strip(s)
    s = tostring(s)
    local out = s:gsub("||", "\0"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%z", "||")
    return out
end

-- The text rule (CLAUDE.md): printable ASCII and no bare pipe. Answers ok and,
-- when not, why. Colour codes and escaped pipes (||) are allowed; opts.newlines
-- allows "\n" (a copy box, a multi-line report); opts.noColour refuses colour
-- codes too (a string that goes somewhere the client does not colour).
function T.Ascii(s, opts)
    opts = opts or {}
    if type(s) ~= "string" then return false, "not a string: " .. type(s) end
    for i = 1, #s do
        local b = s:byte(i)
        if not ((b >= 32 and b <= 126) or (b == 10 and opts.newlines)) then
            return false, string.format("byte %d at %d", b, i)
        end
    end
    local rest = s:gsub("||", "")
    if not opts.noColour then rest = rest:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end
    local at = rest:find("|", 1, true)
    if at then return false, "bare pipe" end
    return true
end

-- Every line printed to the default chat frame while body() runs, in order.
-- Patches AddMessage on the frame the stub installed (MD.API.Print reads the
-- global at every call), and puts it back even when body raises.
function T.CapturedChat(body)
    local lines = {}
    local frame = _G.DEFAULT_CHAT_FRAME
    if not frame then
        body()
        return lines
    end
    local orig = frame.AddMessage
    frame.AddMessage = function(_, m) lines[#lines + 1] = m end
    local ran, err = pcall(body)
    frame.AddMessage = orig
    if not ran then error(err, 0) end
    return lines
end

-- A plain substring test (never a pattern: report text carries "%" and "-").
function T.Has(s, sub) return s ~= nil and tostring(s):find(sub, 1, true) ~= nil end

--------------------------------------------------------------------------------
-- Self-test, when run as a script rather than dofile'd by a suite.
--------------------------------------------------------------------------------
local self = arg and arg[0] and arg[0]:match("lib/t%.lua$")
if self then
    local check = T.check
    T.section("check and the counts")
    local okBefore = ok
    -- a failing check counts as a failure, then is taken back off so the
    -- footer below reports only the self-test's own verdicts
    -- (printed into a table, so no FAIL line reaches tools/check.sh)
    local printed = {}
    local realPrint = print
    print = function(s) printed[#printed + 1] = s end
    local r = T.check("a deliberate failure", false, "x")
    print = realPrint
    local _, failed = T.counts()
    table.remove(fails)
    check("check answers false, counts a failure and prints it as FAIL",
        r == false and failed == 1 and ok == okBefore and T.Has(printed[1], " FAIL - x"))

    T.section("Ascii")
    check("plain text passes", (T.Ascii("OOM 1:20 v  rest 2:10")))
    check("colour codes and an escaped pipe pass", (T.Ascii("|cff33ff66ok|r a || b")))
    local okPipe, whyPipe = T.Ascii("a | b")
    check("a bare pipe fails, and says so", not okPipe and whyPipe == "bare pipe", whyPipe)
    local okDash, whyDash = T.Ascii("a \226\128\148 b")
    check("an em dash fails, naming the byte", not okDash and T.Has(whyDash, "byte 226"), whyDash)
    check("a newline fails unless allowed", not T.Ascii("a\nb") and T.Ascii("a\nb", { newlines = true }))
    check("noColour refuses a colour code", not T.Ascii("|cff33ff66ok|r", { noColour = true }))
    check("a non-string fails", not T.Ascii(nil))

    T.section("Strip")
    check("Strip removes colour codes", T.Strip("|cff33ff66ok|r now") == "ok now", T.Strip("|cff33ff66ok|r now"))
    check("Strip keeps an escaped pipe", T.Strip("a || |cffffffffb|r") == "a || b", T.Strip("a || |cffffffffb|r"))

    T.section("CapturedChat")
    local sent = {}
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) sent[#sent + 1] = m end }
    local lines = T.CapturedChat(function()
        DEFAULT_CHAT_FRAME:AddMessage("one")
        DEFAULT_CHAT_FRAME:AddMessage("two")
    end)
    DEFAULT_CHAT_FRAME:AddMessage("after")
    check("CapturedChat keeps what body printed, in order, and restores the frame",
        #lines == 2 and lines[1] == "one" and lines[2] == "two" and #sent == 1 and sent[1] == "after")
    local raised = not pcall(T.CapturedChat, function() error("boom") end)
    DEFAULT_CHAT_FRAME:AddMessage("after a raise")
    check("CapturedChat restores the frame when body raises", raised and sent[2] == "after a raise")
    _G.DEFAULT_CHAT_FRAME = nil

    T.done()
end

return T
