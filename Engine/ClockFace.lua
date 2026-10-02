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
--            the client's. T114: mp5 is the regen feed's number at that
--            moment (UI/Feeds.lua RegenReading): the casting rate inside the
--            rule, the full rate after it
--   mana     T114: the pool's mana, a number | nil
--   manaMax  T114: its max | nil
--   manaModelled  T114: true on Forever (the model's), false on TBC (plain)
--   combat   in a fight
-- (fsr may read 0 after the rule on TBC: a slot treats <= 0 as no rule.)
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
--   "auto"  TBC's: "15s" under a minute, "1:20" above (also any unknown fmt)
--   "mss"   Forever's: always "0:15"
--   "sec"   T114: always seconds, "80s"
--   "msec"  T114: "1m20", "2m00"; "15s" under a minute
-- Past CF.CAP every format reads ">10m"; nil is "--", never a 0. A format
-- changes words only: the precision is the face's (the value comes rounded).
function CF.Time(sec, fmt)
    if type(sec) ~= "number" then return "--" end
    if sec > CF.CAP then return ">10m" end
    if fmt == "mss" then
        if sec < 0 then sec = 0 end
        return string.format("%d:%02d", math.floor(sec / 60), math.floor(sec % 60))
    end
    if fmt == "sec" then
        if sec < 0 then sec = 0 end
        return string.format("%ds", math.floor(sec))
    end
    if fmt == "msec" then
        if sec < 0 then sec = 0 end
        if sec < 60 then return string.format("%ds", math.floor(sec)) end
        return string.format("%dm%02d", math.floor(sec / 60), math.floor(sec % 60))
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

--------------------------------------------------------------------------------
-- T114 (docs/tasks/T114-clock-face-slots.md; mockup clock-v2 C1): the SLOTS.
-- Every place a layout draws is a slot filled from one list of kinds:
--   label  "OOM" / "FULL" ("out" / "full" with labels = lower); "~" on Forever
--   time   today's value piece: "1:20 v", ">1:50 =", "...", "--"
--   pct    "62%" (Forever "~62%", the model's); "--%" without a number
--   mana   "4210", "4210/6800" with ofMax (Forever "~4210")
--   mp5    "92 mp5"; Forever "~92 mp5" in a fight (the last plain reading)
--   fsr    "5SR 3.0" while the five-second rule runs; nothing after it
--   rest   the face's secondary as today ("rest 2:10", TBC's "inn 2:10")
--   cd     only a cooldown secondary (TBC; facts.cd false refuses it)
--   none   nothing
-- CF.TEXT holds each layout's defaults (today's words), CF.TEXT_OPTIONS what
-- each slot accepts, CF.TEXT_HOME the time's home and CF.TEXT_LABEL the
-- label's slot. Pure data: no frame here (T116 draws the slots).
--------------------------------------------------------------------------------
CF.KINDS = { "label", "time", "pct", "mana", "mp5", "fsr", "rest", "cd", "none" }

local RIGHT = { "rest", "pct", "mana", "mp5", "fsr", "cd", "none" }
CF.TEXT_SLOTS = {
    line = { "left", "main", "right", "right2" },
    compact = { "top", "main", "bottom" },
    bar = { "left", "right" },
}
CF.TEXT_HOME = { line = "main", compact = "main", bar = "right" }
CF.TEXT_LABEL = { line = "left", compact = "top", bar = "left" }
CF.TEXT_WORDS = {
    labels = { "caps", "lower" },
    ofMax = { false, true },
    time = { "line", "sec", "msec" },
}
CF.TEXT_OPTIONS = {
    line = {
        left = { "label", "pct", "mana", "none" },
        main = { "time", "pct", "mana" },
        right = RIGHT,
        right2 = RIGHT,
    },
    compact = {
        top = { "label", "time", "none" },
        main = { "time", "pct", "mana" },
        bottom = RIGHT,
    },
    bar = {
        left = { "label", "pct", "mana", "none" },
        right = { "time", "pct", "mana", "none" },
    },
}
CF.TEXT = {
    line = { left = "label", main = "time", right = "rest", right2 = "none",
        labels = "caps", ofMax = false, time = "line" },
    compact = { top = "label", main = "time", bottom = "none",
        labels = "caps", ofMax = false, time = "line" },
    bar = { left = "label", right = "time",
        labels = "caps", ofMax = false, time = "line" },
}

local function Accepts(list, v)
    for i = 1, #list do if list[i] == v then return true end end
    return false
end

-- The resolved text of one layout from its saved table (sparse) -> text,
-- refused. `facts.cd == false` (a line with no mana-cooldown model: Forever)
-- refuses `cd`. Every slot and word option comes from CF.TEXT; a value the
-- slot does not accept is ignored and named in `refused` (a map
-- "text.<layout>.<key>" -> why; nil when nothing was refused). The time is
-- never lost (it carries the honesty marks): the resolved text says where it
-- is drawn (`timeAt`, a slot) and whether the label rides with it
-- (`timeLabel`):
--   * the time's home (Line / Compact main, Bar right) holds it: there, with
--     the label beside it when the label's slot holds neither `label` nor
--     `none` (Bar "Left = Mana %": "62%  OOM 1:20 v");
--   * else the label's slot carries the pair when it holds `label` (or, on
--     Compact, `time`): "OOM 1:20 v" over the big "62%";
--   * else the home is put back to `time` and the refusal named.
-- Compact `top = time` beside a `main = time` is refused (top: the label).
-- An unknown layout answers nil, { text = why }.
function CF.ResolveText(stored, layout, facts)
    local defaults, options = CF.TEXT[layout], CF.TEXT_OPTIONS[layout]
    if not defaults then return nil, { text = "unknown layout " .. tostring(layout) } end
    if type(stored) ~= "table" then stored = {} end
    local noCd = type(facts) == "table" and facts.cd == false
    local out, refused = {}, {}
    local function Refuse(key, why) refused["text." .. layout .. "." .. key] = why end

    for _, slot in ipairs(CF.TEXT_SLOTS[layout]) do
        local v = stored[slot]
        out[slot] = defaults[slot]
        if v ~= nil then
            if v == "cd" and noCd and Accepts(options[slot], v) then
                Refuse(slot, "cd is not offered on this line")
            elseif type(v) == "string" and Accepts(options[slot], v) then
                out[slot] = v
            else
                Refuse(slot, tostring(v) .. " is not a " .. slot .. " choice")
            end
        end
    end
    for key, list in pairs(CF.TEXT_WORDS) do
        local v = stored[key]
        out[key] = defaults[key]
        if v ~= nil then
            if Accepts(list, v) then out[key] = v
            else Refuse(key, tostring(v) .. " is not a " .. key .. " choice") end
        end
    end

    local home, lslot = CF.TEXT_HOME[layout], CF.TEXT_LABEL[layout]
    if out[lslot] == "time" and out[home] == "time" then
        Refuse(lslot, "time is already in " .. home)
        out[lslot] = defaults[lslot]
    end
    if out[home] == "time" then
        out.timeAt = home
        out.timeLabel = out[lslot] ~= "label" and out[lslot] ~= "none"
    elseif out[lslot] == "label" or out[lslot] == "time" then
        out.timeAt, out.timeLabel = lslot, true
    else
        Refuse(home, out[home] .. " would leave the time nowhere: " .. home .. " holds the time again")
        out[home] = "time"
        out.timeAt = home
        out.timeLabel = out[lslot] ~= "label" and out[lslot] ~= "none"
    end
    if next(refused) == nil then refused = nil end
    return out, refused
end

-- Whether a text (resolved or sparse) words its layout's slots as the
-- defaults do (the word options aside).
local function DefaultSlots(text, layout)
    local defaults = CF.TEXT[layout]
    if type(text) ~= "table" or not defaults then return true end
    for _, slot in ipairs(CF.TEXT_SLOTS[layout]) do
        local v = text[slot]
        if v ~= nil and v ~= defaults[slot] then return false end
    end
    return true
end
CF.DefaultSlots = DefaultSlots

local function LabelWord(face, labels)
    local label = face.label or (FULL_LABEL[face.mode] and "FULL" or "OOM")
    if labels == "lower" then
        if label == "OOM" then label = "out" elseif label == "FULL" then label = "full" end
    end
    if face.modelled then label = "~" .. label end
    return label
end

local function TimeFmt(face, opt)
    if opt == "sec" or opt == "msec" then return opt end
    return face.timeFmt
end

-- Today's line, worded with a label and a time format: the one place the
-- clock's words and colour codes are assembled for the default slots.
local function DefaultLine(face, valueHex, label, fmt)
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
--   look.text                 T114: Line's slots (CF.Slots), see below
-- An absent look, or an absent switch, keeps the segment. Never raises on a
-- face that is not a table: nil.
--------------------------------------------------------------------------------
local function Shown(look, key)
    local show = type(look) == "table" and look.show
    if type(show) ~= "table" then return true end
    return show[key] ~= false
end

-- The three pieces, worded with a label word and a time format.
local function Pieces(face, look, label, fmt)
    local known, v = face.known, face.value
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

local function Round(x) return math.floor(x + 0.5) end
local function Num(x) return type(x) == "number" and x == x end

-- One kind's piece outside the time (see CF.KINDS), or nil for an empty slot.
local function KindPiece(kind, face, base, text, atHome)
    if kind == "pct" then
        local p = face.pct
        local words = Num(p) and ((face.pctModelled and "~" or "") .. Round(p * 100) .. "%") or "--%"
        return { text = words, tone = atHome and "mana" or "muted" }
    elseif kind == "mana" then
        local m, mx = face.mana, face.manaMax
        local words
        if Num(m) then
            words = (face.manaModelled and "~" or "") .. Round(m)
            if text.ofMax then words = words .. "/" .. (Num(mx) and tostring(Round(mx)) or "--") end
        else
            words = text.ofMax and "--/--" or "--"
        end
        return { text = words, tone = atHome and "mana" or "muted" }
    elseif kind == "mp5" then
        local r = face.mp5
        if not Num(r) then return { text = "-- mp5", tone = "muted" } end
        local mark = (face.mp5Modelled and face.combat) and "~" or ""
        return { text = mark .. Round(r) .. " mp5", tone = "muted" }
    elseif kind == "fsr" then
        local f = face.fsr
        if not Num(f) or f <= 0 then return nil end
        return { text = string.format("5SR %.1f", f), tone = "warn" }
    elseif kind == "rest" then
        local s = base.second
        if not s then return nil end
        return { text = s.text, tone = s.tone }
    elseif kind == "cd" then
        local s = base.second
        if not s or not (type(face.second) == "table" and face.second.kind == "cd") then return nil end
        return { text = s.text, tone = s.tone }
    end
    return nil
end

-- CF.Slots(face, text, layout [, look]) -> pieces: { left, main, right,
-- right2 } (Line), { top, main, bottom } (Compact), { left, right } (Bar),
-- each nil or { text, tone, arrow, arrowTone } in Segments' shape. A piece that
-- carries the time is marked `time = true`; one that carries the label with
-- it has `labelText` / `labelTone` / `valueText` too ("OOM" + "1:20"), so a
-- renderer can tone the two apart. `text` is resolved here (sparse or not:
-- CF.ResolveText is idempotent); `look.show` gates the secondary as in
-- Segments. With the label drawn nowhere, Forever's "~" stays on the time
-- ("~1:20": it cannot be configured away); a FULL with no time draws its
-- label in the time's place.
function CF.Slots(face, text, layout, look)
    if type(face) ~= "table" then return nil end
    layout = CF.TEXT[layout] and layout or "line"
    local t = CF.ResolveText(text, layout)
    local base = Pieces(face, look, LabelWord(face, t.labels), TimeFmt(face, t.time))
    local lslot = CF.TEXT_LABEL[layout]
    local labelDrawn = t[lslot] == "label" or t.timeLabel

    local timePiece
    local v, l = base.value, base.label
    if t.timeLabel then
        if v then
            timePiece = { text = l.text .. " " .. v.text, tone = v.tone, arrow = v.arrow, arrowTone = v.arrowTone,
                labelText = l.text, labelTone = l.tone, valueText = v.text, time = true }
        else
            timePiece = { text = l.text, tone = l.tone, time = true, labelOnly = true }
        end
    elseif v then
        local words = v.text
        if not labelDrawn and face.modelled then words = "~" .. words end
        timePiece = { text = words, tone = v.tone, arrow = v.arrow, arrowTone = v.arrowTone, time = true }
    elseif not labelDrawn then
        timePiece = { text = l.text, tone = l.tone, time = true, labelOnly = true } -- "FULL": the label is the time
    end

    local home = CF.TEXT_HOME[layout]
    local out = {}
    for _, slot in ipairs(CF.TEXT_SLOTS[layout]) do
        local kind = t[slot]
        if slot == t.timeAt then
            out[slot] = timePiece
        elseif kind == "label" then
            out[slot] = { text = l.text, tone = l.tone }
        elseif kind ~= "time" then
            out[slot] = KindPiece(kind, face, base, t, slot == home)
        end
    end
    return out
end

function CF.Segments(face, look)
    if type(face) ~= "table" then return nil end
    local text = type(look) == "table" and look.text or nil
    if type(text) ~= "table" then
        return Pieces(face, look, LabelWord(face, "caps"), face.timeFmt)
    end
    local segs = CF.Slots(face, text, "line", look)
    segs.label, segs.value, segs.second = segs.left, segs.main, segs.right
    return segs
end

-- The value piece's own words: the time, then its arrow after one space.
function CF.ValueText(value)
    if type(value) ~= "table" then return "" end
    if value.arrow then return value.text .. " " .. value.arrow end
    return value.text
end

-- The line's plain text from its pieces (see Segments): the label, one space,
-- the value and its arrow, then two spaces before the secondary and (T114)
-- the second Right slot. A missing piece takes its separator with it.
function CF.JoinSegments(segs)
    if type(segs) ~= "table" then return "" end
    local out = ""
    if type(segs.label) == "table" then out = segs.label.text end
    if type(segs.value) == "table" then
        out = (out ~= "" and (out .. " ") or "") .. CF.ValueText(segs.value)
    end
    for _, p in ipairs({ segs.second or false, segs.right2 or false }) do
        if p then out = (out ~= "" and (out .. "  ") or "") .. CF.ValueText(p) end
    end
    return out
end

-- A piece in its colours (the generic line: slots other than the defaults).
-- The time's value takes the host's valueHex as today's line does -- not in
-- the crit band, not when muted.
local function PaintPiece(face, p, valueHex)
    local function Hex(tone, isValue)
        if isValue and valueHex and tone ~= "crit" and tone ~= "muted" then return valueHex end
        return HEX[tone] or HEX.normal
    end
    local out
    if p.labelText then
        out = Paint(face, Hex(p.labelTone), p.labelText) .. " " .. Paint(face, Hex(p.tone, true), p.valueText)
    else
        out = Paint(face, Hex(p.tone, p.time and not p.labelOnly), p.text)
    end
    if p.arrow then
        out = out .. " " .. Paint(face, HEX[p.arrowTone or "muted"] or HEX.muted, p.arrow)
    end
    return out
end

-- The ONE place the clock's words and colour codes are assembled: the TBC
-- widget, the ElvUI datatext, the debug log and the Forever clock all show
-- this string. valueHex (e.g. "|cff16c3f2") replaces the value's colour so a
-- datatext can follow its theme -- except the crit band, which stays red, and
-- an unstable value, which stays muted. Two-space separator before the
-- secondary segment; a missing number is "--", never a 0.
-- T114: `text`, optional, is Line's text (resolved or sparse, CF.ResolveText).
-- Absent, or with the default slots, the string is today's byte for byte (the
-- word options -- labels, time -- worded into it); with other slots each piece
-- is painted in its tone (mono still one colour), joined as JoinSegments.
function CF.LineString(face, valueHex, text)
    if type(face) ~= "table" then return "" end
    if type(text) ~= "table" then
        return DefaultLine(face, valueHex, LabelWord(face, "caps"), face.timeFmt)
    end
    local t = CF.ResolveText(text, "line")
    if DefaultSlots(t, "line") then
        return DefaultLine(face, valueHex, LabelWord(face, t.labels), TimeFmt(face, t.time))
    end
    local slots = CF.Slots(face, t, "line")
    local out = ""
    if slots.left then out = PaintPiece(face, slots.left, valueHex) end
    if slots.main then out = (out ~= "" and (out .. " ") or "") .. PaintPiece(face, slots.main, valueHex) end
    for _, key in ipairs({ "right", "right2" }) do
        if slots[key] then out = (out ~= "" and (out .. "  ") or "") .. PaintPiece(face, slots[key], valueHex) end
    end
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
