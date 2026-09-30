-- Engine/Recordings.lua (T62, P18, review A5 and B16's root): one router for
-- every recording on both lines. Pure -- no frames, no client calls.
--
-- A recording is addressed by one grammar, whatever keeps it:
--
--   nil, "" (or blanks)   the newest single fight ("1")
--   "N"                   the Nth single fight, newest first
--   "pN" / "PN"           the Nth practice fight
--   "a:b"                 pull b of run a
--
-- Each shape is answered by the provider that registered it: bare N by
-- Engine/FightRecorder.lua (TBC) or Recorder_Forever.lua (Forever), "p" by
-- Engine/Practice.lua, ":" by Engine/RunRecorder.lua (TBC only: Forever
-- records no runs, so "a:b" answers nil there). An address neither shape
-- reads -- "foo", "2x", "p", ":7", "0x2" -- is REFUSED (nil): it used to mean
-- recording 1 (`tonumber(spec) or 1`) on both lines, which is how B16 printed
-- a coach card for the wrong fight. Blanks around an address are ignored, as
-- `tonumber` ignored them.
--
-- Each provider keeps its own retention (which recording is dropped when the
-- list is full); only the address and the pin cap are shared here. The cap
-- is a provider's `pinCap`: REC.MAX_PINNED for single fights on both lines,
-- practice its own (PR.MAX_PINNED); a provider without one (runs: a run is
-- pinned whole on the Review tab, never through an address) pins nothing.
--
-- MD:GetRecording(spec) is the router's entry point, so its callers
-- (UI/ReplayWindow.lua, UI/Dashboard_Review.lua, Engine/ReviewCommands.lua,
-- the Replay module's commands) did not change; it is provided here once,
-- through MD:Provide, and a second definition raises.
local _, MD = ...

local REC = {}
MD.Recordings = REC

-- Single fights pinned at most, on both lines (the retention of
-- Engine/FightRecorder.lua and Recorder_Forever.lua protects this many).
REC.MAX_PINNED = 2

local providers = {}

-- provider = {
--   Get(a [, b])   -> recording [, run]  ("a:b" hands both numbers; the run
--                                         provider answers the run as well)
--   List()         -> its recordings, newest first
--   pinCap         -> how many may be pinned (nil: none through the router)
--   noun           -> what the refusal calls them ("fights")
--   Refusal(count, cap) -> the refusal line, when the provider words its own
--                     (practice keeps the line it always printed)
-- }
-- One provider per shape: a second raises, as MD:Provide does -- two
-- recorders answering one address is a load-order mistake, never a feature.
function REC.Register(prefix, provider)
    if prefix ~= "" and prefix ~= "p" and prefix ~= ":" then
        error("SpellTuner: Recordings.Register: no address shape '" .. tostring(prefix) .. "'", 2)
    end
    if type(provider) ~= "table" or type(provider.Get) ~= "function" then
        error("SpellTuner: Recordings.Register '" .. prefix .. "': a provider needs Get", 2)
    end
    if providers[prefix] then
        error("SpellTuner: a second provider for recordings '" .. prefix .. "'", 2)
    end
    providers[prefix] = provider
    return provider
end

function REC.Provider(prefix)
    return providers[prefix]
end

-- The grammar alone: shape, first number, second number, label -- or nil and
-- the address as given (for the caller's "no recording <label>" line).
function REC.Parse(spec)
    local s = tostring(spec == nil and "" or spec):match("^%s*(.-)%s*$")
    if s == "" then return "", 1, nil, "1" end
    local d = s:match("^(%d+)$")
    if d then
        local n = tonumber(d)
        return "", n, nil, tostring(n)
    end
    d = s:match("^[pP](%d+)$")
    if d then return "p", tonumber(d), nil, "p" .. d end
    local a, b = s:match("^(%d+):(%d+)$")
    if a then return ":", tonumber(a), tonumber(b), s end
    return nil, nil, nil, s
end

-- Returns recording, label, run, pullIndex -- MD:GetRecording's contract
-- since v0.9.2. `run` and `pullIndex` only for "a:b" (the run even when the
-- pull is not in it, as RunRecorder:GetPull answers).
function REC.Get(spec)
    local shape, a, b, label = REC.Parse(spec)
    if not shape then return nil, label end
    local p = providers[shape]
    if not p then return nil, label end
    if shape == ":" then
        local rec, run = p.Get(a, b)
        return rec, label, run, b
    end
    return p.Get(a), label
end

-- A shape's recordings, newest first ({} with no provider for it).
function REC.List(prefix)
    local p = providers[prefix or ""]
    if not (p and p.List) then return {} end
    return p.List() or {}
end

-- Pin or unpin one recording of a shape. `on` nil toggles. Returns true, or
-- false and why (a line the caller prints). Pinning one already pinned is not
-- another pin; a list that already holds more than the cap (an old file) is
-- left as it is -- only a new pin is refused.
function REC.PinRecord(prefix, rec, on)
    local p = providers[prefix or ""]
    if not (p and p.pinCap) then return false, "only a single fight or a practice fight is pinned" end
    if not rec then return false, "no recording" end
    if on == nil then on = not rec.pinned end
    if on and not rec.pinned then
        local count = 0
        for _, r in ipairs(p.List and p.List() or {}) do
            if r.pinned then count = count + 1 end
        end
        if count >= p.pinCap then
            if p.Refusal then return false, p.Refusal(count, p.pinCap) end
            return false, string.format("at most %d %s can be pinned - unpin one first.", p.pinCap,
                p.noun or "recordings")
        end
    end
    rec.pinned = on and true or false
    return true
end

-- The same, by address ("3", "p2"); an address that names nothing is refused.
function REC.Pin(spec, on)
    local shape, _, _, label = REC.Parse(spec)
    if not shape then return false, "no recording " .. label end
    if shape == ":" then return false, "a run's pull is pinned with its run, not alone" end
    local rec = REC.Get(spec)
    if not rec then return false, "no recording " .. label end
    return REC.PinRecord(shape, rec, on)
end

MD:Provide("GetRecording", function(_, spec) return REC.Get(spec) end)
