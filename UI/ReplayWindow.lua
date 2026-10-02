-- The replay window (docs/SPEC-v0.8.md 3): a recorded fight played back as two
-- columns of unit frames on one clock -- ACTUAL on the left (the recorded
-- casts through the engine), SUGGESTED on the right (the plan Coach found) --
-- with the recorder's real HP snapshots drawn as ticks on the left bars, so the
-- reconstruction's error is visible at every moment. Both columns are engine
-- output: the damage is identical by construction and every visible difference
-- is a healer decision.
--
-- This file only PAINTS. Everything it knows about a moment comes from
-- Engine/ReplayTrace.lua (`Seek`, `Advance`, `Hp`, `Hot`, `Casting`, ...); the
-- two states advance the same dt from the same OnUpdate, there is no per-column
-- clock. Nothing is interpolated: a heal is a jump and between grid points the
-- bar holds. The window never opens in combat, never runs the search (Play
-- shows what Coach found), and never touches the recorder.
local _, MD = ...
local UI = MD.UI

-- T16c, lead review (2026-09-28), correcting T16a: a target's name and a
-- fallback spell name come straight from the client and paint in the game's
-- own font for that name -- an EU-realm accented byte is not ours to mangle,
-- it reads on this window exactly as it reads on the game's own frames. Only
-- a bare "|" is unsafe (the client reads it as the start of a colour code or
-- texture escape); everything this file composes itself is ASCII by
-- construction, so nothing else needs escaping. That rule is MD.Text.Esc
-- (pipe-doubling only; Core.lua, T60, P16, review A9). Every caller here
-- tests the name first (`name and Esc(name)`), so a nil never reaches it.
local Esc = MD.Text.Esc

-- T43 (docs/SPEC-forever-ui.md 4.1, 4.4): the window's own highlighted words
-- (the header's #n and PRACTICE, the run strip's name, "paused") open with the
-- theme's accent on Forever; TBC keeps its gold. T69 (P25): a token read,
-- TBC's accent token (UI/Style.lua) being that gold.
local function Hi()
    return UI.Hex("accent")
end

local COL_W = 460              -- the healer strip's width; a column is at least this wide
local GUTTER = 16
local HEADER_H, STRIP_H, SCRUB_H = 26, 96, 96
local RUNSTRIP_H = 26          -- the run strip, drawn only when the pull belongs to a run
-- T72 (P28, review U23, mockup M3): under the theme the header line is a status
-- band -- the fight on the left, the verdict on the right -- 28 px tall.
local BAND_H = 28
local function HeadH() return UI.THEMED and BAND_H or HEADER_H end
local CHOOSER_W = 180          -- the strategy chooser's width (v0.11.11)
local TITLE_GAP = 12           -- T72: what keeps a title clear of the chooser, the fight clear of the verdict
local COACH_W = 104            -- T72: the band's Coach anyway
local DIM_ALPHA = 0.32         -- the suggested column while its plan is being searched for
local KEY_SEEK = 5             -- Left / Right move this many seconds
local DT_STEP_MAX = 0.25       -- never advance more than this per frame at 1x (a hitch is not a skip)
local FLASH_CAST, FLASH_TEXT, FLASH_FOREIGN, PULSE_DMG = 0.8, 0.8, 0.4, 0.4
local GCD = 1.5                -- an instant still locks the healer for this long
local SPEEDS = { 0.25, 0.5, 1, 2, 4 }
local TICK_FADE = 5            -- the recorder's snapshot cadence
-- the ticks checkbox's tooltip for health the recorder READ (R5 swaps it for a
-- reconstruction's and back)
local TICKS_TIPS = { "Snapshot ticks", "The recorder's real HP every 5s, drawn over the",
                     "engine's reconstruction on the left bars." }

-- The author's Cell layout ("default"), copied from their SavedVariables on
-- 2026-09-06 -- NOT read from Cell at runtime, by their request. The frames
-- here are shaped to it so a replay reads like the raid frames the healer
-- actually plays on: same button, same icon slots, same colours. When the
-- Cell layout changes, change this table.
local CELL = {
    size = { 66, 46 }, spacingX = 3, spacingY = 3, unitsPerColumn = 5, powerSize = 2,
    lossFactor = 0.2,                                   -- lossColor = class_color_dark (class * 0.2)
    lossFlash = { 0.667, 0, 0 },                        -- the custom loss red, used for the damage pulse
    nameWidth = 0.75,                                   -- nameText textWidth 75% of the bar
    roleIcon = { "TOPLEFT", 0, 0, 11 },
    hots = { "TOPRIGHT", 0, 3, 13, -1 },                -- indicator1 "Healers": 13px, right-to-left
    defensives = { "LEFT", -2, 5, 12, 20, 1, 2 },       -- 12x20, left-to-right, 2
    debuffs = { "BOTTOMLEFT", 1, 4, 13, 1, 3 },         -- 13px, left-to-right, 3
    healthText = { "BOTTOMRIGHT", 0, 0 },               -- deficit_short
    swiftmend = { 9, -1, -(13 + 5) },                   -- ours: 9px at the right edge, under the HoT row
    targetedSpells = { "TOPLEFT", -4, 4, 20 },          -- 20px, one icon, border 2, TOPLEFT -4,4
    aggroBar = { 20, 4 },                               -- 20x4 above the button's top-left
    statusText = { "BOTTOM", 0, 0 },                    -- 11px with background: cast name, label, dead
    fonts = { name = 13, health = 12, status = 11, count = 11 },
    textScaleMax = 2,                                   -- status / deficit / counts stop growing here; the name does not
}
-- Frames scale with the head-count (author, 2026-09-06): a raid at Cell's own
-- size, a party stretched across the column, a solo fight big enough to read.
--   n = 1      : x3.5 both ways
--   n <= 5     : x1.6 tall, as wide as the column
--   n <= 10    : x1.25, two columns
--   otherwise  : x1, five per column
local function ScaleFor(n)
    if n <= 1 then return 3.5, 1, false end
    if n <= 5 then return 1.6, 1, true end
    if n <= 10 then return 1.25, 2, true end
    return 1, math.ceil(n / CELL.unitsPerColumn), false
end
-- Blizzard's role atlas, the coordinates Cell's roleIcon uses
local ROLE_TEX = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
local ROLE_COORD = {
    TANK = { 0, 19 / 64, 22 / 64, 41 / 64 }, HEALER = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 },
    DAMAGER = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 },
}

-- Family colours, one table (spec 3.2). Utility and shifts are grey.
local FAMILY_COLOR = {
    Rejuvenation = { 0.72, 0.45, 0.95 }, Regrowth = { 0.35, 0.85, 0.35 }, Lifebloom = { 0.75, 0.90, 0.25 },
    HealingTouch = { 0.35, 0.60, 1.00 }, Swiftmend = { 1.00, 0.60, 0.20 }, Tranquility = { 0.30, 0.85, 0.85 },
    other = { 0.6, 0.6, 0.6 },
}
-- Label colours (spec 4.2): what the classifier said about each recorded cast,
-- shown in the status slot as the cast lands and on the scrubber's cast ticks.
local LABEL_COLOR = {
    late = { 1, 0.3, 0.3 }, overheal = { 1, 0.6, 0.2 }, early = { 1, 0.9, 0.3 }, stack = { 1, 0.9, 0.3 },
    spell = { 0.8, 0.8, 0.8 }, rank = { 0.8, 0.8, 0.8 }, fine = { 0.5, 0.5, 0.5 },
    unclassified = { 0.5, 0.5, 0.5 },
}
local LABEL_FLASH = 1.5
local SWIFTMEND = 18562

local frame, scrubber, playBtn, timeFS, headerFS, speedHighlight, speedButtons
local runStrip                  -- the run's pulls and drinks on one timeline (v0.9.4)
local stratDrop                                -- the strategy chooser (v0.11.11)
local openSpec, openForce                      -- what the window was opened with, for a rebuild
local runIdx, pullIdx, curRun   -- which pull of which run is open, if any
-- v0.14.0: run mode. The whole dungeon on one clock, gaps included. `runT` is
-- the RUN's time; the per-pull machinery below is untouched and drives whatever
-- pull that time lands in, so this is a layer over the pull replay rather than a
-- rewrite of it.
local runMode, runTL, runT = false, nil, 0
-- T51 (B22): the combat refusal, once per combat for the window's own re-opens
local refusedInCombat, openingQuietly = false, false
-- The window re-opening a pull by itself: MD:OpenReplay, its combat refusal
-- said once per combat rather than once per frame; answers whether it opened.
local function OpenPull(spec)
    openingQuietly = true -- read and cleared first thing by MD:OpenReplay
    return MD:OpenReplay(spec)
end
local topH = HEADER_H           -- header, plus the run strip when there is one
-- v0.15.0: practice mode. A session (Engine/Practice.lua) is being PLAYED: the
-- left column paints its trace as the engine writes it, the frames take presses,
-- and the clock is the session's. When it ends, the recording opens here as an
-- ordinary replay.
local live = nil                -- the running Practice session, or nil
local hoverTi = nil             -- the frame under the mouse, for key presses
local endBtn
local left, right          -- the two columns: { state, frames = {}, strip = {}, title }
local rp                   -- the SP.Replay result being shown
-- T72 (P28, review U27): the replay's keyboard. On only while the pointer is
-- over the window and never in combat (`pointerIn` is the last answer to "is
-- the pointer over it", so the keys come back only when it ENTERS again);
-- practice keeps its own rules (LiveControls).
local keysOn, pointerIn = false, false
local askedToCoach = false -- the band's Coach anyway: coach even with replayAutoCoach off
local coachEvals = nil     -- the search's plan count last written into the dimmed column's title

-- Does the healer of the recording being played have Swiftmend at all?
local function HasSwiftmend()
    local known = rp and rp.rec and rp.rec.initial and rp.rec.initial.known
    if known then return known.Swiftmend ~= nil end
    return (MD.SpellData.maxRank or {}).Swiftmend ~= nil
end
local rows = {}            -- roster indices in display order
local playing, speed = false, 1
local classColorCache = {}

-- Show/Hide rather than SetShown: the older pair exists on every client this
-- addon targets, and a font string has no SetShown on some of them.
local function Shown(obj, on) if on then obj:Show() else obj:Hide() end end

local function ClassColor(class)
    local c = classColorCache[class]
    if c then return c end
    local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    c = cc and { cc.r, cc.g, cc.b } or { 0.6, 0.6, 0.6 }
    classColorCache[class] = c
    return c
end

local rankCount = nil
local function SpellLabel(spellID)
    local SD = MD.SpellData
    local sd = SD.spells[spellID]
    if sd then
        if not rankCount then
            rankCount = {}
            for _, s in pairs(SD.spells) do rankCount[s.family] = (rankCount[s.family] or 0) + 1 end
        end
        local fam = SD.families[sd.family]
        local name = fam and fam.label or sd.family
        if (rankCount[sd.family] or 1) > 1 then name = string.format("%s R%d", name, sd.rank) end
        return name, sd.family
    end
    local name = MD.API.SpellName(spellID)
    return (name and Esc(name)) or ("spell " .. tostring(spellID)), "other"
end

-- m:ss.t, a negative time 0:00.0 (MD.Util.Clock; T60, P16, review A9).
local function Clock(sec) return MD.Util.Clock(sec, true) end

-- "2.3k" from 1000 on (MD.Util.K; T60, P16, review A9) -- except below zero.
-- This window's K has always printed string.format("%d", n + 0.5), which
-- truncates toward zero (-12 -> "-11"), where MD.Util.K rounds (-12 -> "-12");
-- the two agree on every n >= 0. The score line's used and regen go below zero
-- when the pool gains more than it spends (a pull started below full), so the
-- old rule is kept there, byte for byte, until a decision says otherwise.
local function K(n)
    if type(n) == "number" and n < 0 then return string.format("%d", n + 0.5) end
    return MD.Util.K(n)
end

--------------------------------------------------------------------------------
-- Building one column
--------------------------------------------------------------------------------
local function CreateBar(parent, width, height)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetSize(width, height)
    bar:SetStatusBarTexture(UI.whiteTexture)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.06, 0.06, 1)
    bar.bg = bg
    return bar
end

-- The base font the kit uses, for scaled copies
local FONT_PATH, FONT_FLAGS
do
    local fo = _G[UI.FONT]
    local ok, path, _, flags = pcall(function() return fo:GetFont() end)
    FONT_PATH = (ok and path) or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    FONT_FLAGS = (ok and flags) or ""
end
local function Font(fs, size)
    pcall(fs.SetFont, fs, FONT_PATH, size, "OUTLINE")
end

-- The snapshot tick's tooltip, owned by the tick's hover frame (and, under the
-- theme, by the whole button: the bar's tooltip).
local function TickTip(owner, f)
    if not (MD.Tip and f.tickInfo) then return end
    local ti = f.tickInfo
    if ti.recon and UI.THEMED then
        -- T72 (P28, mockup M3): the bar's tooltip, the reconstruction one
        -- marker on its title line and one sentence under it
        local within = math.abs(ti.rec - ti.sim) <= 0.05
        local m = UI.Hex("muted")
        MD.Tip:Show(owner, "ANCHOR_RIGHT", {
            { l = f.name:GetText() or "", r = m .. "reconstructed|r" },
            { l = "Health then", r = string.format("%d%% at %s", ti.rec * 100 + 0.5, Clock(ti.at)) },
            { l = "Engine's replay now", r = string.format("%d%%", ti.sim * 100 + 0.5) },
            { l = "Difference", r = within and (UI.Hex("good") .. "within 5%|r")
                or (UI.Hex("bad") .. "outside 5%|r") },
            { l = m .. "Reconstructed: this client reads no health, so it is|r", r = "" },
            { l = m .. "rebuilt from UNIT_COMBAT every 2 s, from full at the pull.|r", r = "" },
        })
        return
    end
    if ti.recon then
        -- R5 (review 2026-09-29): a v3 (Forever) tick is SM.RecordedHp's
        -- reconstruction -- no health was ever read -- so it is not
        -- called recorded, real or the truth.
        MD.Tip:Show(owner, "ANCHOR_RIGHT", {
            { l = "Reconstructed health", r = string.format("%d%% at %s", ti.rec * 100 + 0.5, Clock(ti.at)) },
            { l = "Engine's replay now", r = string.format("%d%%", ti.sim * 100 + 0.5) },
            { l = string.format("|cff888888%s|r", math.abs(ti.rec - ti.sim) <= 0.05
                and "within the health gate's 5%" or "outside the health gate's 5%"), r = "" },
            { l = "|cff888888No health is read on this client (it is secret). The tick|r", r = "" },
            { l = "|cff888888is rebuilt from UNIT_COMBAT every 2s, from full at the pull,|r", r = "" },
            { l = "|cff888888a party max perhaps estimated: an estimate, not the truth.|r", r = "" },
        })
        return
    end
    MD.Tip:Show(owner, "ANCHOR_RIGHT", {
        { l = "Recorded health", r = string.format("%d%% at %s", ti.rec * 100 + 0.5, Clock(ti.at)) },
        { l = "Engine's reconstruction now", r = string.format("%d%%", ti.sim * 100 + 0.5) },
        { l = string.format("|cff888888%s|r", math.abs(ti.rec - ti.sim) <= 0.05
            and "within the health gate's 5%" or "outside the health gate's 5% -- this is the replay's error"), r = "" },
        { l = "|cff888888The recorder reads real HP every 5s; the bar is the engine's|r", r = "" },
        { l = "|cff888888account of the same fight. The tick is the truth mark.|r", r = "" },
    })
end

local function CreateUnitFrame(parent, x, y)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    UI.StylizeFrame(f, { 0, 0, 0, 1 }, { 0, 0, 0, 1 })
    -- T107: the author's Cell layout keeps its colours under every style
    -- (docs/SPEC-next.md 5.1): a style switch's follow never enters it
    f.restyleExempt = true

    -- Frame levels, as Cell lays them: the bars lowest, indicators above them,
    -- text on top. Two children of one button share a level by default and
    -- the later-drawn bar covered the icons' textures (the first in-game look:
    -- a bare stack count over solid class colour).
    local base = f:GetFrameLevel()
    f.top = CreateFrame("Frame", nil, f)
    f.top:SetAllPoints(f)
    f.top:SetFrameLevel(base + 20)

    -- the health bar fills the button inside its 1px border, above the power strip
    f.bar = CreateBar(f, 10, 10)
    f.bar:SetFrameLevel(base + 1)
    f.power = CreateBar(f, 10, 2)
    f.power:SetFrameLevel(base + 1)
    f.power:SetStatusBarColor(0, 0.5, 1)
    f.power.bg:SetColorTexture(0.15, 0.15, 0.15, 1)

    -- the damage pulse: the loss red washed over the bar, fading
    f.pulse = f.bar:CreateTexture(nil, "ARTWORK", nil, 1)
    f.pulse:SetAllPoints(f.bar)
    f.pulse:SetColorTexture(CELL.lossFlash[1], CELL.lossFlash[2], CELL.lossFlash[3], 0)

    -- the snapshot tick (left column only): the truth over the reconstruction,
    -- with a hover frame wide enough to hit that says what it is
    f.tick = f.bar:CreateTexture(nil, "OVERLAY")
    f.tick:SetColorTexture(1, 1, 1, 0)
    f.tickHit = CreateFrame("Frame", nil, f)
    f.tickHit:SetFrameLevel(base + 21)
    f.tickHit:EnableMouse(true)
    f.tickHit:Hide()
    f.tickHit:SetScript("OnEnter", function(self) TickTip(self, f) end)
    f.tickHit:SetScript("OnLeave", function() if MD.Tip then MD.Tip:Hide() end end)

    -- nameText: centred on the bar, class colour, 75% of the bar's width
    f.name = f.bar:CreateFontString(nil, "OVERLAY", UI.FONT)
    f.name:SetPoint("CENTER", f.bar, "CENTER", 0, 0)
    f.name:SetJustifyH("CENTER")
    f.name:SetWordWrap(false)

    -- healthText: deficit_short, bottom-right of the bar
    f.pct = f.bar:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    f.pct:SetJustifyH("RIGHT")

    -- roleIcon, top-left
    f.role = f.top:CreateTexture(nil, "OVERLAY")
    pcall(f.role.SetTexture, f.role, ROLE_TEX)

    -- statusText: the bottom strip -- the cast in flight to this unit or the
    -- one that just landed, then the classifier's label, or DEAD. Cell has no
    -- slot for a cast target; this is the one addition. The background is
    -- drawn only while there is text.
    f.statusBG = f.top:CreateTexture(nil, "ARTWORK")
    f.statusBG:SetColorTexture(0, 0, 0, 0.6)
    f.statusBG:Hide()
    f.cast = f.top:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    f.cast:SetJustifyH("CENTER")
    f.cast:SetWordWrap(false)
    f.cast:SetText("")
    f.label = f.top:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    f.label:SetJustifyH("CENTER")
    f.label:SetWordWrap(false)
    f.label:SetText("")
    -- what the two strings hold, kept here: GetText() on an empty font string
    -- is nil on this client, and "nil ~= ''" drew the strip's background over
    -- every button that had nothing to say (the brown band of the first look)
    f.castText, f.labelText = "", ""
    function f.SetCast(text) f.castText = text or ""; f.cast:SetText(f.castText) end
    function f.SetLabel(text) f.labelText = text or ""; f.label:SetText(f.labelText) end

    -- One icon builder for HoTs, defensives and debuffs: the spell's texture,
    -- a Cell-style VERTICAL sweep (the elapsed share of the icon dimmed from
    -- the top down, a 1px spark at the edge -- Cell/Indicators/Base.lua's
    -- VerticalCooldown, done with an overlay rather than a mask because the
    -- window paints every frame anyway), a stack count bottom-right, and a
    -- lettered fallback when no texture resolves.
    local function Icon(level)
        local ic = CreateFrame("Frame", nil, f, "BackdropTemplate")
        ic:SetFrameLevel(base + (level or 5))
        UI.StylizeFrame(ic, { 0.15, 0.15, 0.15, 1 }, { 0, 0, 0, 1 })
        ic.tex = ic:CreateTexture(nil, "ARTWORK")
        ic.tex:SetPoint("TOPLEFT", ic, "TOPLEFT", 1, -1)
        ic.tex:SetPoint("BOTTOMRIGHT", ic, "BOTTOMRIGHT", -1, 1)
        ic.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        ic.dim = ic:CreateTexture(nil, "OVERLAY", nil, 1)
        ic.dim:SetPoint("TOPLEFT", ic, "TOPLEFT", 1, -1)
        ic.dim:SetPoint("TOPRIGHT", ic, "TOPRIGHT", -1, -1)
        ic.dim:SetHeight(1)
        ic.dim:SetColorTexture(0, 0, 0, 0.65)
        ic.dim:Hide()
        ic.spark = ic:CreateTexture(nil, "OVERLAY", nil, 2)
        ic.spark:SetPoint("TOPLEFT", ic.dim, "BOTTOMLEFT", 0, 0)
        ic.spark:SetPoint("TOPRIGHT", ic.dim, "BOTTOMRIGHT", 0, 0)
        ic.spark:SetHeight(1)
        ic.spark:SetColorTexture(0.8, 0.8, 0.8, 0.9)
        ic.spark:Hide()
        ic.letter = ic:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
        ic.letter:SetPoint("CENTER")
        ic.count = ic:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
        ic.count:SetPoint("BOTTOMRIGHT", ic, "BOTTOMRIGHT", 1, -1)
        ic.text = ic.count   -- older name, kept for the harness
        ic:EnableMouse(true)
        ic:SetScript("OnEnter", function(self)
            if MD.Tip and self.tip then MD.Tip:Show(self, "ANCHOR_RIGHT", self.tip) end
        end)
        ic:SetScript("OnLeave", function() if MD.Tip then MD.Tip:Hide() end end)
        ic:Hide()
        return ic
    end

    f.hots = {}
    for fi = 1, 3 do f.hots[fi] = Icon(5) end
    -- Swiftmend: an icon under the HoT row -- full while it is ready and has
    -- something to eat, sweeping its cooldown otherwise (the author asked for
    -- the icon in place of the 5px dot)
    f.dot = Icon(5)
    f.defIcon = Icon(10)
    UI.Tint(f.defIcon, "border", "accent", 1) -- T107
    f.debuffs = {}
    for i = 1, CELL.debuffs[6] do f.debuffs[i] = Icon(5) end
    -- v0.12.2: the two indicators the author has that show what is COMING --
    -- Cell's "Targeted Spells" (a hostile cast aimed here) and its "Aggro (bar)"
    -- -- in their own positions. Drawn on both columns: both are watching the
    -- same fight, and the suggested column is answering the same cast bar.
    f.incoming = Icon(12)
    f.aggro = f:CreateTexture(nil, "OVERLAY")
    f.aggro:Hide()
    f.auraBuf = {}

    -- Size and place everything for a button of W x H pixels at scale s: the
    -- slots keep their Cell positions, the offsets and icons grow with s, the
    -- bar and the name stretch with the width.
    function f.Resize(W, H, sc)
        f.scale, f.width = sc, W
        f:SetSize(W, H)
        local pw = math.max(1, CELL.powerSize * sc)
        f.bar:ClearAllPoints()
        f.bar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
        f.bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1 + pw)
        f.power:ClearAllPoints()
        f.power:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
        f.power:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
        f.power:SetHeight(pw)
        f.tick:SetSize(math.max(2, 2 * sc), H - 2 - pw)
        f.name:SetWidth((W - 2) * CELL.nameWidth)
        local ts = CELL.targetedSpells
        f.incoming:SetSize(ts[4] * sc, ts[4] * sc)
        f.incoming.size = ts[4] * sc      -- Sweep reads it to size the dim overlay
        f.incoming:ClearAllPoints()
        f.incoming:SetPoint("TOPLEFT", f, "TOPLEFT", ts[2] * sc, ts[3] * sc)
        f.aggro:SetSize(CELL.aggroBar[1] * sc, math.max(1, CELL.aggroBar[2] * sc))
        f.aggro:ClearAllPoints()
        f.aggro:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 1)
        Font(f.name, CELL.fonts.name * sc)
        local ht = CELL.healthText
        f.pct:ClearAllPoints()
        f.pct:SetPoint(ht[1], f.bar, ht[1], ht[2] * sc, ht[3] * sc)
        local ts = math.min(sc, CELL.textScaleMax)
        Font(f.pct, CELL.fonts.health * ts)
        local ri = CELL.roleIcon
        f.role:SetSize(ri[4] * sc, ri[4] * sc)
        f.role:ClearAllPoints()
        f.role:SetPoint(ri[1], f, ri[1], ri[2] * sc, ri[3] * sc)
        local stt = CELL.statusText
        local sh = 12 * ts
        f.statusBG:ClearAllPoints()
        f.statusBG:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1 + pw)
        f.statusBG:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1 + pw)
        f.statusBG:SetHeight(sh)
        for _, fs in ipairs({ f.cast, f.label }) do
            fs:ClearAllPoints()
            fs:SetPoint(stt[1], f, stt[1], stt[2] * sc, stt[3] + pw + 1)
            fs:SetWidth(W - 4)
            Font(fs, CELL.fonts.status * ts)
        end
        -- the HoT icons are sized here and PLACED in PaintFrame: like Cell's
        -- icon indicators they pack from the anchor, so a lone Lifebloom sits
        -- in the first slot rather than floating in the third
        local ho = CELL.hots
        for fi = 1, 3 do
            local ic = f.hots[fi]
            ic:SetSize(ho[4] * sc, ho[4] * sc); ic.size = ho[4] * sc
            ic.slot = nil
            Font(ic.count, CELL.fonts.count * ts); Font(ic.letter, CELL.fonts.count * ts)
        end
        -- Swiftmend: smaller than a HoT icon, at the right edge under the row
        local sm = CELL.swiftmend
        f.dot:SetSize(sm[1] * sc, sm[1] * sc); f.dot.size = sm[1] * sc
        f.dot:ClearAllPoints()
        f.dot:SetPoint("TOPRIGHT", f, "TOPRIGHT", sm[2] * sc, sm[3] * sc)
        Font(f.dot.count, CELL.fonts.count * ts); Font(f.dot.letter, CELL.fonts.count * ts)
        f.pctRaised = nil
        local de = CELL.defensives
        f.defIcon:SetSize(de[4] * sc, de[5] * sc); f.defIcon.size = de[5] * sc
        f.defIcon:ClearAllPoints()
        f.defIcon:SetPoint(de[1], f, de[1], de[2] * sc, de[3] * sc)
        Font(f.defIcon.count, CELL.fonts.count * ts); Font(f.defIcon.letter, CELL.fonts.count * ts)
        local db = CELL.debuffs
        for i, ic in ipairs(f.debuffs) do
            ic:SetSize(db[4] * sc, db[4] * sc); ic.size = db[4] * sc
            ic:ClearAllPoints()
            ic:SetPoint(db[1], f, db[1], (db[2] + db[5] * (i - 1) * db[4]) * sc, db[3] * sc)
            Font(ic.count, CELL.fonts.count * ts); Font(ic.letter, CELL.fonts.count * ts)
        end
    end
    f.Resize(CELL.size[1], CELL.size[2], 1)

    f.flashUntil, f.textUntil, f.labelFrom, f.labelUntil, f.pulseUntil = 0, 0, 0, 0, 0

    -- v0.15.0: practice. A press anywhere on the button -- its icons included,
    -- which take the mouse for their tooltips -- is a press on this unit, and
    -- hovering any part of it makes it the mouseover a key press heals.
    local function Press(_, button) if f.onPress then f.onPress(button) end end
    local function Hover() if f.onHover then f.onHover(true) end end
    local function Unhover() if f.onHover then f.onHover(false) end end
    f:EnableMouse(true)
    f:SetScript("OnMouseDown", Press)
    if UI.THEMED then
        -- T72 (P28, mockup M3): outside practice, hovering the left button is
        -- hovering its bar -- the tick's tooltip, with the reconstruction marked
        f:SetScript("OnEnter", function(self)
            Hover()
            if not f.onHover and f.tickHit:IsShown() then TickTip(self, f) end
        end)
        f:SetScript("OnLeave", function()
            Unhover()
            if not f.onHover and MD.Tip then MD.Tip:Hide() end
        end)
    else
        f:SetScript("OnEnter", Hover)
        f:SetScript("OnLeave", Unhover)
    end
    -- T51 (B23): the button's OnLeave fires when the pointer moves onto one of
    -- its icons, so every icon makes the button the mouseover again on enter;
    -- and leaving an icon clears it unless the pointer is still on the button
    -- (back onto its body), so a key never heals a frame the pointer has left.
    local function IconLeave() if not f:IsMouseOver() then Unhover() end end
    local icons = { f.dot, f.defIcon, f.incoming }
    for _, ic in ipairs(f.hots) do icons[#icons + 1] = ic end
    for _, ic in ipairs(f.debuffs) do icons[#icons + 1] = ic end
    for _, ic in ipairs(icons) do
        ic:HookScript("OnMouseDown", Press)
        ic:HookScript("OnEnter", Hover)
        ic:HookScript("OnLeave", IconLeave)
    end
    return f
end

local function CreateStrip(parent, x, y)
    local s = {}
    s.mana = CreateBar(parent, COL_W - 70, 18)
    s.mana:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    s.mana:SetStatusBarColor(0.25, 0.45, 0.95)
    s.manaFS = s.mana:CreateFontString(nil, "OVERLAY", UI.FONT)
    s.manaFS:SetPoint("CENTER")
    s.form = parent:CreateFontString(nil, "OVERLAY", UI.FONT)
    s.form:SetPoint("LEFT", s.mana, "RIGHT", 8, 0)
    s.form:SetTextColor(0.7, 0.7, 0.7)

    -- the cast bar: a real cast fills over its cast time in the family colour;
    -- an instant sweeps the GCD in grey (the healer is locked either way; a
    -- hard cast's GCD ran under its own bar, so none follows it -- F2).
    -- The name STAYS until the next cast, dimmed once the bar is done -- the
    -- question the strip answers is "what was I doing", not "is a bar moving".
    s.cast = CreateBar(parent, COL_W - 70, 18)
    s.cast:SetPoint("TOPLEFT", s.mana, "BOTTOMLEFT", 0, -6)
    s.cast:SetStatusBarColor(0.8, 0.8, 0.8)
    s.castFS = s.cast:CreateFontString(nil, "OVERLAY", UI.FONT)
    s.castFS:SetPoint("LEFT", s.cast, "LEFT", 5, 0)
    s.castFS:SetJustifyH("LEFT")
    s.castFS:SetWordWrap(false)
    s.wait = parent:CreateFontString(nil, "OVERLAY", UI.FONT)
    s.wait:SetPoint("LEFT", s.cast, "RIGHT", 8, 0)
    s.wait:SetTextColor(0.6, 0.6, 0.6)
    -- the wait band: a grey wash over the cast bar while the plan holds
    s.band = s.cast:CreateTexture(nil, "ARTWORK")
    s.band:SetAllPoints(s.cast)
    s.band:SetColorTexture(0.5, 0.5, 0.5, 0)
    -- hovering the cast bar names the rule behind the current cast or wait
    s.cast:EnableMouse(true)
    s.cast:SetScript("OnEnter", function(self)
        if not (MD.Tip and s.why) then return end
        MD.Tip:Show(self, "ANCHOR_TOP", s.why)
    end)
    s.cast:SetScript("OnLeave", function() if MD.Tip then MD.Tip:Hide() end end)

    s.score = parent:CreateFontString(nil, "OVERLAY", UI.FONT)
    s.score:SetPoint("TOPLEFT", s.cast, "BOTTOMLEFT", 0, -8)
    s.score:SetJustifyH("LEFT")
    s.score:SetWidth(COL_W)
    s.gcdUntil, s.gcdStart = 0, 0
    return s
end

local function CreateColumn(x, titleText)
    local col = { frames = {}, x = x }
    col.title = frame:CreateFontString(nil, "OVERLAY", UI.FONT_TITLE)
    col.title:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -(HEADER_H + 6))
    col.title:SetText(titleText)
    col.strip = CreateStrip(frame, x, -(HEADER_H + 30))
    return col
end

--------------------------------------------------------------------------------
-- Visual events: what onEvent does with a crossed event. State is read from
-- the machine every frame; these only start the short-lived effects.
--------------------------------------------------------------------------------
local function MakeOnEvent(col)
    local RT, TK = MD.ReplayTrace, MD.SimModel.TK
    return function(kind, tgt, a, b, t)
        local now = GetTime()
        local f = tgt and col.frames[tgt]
        if kind == TK.CAST then
            local label, family = SpellLabel(a)
            if f then
                local c = FAMILY_COLOR[family] or FAMILY_COLOR.other
                f:SetBackdropBorderColor(c[1], c[2], c[3], 1)
                f.flashUntil = now + FLASH_CAST
                f.SetCast(label)
                f.cast:SetTextColor(c[1], c[2], c[3])
                f.textUntil = now + FLASH_TEXT
                -- the classifier's word for this cast (left column, plan present),
                -- in the same slot once the name has had its moment
                local lc = col.state and col.state.lastCast
                local cl = col.isLeft and rp.casts and lc and rp.casts[lc.n]
                if cl and cl.label and cl.label ~= "utility" and cl.label ~= "shift" then
                    local lcol = LABEL_COLOR[cl.label] or LABEL_COLOR.unclassified
                    f.SetLabel(cl.label)
                    f.label:SetTextColor(lcol[1], lcol[2], lcol[3])
                    f.labelFrom, f.labelUntil = now + FLASH_TEXT, now + FLASH_TEXT + LABEL_FLASH
                end
            end
            local tgtName = rp.rec.roster[tgt] and rp.rec.roster[tgt].name
            col.strip.lastCast = label .. (tgtName and (" -> " .. Esc(tgtName)) or "")
            col.strip.lastFamily = family
            -- F2: only an instant sweeps the GCD, from this moment (replay
            -- clock, not wall clock). A hard cast's GCD began with its cast
            -- bar and is over by its success, so after it the name stays,
            -- dimmed -- no "instant" sweep of a cast that had a bar.
            local s = col.strip
            local hard = s.barSpell == a and s.barAt and t > s.barAt
            s.barSpell, s.barAt = nil, nil
            if hard then
                s.gcdStart, s.gcdUntil = 0, 0
            else
                s.gcdStart, s.gcdUntil = t, t + GCD
            end
        elseif kind == TK.CAST_START then
            -- F2: the bar a following CAST of this spell finishes
            col.strip.barSpell, col.strip.barAt = a, t
        elseif kind == TK.CANCEL then
            col.strip.barSpell, col.strip.barAt = nil, nil
        elseif kind == RT.EV_DMG then
            if f then
                local maxHP = rp.scenario.targets[tgt] and rp.scenario.targets[tgt].maxHP or 1
                local frac = (a or 0) / maxHP
                if frac > 1 then frac = 1 end
                f.pulseAlpha = 0.25 + 0.6 * frac
                f.pulseUntil = now + PULSE_DMG
            end
        elseif kind == RT.EV_FHEAL then
            if f then
                f:SetBackdropBorderColor(1, 1, 1, 0.8)
                f.flashUntil = now + FLASH_FOREIGN
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Painting a moment
--------------------------------------------------------------------------------
local function AuraName(spellID)
    local d = MD.AuraList and MD.AuraList.Defensive(spellID)
    if d then return d[1] end
    local name = MD.API.SpellName(spellID)
    return (name and Esc(name)) or ("spell " .. tostring(spellID))
end

local textureCache = {}
local function SpellTexture(spellID)
    local tex = textureCache[spellID]
    if tex ~= nil then return tex or nil end
    local t = MD.API.SpellTexture(spellID)
    if not t then
        -- this client may not have GetSpellTexture; MD.API.SpellName's third
        -- return is the icon on the 2.5.x client (T7/T15's Bind of
        -- SpellName -> GetSpellInfo there); Forever's own SpellTexture binding
        -- (Client/API_Forever.lua's C_Spell.GetSpellTexture) always answers
        -- one way or the other, so this fallback is TBC-only in practice.
        local icon = select(3, MD.API.SpellName(spellID))
        if icon then t = icon end
    end
    if not t then MD:Debug("sim", "replay: no texture for spell %d", spellID); t = false end
    textureCache[spellID] = t
    return t or nil
end

-- Set the icon's texture (or its lettered fallback) once per spell, then the
-- sweep: the elapsed share of (since .. until) dimmed from the top down.
local function SetIcon(ic, spellID, fallbackName)
    if ic.spellID ~= spellID then
        ic.spellID = spellID
        local tex = SpellTexture(spellID)
        if tex then
            ic.tex:SetTexture(tex)
            ic.letter:SetText("")
        else
            ic.tex:SetTexture(nil)
            ic.letter:SetText((fallbackName or "?"):sub(1, 1))
        end
    end
end

local function Sweep(ic, since, until_, t)
    local dur = (until_ or 0) - (since or 0)
    if dur <= 0 then ic.dim:Hide(); ic.spark:Hide(); return end
    local frac = (t - since) / dur
    if frac < 0 then frac = 0 end
    if frac > 1 then frac = 1 end
    local h = (ic.size - 2) * frac
    if h < 0.5 then
        ic.dim:Hide(); ic.spark:Hide()
    else
        ic.dim:SetHeight(h)
        ic.dim:Show()
        Shown(ic.spark, frac < 1)
    end
end

local function PaintIcon(ic, a, t, isDef)
    SetIcon(ic, a.spellID, AuraName(a.spellID))
    Sweep(ic, a.since, a.until_, t)
    ic.count:SetText((a.stacks or 1) > 1 and tostring(a.stacks) or "")
    ic.tip = ic.tip or {}
    ic.tip[1] = { l = AuraName(a.spellID), r = isDef and "|cff888888defensive|r" or "|cff888888debuff|r" }
    ic.tip[2] = { l = string.format("applied at %s", Clock(a.since)), r = string.format("up %.0fs", t - a.since) }
    ic.tip[3] = (a.stacks or 1) > 1 and { l = string.format("%d stacks", a.stacks), r = "" } or nil
    ic:Show()
end

local function Deficit(hp, maxHP)
    local d = (1 - (hp or 0)) * (maxHP or 0)
    if d < 1 then return "" end
    if d >= 1000 then return string.format("-%.1fk", d / 1000) end
    return string.format("-%d", d + 0.5)
end

local function PaintFrame(f, st, ti, isLeft, now)
    local hp = st:Hp(ti)
    local dead = st:Dead(ti)
    local c = f.classColor
    local sc = f.scale or 1
    local maxHP = rp.scenario.targets[ti] and rp.scenario.targets[ti].maxHP or 0
    if dead then
        f.bar:SetValue(0)
        f.pct:SetText("dead")
        f.pct:SetTextColor(1, 0.19, 0.19)
        f.name:SetTextColor(0.5, 0.5, 0.5)
    else
        f.bar:SetValue(hp or 0)
        f.pct:SetText(Deficit(hp, maxHP))
        f.pct:SetTextColor(1, 1, 1)
        f.name:SetTextColor(c[1], c[2], c[3])
    end
    if f.isHealer then f.power:SetValue((st:Mana() or 0) / (rp.scenario.pool or 1)) end

    -- the cast in flight to this unit: the button's border in the family
    -- colour and the spell's name in the status strip for as long as it casts
    local casting = st:Casting()
    local inFlight = casting and casting.target == ti and casting.castTime and casting.castTime > 0
    if inFlight then
        local label, family = SpellLabel(casting.spellID)
        local fc = FAMILY_COLOR[family] or FAMILY_COLOR.other
        f:SetBackdropBorderColor(fc[1], fc[2], fc[3], 1)
        f.SetCast(label .. " ...")
        f.cast:SetTextColor(fc[1], fc[2], fc[3])
        f.textUntil = now + 0.1   -- refreshed every frame while in flight
    elseif f.flashUntil <= now then
        f:SetBackdropBorderColor(0, 0, 0, 1)
    end

    -- the status slot: the landed cast's name, then its label; DEAD wins.
    -- Nothing is drawn -- no background either -- when there is nothing to say.
    if f.textUntil <= now and f.castText ~= "" then f.SetCast("") end
    local showLabel = f.labelFrom <= now and now < f.labelUntil and f.labelText ~= ""
    if f.labelUntil <= now and f.labelText ~= "" then f.SetLabel("") end
    Shown(f.label, showLabel and not dead)
    Shown(f.cast, f.castText ~= "" and not showLabel and not dead)
    local stripShown = (not dead) and (showLabel or f.castText ~= "")
    Shown(f.statusBG, stripShown)
    -- the deficit steps up above the strip while the strip has text
    if f.pctRaised ~= stripShown then
        f.pctRaised = stripShown
        local ht = CELL.healthText
        f.pct:ClearAllPoints()
        f.pct:SetPoint(ht[1], f.bar, ht[1], ht[2] * sc, ht[3] * sc + (stripShown and (12 * math.min(sc, CELL.textScaleMax) + 1) or 0))
    end

    -- HoT icons with the vertical sweep of their remaining time; Lifebloom
    -- shows its stacks and its border turns white in the last second (the
    -- bloom is coming). The dot: Swiftmend has something to eat and is ready.
    -- T96: a slot is named by the kit's own profile (State:HotSlots), never
    -- the logged-in player's; for a druid's kit it is SM.HOT_NAME exactly.
    local hotSlots = st:HotSlots()
    local eatable = false
    local slot, ho = 0, CELL.hots
    for fi = 1, #f.hots do
        local ic = f.hots[fi]
        local h = (not dead) and st:Hot(ti, fi) or nil
        if h then
            slot = slot + 1
            if ic.slot ~= slot then
                ic.slot = slot
                ic:ClearAllPoints()
                ic:SetPoint(ho[1], f, ho[1], (ho[2] + ho[5] * (slot - 1) * ho[4]) * sc, ho[3] * sc)
            end
            local fam = hotSlots.name[fi]
            SetIcon(ic, MD.SpellData.maxRank[fam] or 0, fam)
            Sweep(ic, h.since, h.since + (h.duration or 0), st.t)
            if fi == hotSlots.lifebloom then
                ic.count:SetText(tostring(h.stacks or 1))
                if h.remaining <= 1 then ic:SetBackdropBorderColor(1, 1, 1, 1)
                else ic:SetBackdropBorderColor(0, 0, 0, 1) end
            else
                ic.count:SetText("")
                eatable = true
            end
            ic:Show()
        else
            ic.slot = nil
            ic:Hide()
        end
    end
    -- ...but only for a healer who HAS Swiftmend. The recording says which
    -- spells existed at that pull (v0.9.7); older recordings fall back to what
    -- the player knows now. Drawing a "Swiftmend is ready" indicator for a druid
    -- who never trained it is an instruction to press a key they do not have.
    if eatable and not dead and HasSwiftmend() then
        SetIcon(f.dot, SWIFTMEND, "Swiftmend")
        local cdUntil = st:CooldownUntil(SWIFTMEND)
        if cdUntil then
            -- T90: the length the engine and the state machine kept it by
            -- (the kit entry's `cooldown`, else SM.SPELL_CD), not a literal
            local _, cd = MD.SimModel.CooldownOf(st, SWIFTMEND)
            Sweep(f.dot, cdUntil - (cd or 0), cdUntil, st.t)
            f.dot.tip = f.dot.tip or {}
            f.dot.tip[1] = { l = "Swiftmend", r = string.format("|cffff9966%.1fs|r", cdUntil - st.t) }
            f.dot.tip[2] = { l = "|cff888888a HoT to eat, the cooldown running|r", r = "" }
        else
            f.dot.dim:Hide(); f.dot.spark:Hide()
            f.dot.tip = f.dot.tip or {}
            f.dot.tip[1] = { l = "Swiftmend", r = "|cff99dd99ready|r" }
            f.dot.tip[2] = { l = "|cff888888a Rejuvenation or Regrowth to eat, and it is off cooldown|r", r = "" }
        end
        f.dot:Show()
    else
        f.dot:Hide()
    end

    -- auras: the defensive on the left edge, the debuffs bottom-left
    local auras = st:Auras(ti, f.auraBuf)
    local defShown, nDeb = false, 0
    for _, a in ipairs(auras) do
        if a.buff and not defShown then
            PaintIcon(f.defIcon, a, st.t, true)
            defShown = true
        elseif not a.buff and nDeb < #f.debuffs then
            nDeb = nDeb + 1
            PaintIcon(f.debuffs[nDeb], a, st.t, false)
        end
    end
    if not defShown then f.defIcon:Hide() end
    for i = nDeb + 1, #f.debuffs do f.debuffs[i]:Hide() end

    -- v0.12.2: what is coming, from the recording rather than from the trace --
    -- both columns are watching the same fight and answering the same cast bar.
    do
        local inbound = rp and rp.IncomingAt and rp.IncomingAt(ti, st.t)
        if inbound and not dead then
            SetIcon(f.incoming, inbound.spellID, rp.rec.names and rp.rec.names[inbound.spellID])
            f.incoming:SetBackdropBorderColor(1, 0.2, 0.2, 1)
            if inbound.at then Sweep(f.incoming, inbound.t, inbound.at, st.t) end
            f.incoming.tip = f.incoming.tip or {}
            f.incoming.tip[1] = { l = (rp.rec.names and rp.rec.names[inbound.spellID])
                or ("spell " .. inbound.spellID), r = inbound.at
                and string.format("|cffff9966lands in %.1fs|r", inbound.at - st.t) or "|cff888888no landing|r" }
            f.incoming.tip[2] = { l = "|cff888888cast at this target - Cell's Targeted Spells|r",
                r = inbound.amount and string.format("hit for %d", inbound.amount) or "" }
            f.incoming:Show()
        else
            f.incoming:Hide()
        end
        local threat = rp and rp.ThreatAt and rp.ThreatAt(ti, st.t) or 0
        if threat > 0 and not dead then
            -- Cell's aggro bar: yellow while somebody else holds it, red on you
            if threat >= 2 then f.aggro:SetColorTexture(1, 0.1, 0.1, 1)
            else f.aggro:SetColorTexture(1, 0.8, 0.2, 1) end
            f.aggro:Show()
        else
            f.aggro:Hide()
        end
    end

    if f.pulseUntil > now then
        local left = (f.pulseUntil - now) / PULSE_DMG
        f.pulse:SetColorTexture(CELL.lossFlash[1], CELL.lossFlash[2], CELL.lossFlash[3], (f.pulseAlpha or 0.4) * left)
    else
        f.pulse:SetColorTexture(CELL.lossFlash[1], CELL.lossFlash[2], CELL.lossFlash[3], 0)
    end

    -- the snapshot tick: the latest recorded HP at or before t, fading until
    -- the next one is due
    if isLeft and MD.db.replayTicks and rp.ticks and rp.ticks.hp[ti] then
        local ts, col = rp.ticks.t, rp.ticks.hp[ti]
        local t = st.t
        local j = f.tickIdx or 1
        if j > 1 and ts[j - 1] and ts[j - 1] > t then j = 1 end       -- seeked backwards
        while ts[j + 1] and ts[j + 1] <= t do j = j + 1 end
        f.tickIdx = j
        local v = (ts[j] and ts[j] <= t) and col[j] or nil
        if v and v >= 0 and not dead then
            local age = t - ts[j]
            local alpha = 0.9 - 0.6 * (age / TICK_FADE)
            if alpha < 0.3 then alpha = 0.3 end
            f.tick:SetColorTexture(1, 1, 1, alpha)
            f.tick:ClearAllPoints()
            local x = v * f.bar:GetWidth()
            f.tick:SetPoint("LEFT", f.bar, "LEFT", x, 0)
            f.tickInfo = f.tickInfo or {}
            f.tickInfo.rec, f.tickInfo.at, f.tickInfo.sim = v, ts[j], hp or 0
            f.tickInfo.recon = rp.ticks.reconstructed -- R5: nil on TBC
            f.tickHit:SetSize(8, f.bar:GetHeight())
            f.tickHit:ClearAllPoints()
            f.tickHit:SetPoint("CENTER", f.tick, "CENTER", 0, 0)
            f.tickHit:Show()
        else
            f.tick:SetColorTexture(1, 1, 1, 0)
            f.tickHit:Hide()
        end
    else
        f.tick:SetColorTexture(1, 1, 1, 0)
        f.tickHit:Hide()
    end
end

local function PaintStrip(s, st, pool, now, col)
    local mana = st:Mana() or 0
    s.mana:SetValue(pool > 0 and mana / pool or 0)
    s.manaFS:SetText(string.format("%d", mana + 0.5))
    s.form:SetText(st:Form() == "tree" and "[tree]" or "[caster]")

    local c = st:Casting()
    if c and c.castTime > 0 then
        -- a real cast, filling over its recorded (left) or modelled (right) time
        local label, family = SpellLabel(c.spellID)
        local frac = (st.t - c.startedAt) / c.castTime
        if frac > 1 then frac = 1 end
        if frac < 0 then frac = 0 end
        local fc = FAMILY_COLOR[family] or FAMILY_COLOR.other
        s.cast:SetStatusBarColor(fc[1], fc[2], fc[3])
        s.cast:SetValue(frac)
        local tgt = rp.rec.roster[c.target]
        s.castFS:SetText(label .. (tgt and (" -> " .. Esc(tgt.name)) or "") .. string.format("  %.1fs", c.castTime))
        s.castFS:SetTextColor(1, 1, 1)
    elseif s.lastCast and st.t < s.gcdUntil and st.t >= s.gcdStart then
        -- just after an instant: the GCD sweeping, in grey
        s.cast:SetStatusBarColor(0.3, 0.3, 0.3)
        s.cast:SetValue((st.t - s.gcdStart) / GCD)
        s.castFS:SetText(s.lastCast .. "  instant")
        s.castFS:SetTextColor(1, 1, 1)
    else
        -- idle: the last cast's name stays, dimmed, so "what was I doing" has an answer
        s.cast:SetValue(0)
        s.castFS:SetText(s.lastCast or "")
        s.castFS:SetTextColor(0.55, 0.55, 0.55)
    end
    local w = st:Waiting()
    -- a player is not "waiting": the engine polls for their press (v0.15.0)
    if rp and rp.live then w = nil end
    s.wait:SetText(w and string.format("waiting %.1fs", w) or "")
    s.band:SetColorTexture(0.5, 0.5, 0.5, w and 0.35 or 0)

    -- the rule behind what the bar shows, for the hover (right column: the
    -- plan's reasons; left: none are on record)
    -- v0.12.3: the rule, and the numbers that made it fire. A rule name says
    -- what kind of decision it was; the sentence says why THIS one, here, now.
    local SP2 = MD.SimPlanner
    local reason = st.LastReason and st:LastReason() or nil
    local why = (c and c.why) or (st.lastCast and st.lastCast.why) or 0
    local sentence = reason and SP2.ReasonText(reason, rp and rp.rec and rp.rec.names) or nil
    if why and why > 0 and SP2.RULE_NAMES[why] then
        s.why = { { l = string.format("rule %d: %s", why, SP2.RULE_NAMES[why]), r = "" } }
        if sentence then s.why[#s.why + 1] = { l = "|cff888888" .. sentence .. "|r", r = "" } end
    elseif w then
        s.why = { { l = "waiting", r = "" },
                  { l = "|cff888888" .. (sentence or "nobody under a threshold, or nothing affordable")
                        .. "|r", r = "" } }
    else
        s.why = nil
    end
    -- the left column's label is the classifier's; its sentence is the same idea
    -- from the other side -- why THAT cast, in the recording's numbers
    if col and col.isLeft and rp and rp.casts and st.lastCast and st.lastCast.n then
        local rec2 = rp.casts[st.lastCast.n]
        local text = rec2 and MD.SimPlanner.CastWhy(rec2, rp.rec and rp.rec.names)
        if text then
            s.why = s.why or {}
            s.why[1] = { l = string.format("%s: %s", rec2.label, text), r = "" }
            for i = 2, #s.why do s.why[i] = nil end
        end
    end
    s.reasonText = sentence

    -- spent, floor, deaths -- and (v0.11.14) how much of the healing landed and
    -- how much mana came back, which is what comparing two strategies needs:
    -- cheap is only cheap if it was not thrown away. 2026-09-29: led by USED,
    -- what has left the pool so far -- the number the coach ranks on. The
    -- author read "spent 385" against his "spent 425" as the coach being
    -- cheaper while it had 24 mana left to his 76.
    local spent, lowest, deaths = st:Score()
    local oh = st:Overheal()
    s.score:SetText(string.format("used %s   spent %s   regen %s   overheal %s   lowest %d%%   %s",
        K(st:Used()), K(spent), K(st:Regen()),
        oh and string.format("%d%%", oh * 100 + 0.5) or "-",
        lowest * 100 + 0.5,
        deaths > 0 and string.format("|cffff5555%d dead|r", deaths) or "0 dead"))
end

-- In a gap there is no trace and no casts: health comes from the run's own 2s
-- samples (v0.13.7), keyed by name, and mana from the same beat. Everything that
-- belongs to a fight -- cast bars, HoT icons, labels -- is cleared, because
-- nothing is happening and the last pull's leftovers would be a lie.
local function PaintGap()
    local RTL = MD.RunTimeline
    local hpBy = RTL.HpAt(runTL, runT)
    local mana = RTL.ManaAt(runTL, runT)
    local pool = (runTL.run and runTL.run.pool) or (rp and rp.scenario.pool) or 1
    for _, ti in ipairs(rows) do
        local who = rp and rp.rec.roster[ti]
        for _, col in ipairs({ left, right }) do
            local f = col and col.frames[ti]
            if f then
                local frac = (hpBy and who) and hpBy[who.name] or nil
                if frac then
                    f.bar:SetValue(frac)
                    f.pct:SetText(string.format("%d%%", frac * 100 + 0.5))
                    f.pct:SetTextColor(1, 1, 1)
                    local c = f.classColor
                    f.name:SetTextColor(c[1], c[2], c[3])
                end
                if f.isHealer and mana then f.power:SetValue(mana / (pool > 0 and pool or 1)) end
                f.SetCast("")
                f.SetLabel("")
                f.flashUntil, f.textUntil, f.pulseUntil = 0, 0, 0
                if f.border then f.border[4] = 0 end
                for _, ic in ipairs(f.hots or {}) do ic:Hide() end
                if f.dot then f.dot:Hide() end
                if f.incoming then f.incoming:Hide() end
            end
        end
    end
    local e = RTL.EventAt(runTL, runT, 8)
    local RRK = MD.RunRecorder.K
    local what = "out of combat"
    if e then
        if e.kind == RRK.DRINK then what = "drinking"
        elseif e.kind == RRK.DRINK_END then what = "done drinking"
        elseif e.kind == RRK.DEAD then what = "dead"
        elseif e.kind == RRK.ALIVE then what = "back up"
        elseif e.kind == RRK.ZONE then what = "moving"
        elseif e.kind == RRK.INNERVATE then what = "Innervate"
        elseif e.kind == RRK.POTION then what = "potion" end
    end
    for _, col in ipairs({ left, right }) do
        if col then
            col.strip.cast:SetValue(0)
            col.strip.castFS:SetText(what)
            col.strip.castFS:SetTextColor(0.6, 0.6, 0.6)
            col.strip.wait:SetText("")
            col.strip.band:SetColorTexture(0.5, 0.5, 0.5, 0)
            col.strip.why = nil
        end
    end
end

local function Paint()
    if not rp then return end
    local now = GetTime()
    local pool = rp.scenario.pool or 1
    -- In a gap there is no trace to read: PaintGap owns the frames, and painting
    -- them from the last pull's state afterwards would immediately undo it.
    local inGap = false
    if runMode and runTL then
        local seg = MD.RunTimeline.At(runTL, runT)
        inGap = seg and seg.kind == "gap" or false
    end
    if inGap then
        PaintGap()
    else
        for _, ti in ipairs(rows) do
            PaintFrame(left.frames[ti], left.state, ti, true, now)
            if right and right.state then PaintFrame(right.frames[ti], right.state, ti, false, now) end
        end
        PaintStrip(left.strip, left.state, pool, now, left)
        if right and right.state then PaintStrip(right.strip, right.state, pool, now, right) end
    end
    if runMode and runTL then
        -- the RUN's clock. A clock that resets to 0:00 at every pull is what
        -- made a dungeon feel like thirty-six separate videos.
        local seg = MD.RunTimeline.At(runTL, runT)
        timeFS:SetText(string.format("%s / %s   %s", Clock(runT), Clock(runTL.dur),
            seg and (seg.kind == "pull" and ("pull " .. tostring(seg.k)) or "between pulls") or ""))
        if not scrubber.dragging then
            scrubber.settingValue = true
            scrubber:SetValue(runT)
            scrubber.settingValue = false
        end
        return
    end
    timeFS:SetText(Clock(left.state.t) .. " / " .. Clock(left.state.dur))
    if not scrubber.dragging then
        scrubber.settingValue = true
        scrubber:SetValue(left.state.t)
        scrubber.settingValue = false
    end
end

--------------------------------------------------------------------------------
-- Time control
--------------------------------------------------------------------------------
local function SeekTo(t)
    left.state:Seek(t)
    if right and right.state then right.state:Seek(t) end
    -- a seek clears every short-lived effect: they belong to the crossed events
    for _, ti in ipairs(rows) do
        for _, col in ipairs({ left, right }) do
            local f = col and col.frames[ti]
            if f then
                f.flashUntil, f.textUntil, f.labelFrom, f.labelUntil, f.pulseUntil, f.tickIdx = 0, 0, 0, 0, 0, nil
                f.SetCast(""); f.SetLabel("")
            end
        end
    end
    for _, col in ipairs({ left, right }) do
        if col then
            col.strip.lastCast, col.strip.gcdStart, col.strip.gcdUntil = nil, 0, 0
            -- F2: a seek into a cast bar crosses its CAST_START silently; the
            -- state still knows it, so its success is not taken for an instant
            local c = col.state and col.state:Casting()
            if c and c.castTime > 0 then
                col.strip.barSpell, col.strip.barAt = c.spellID, c.startedAt
            else
                col.strip.barSpell, col.strip.barAt = nil, nil
            end
        end
    end
    Paint()
end

local function SetPlaying(on)
    playing = on
    playBtn:SetText(on and "II" or ">")
    if live then return end
    if on and left.state:AtEnd() then SeekTo(0) end
end

-- Put the run clock somewhere and make the window show it: inside a pull, open
-- that pull (if it is not already) and seek to the offset; in a gap, paint the
-- gap. This is the whole of run mode -- the pull machinery does the rest.
-- T51 (B22): a refused open (combat) leaves the clock where it was and pauses,
-- so nothing retries it; OpenPull reports the refusal once per combat.
local function RunSeek(t, keepPlaying)
    local RTL = MD.RunTimeline
    local was = runT
    runT = math.max(0, math.min(t or 0, runTL.dur))
    local seg, into = RTL.At(runTL, runT)
    if not seg then return end
    if seg.kind == "pull" then
        if pullIdx ~= seg.k then
            local wasPlaying = playing
            if not OpenPull(runIdx .. ":" .. seg.k) then
                runT = was
                SetPlaying(false)
                Paint()
                return
            end
            if (wasPlaying or keepPlaying) then SetPlaying(true) end
        end
        SeekTo(into)
    else
        Paint()
    end
end

--------------------------------------------------------------------------------
-- T72 (P28, review U27, docs/DECISIONS.md): the replay's keyboard, on both
-- lines. Space plays and pauses, Left / Right move 5 s, every other key goes on
-- to the game (practice's propagate pattern). Space and the arrows are jump and
-- turn, and under "Keep them open" (db.ui.combat = "keep"; T80: on TBC too, the
-- manager hides it by default) the replay stays in combat, so the window takes the
-- keyboard only while the pointer is over it and never in combat: it lets go
-- on PLAYER_REGEN_DISABLED, when the pointer leaves and when it hides, and
-- takes it only when the pointer ENTERS out of combat. A failed
-- SetPropagateKeyboardInput (it is only pcall'd) can then swallow keys at most
-- while the player points at the window out of combat. Practice keeps its own
-- rules (LiveControls; it ends in combat).
--------------------------------------------------------------------------------
local function Propagate(on)
    if frame.SetPropagateKeyboardInput then pcall(frame.SetPropagateKeyboardInput, frame, on) end
end

local function InCombat()
    return MD.API.InCombatLockdown() or MD.API.UnitAffectingCombat("player") or false
end

-- The key hint under the theme: the caps light in the accent while the keys
-- are live, grey otherwise.
local function KeyHintText(on, long)
    local cap = on and UI.Hex("accent") or UI.Hex("muted")
    local word = on and UI.Hex("text2") or UI.Hex("muted")
    local s = string.format("%sSpace|r %splay|r   %sLeft  Right|r %s5 s|r", cap, word, cap, word)
    if long then s = s .. "   " .. UI.Hex("muted") .. "keys work while the pointer is over this window|r" end
    return s
end

local function SetKeys(on)
    on = on and true or false
    keysOn = on
    if not frame then return end
    if frame.EnableKeyboard then frame:EnableKeyboard(on) end
    if frame.keyHint then frame.keyHint:SetText(KeyHintText(on, frame.keyHint.long)) end
end

-- Asked on the window's OnEnter / OnLeave and every frame: the pointer moving
-- onto a unit frame or a button fires the window's OnLeave, but it is still
-- over the window, so only the answer to IsMouseOver counts.
local function PointerCheck()
    if not frame or live then return end
    local over = (frame:IsShown() and frame:IsMouseOver()) and true or false
    if over and not pointerIn then
        if not InCombat() then SetKeys(true) end
    elseif not over and keysOn then
        SetKeys(false)
    end
    pointerIn = over
end

-- Move the clock by dt seconds: the run's clock in run mode, the fight's
-- otherwise; playing or paused stays as it was.
local function Nudge(dt)
    if not rp or live or not (left and left.state) then return end
    if runMode and runTL then RunSeek(runT + dt) return end
    local t = left.state.t + dt
    if t < 0 then t = 0 end
    if t > left.state.dur then t = left.state.dur end
    SeekTo(t)
end

local function ReplayKey(_, key)
    if not keysOn or live or not rp then Propagate(true) return end
    if key == "SPACE" then
        Propagate(false)
        SetPlaying(not playing)
        return
    end
    if key == "LEFT" or key == "RIGHT" then
        Propagate(false)
        Nudge(key == "LEFT" and -KEY_SEEK or KEY_SEEK)
        return
    end
    Propagate(true)
end

-- The dimmed column's title: what the search has done so far.
local function PendingTitle(n)
    return string.format("%sSUGGESTED|r  %scoaching...|r %s%d plans|r", UI.Hex("muted"), UI.Hex("accent"),
        UI.Hex("muted"), n or 0)
end
local function CoachProgress()
    if not (right and right.dimmed and right.waiting == "search") then return end
    local h = MD.coachSearch
    local n = (h and h.evals) or 0
    if n ~= coachEvals then
        coachEvals = n
        right.title:SetText(PendingTitle(n))
    end
end

local LiveUpdate    -- defined with the practice functions below
local function OnUpdate(_, elapsed)
    PointerCheck()   -- T72
    CoachProgress()  -- T72
    if live then LiveUpdate(elapsed) return end
    if not rp or not playing then return end
    local dt = elapsed * speed
    local cap = DT_STEP_MAX * speed
    if dt > cap then dt = cap end

    if runMode and runTL then
        -- one clock for the whole dungeon. Crossing out of a pull no longer
        -- stops: the gap is played too, which is where the drinking happens.
        local was = runT
        runT = runT + dt
        if runT >= runTL.dur then
            runT = runTL.dur
            SetPlaying(false)
            Paint()
            return
        end
        local seg, into = MD.RunTimeline.At(runTL, runT)
        if seg.kind == "pull" then
            if pullIdx ~= seg.k then
                -- T51 (B22): refused (combat): stay before the boundary, paused,
                -- instead of asking again on every frame
                if not OpenPull(runIdx .. ":" .. seg.k) then
                    runT = was
                    SetPlaying(false)
                    Paint()
                    return
                end
                playing = true
                SeekTo(into)
            else
                left.state:Advance(dt)
                if right and right.state then right.state:Advance(dt) end
            end
            Paint()
        else
            Paint()
        end
        return
    end

    left.state:Advance(dt)
    if right and right.state then right.state:Advance(dt) end
    Paint()
    if left.state:AtEnd() then
        -- inside a run, the next pull follows on its own: pull by pull IS the
        -- way a dungeon is reviewed, and stopping at every boundary to click
        -- makes it a chore. db.replayNextPull turns it off.
        local nextK = pullIdx and (pullIdx + 1)
        if curRun and runIdx and nextK and curRun.pulls[nextK]
           and MD.db.replayNextPull ~= false then
            SetPlaying(false)
            if OpenPull(runIdx .. ":" .. nextK) then SetPlaying(true) end
            return
        end
        SetPlaying(false)
    end
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------
-- T34 (docs/SPEC-forever-ui.md 6.3, 6.5): one ESC on the window. A practice
-- being played pauses on the first press and stays; a second, while paused,
-- ends it and opens its replay in place (so the entry stays, for the replay).
-- A replay closes -- the window manager then gives the main window back.
local function EscPress(f)
    if live then
        if playing then
            SetPlaying(false)
            live:SetPaused(true)
            return true
        end
        MD:StopPractice(true)
        if f:IsShown() then return true end
        return nil
    end
    f:Hide()
end

local function Build()
    if frame then return end
    -- T34: the window manager places it (not user-placed) and the header
    -- carries the "< SpellTuner" back button. T80 (C1): on both lines -- TBC's
    -- HIGH strata and UISpecialFrames entry are gone with the manager there.
    local W = MD.Win
    frame = UI.CreateMovableFrame("SpellTuner: Replay", "SpellTunerReplayWindow", 2 * COL_W + 3 * GUTTER, 300,
        nil, nil, true, { back = "< SpellTuner" })
    frame:SetScript("OnUpdate", OnUpdate)
    frame:SetScript("OnHide", function()
        playing = false
        if live and MD.StopPractice then MD:StopPractice(false) end
        SetKeys(false) -- T72: a hidden window holds no keys
        pointerIn = false
    end)
    -- T72 (P28): the replay's keys, live only under the pointer (PointerCheck)
    frame:SetScript("OnKeyDown", ReplayKey)
    frame:HookScript("OnEnter", PointerCheck)
    frame:HookScript("OnLeave", PointerCheck)
    -- T34 (6.2, 6.3): a takeover -- DIALOG / 10, on the ESC stack, placed by
    -- the manager (db.ui.win.replay once dragged); registered after the
    -- OnHide script above, since Register hooks it. A practice being played
    -- is not hidden by combat here: the guard below ends it; while one plays,
    -- a command that wants the main window is refused with `busy`.
    W:Register(frame, { key = "replay", role = "takeover", onEsc = EscPress,
                        combat = function() if live then return "stay" end return nil end,
                        busy = "Practice is running: ESC pauses, ESC again ends it." })
    -- the place kept before the manager (TBC's until T80 / C1), adopted once
    if MD.db.replayPos then
        W:Adopt("replay", MD.db.replayPos) -- once: the old key goes
        MD.db.replayPos = nil
    end

    if UI.THEMED then
        -- T72 (P28, review U23, mockup M3): the status band. The fight on the
        -- left (headerFS: #n, where, when, how long, how many), the verdict on
        -- the right in good / bad, and Coach anyway where "/md replay N force"
        -- was quoted. The reconstruction is one word beside the fight, its
        -- explanation that word's hover. Every piece is anchored by PlaceBand
        -- on each open, which also bounds the fight's width by the verdict's.
        local band = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        band:SetHeight(BAND_H)
        UI.StylizeFrame(band, UI.PALETTE.pane or { 0.11, 0.11, 0.11, 1 }, UI.PALETTE.border or { 0, 0, 0, 1 })
        frame.band = band

        headerFS = band:CreateFontString(nil, "OVERLAY", UI.FONT)
        headerFS:SetJustifyH("LEFT")
        headerFS:SetWordWrap(false)

        band.word = band:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
        UI.Tint(band.word, "text", "muted")
        band.word:Hide()
        band.wordLine = band:CreateTexture(nil, "ARTWORK")   -- the word's dotted underline, drawn solid
        band.wordLine:SetPoint("TOPLEFT", band.word, "BOTTOMLEFT", 0, -1)
        band.wordLine:SetPoint("TOPRIGHT", band.word, "BOTTOMRIGHT", 0, -1)
        band.wordLine:SetHeight(1)
        do
            local r, g, b = UI.RGB("muted")
            band.wordLine:SetColorTexture(r, g, b, 0.6)
        end
        band.wordLine:Hide()
        band.wordHit = CreateFrame("Frame", nil, band)
        band.wordHit:SetAllPoints(band.word)
        band.wordHit:EnableMouse(true)
        band.wordHit:SetScript("OnEnter", function(self)
            if not (MD.Tip and band.wordTip) then return end
            local lines = { { l = band.wordTip[1] or "", r = "" } }
            for i = 2, #band.wordTip do
                lines[#lines + 1] = { l = UI.Hex("muted") .. band.wordTip[i] .. "|r", r = "" }
            end
            MD.Tip:Show(self, "ANCHOR_BOTTOM", lines)
        end)
        band.wordHit:SetScript("OnLeave", function() if MD.Tip then MD.Tip:Hide() end end)
        band.wordHit:Hide()

        band.coach = UI.CreateButton(band, "Coach anyway", "accent", { COACH_W, 20 }, false, false, UI.FONT_SMALL, nil,
            "Coach anyway", "This fight does not replay within the gates, so a plan",
            "found on it may be advice the engine got wrong.")
        band.coach:SetScript("OnClick", function() if MD.Replay then MD.Replay.CoachAnyway() end end)
        band.coach:Hide()

        band.verdict = band:CreateFontString(nil, "OVERLAY", UI.FONT)
        band.verdict:SetJustifyH("RIGHT")
        band.verdict:SetWordWrap(false)
        band.verdict:SetText("")
        band.verdictHit = CreateFrame("Frame", nil, band)
        band.verdictHit:SetAllPoints(band.verdict)
        band.verdictHit:EnableMouse(true)
        band.verdictHit:SetScript("OnEnter", function(self)
            if MD.Tip and band.verdictTip then MD.Tip:Show(self, "ANCHOR_BOTTOM", band.verdictTip) end
        end)
        band.verdictHit:SetScript("OnLeave", function() if MD.Tip then MD.Tip:Hide() end end)

        frame.reconFS = band.word
    else
        headerFS = frame:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
        headerFS:SetPoint("TOPLEFT", frame, "TOPLEFT", GUTTER, -6)
        headerFS:SetJustifyH("LEFT")
        headerFS:SetWidth(2 * COL_W + GUTTER)

        -- T16a: a v3 recording (Forever) never carried a real health log -- every
        -- percentage and danger line drawn from it is T13d's reconstruction, and a
        -- party member's max may itself be a stand-in (Planner ruling 1). One grey
        -- line says so; hidden on a v2/TBC recording, which has neither question.
        frame.reconFS = frame:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
        frame.reconFS:SetPoint("TOPLEFT", headerFS, "BOTTOMLEFT", 0, -2)
        frame.reconFS:SetJustifyH("LEFT")
        frame.reconFS:SetWidth(2 * COL_W + GUTTER)
        frame.reconFS:SetTextColor(0.6, 0.6, 0.6)
        frame.reconFS:Hide()
    end

    -- The strategies the last search produced for this recording. One dropdown
    -- rather than four buttons: the names are long and ran off the window
    -- (v0.11.11). Switching does NOT search again -- the plans are in hand and
    -- this redraws the suggested column from the chosen one.
    stratDrop = UI.CreateDropdown(frame, CHOOSER_W, 16, function(id)
        local SP = MD.SimPlanner
        if not (rp and rp.rec) then return end
        -- v0.13.7: two kinds of entry share this list. A search objective picks
        -- one of the plans the search already found; a STRATEGY_SET entry is a
        -- whole planner (the rules, or the solver in one of its configurations)
        -- and is built here on demand -- it needs no search at all, which is why
        -- the chooser now has something to offer before Coach has ever run.
        local entry = SP.Strategy and SP.Strategy(id)
        if entry then
            local kit = MD.RankMath:SpellKit({ live = true })
            local sc = MD.SimModel.ScenarioFromRecording(rp.rec, kit)
            local plan = SP.MakeStrategy(entry, SP.BindsFromRecording and
                SP.BindsFromRecording(rp.rec) or SP.MaxRankBinds(), kit,
                { scenario = sc, seed = rp.rec.id or 1,
                  encounter = rp.rec.encounter, zone = rp.rec.zone,
                  recs = MD.cdb and MD.cdb.recordings, excludeID = rp.rec.id })
            if not plan then return end
            SP.plans[rp.rec.id] = plan
        else
            local w = SP.strategies[rp.rec.id]
            w = w and w[id]
            if not w then return end
            SP.plans[rp.rec.id] = w.plan
        end
        SP.strategyPick[rp.rec.id] = id
        MD:RebuildSuggested()
    end)
    stratDrop:Hide()

    runStrip = CreateFrame("Frame", nil, frame)
    runStrip:SetPoint("TOPLEFT", frame, "TOPLEFT", GUTTER, UI.THEMED and -(BAND_H + 2) or -(HEADER_H - 2))
    runStrip:SetSize(2 * COL_W + GUTTER, 18)
    runStrip.pulls, runStrip.drinks, runStrip.marks = {}, {}, {}
    runStrip.label = frame:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    runStrip.label:SetPoint("TOPLEFT", runStrip, "BOTTOMLEFT", 0, -1)
    runStrip.label:SetJustifyH("LEFT")
    runStrip:Hide()

    left = CreateColumn(GUTTER, "ACTUAL")
    right = CreateColumn(2 * GUTTER + COL_W, "SUGGESTED")
    left.isLeft = true

    -- scrubber row, anchored to the bottom
    -- T72: the promise the keyboard now keeps, and its two guards
    playBtn = UI.CreateButton(frame, ">", "accent-hover", { 24, 18 }, false, false, nil, nil,
        "Play / pause", "Space plays and pauses, Left / Right move 5 s, while",
        "the pointer is over this window and you are out of combat.")
    playBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", GUTTER, 30)
    playBtn:SetSize(34, 22)
    playBtn:SetScript("OnClick", function() SetPlaying(not playing) end)

    local speeds, prev = {}, playBtn
    for _, sp in ipairs(SPEEDS) do
        local text = sp >= 1 and (sp .. "x") or ("1/" .. math.floor(1 / sp + 0.5) .. "x")
        local b = UI.CreateButton(frame, text, "accent-hover", { 40, 22 }, false, false, UI.FONT_SMALL)
        b.id = sp
        b:SetPoint("LEFT", prev, "RIGHT", 3, 0)
        speeds[#speeds + 1] = b
        prev = b
    end
    speedButtons = speeds
    speedHighlight = UI.CreateButtonGroup(speeds, function(id)
        speed = id
        MD.db.replaySpeed = id
    end)

    -- v0.15.0: ends a practice fight and opens it as a replay
    endBtn = UI.CreateButton(frame, "End", "red-hover", { 48, 22 }, false, false, UI.FONT_SMALL, nil,
        "End the practice", "What you played so far is kept, and opens as a replay.")
    endBtn:SetPoint("LEFT", prev, "RIGHT", 12, 0)
    endBtn:SetScript("OnClick", function() if MD.StopPractice then MD:StopPractice(true) end end)
    endBtn:Hide()

    timeFS = frame:CreateFontString(nil, "OVERLAY", UI.FONT)
    timeFS:SetPoint("LEFT", prev, "RIGHT", 12, 0)
    timeFS:SetWidth(130)
    timeFS:SetJustifyH("LEFT")

    -- the scrubber on its own row above the buttons, full width
    scrubber = CreateFrame("Slider", nil, frame, "BackdropTemplate")
    scrubber:SetOrientation("HORIZONTAL")
    scrubber:SetSize(2 * COL_W + GUTTER, 14)
    scrubber:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", GUTTER, 62)
    UI.StylizeFrame(scrubber, { 0.115, 0.115, 0.115, 1 })
    local thumb = scrubber:CreateTexture(nil, "ARTWORK")
    UI.Tint(thumb, "texture", "accent", 1) -- T107
    thumb:SetSize(6, 18)
    scrubber:SetThumbTexture(thumb)
    scrubber:SetMinMaxValues(0, 1)
    scrubber:SetValueStep(0.05)
    scrubber:SetObeyStepOnDrag(true)
    scrubber:SetScript("OnValueChanged", function(self, v, user)
        -- in run mode the scrubber IS the run's timeline: dragging it moves
        -- through the gaps as well as the fights
        if runMode and runTL and not self.settingValue and (user or self.dragging) then
            RunSeek(v)
            return
        end
        if self.settingValue or not rp then return end
        SeekTo(v)
    end)
    scrubber:SetScript("OnMouseDown", function(self) self.dragging = true end)
    scrubber:SetScript("OnMouseUp", function(self) self.dragging = false end)
    scrubber.markers = {}

    local ticksCB = UI.CreateCheckButton(frame, "ticks", function(checked)
        MD.db.replayTicks = checked
        Paint()
    end, TICKS_TIPS[1], TICKS_TIPS[2], TICKS_TIPS[3])
    -- anchored from the right edge, label included, so it cannot fall off a
    -- one-column window (it did, twice)
    local labelW = (ticksCB.label and ticksCB.label.GetStringWidth and ticksCB.label:GetStringWidth()) or 32
    ticksCB:SetPoint("RIGHT", frame, "RIGHT", -(GUTTER + labelW + 6), 0)
    ticksCB:SetPoint("BOTTOM", playBtn, "BOTTOM", 0, 4)
    ticksCB:SetChecked(MD.db.replayTicks ~= false)
    frame.ticksCB = ticksCB

    -- the hint on its own line at the very bottom, never under a control
    frame.hint = frame:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    frame.hint:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", GUTTER, 9)
    frame.hint:SetTextColor(0.5, 0.5, 0.5)
    frame.hint:SetJustifyH("LEFT")
    frame.hint:SetWordWrap(false)

    if UI.THEMED then
        -- T72 (mockup M3): which keys work, lit while they do; the footer's
        -- right end, so it never crowds the controls row of a one-column window
        frame.keyHint = frame:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
        frame.keyHint:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -GUTTER, 9)
        frame.keyHint:SetJustifyH("RIGHT")
        frame.keyHint:SetWordWrap(false)
        frame.keyHint:SetText(KeyHintText(false, false))
    end
end

-- Markers along the scrubber: deaths red, big hits orange, the left column's
-- casts as faint grey ticks.
local function PlaceMarkers()
    for _, m in ipairs(scrubber.markers) do m:Hide() end
    local n = 0
    local function Mark(t, r, g, b, a, h)
        n = n + 1
        local m = scrubber.markers[n]
        if not m then
            m = scrubber:CreateTexture(nil, "OVERLAY")
            scrubber.markers[n] = m
        end
        m:SetSize(1, h or 10)
        m:SetColorTexture(r, g, b, a)
        m:ClearAllPoints()
        local dur = left.state.dur
        m:SetPoint("LEFT", scrubber, "LEFT", dur > 0 and (t / dur) * scrubber:GetWidth() or 0, 0)
        m:Show()
    end
    local TK, K = MD.SimModel.TK, MD.SimModel.K
    local L = rp.left.trace
    local n = 0
    for i = 1, L.nEv do
        if L.ev.kind[i] == TK.CAST then
            n = n + 1
            local cl = rp.casts and rp.casts[n]
            local lc = cl and LABEL_COLOR[cl.label]
            if lc and cl.label ~= "fine" and cl.label ~= "unclassified" then
                Mark(L.ev.t[i], lc[1], lc[2], lc[3], 0.9, 8)
            else
                Mark(L.ev.t[i], 1, 1, 1, 0.25, 6)
            end
        end
    end
    local big = MD:Setting("simBigHit")
    local sev = rp.scenario.ev
    if sev then
        for i = 1, #sev.t do
            if sev.kind[i] == K.DMG then
                local tg = rp.scenario.targets[sev.tgt[i]]
                if tg and tg.maxHP > 0 and (sev.amt[i] or 0) / tg.maxHP >= big then
                    Mark(sev.t[i], 1, 0.6, 0.2, 0.9, 10)
                end
            end
        end
    end
    for i = 1, L.nEv do
        if L.ev.kind[i] == TK.DEATH then Mark(L.ev.t[i], 1, 0.2, 0.2, 1, 14) end
    end
end

--------------------------------------------------------------------------------
-- The run strip (docs/SPEC-v0.9.md 6): the whole dungeon on one line -- each
-- pull a block as wide as it was long, the drinks between them in blue, deaths
-- as red marks, and the gaps left as gaps. The pull being played is bright.
--
-- It is the map a run needs and a scrubber cannot be: half an hour at 1x is not
-- review, so there is no "play the run through". Click a block and the window
-- re-opens on that pull, keeping the same clock controls.
--------------------------------------------------------------------------------
local function RunBlock(kind, i)
    local pool = runStrip[kind]
    local b = pool[i]
    if not b then
        b = CreateFrame("Button", nil, runStrip)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetAllPoints()
        pool[i] = b
    end
    b:Show()
    return b
end

local function PaintRunStrip(width)
    if not runStrip then return end
    for _, kind in ipairs({ "pulls", "drinks", "marks" }) do
        for _, b in ipairs(runStrip[kind]) do b:Hide() end
    end
    if not curRun then runStrip:Hide(); return end
    runStrip:Show()
    runStrip:SetWidth(width)

    local wall = (curRun.stats and curRun.stats.wall) or 0
    if wall <= 0 then runStrip:Hide(); return end
    local W = width
    local function X(t) return math.max(0, math.min(W, (t / wall) * W)) end

    local ar, ag, ab = UI.GetAccentColorRGB()
    for k, rec in ipairs(curRun.pulls or {}) do
        local x0, x1 = X(rec.runT0 or 0), X((rec.runT0 or 0) + (rec.dur or 0))
        local b = RunBlock("pulls", k)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", runStrip, "TOPLEFT", x0, -2)
        b:SetSize(math.max(2, x1 - x0), 14)
        local on = (k == pullIdx)
        if rec.short then
            b.tex:SetColorTexture(0.45, 0.45, 0.45, on and 1 or 0.55)
        else
            b.tex:SetColorTexture(ar, ag, ab, on and 1 or 0.5)
        end
        b.pull = k
        b:SetScript("OnClick", function(self)
            -- T51: in run mode the click moves the RUN's clock to the pull, so
            -- the clock, the scrubber and the open pull agree
            if runMode and runTL then
                local seg = MD.RunTimeline.PullSeg(runTL, self.pull)
                if seg then RunSeek(seg.from) return end
            end
            if runIdx then OpenPull(runIdx .. ":" .. self.pull) end
        end)
        b:SetScript("OnEnter", function(self)
            if not MD.Tip then return end
            MD.Tip:Show(self, "ANCHOR_BOTTOM", {
                { l = string.format("pull %d%s", self.pull, rec.short and " (short)" or ""),
                  r = Clock(rec.dur or 0) },
                { l = "into the run", r = Clock(rec.runT0 or 0) },
                { l = rec.zone or "", r = string.format("%d casts, %s mana", rec.ownCasts or 0, K(rec.spent or 0)) },
                { l = "|cff888888click to play this pull|r", r = "" },
            })
        end)
        b:SetScript("OnLeave", function() if MD.Tip then MD.Tip:Hide() end end)
    end

    -- drinks and deaths from the run's own timeline
    local RR = MD.RunRecorder
    local ev = curRun.ev or {}
    local nD, nM, openDrink = 0, 0, nil
    for i = 1, #(ev.t or {}) do
        local k = ev.kind[i]
        if k == RR.K.DRINK then
            openDrink = ev.t[i]
        elseif k == RR.K.DRINK_END and openDrink then
            nD = nD + 1
            local b = RunBlock("drinks", nD)
            local x0, x1 = X(openDrink), X(ev.t[i])
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", runStrip, "TOPLEFT", x0, -2)
            b:SetSize(math.max(2, x1 - x0), 14)
            b.tex:SetColorTexture(0.35, 0.6, 1, 0.8)
            b:EnableMouse(false)
            openDrink = nil
        elseif k == RR.K.DEAD then
            nM = nM + 1
            local b = RunBlock("marks", nM)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", runStrip, "TOPLEFT", X(ev.t[i]) - 1, 0)
            b:SetSize(2, 18)
            b.tex:SetColorTexture(1, 0.2, 0.2, 1)
            b:EnableMouse(false)
        end
    end

    local st = curRun.stats or {}
    runStrip.label:SetText(string.format(Hi() .. "%s|r  %s, %d pull(s)%s%s", curRun.name or "run",
        Clock(st.wall or 0), st.pulls or 0,
        (st.drinks or 0) > 0 and string.format(", %d drink(s)", st.drinks) or "",
        (st.deaths or 0) > 0 and string.format(", %d death(s)", st.deaths) or ""))
end

--------------------------------------------------------------------------------
-- Opening a fight
--------------------------------------------------------------------------------
-- T72 (P28, review U21): the suggested column while its plan is searched for.
-- Laid out with the rest and dimmed, so the window has its final size from the
-- moment it opens; painted blank (the plan has not happened yet).
-- T72: does the band offer Coach anyway? A fight that does not replay, with no
-- plan and no search for it, that the coach can take (MD:CoachOnOpen's druid).
-- T99 (docs/SPEC-next.md 4.4): "druid" is the class profile's coach capability.
local function CoachOffered()
    if not (UI.THEMED and rp and rp.rec and not rp.live and not rp.right) then return false end
    local v = rp.validation
    if not v or v.ok then return false end
    if MD.replayCoaching ~= nil and MD.replayCoaching == rp.rec.id then return false end
    return MD.ClassProfile:Can("coach") and MD.SimPlanner ~= nil or false
end

-- A font string's text width, whatever width it was last given.
local function TextW(fs)
    local w = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()
    if type(w) ~= "number" then w = fs:GetStringWidth() end
    return type(w) == "number" and w or 0
end

-- T72 (review of P28): the band's anchors, and the fight's width. The fight is
-- anchored left and the verdict right on one line, so the fight (and the
-- reconstruction word after it) is given the room left of the verdict -- left
-- of Coach anyway, or of the band's end, with nothing to say -- less
-- TITLE_GAP, and is truncated there rather than drawn under the verdict.
local function PlaceBand()
    local band = frame and frame.band
    if not band then return end
    band:ClearAllPoints()
    band:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    band:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    headerFS:ClearAllPoints()
    headerFS:SetPoint("LEFT", band, "LEFT", GUTTER, 0)
    band.word:ClearAllPoints()
    band.word:SetPoint("LEFT", headerFS, "RIGHT", TITLE_GAP, 0)
    band.coach:ClearAllPoints()
    band.coach:SetPoint("RIGHT", band, "RIGHT", -GUTTER, 0)
    band.verdict:ClearAllPoints()
    local stop = frame:GetWidth() - GUTTER          -- where the verdict ends
    if band.coach:IsShown() then
        band.verdict:SetPoint("RIGHT", band.coach, "LEFT", -10, 0)
        stop = stop - COACH_W - 10
    else
        band.verdict:SetPoint("RIGHT", band, "RIGHT", -GUTTER, 0)
    end
    local vw = TextW(band.verdict)
    local room = stop - (vw > 0 and (vw + TITLE_GAP) or 0) - GUTTER
    if band.word:IsShown() then room = room - TITLE_GAP - TextW(band.word) end
    -- never 0: a font string given no width draws its whole text
    headerFS:SetWidth(math.max(GUTTER, math.min(TextW(headerFS) + 1, room)))
end

local function Dim(col, on)
    local a = on and DIM_ALPHA or 1
    for _, f in pairs(col.frames) do f:SetAlpha(a) end
    for _, k in ipairs({ "mana", "cast", "form", "wait", "score" }) do col.strip[k]:SetAlpha(a) end
    col.dimmed = on
end

local function BlankColumn(col)
    for _, ti in ipairs(rows) do
        local f = col.frames[ti]
        if f then
            f.bar:SetValue(1)
            f.pct:SetText("")
            local c = f.classColor
            f.name:SetTextColor(c[1], c[2], c[3])
            for _, ic in ipairs(f.hots) do ic.slot = nil; ic:Hide() end
            for _, ic in ipairs(f.debuffs) do ic:Hide() end
            f.dot:Hide(); f.defIcon:Hide(); f.incoming:Hide(); f.aggro:Hide()
            f.statusBG:Hide(); f.cast:Hide(); f.label:Hide()
            f.tick:SetColorTexture(1, 1, 1, 0)
            f.tickHit:Hide()
        end
    end
    local s = col.strip
    local pool = rp.scenario.pool or 0
    s.mana:SetValue(1)
    s.manaFS:SetText(string.format("%d", pool + 0.5))
    s.form:SetText("")
    s.cast:SetValue(0)
    s.castFS:SetText("no plan yet")
    s.castFS:SetTextColor(0.55, 0.55, 0.55)
    s.wait:SetText("")
    s.band:SetColorTexture(0.5, 0.5, 0.5, 0)
    s.why = nil
    s.score:SetText("used -   spent -   regen -   overheal -   lowest -")
end

local function Layout()
    -- roster order, as the author's layout has sortByRole off; columns of
    -- unitsPerColumn, a raid's subgroup and main tanks filling the next ones
    rows = {}
    for _, ti in ipairs(rp.rec.tracked or {}) do rows[#rows + 1] = ti end
    table.sort(rows)
    local roster = rp.rec.roster
    local healerIdx = nil
    local myName = MD.API.UnitName("player")
    for i, r in ipairs(roster) do
        if (r.guid and r.guid == MD.player.guid) or (not r.guid and myName and r.name == myName) then healerIdx = i end
    end

    local n = #rows
    local sc, nCols, stretch = ScaleFor(n)
    local perCol = (sc == 1) and CELL.unitsPerColumn or math.max(1, math.ceil(n / nCols))
    local spX, spY = CELL.spacingX * sc, CELL.spacingY * sc
    local H = CELL.size[2] * sc
    local W = CELL.size[1] * sc
    local pitch = COL_W
    if stretch then
        W = (pitch - (nCols - 1) * spX) / nCols     -- as wide as the column allows
    else
        pitch = math.max(COL_W, nCols * W + (nCols - 1) * spX)
    end
    local gridH = math.min(n, perCol) * H + (math.min(n, perCol) - 1) * spY
    local overhang = CELL.hots[3] * sc + 4        -- the HoT slot sits above the button's top edge
    -- T72 (P28, review U21): under the theme a fight the auto-coach is
    -- searching gets both columns now, the right one dimmed, so the window
    -- does not grow and re-centre when the plan arrives
    local searching = UI.THEMED and not rp.right and not rp.live and rp.rec ~= nil
        and MD.replayCoaching ~= nil and MD.replayCoaching == rp.rec.id or false
    -- T72 (review of P28): so is a fight the band offers Coach anyway for --
    -- mockup M3 draws that band at the two-column width, where the verdict and
    -- its button have room, and the window keeps its size when it is clicked
    local offered = not searching and CoachOffered() or false
    local pending = searching or offered
    right.waiting = searching and "search" or (offered and "offer") or nil
    local hasRight = rp.right ~= nil or pending
    local width = hasRight and (2 * pitch + 3 * GUTTER) or (pitch + 2 * GUTTER)
    -- the run strip pushes everything below it down, and only exists when this
    -- pull belongs to a run
    topH = HeadH() + (curRun and RUNSTRIP_H or 0)
    local height = topH + STRIP_H + overhang + gridH + SCRUB_H + 12
    frame:SetSize(width, height)
    if UI.THEMED then
        -- the footer shares its row with the key hint (T72)
        frame.hint:SetWidth(rp.live and (width - 2 * GUTTER) or math.floor((width - 2 * GUTTER) / 2))
        if frame.keyHint then
            frame.keyHint.long = hasRight
            frame.keyHint:SetText(KeyHintText(keysOn, hasRight))
        end
    else
        frame.hint:SetWidth(width - 2 * GUTTER)
    end
    left.title:ClearAllPoints()
    left.title:SetPoint("TOPLEFT", frame, "TOPLEFT", left.x, -(topH + 6))
    left.strip.mana:ClearAllPoints()
    left.strip.mana:SetPoint("TOPLEFT", frame, "TOPLEFT", left.x, -(topH + 30))
    right.x = 2 * GUTTER + pitch
    right.title:ClearAllPoints()
    right.title:SetPoint("TOPLEFT", frame, "TOPLEFT", right.x, -(topH + 6))
    if UI.THEMED then
        -- T72 (review of P28): the strategy chooser shares this line at the
        -- column's right end; the title stops short of it
        right.title:SetJustifyH("LEFT")
        right.title:SetWordWrap(false)
        right.title:SetWidth(pitch - CHOOSER_W - TITLE_GAP)
    end
    right.strip.mana:ClearAllPoints()
    right.strip.mana:SetPoint("TOPLEFT", frame, "TOPLEFT", right.x, -(topH + 30))
    PaintRunStrip(width - 2 * GUTTER)
    Shown(right.title, hasRight)
    for _, k in ipairs({ "mana", "cast", "form", "wait", "score" }) do Shown(right.strip[k], hasRight) end
    scrubber:SetWidth(width - 2 * GUTTER)

    for _, col in ipairs({ left, right }) do
        for _, f in pairs(col.frames) do f:Hide() end
    end
    local y0 = -(topH + STRIP_H + overhang)
    for k, ti in ipairs(rows) do
        local cI, rI = math.floor((k - 1) / perCol), (k - 1) % perCol
        local dx, y = cI * (W + spX), y0 - rI * (H + spY)
        for ci, col in ipairs({ left, right }) do
            if ci == 1 or hasRight then
                local f = col.frames[ti]
                if not f then
                    f = CreateUnitFrame(frame, col.x + dx, y)
                    col.frames[ti] = f
                else
                    f:ClearAllPoints()
                    f:SetPoint("TOPLEFT", frame, "TOPLEFT", col.x + dx, y)
                end
                f.Resize(W, H, sc)
                local r = roster[ti] or {}
                f.classColor = ClassColor(r.class)
                f.isHealer = (ti == healerIdx)
                local rc = ROLE_COORD[r.role]
                if rc then f.role:SetTexCoord(rc[1], rc[2], rc[3], rc[4]); f.role:Show() else f.role:Hide() end
                f.name:SetText(r.name and Esc(r.name) or ("#" .. ti))
                local c = f.classColor
                f.bar:SetStatusBarColor(c[1], c[2], c[3])
                f.bar.bg:SetColorTexture(c[1] * CELL.lossFactor, c[2] * CELL.lossFactor, c[3] * CELL.lossFactor, 1)
                f.power:SetValue(f.isHealer and 1 or 0)
                f.flashUntil, f.textUntil, f.labelFrom, f.labelUntil, f.pulseUntil, f.tickIdx = 0, 0, 0, 0, 0, nil
                f.SetCast(""); f.SetLabel("")
                f:SetBackdropBorderColor(0, 0, 0, 1)
                f.defIcon.spellID, f.dot.spellID = nil, nil
                for _, ic in ipairs(f.debuffs) do ic.spellID = nil end
                for _, ic in ipairs(f.hots) do ic.spellID = nil end
                if live and ci == 1 then
                    local unit = ti
                    f.onPress = function(button)
                        local key = MD.Practice.MOUSE[button]
                        if key then MD:PracticePress(key, unit) end
                    end
                    f.onHover = function(on)
                        if on then hoverTi = unit elseif hoverTi == unit then hoverTi = nil end
                    end
                else
                    f.onPress, f.onHover = nil, nil
                end
                f:Show()
            end
        end
    end
    if UI.THEMED then
        Dim(right, pending)
        coachEvals = nil
        if pending then BlankColumn(right) end
    end
end

-- Redraw the suggested column from whatever plan is now cached for this
-- recording, keeping the clock where it is. Switching strategy is a redraw, not
-- a search: the window never searches (SPEC-v0.8 2.5).
-- v0.13.9: coach on open. A replay with no suggested column is the question
-- half answered, and making the author run three commands to get the other half
-- was friction with nothing behind it. The search is frame-sliced and its result
-- is cached per recording, so this happens once per fight and never in combat.
--
-- A fight that does not replay is still NOT coached silently: the window says
-- which gate failed and names the force spelling. That rule (v0.9.6) is about
-- not handing out advice the engine got wrong, and it survives.
function MD:CoachOnOpen(rec, force, validation)
    local SP = MD.SimPlanner
    if not (rec and SP and MD.ClassProfile:Can("coach")) then return end
    -- T72: the band's Coach anyway is a request, not the automatic coach
    if MD.db and MD.db.replayAutoCoach == false and not askedToCoach then return end
    if SP.plans[rec.id] or MD.coachSearch or MD.replayCoaching then return end
    if not force and not (validation and validation.ok) then return end
    MD.replayCoaching = rec.id
    MD:Print("replay: no plan for this fight yet - coaching it now.")
    MD.coachSearch = SP.CoachAsync(rec, { n = openSpec, force = force, quiet = true },
        function(lines)
            MD.coachSearch = nil
            MD.replayCoaching = nil
            -- one line, not the whole card: the window is the answer here, and
            -- /md coach N still prints the card in full when it is wanted
            local p = SP.plans[rec.id]
            if p then
                MD:Print(string.format("replay: coached - %s. The suggested column is drawn.",
                    p.name or "plan"))
            elseif lines and lines[1] then
                MD:Print(lines[1])
            end
            -- only redraw if the window is still on the fight we coached
            if frame and frame:IsShown() and rp and rp.rec and rp.rec.id == rec.id then
                MD:RebuildSuggested()
            end
        end)
end

function MD:RebuildSuggested()
    if not (rp and openSpec) then return end
    local at = left.state and left.state.t or 0
    local wasPlaying = playing
    if not OpenPull(openSpec .. (openForce and " force" or "")) then return end
    if left.state and at > 0 then SeekTo(at) end
    if wasPlaying then SetPlaying(true) end
end

-- T51 (B22): MD:OpenReplay answers whether it opened. A refusal in combat is
-- printed every time it is asked for by hand; the window's own re-opens (a run
-- crossing into its next pull, a drag, a strip click, the suggested column
-- filling in) go through OpenPull and say it once per combat.
function MD:OpenReplay(n)
    local quiet = openingQuietly
    openingQuietly = false
    local FR, SP = MD.FightRecorder, MD.SimPlanner
    if live then MD:StopPractice(false) end
    if not (FR and SP and MD.ReplayTrace) then MD:Print("replay: not loaded.") return false end
    if MD.API.InCombatLockdown() or MD.API.UnitAffectingCombat("player") then
        if not (quiet and refusedInCombat) then
            MD:Print("replay: not in combat - it is a review tool.")
        end
        refusedInCombat = true
        return false
    end
    refusedInCombat = false
    -- "3" is a single fight, "2:7" the seventh pull of run 2 (v0.9.2); "run 2"
    -- opens the first pull of run 2 with its strip (v0.9.4); a trailing "force"
    -- draws the suggested column on a fight the gates rejected (v0.9.6)
    local spec = tostring(n or 1)
    local force = false
    if spec:find("force") then
        force = true
        spec = spec:gsub("force", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if spec == "" then spec = "1" end
    end
    -- "/md replay run 2" plays the WHOLE run on one clock, gaps included
    -- (v0.14.0). "2:7" still opens that one pull. "run 2 pull" opens the run's
    -- first pull the old way, for when only the fight is wanted.
    -- T51: asked for by hand while a run plays, it starts that run afresh
    -- (it opened the run's first pull on the old run's clock).
    local r = spec:match("^run%s*(%d+)$")
    if r then
        return MD:OpenRunPlay(tonumber(r)) and true or false
    end
    local rp2 = spec:match("^run%s*(%d+)%s*pull$")
    if rp2 then spec = rp2 .. ":1" end
    local rec, label, run, pullK = MD:GetRecording(spec)
    if not rec then MD:Print("replay: no recording " .. tostring(n) .. ".") return false end
    n = label
    curRun, runIdx, pullIdx = run, run and tonumber(label:match("^(%d+):")) or nil, pullK

    Build()
    playing = false
    local t0 = debugprofilestop and debugprofilestop() or 0
    -- opening a single pull by hand leaves run mode; OpenRunPlay turns it back on.
    -- T51: "by hand" is every open but the window's own (OpenPull): a run
    -- crossing into its next pull stays on the run's clock, `/md replay 3`
    -- after a run no longer plays on it.
    if not quiet then runMode = false end
    if not runMode then runTL, runT = nil, 0 end
    openSpec, openForce = n, force
    rp = SP.Replay(rec, { dt = 0.25, force = force })
    if not rp then MD:Print("replay: could not build the fight.") return false end
    -- v0.13.9: no plan yet? coach it now, and let the window fill in.
    if not rp.right then MD:CoachOnOpen(rec, force, rp.validation) end
    -- T72: under the theme a forced open that started the coach has
    -- something to force: the column fills in when the search ends
    if force and not rp.right and not (UI.THEMED and MD.replayCoaching == rec.id) then
        MD:Print(string.format("replay: nothing to force - no plan has been coached for this fight. " ..
            "|cffffff00/md coach %s force|r first.", tostring(n)))
    end
    local RT = MD.ReplayTrace
    left.state = RT.New(rp.left.trace, rp.scenario, { onEvent = MakeOnEvent(left) })
    right.state = rp.right and RT.New(rp.right.trace, rp.scenario, { onEvent = MakeOnEvent(right) }) or nil
    MD:Debug("sim", "replay %s opened: %d rows, %d/%d trace events, dt %.2f, %.0f ms", tostring(n), #(rec.tracked or {}),
        rp.left.trace.nEv, rp.right and rp.right.trace.nEv or 0, rp.left.trace.dt,
        (debugprofilestop and debugprofilestop() or 0) - t0)

    Layout()
    speed = MD:Setting("replaySpeed")
    speedHighlight(speed)

    local v = rp.validation
    local fit = ""
    if v and v.gates then
        for _, g in ipairs(v.gates) do
            if g.name == "mana" then fit = g.text; break end
        end
    end
    local when = rec.id and date and date("%H:%M", rec.id) or ""
    if UI.THEMED then
        -- T72 (P28, mockup M3): the band -- the fight left, the verdict right
        local day = when
        if rec.id and date then
            day = (date("%Y-%m-%d", rec.id) == date("%Y-%m-%d")) and ("today " .. when)
                or date("%Y-%m-%d %H:%M", rec.id)
        end
        local t2 = UI.Hex("text2")
        headerFS:SetText(string.format(Hi() .. "#%s|r  %s%s  %s%s|r  %s%s|r  %s%d targets|r", tostring(n),
            run and (Esc(run.name or "run") .. " pull " .. tostring(pullK) .. " - ") or "",
            Esc(rec.zone or "?"), t2, day, t2, MD.Util.Clock(rec.dur or 0), t2, #rows))
        local band = frame.band
        local verdict, tip = "", nil
        if v then
            local failed
            tip = {}
            for _, g in ipairs(v.gates or {}) do
                if not g.ok and not failed then failed = g.name end
                tip[#tip + 1] = { l = tostring(g.name or "?"),
                    r = g.ok and (UI.Hex("good") .. "ok|r") or (UI.Hex("bad") .. "FAIL|r") }
            end
            -- the FORCED marker the TBC title carries lives here under the
            -- theme, where the strategy chooser does not share its line
            verdict = v.ok and (UI.Hex("good") .. "replays|r")
                or (UI.Hex("bad") .. "does not replay: " .. (failed or "a gate failed")
                    .. (rp.right and rp.forced and ", coached anyway" or "") .. "|r")
            if fit ~= "" then tip[#tip + 1] = { l = UI.Hex("muted") .. fit .. "|r", r = "" } end
        end
        band.verdict:SetText(verdict)
        band.verdictTip = tip
        Shown(band.coach, right.waiting == "offer")
    else
        headerFS:SetText(string.format(Hi() .. "#%s|r  %s%s  %s  %s   %s%s", tostring(n),
            run and (run.name .. " pull " .. tostring(pullK) .. " - ") or "", rec.zone or "?", when,
            Clock(rec.dur or 0), v and (v.ok and "|cff99dd99replays|r" or "|cffff9966does not replay|r") or "",
            fit ~= "" and ("  |cff888888" .. fit .. "|r") or ""))
    end
    -- T16a: a v3 recording (Forever) has no real health log at all -- every
    -- bar and tick drawn is T13d's reconstruction, and `maxEstimated` says
    -- whether any tracked target's max was itself a stand-in. T66 (review
    -- A18): the scenario says it is reconstructed; the version is not tested.
    if UI.THEMED then
        -- T72: one word in the band, what it means on its hover
        local band = frame.band
        local recon = rp.scenario and rp.scenario.reconstructed
        if recon then
            band.word:SetText("reconstructed")
            band.wordTip = { "Reconstructed health",
                "This client reads no health (it is secret), so every bar",
                "and tick here is rebuilt from UNIT_COMBAT every 2 s,",
                "from full at the pull: an estimate, not the truth." }
            if rp.scenario.maxEstimated then
                band.wordTip[#band.wordTip + 1] = "A party member's max health is estimated too."
            end
        else
            band.word:SetText("")
            band.wordTip = nil
        end
        Shown(band.word, recon); Shown(band.wordLine, recon); Shown(band.wordHit, recon)
        PlaceBand()
    elseif rp.scenario and rp.scenario.reconstructed then
        local estimated = rp.scenario.maxEstimated
        frame.reconFS:SetText("health reconstructed from UNIT_COMBAT"
            .. (estimated and "; party max estimated" or ""))
        frame.reconFS:Show()
    else
        frame.reconFS:Hide()
    end
    -- R5 (review 2026-09-29): the ticks checkbox says what the ticks are; only
    -- a reconstructed set changes it, and the next recording puts it back.
    if frame.ticksCB then
        if rp.ticks and rp.ticks.reconstructed then
            UI.SetTooltips(frame.ticksCB, "ANCHOR_TOPLEFT", 0, 3, "Reconstructed health ticks",
                "Health rebuilt from UNIT_COMBAT every 2s (none is read on",
                "this client), drawn over the engine's replay on the left bars.")
            frame.ticksCB.reconTips = true
        elseif frame.ticksCB.reconTips then
            UI.SetTooltips(frame.ticksCB, "ANCHOR_TOPLEFT", 0, 3, TICKS_TIPS[1], TICKS_TIPS[2], TICKS_TIPS[3])
            frame.ticksCB.reconTips = nil
        end
    end
    -- the strategy chooser, when a search has produced strategies for this fight
    do
        local SP = MD.SimPlanner
        local winners = rp.rec and SP.strategies[rp.rec.id]
        local items, current = {}, nil
        if rp.right and rp.rec then
            local pick = SP.strategyPick[rp.rec.id]
            -- the planners first: they are available whether or not a search has
            -- run, and they are what the author is actually choosing between
            for _, e in ipairs(SP.STRATEGY_SET or {}) do
                items[#items + 1] = { id = e.key, text = e.label, tooltip = e.why }
                if pick == e.key then current = e.key end
            end
            -- then the four readings of the last search, when there was one
            if winners then
                for _, obj in ipairs(SP.OBJECTIVES) do
                    local w = winners[obj.key]
                    if w then
                        items[#items + 1] = { id = obj.key, text = "Search: " .. obj.name,
                                              tooltip = obj.what }
                        -- what the author CHOSE, not the first objective that
                        -- happens to share the winning plan
                        if pick == obj.key then current = obj.key end
                        if not current and SP.plans[rp.rec.id] == w.plan then current = obj.key end
                    end
                end
            end
        end
        if #items > 0 then
            stratDrop:SetItems(items)
            if current then stratDrop:SetValue(current) end
            stratDrop:ClearAllPoints()
            -- Anchored to the window's RIGHT edge on the header line, so it
            -- cannot run off the way four buttons growing rightward from the
            -- column title did. The header text is left-anchored and short; a
            -- one-column window has no suggested column and so no chooser.
            -- T72: under the theme the band holds the verdict there, so the
            -- chooser sits at the right end of the column titles' line.
            stratDrop:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -GUTTER, UI.THEMED and -(topH + 4) or -6)
            stratDrop:Show()
        else
            stratDrop:Close()
            stratDrop:Hide()
        end
    end

    local coachable, coachWhy = MD.ClassProfile:Can("coach")
    if rp.right then
        local p = rp.right.plan
        right.title:SetText(string.format("SUGGESTED  |cff888888(%s, %d binds)|r%s", p.name or "plan", p:BindCount(),
            (rp.forced and not UI.THEMED) and "  |cffff9966FORCED - this fight does not replay|r" or ""))
        frame.hint:SetText("")
    elseif right.waiting == "offer" then
        -- T72 (review of P28): laid out, dimmed, waiting for Coach anyway
        right.title:SetText(string.format("%sSUGGESTED|r  %snot coached|r", UI.Hex("muted"), UI.Hex("muted")))
        frame.hint:SetText("")
    elseif right.dimmed then
        -- T72: the dimmed column's title carries the search's progress
        coachEvals = (MD.coachSearch and MD.coachSearch.evals) or 0
        right.title:SetText(PendingTitle(coachEvals))
        frame.hint:SetText("")
    elseif not coachable then
        -- T99 (docs/SPEC-next.md 4.4): no suggested column will come -- say why
        -- (a druid never reaches this: its profile coaches)
        frame.hint:SetText(MD.Profiles.Refusal("coach", coachWhy, "Coaching"))
    elseif UI.THEMED then
        -- T72: the band says whether it replays and offers Coach anyway
        frame.hint:SetText(v and not v.ok and "" or "no plan yet")
    elseif MD.replayCoaching == (rp.rec and rp.rec.id) then
        frame.hint:SetText("coaching this fight - the suggested column fills in when the search finishes")
    else
        -- v0.13.9: opening a replay coaches it. The old flow was validate, then
        -- coach, then play -- three commands to answer one question, and two of
        -- them only existed because the third had nothing to draw.
        frame.hint:SetText(v and not v.ok
            and string.format("does not replay (%s) - |cffffff00/md replay %s force|r coaches it anyway",
                (function()
                    for _, g in ipairs(v.gates or {}) do if not g.ok then return g.name end end
                    return "a gate failed"
                end)(), tostring(openSpec or ""))
            or "no plan yet")
    end

    -- T51 (B21): in run mode the scrubber is the RUN's timeline, set once by
    -- OpenRunPlay; a pull opened inside the run leaves its range alone
    if not (runMode and runTL) then
        scrubber.settingValue = true
        scrubber:SetMinMaxValues(0, left.state.dur)
        scrubber:SetValue(0)
        scrubber.settingValue = false
    end
    PlaceMarkers()
    SeekTo(0)
    MD.Win:TakeOver("replay", "replay") -- T34 (6.3)
    frame:Show()
    return true
end

-- /md replay run 2 play  -- the whole dungeon on one clock (docs/SPEC-v0.14.md).
-- The pull replay is untouched; this drives it from the run's time and fills the
-- gaps, which is half of a dungeon and where the drinking happens.
function MD:OpenRunPlay(idx)
    local run = MD.RunRecorder and MD.RunRecorder:Get(idx)
    if not run then MD:Print("replay: no run " .. tostring(idx) .. ".") return end
    local tl = MD.RunTimeline.Build(run)
    if not tl or #tl.segs == 0 then MD:Print("replay: run " .. tostring(idx) .. " has nothing to play.") return end
    if not MD:OpenReplay(idx .. ":1") then return false end
    if not (frame and frame:IsShown()) then return false end
    runMode, runTL, runT = true, tl, 0
    scrubber.settingValue = true
    scrubber:SetMinMaxValues(0, tl.dur)
    scrubber.settingValue = false
    if not tl.hasGapHealth then
        MD:Print("replay: this run was recorded before v0.13.7, so the gaps have no health "
            .. "samples - the bars hold their last value between pulls.")
    end
    RunSeek(0)
    SetPlaying(true)
    return true
end

function MD:ToggleReplay(arg)
    if frame and frame:IsShown() and (arg == nil or arg == "") then
        frame:Hide()
        return
    end
    MD:OpenReplay(arg)
end

--------------------------------------------------------------------------------
-- Practice (v0.15.0, docs/SPEC-v0.15.md). The window's controls change hands:
-- no scrubber (the future has not happened), speeds 1/4x to 1x (slow practice,
-- never fast), an End button; the frames take presses and the window takes the
-- keyboard. Everything painted is still read from Engine/ReplayTrace.lua, off
-- the trace the engine is writing.
--------------------------------------------------------------------------------
local practiceErr, practiceErrUntil, practiceErrTi = nil, 0, nil

local function LiveControls(on)
    Shown(scrubber, not on)
    for _, b in ipairs(speedButtons or {}) do Shown(b, not on or b.id <= 1) end
    Shown(endBtn, on)
    if frame.ticksCB then Shown(frame.ticksCB, not on) end
    timeFS:ClearAllPoints()
    timeFS:SetPoint("LEFT", on and endBtn or speedButtons[#speedButtons], "RIGHT", 12, 0)
    if frame.EnableKeyboard then frame:EnableKeyboard(on) end
    keysOn = on and true or false
    if frame.keyHint then Shown(frame.keyHint, not on) end
    -- T72: off, the replay's own keys (live only under the pointer) come back
    frame:SetScript("OnKeyDown", on and function(_, key)
        if key == "ESCAPE" then Propagate(true) return end
        if key == "SPACE" then
            Propagate(false)
            SetPlaying(not playing)
            if live then live:SetPaused(not playing) end
            return
        end
        local mods = MD.Practice.Mods(MD.API.IsAltKeyDown(), MD.API.IsControlKeyDown(),
            MD.API.IsShiftKeyDown())
        if MD.Practice.BindFor(mods .. key) then
            Propagate(false)
            MD:PracticePress(key, hoverTi)
        else
            Propagate(true)
        end
    end or ReplayKey)
    if not on then hoverTi = nil; pointerIn = false end
end

-- A press, from a mouse button on a frame or a key over one. `key` is bare
-- ("BUTTON5", "1"); the modifiers are read now, as the client reads them.
function MD:PracticePress(key, ti)
    if not live then return end
    local PR = MD.Practice
    local mods = PR.Mods(MD.API.IsAltKeyDown(), MD.API.IsControlKeyDown(),
        MD.API.IsShiftKeyDown())
    local bind, spellID = PR.BindFor(mods .. key)
    if not bind then return end
    if not spellID then live:Error("You don't know " .. bind.family, nil, ti) return end
    if not ti then live:Error("No target", spellID, nil) return end
    live:Cast(spellID, ti)
end

LiveUpdate = function(elapsed)
    if not live then return end
    live:SetSpeed(speed)
    if playing then live:Update(elapsed) end
    local st = left.state
    if st and live.clock > st.t then st:Advance(live.clock - st.t) end
    Paint()
    local now = GetTime()
    if practiceErr and now < practiceErrUntil then
        frame.hint:SetText("|cffff4040" .. practiceErr .. "|r")
    else
        frame.hint:SetText(playing and "hover a frame and press a binding   |cff888888space pauses, End keeps it|r"
            or Hi() .. "paused|r   |cff888888space to go on|r")
    end
    if practiceErrTi and now < practiceErrUntil then
        local f = left.frames[practiceErrTi]
        if f then f.SetCast(practiceErr); f.cast:SetTextColor(1, 0.25, 0.25); f.textUntil = practiceErrUntil end
        practiceErrTi = nil
    end
    if live.state == "done" or live.state == "failed" then MD:StopPractice(true) end
end

-- setup: Engine/Practice.lua's shape (the Simulate -> Practice panel builds it)
function MD:OpenPractice(setup, seed)
    local PR = MD.Practice
    if not (PR and MD.ReplayTrace) then MD:Print("practice: not loaded.") return end
    if MD.API.InCombatLockdown() or MD.API.UnitAffectingCombat("player") then
        MD:Print("practice: not in combat.")
        return
    end
    -- T99 (4.4): the class profile's practice capability, in place of the druid check
    local canPractise, why = MD.ClassProfile:Can("practice")
    if not canPractise then MD:Print(MD.Profiles.Refusal("practice", why) .. ".") return end
    Build()
    if live then MD:StopPractice(false) end
    local session = PR.New(setup, { seed = seed, onError = function(msg, _, ti)
        practiceErr, practiceErrUntil, practiceErrTi = msg, GetTime() + 1.5, ti
    end })
    session:Start()
    if session.state ~= "running" or not session:LiveTrace() then
        MD:Print("practice: the session did not start - " .. tostring(session.failure))
        return
    end
    live = session
    runMode, runTL, runT, curRun, runIdx, pullIdx = false, nil, 0, nil, nil, nil
    local roster, tracked = {}, {}
    for i, tg in ipairs(setup.targets) do
        roster[i] = { name = tg.name, class = tg.class, role = tg.role,
                      guid = tg.you and MD.player.guid or nil }
        tracked[i] = i
    end
    local known = {}
    for family, id in pairs(MD.SpellData.maxRank or {}) do known[family] = id end
    rp = { live = true, scenario = session.scenario, kit = session.kit,
           rec = { roster = roster, tracked = tracked, initial = { known = known }, names = {} },
           left = { trace = session:LiveTrace() } }
    left.state = MD.ReplayTrace.New(rp.left.trace, rp.scenario, { onEvent = MakeOnEvent(left) })
    right.state = nil
    stratDrop:Close()
    stratDrop:Hide()
    Layout()
    LiveControls(true)
    for _, col in ipairs({ left, right }) do
        col.strip.lastCast, col.strip.gcdStart, col.strip.gcdUntil = nil, 0, 0
        col.strip.barSpell, col.strip.barAt = nil, nil
    end
    local g
    for _, x in ipairs(PR.GROUPS) do if x.id == setup.group then g = x end end
    headerFS:SetText(string.format(Hi() .. "PRACTICE|r  %s, %d people   %s",
        g and g.label or "custom", #setup.targets, Clock(session.scenario.dur)))
    frame.reconFS:Hide()
    if frame.band then
        -- T72: a practice has no verdict and nothing to reconstruct
        frame.band.verdict:SetText("")
        frame.band.verdictTip, frame.band.wordTip = nil, nil
        frame.band.coach:Hide(); frame.band.wordLine:Hide(); frame.band.wordHit:Hide()
        PlaceBand()
    end
    left.title:SetText("YOU")
    speed = 1
    speedHighlight(1)
    playing = true
    playBtn:SetText("II")
    MD.Win:TakeOver("replay", "practice") -- T34 (6.3): always a takeover
    frame:Show()
    return session
end

-- End the practice. `reopen`: open what was played as a replay (the End
-- button, and the fight running out); closing the window only keeps it.
function MD:StopPractice(reopen)
    local s = live
    if not s then return end
    live = nil
    if s.state == "running" then s:Stop() end
    LiveControls(false)
    playing = false
    local rec = s.rec
    if s.state == "failed" then
        MD:Print("practice: the session failed - " .. tostring(s.failure))
        return
    end
    if not rec then
        MD:Print("practice: nothing was cast, so nothing was kept.")
        if reopen and frame then frame:Hide() end
        return
    end
    MD:Print(string.format("practice: %s played, %d casts, %d mana, %d dead - kept as |cffffff00p1|r " ..
        "(Reports -> Review -> Practice, or /md replay p1).", Clock(rec.dur), rec.ownCasts or 0,
        rec.spent or 0, #(rec.deaths or {})))
    if reopen then MD:OpenReplay("p1") end
end

-- combat ends practice: the window is a review tool, and the keyboard is yours
-- T57 (P13, review Q2): through the kernel's MD:On like every other event
-- (tools/apicheck.py rule 9), not a raw frame of its own -- same event, same
-- handler.
MD:On("PLAYER_REGEN_DISABLED", function()
    refusedInCombat = false -- T51 (B22): a new combat says its refusal once
    if live then
        MD:StopPractice(false)
        if frame then frame:Hide() end
    end
    -- T72: combat takes the keyboard back, and it stays back until the pointer
    -- enters the window again out of combat (pointerIn is left as it is)
    if frame then SetKeys(false) end
end)

-- T72 (P28, review U23): the band's Coach anyway -- what "/md replay N force"
-- did, from the window: coach this fight although it does not replay, both
-- columns laid out at once while the search runs.
local function CoachAnyway()
    if live or not (rp and rp.rec and openSpec) then return end
    if MD.coachSearch then
        MD:Print("replay: another fight is being coached - this one can be coached when it finishes.")
        return
    end
    -- the window's own reopen (RebuildSuggested's): a run keeps its clock and
    -- the replay its time, as when the plan arrives
    askedToCoach = true
    openForce = true
    local ok, err = pcall(MD.RebuildSuggested, MD)
    askedToCoach = false
    if not ok then error(err, 0) end
end

MD.Replay = {
    Open = function(_, n) MD:OpenReplay(n) end,
    CoachAnyway = CoachAnyway, -- T72: the band's button
    _live = function() return live, hoverTi end,
    -- for tools/replayui.lua: what the window is showing, read-only
    -- for tools/replayui.lua: where the run clock is, and what it thinks is
    -- happening there
    _run = function()
        if not (runMode and runTL) then return nil end
        local seg, into = MD.RunTimeline.At(runTL, runT)
        return { t = runT, dur = runTL.dur, seg = seg and seg.kind, k = seg and seg.k,
                 into = into, hasGapHealth = runTL.hasGapHealth, playing = playing }
    end,
    _runSeek = function(_, t) if runMode then RunSeek(t) end end,
    _state = function() return { frame = frame, left = left, right = right, rows = rows, rp = rp,
                                 scrubber = scrubber, timeFS = timeFS, playing = playing, speeds = speedButtons,
                                 headerFS = headerFS, reconFS = frame and frame.reconFS, hint = frame and frame.hint,
                                 -- T72: the band (themed only), its word's hover, the keys
                                 band = frame and frame.band,
                                 reconTip = frame and frame.band and frame.band.wordTip, keys = keysOn } end,
    _runStrip = function()
        if not runStrip then return nil end
        return { shown = runStrip:IsShown(), pulls = runStrip.pulls, drinks = runStrip.drinks,
                 marks = runStrip.marks, label = runStrip.label:GetText(), run = curRun,
                 pull = pullIdx, runIdx = runIdx }
    end,
    _strategy = function() return stratDrop end,
    _setPlaying = function(on) SetPlaying(on) end,
    _seek = function(t) SeekTo(t) end,
}
