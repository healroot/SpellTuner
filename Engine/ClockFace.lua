-- T88 (docs/SPEC-next.md 2.4, seam S4 step 1; docs/research/next/R-clock.md 5.1):
-- the clock FACE -- what the mana clock says, as a plain record, apart from how
-- it is drawn. Each line builds its own face:
--   TBC     MD:GetClockFace(now)        Engine/TTO.lua, from the display latch
--   Forever MD.ManaModel.Face(state, now) Engine/ManaModel.lua, from the model
-- and provides it as MD.ClockFace.Current (MD:Provide, one provider per TOC),
-- so a renderer, a feed or a preview asks for "the face now" without asking
-- which client it runs on. MD:GetDisplayString and MD.ManaModel.Text are
-- wrappers over LineString below and stay byte-identical (tools/clockfacecheck.lua's
-- goldens, captured before the split).
--
-- PURE: Lua's own library only -- no frame, no client call, no MD.db, no
-- GetTime (tools/clockfacecheck.lua loads it in an environment holding nothing
-- else). Listed by every main TOC before Engine/TTO.lua / Engine/ManaModel.lua,
-- so neither the offline tools nor the Replay module ever reach a UI file for it.
--
-- The face:
--   mode     "oom" | "hold" | "full" | "warmup" | "ooc" | "fullnow" | "nodata"
--   label    "OOM" | "FULL"
--   value    seconds as SHOWN (TBC: the latched value; Forever: rounded to 5 s,
--            anything past 600 kept as it is) | nil
--   known    "point" (a number) | "bound" (">t =", no sooner than) |
--            "pending" ("...", warm-up) | "none" ("--": never a 0)
--   unstable TBC's "~" before the value: the spend estimate is not yet stable
--   modelled Forever's "~" before the label: the pool is modelled, always
--   tone     "crit" | "warn" | "normal" | "good" | "muted" -- the band of the value
--            (crit under 20 s, warn under 60 s); an unstable value is drawn muted
--            whatever its band
--   arrow    "v" | "^" | "=" | "vv" | nil -- TBC's trend from the SHOWN value;
--            "vv" is TBC's crit-band mark (under 20 s, whatever the trend), not a
--            trend; "=" also closes a bound; nil in FULL, out of combat and on
--            Forever (which keeps no history of shown values)
--   second   { kind = "rest" | "cd", label = "rest" | <cooldown short name>,
--              value = <seconds as shown> } | nil -- AT MOST ONE, already gated
--            by the producer (the 25 % rule, the switches, never beside FULL)
--   fsr      seconds left in the five-second rule | nil;  tick: nil for now
--   mp5, mp5Modelled; pct (0..1), pctModelled -- Forever: the model's, never
--            the client's
--   combat   in a fight
-- and two facts about how its own line words it today, which LineString obeys:
--   timeFmt  "auto" (TBC: "15s" under a minute, "1:20" above) |
--            "mss" (Forever: always "0:15")
--   mono     true: no colour codes in LineString (ManaModel.Text, the Forever
--            string, stays one colour); the renderer (UI/ClockView.lua, T93)
--            draws Segments below, which ignore it: F1 tones on both lines
local _, MD = ...

MD.ClockFace = MD.ClockFace or {}
local CF = MD.ClockFace

CF.CAP = 600 -- seconds; past this a time reads ">10m"

-- The colours the TBC line has always used (Engine/TTO.lua's literals before T88).
CF.HEX = {
    crit   = "|cffff4444",
    warn   = "|cffffaa33",
    normal = "|cffffffff",
    good   = "|cff33ff66",
    muted  = "|cff999999",
    mana   = "|cff4fa9f0",
}
local HEX = CF.HEX
-- The arrow's own colour: up is good, down a warning, steady muted.
CF.ARROW_TONE = { ["^"] = "good", v = "warn", ["="] = "muted", vv = "crit" }

-- The band of a shown OOM value.
function CF.Tone(v)
    if type(v) ~= "number" then return "muted" end
    if v < 20 then return "crit" end
    if v < 60 then return "warn" end
    return "normal"
end

-- A time as the face's line words it. ASCII, never a pipe.
function CF.Time(sec, fmt)
    if type(sec) ~= "number" then return "--" end
    if sec > CF.CAP then return ">10m" end
    if fmt == "mss" then
        if sec < 0 then sec = 0 end
        return string.format("%d:%02d", math.floor(sec / 60), math.floor(sec % 60))
    end
    if sec >= 60 then
        return string.format("%d:%02d", math.floor(sec / 60), math.floor(sec % 60))
    end
    return string.format("%ds", math.floor(sec))
end

local function Paint(face, hex, s)
    if face.mono then return s end
    return hex .. s .. "|r"
end

local FULL_LABEL = { full = true, ooc = true, fullnow = true, nodata = true }

-- The ONE place the clock's words and colour codes are assembled: the TBC
-- widget, the ElvUI datatext, the debug log and the Forever clock all show
-- this string. valueHex (e.g. "|cff16c3f2") replaces the value's colour so a
-- datatext can follow its theme -- except the crit band, which stays red, and
-- an unstable value, which stays muted. Two-space separator before the
-- secondary segment; a missing number is "--", never a 0.
function CF.LineString(face, valueHex)
    if type(face) ~= "table" then return "" end
    local label = face.label or (FULL_LABEL[face.mode] and "FULL" or "OOM")
    if face.modelled then label = "~" .. label end
    local fmt = face.timeFmt
    local known = face.known
    local v = face.value
    local out

    if face.mode == "fullnow" then
        out = Paint(face, HEX[face.tone] or HEX.good, label)        -- "FULL": the label says it
    elseif known == "pending" then
        out = Paint(face, HEX.muted, label .. " ...")
    elseif known == "bound" then
        local bound = (type(v) == "number" and v <= CF.CAP) and CF.Time(v, fmt) or "10m"
        out = Paint(face, HEX.muted, label .. " >" .. bound .. " " .. (face.arrow or "="))
    elseif known == "point" and type(v) == "number" then
        local t = CF.Time(v, fmt)
        if face.tone == "crit" then
            out = Paint(face, HEX.crit, label .. " " .. t .. (face.arrow and (" " .. face.arrow) or ""))
        else
            local hex, prefix = valueHex or HEX[face.tone] or HEX.normal, ""
            if face.unstable then hex, prefix = HEX.muted, "~" end
            out = Paint(face, HEX.muted, label) .. " " .. Paint(face, hex, prefix .. t)
            if face.arrow then
                out = out .. " " .. Paint(face, HEX[CF.ARROW_TONE[face.arrow] or "muted"], face.arrow)
            end
        end
    else
        out = Paint(face, HEX.muted, label .. " --")                -- never fabricate a number
    end

    local sec = face.second
    if type(sec) == "table" and type(sec.value) == "number" then
        local hex = sec.kind == "cd" and HEX.mana or HEX.muted
        out = out .. "  " .. Paint(face, hex, (sec.label or sec.kind or "rest") .. " " .. CF.Time(sec.value, fmt))
    end
    return out
end

--------------------------------------------------------------------------------
-- T93 (docs/SPEC-next.md 7.1 F2 and 2.4; decision 14): the same words cut into
-- the three pieces a layout draws at fixed places, so only the value's own
-- digits move when it changes width ("OOM 59s" -> "OOM 1:00" -> "OOM >10m"):
--   label   { text, tone }                          "OOM", "~FULL"
--   value   { text, tone, arrow, arrowTone } | nil  "1:20" + "v"; ">1:50" + "=";
--                                                   "..."; "--"; nil beside "FULL" alone
--   second  { text, tone } | nil                    "rest 2:10", "inn 2:15"
-- Plain text and tone NAMES only (crit / warn / normal / good / muted / mana):
-- the renderer turns a tone into a colour (ToneRGB / ToneHex, or a look's own
-- colours), so a face is never drawn by a second colour table. The tones are
-- the ones LineString paints with, piece for piece -- the crit band red from
-- the label on, a bound and a warm-up all muted, otherwise a muted label, the
-- value in its band and the arrow in its own tone (ARROW_TONE). A face's
-- `mono` is LineString's business (the Forever string stays one colour) and is
-- not read here: a renderer always colours (F1). JoinSegments(segs) is the
-- line's plain text -- label, one space, the value and its arrow, two spaces,
-- the secondary -- byte for byte LineString's with the colour codes removed.
--   look.show.rest == false   drops a "rest" secondary (F6)
--   look.show.cd   == false   drops a cooldown secondary
-- An absent look, or an absent switch, keeps the segment. Never raises on a
-- face that is not a table: nil.
--------------------------------------------------------------------------------
local function Shown(look, key)
    local show = type(look) == "table" and look.show
    if type(show) ~= "table" then return true end
    return show[key] ~= false
end

function CF.Segments(face, look)
    if type(face) ~= "table" then return nil end
    local label = face.label or (FULL_LABEL[face.mode] and "FULL" or "OOM")
    if face.modelled then label = "~" .. label end
    local fmt, known, v = face.timeFmt, face.known, face.value
    local segs = {}

    if face.mode == "fullnow" then
        segs.label = { text = label, tone = HEX[face.tone] and face.tone or "good" }
    elseif known == "pending" then
        segs.label = { text = label, tone = "muted" }
        segs.value = { text = "...", tone = "muted" }
    elseif known == "bound" then
        local bound = (type(v) == "number" and v <= CF.CAP) and CF.Time(v, fmt) or "10m"
        segs.label = { text = label, tone = "muted" }
        segs.value = { text = ">" .. bound, tone = "muted", arrow = face.arrow or "=", arrowTone = "muted" }
    elseif known == "point" and type(v) == "number" then
        local t = CF.Time(v, fmt)
        if face.tone == "crit" then
            segs.label = { text = label, tone = "crit" }
            segs.value = { text = t, tone = "crit", arrow = face.arrow, arrowTone = face.arrow and "crit" or nil }
        else
            local tone, prefix = HEX[face.tone] and face.tone or "normal", ""
            if face.unstable then tone, prefix = "muted", "~" end
            segs.label = { text = label, tone = "muted" }
            segs.value = { text = prefix .. t, tone = tone, arrow = face.arrow,
                arrowTone = face.arrow and (CF.ARROW_TONE[face.arrow] or "muted") or nil }
        end
    else
        segs.label = { text = label, tone = "muted" }
        segs.value = { text = "--", tone = "muted" }                -- never fabricate a number
    end

    local sec = face.second
    if type(sec) == "table" and type(sec.value) == "number"
        and Shown(look, sec.kind == "cd" and "cd" or "rest") then
        segs.second = { text = (sec.label or sec.kind or "rest") .. " " .. CF.Time(sec.value, fmt),
            tone = sec.kind == "cd" and "mana" or "muted" }
    end
    return segs
end

-- The value piece's own words: the time, then its arrow after one space.
function CF.ValueText(value)
    if type(value) ~= "table" then return "" end
    if value.arrow then return value.text .. " " .. value.arrow end
    return value.text
end

-- The line's plain text from its pieces (see Segments).
function CF.JoinSegments(segs)
    if type(segs) ~= "table" or type(segs.label) ~= "table" then return "" end
    local out = segs.label.text
    if segs.value then out = out .. " " .. CF.ValueText(segs.value) end
    if segs.second then out = out .. "  " .. segs.second.text end
    return out
end

-- A tone as a colour: "|cffRRGGBB" (ToneHex) or 0..1 numbers (ToneRGB).
-- `colors` (optional) maps a tone to six hex digits ("ff4444") and wins over
-- HEX; an unknown tone is `normal`'s.
function CF.ToneHex(tone, colors)
    local own = type(colors) == "table" and colors[tone]
    if type(own) == "string" and own:match("^%x%x%x%x%x%x$") then return "|cff" .. own end
    return HEX[tone] or HEX.normal
end

function CF.ToneRGB(tone, colors)
    local h = CF.ToneHex(tone, colors):sub(5, 10)
    return tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255
end

--------------------------------------------------------------------------------
-- Fixture faces: tools/clockfacecheck.lua renders every one (as TBC draws it,
-- and with Forever's modelled / mono / "mss"), and Settings -> Clock's preview
-- chips (docs/SPEC-next.md 7.4) will paint the same table, so what is previewed
-- is what is tested. TBC-shaped; a line makes its own copy with its marks.
--------------------------------------------------------------------------------
local function Face(t)
    t.modelled, t.mono, t.unstable = t.modelled or false, t.mono or false, t.unstable or false
    t.timeFmt = t.timeFmt or "auto"
    return t
end
CF.SAMPLES = {
    { key = "oom", name = "OOM", face = Face({ mode = "oom", label = "OOM", value = 80, known = "point",
        tone = "normal", arrow = "v", combat = true }) },
    { key = "crit", name = "OOM <20s", face = Face({ mode = "oom", label = "OOM", value = 15, known = "point",
        tone = "crit", arrow = "vv", combat = true }) },
    { key = "bound", name = "bound", face = Face({ mode = "oom", label = "OOM", value = 110, known = "bound",
        tone = "muted", arrow = "=", combat = true }) },
    { key = "hold", name = "hold", face = Face({ mode = "hold", label = "OOM", value = 330, known = "bound",
        tone = "muted", arrow = "=", combat = true }) },
    { key = "warmup", name = "warm-up", face = Face({ mode = "warmup", label = "OOM", known = "pending",
        tone = "muted", combat = true, second = { kind = "rest", label = "rest", value = 250 } }) },
    { key = "full", name = "FULL", face = Face({ mode = "full", label = "FULL", value = 130, known = "point",
        tone = "good", combat = true }) },
    { key = "rest", name = "rest", face = Face({ mode = "oom", label = "OOM", value = 80, known = "point",
        tone = "normal", arrow = "=", combat = true, second = { kind = "rest", label = "rest", value = 220 } }) },
    { key = "ooc", name = "ooc", face = Face({ mode = "ooc", label = "FULL", value = 250, known = "point",
        tone = "good", combat = false }) },
    { key = "fullnow", name = "full now", face = Face({ mode = "fullnow", label = "FULL", known = "none",
        tone = "good", combat = false }) },
    { key = "nodata", name = "no data", face = Face({ mode = "nodata", label = "FULL", known = "none",
        tone = "muted", combat = false }) },
    { key = "none", name = "no value", face = Face({ mode = "oom", label = "OOM", known = "none",
        tone = "muted", combat = true }) },
    { key = "unstable", name = "unstable", face = Face({ mode = "oom", label = "OOM", value = 95, known = "point",
        tone = "normal", unstable = true, arrow = "^", combat = true }) },
    { key = "cd", name = "cooldown", face = Face({ mode = "oom", label = "OOM", value = 75, known = "point",
        tone = "normal", arrow = "v", combat = true, second = { kind = "cd", label = "inn", value = 135 } }) },
    { key = "long", name = ">10m", face = Face({ mode = "ooc", label = "FULL", value = 900, known = "point",
        tone = "good", combat = false }) },
}
