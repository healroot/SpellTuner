-- tools/run.sh --flavour forever|tbc tools/stylecheck.lua [--print | --golden]
--
-- T94 (docs/SPEC-next.md 2.2, 5.1-5.4, section 11's T94 row; R-styles.md 3):
-- the style registry, S2's first step. A style is paint only -- a data table
-- of fills, text tokens, fonts and one recipe per role -- and Flat, today's
-- look, is the first one registered. What this suite holds, on both lines:
--
--   * Flat validates, carries every role (its `clock` role included) and is
--     the style applied at CORE_LOGIN; a malformed style is refused by name.
--   * The first Flat paint of a nav frame, a kit button, a check box, a rail
--     and the clock equals the paint the PARENT commit drew (the golden at
--     the bottom: per section a line count and a checksum, captured with
--     `--golden` on 231525d before the first edit) -- the registry changed
--     nothing a player sees.
--   * Flat -> a test style -> Flat repaints those regions (the test style's
--     colours, its `strips` edge, its fonts in between) and returns BYTE-
--     IDENTICAL to the first paint: every colour, backdrop, texture, the
--     palette and the tokens, the font objects; the strips it made hidden.
--   * STYLE_CHANGED once per switch; an unknown name refused (nothing changes,
--     nothing fires); UI.SetStyle before CORE_LOGIN raises; no styled frame is
--     built before PLAYER_LOGIN (the TOC's files register nothing at load).
--   * `/st ui style <name>` through MD:AddSubcommand, and `/st ui reset` still
--     reaching the window manager with `ui style` registered in either order.
--   * the dump line (MD:AddDumpLine) once a style other than Flat has been
--     applied, and the per-role fallback for art a style needs and the
--     client does not answer for.
--
-- This suite loads the flavour's TOC itself (the harness's own steps, without
-- the events) so it can look between the last file and PLAYER_LOGIN. Until
-- the TOCs list UI/Styles.lua it is loaded where the integrator will put it,
-- right after UI/Theme_Flat.lua. TBC's whole TOC is loaded, UI files
-- included (the harness drops them for TBC), since the clock and the slash
-- verb live there.
HARNESS_FLAVOUR = { "forever", "tbc" }

local here = arg[0]:match("^(.*)/[^/]+$")
local root = arg[1] or "."
local mode = "check"
for i = 2, #arg do
    if arg[i] == "--print" then mode = "print" elseif arg[i] == "--golden" then mode = "golden" end
end

local flavour = os.getenv("ST_FLAVOUR")
if flavour == nil or flavour == "" then flavour = "forever" end
if flavour ~= "forever" and flavour ~= "tbc" then
    print("skip: stylecheck.lua runs under forever, tbc only")
    os.exit(3)
end

local T = dofile(here .. "/lib/t.lua")
local check = T.check

dofile(here .. "/wowstub.lua")
local S = _G.STUB
S.root = root
S.flavour = flavour

local MD = {}
local toc = "SpellTuner_TBC.toc"
if flavour == "forever" then
    S.UseProfile("forever")
    toc = "SpellTuner_Mainline.toc"
end
local files = S.TocFiles(toc)
-- a file the TOC does not list yet, loaded right after `after` (where the
-- integrator puts it) when it exists in this tree
local function InsertAfter(rel, after)
    local h = io.open(root .. "/" .. rel, "r")
    if not h then return end
    h:close()
    for _, f in ipairs(files) do if f == rel then return end end
    local out = {}
    for _, f in ipairs(files) do
        out[#out + 1] = f
        if f == after then out[#out + 1] = rel end
    end
    files = out
end
InsertAfter("UI/Styles.lua", "UI/Theme_Flat.lua")
-- T100: the Ellesmere style, right after the registry
InsertAfter("UI/Style_Ellesmere.lua", "UI/Styles.lua")
S.loadedFiles = files
S.Load(files, "SpellTuner", MD)
local UI = MD.UI

--------------------------------------------------------------------------------
-- Between the last file and PLAYER_LOGIN
--------------------------------------------------------------------------------
local function Count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end
local registry = UI.skinned or UI.pixelFrames
local skinnedAtLoad = Count(registry)
local earlyOk, earlyErr = false, "no UI.SetStyle"
if UI.SetStyle then earlyOk, earlyErr = pcall(UI.SetStyle, "flat") end
local styleAtLoad = UI.STYLE

-- STYLE_CHANGED, counted from the first event on
local changed = {}
if MD.RegisterCallback then
    MD:RegisterCallback("STYLE_CHANGED", function(key) changed[#changed + 1] = key end)
end

S.Fire("ADDON_LOADED", "SpellTuner")
S.Fire("PLAYER_LOGIN")
S.Fire("PLAYER_ENTERING_WORLD")
local changedAtLogin = #changed

--------------------------------------------------------------------------------
-- The regions: a nav frame (its active group and view tab), two kit buttons,
-- a ticked check box, a rail with a selected row, and the clock.
--------------------------------------------------------------------------------
local firstBuilt = #S.allFrames + 1
local host = CreateFrame("Frame", "STStyleHost", UIParent, "BackdropTemplate")
host:SetSize(400, 300)
local groups = {
    { id = "a", text = "Spells", views = { { id = "one", text = "One" }, { id = "two", text = "Two" } } },
    { id = "b", text = "Reports", views = { { id = "three", text = "Three" } } },
}
local nav = UI.CreateNavFrame("SpellTuner", "STStyleNav", 700, 400, groups,
    function(_, _, content) return CreateFrame("Frame", nil, content) end)
nav:Select("a", "one")
local btn = UI.CreateButton(host, "Go", "accent-hover", { 60, 20 })
local red = UI.CreateButton(host, "x", "red", { 20, 20 })
local cb = UI.CreateCheckButton(host, "Tick")
cb:SetChecked(true)
local rail = UI.CreateRail(host, 172, { title = "MY SPELLS" })
rail:SetRows({ { id = "ov", text = "Overview", fixed = true },
               { id = "ht", text = "Healing Touch" }, { id = "rj", text = "Rejuvenation" } })
rail:Select("ht")
local clock = flavour == "forever" and _G.SpellTunerClock or _G.SpellTunerWidget

local ROOTS = { nav = nav.frame, host = host, clock = clock }

-- every frame, texture and font string under a root, in creation order
local function Under(rootFrame, upto)
    local out = {}
    for i = 1, upto or #S.allFrames do
        local f, guard = S.allFrames[i], 0
        local g = f
        while g and guard < 60 do
            if rawequal(g, rootFrame) then out[#out + 1] = f; break end
            g, guard = g.parentFrame, guard + 1
        end
    end
    return out
end
local lastBuilt = #S.allFrames
local SETS = {}
for _, name in ipairs({ "nav", "host", "clock" }) do
    SETS[name] = ROOTS[name] and Under(ROOTS[name], lastBuilt) or {}
end

--------------------------------------------------------------------------------
-- The paint, as text: one line per region, and the style state (the palette,
-- the tokens, the aliases, the font objects, the accent). Numbers at 6
-- significant digits, so a recomputed 0.12 reads like the literal.
--------------------------------------------------------------------------------
local function N(v)
    if type(v) == "number" then return string.format("%.6g", v) end
    return tostring(v)
end
local function C(c)
    if type(c) ~= "table" then return tostring(c) end
    return N(c[1]) .. "," .. N(c[2]) .. "," .. N(c[3]) .. "," .. N(c[4])
end
local function BD(bd)
    if type(bd) ~= "table" then return tostring(bd) end
    local ins = bd.insets
    local i = type(ins) == "table" and (N(ins.left) .. "/" .. N(ins.right) .. "/" .. N(ins.top) .. "/" .. N(ins.bottom))
        or tostring(ins)
    return tostring(bd.bgFile) .. "|" .. tostring(bd.edgeFile) .. "|" .. N(bd.edgeSize) .. "|" .. i
end
local function Region(f)
    return table.concat({ tostring(f.kind), f.shown and "shown" or "hidden", "bd=" .. BD(f.backdrop),
        "bg=" .. C(f.bg), "edge=" .. C(f.border), "tex=" .. C(f.color), "text=" .. C(f.textColor),
        "bar=" .. C(f.barColor), "w=" .. N(f.w), "h=" .. N(f.h) }, " ")
end
local function Sorted(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end
local function Paint()
    local sections = {}
    for _, name in ipairs({ "nav", "host", "clock" }) do
        local lines = {}
        for _, f in ipairs(SETS[name]) do lines[#lines + 1] = Region(f) end
        sections[#sections + 1] = { name = name, lines = lines }
    end
    local pal = {}
    for _, k in ipairs(Sorted(UI.PALETTE)) do pal[#pal + 1] = k .. "=" .. C(UI.PALETTE[k]) end
    pal[#pal + 1] = "frame==bg " .. tostring(UI.PALETTE.frame == UI.PALETTE.bg)
    pal[#pal + 1] = "header==nav " .. tostring(UI.PALETTE.header == UI.PALETTE.nav)
    sections[#sections + 1] = { name = "palette", lines = pal }
    local txt = {}
    for _, k in ipairs(Sorted(UI.TEXT)) do
        local t = UI.TEXT[k]
        txt[#txt + 1] = k .. "=" .. N(t[1]) .. "," .. N(t[2]) .. "," .. N(t[3]) .. " " .. tostring(t.hex)
    end
    local Tx = UI.TEXT
    txt[#txt + 1] = "aliases " .. tostring(Tx.text2 == Tx.label) .. " " .. tostring(Tx.dominated == Tx.text)
        .. " " .. tostring(Tx.note == Tx.text2) .. " " .. tostring(Tx.tipGold == Tx.accent)
    txt[#txt + 1] = "accent " .. C(UI.accent) .. " " .. tostring(UI.accentHex)
    sections[#sections + 1] = { name = "text", lines = txt }
    local fonts = {}
    for _, k in ipairs(Sorted(UI.fontObjects)) do
        local o = UI.fontObjects[k]
        fonts[#fonts + 1] = k .. " " .. tostring(o.fontPath) .. " " .. N(o.fontSize) .. " " .. tostring(o.fontFlags)
            .. " " .. C(o.textColor)
    end
    sections[#sections + 1] = { name = "fonts", lines = fonts }
    return sections
end

local function Sum(lines)
    local h = 0
    for _, l in ipairs(lines) do
        for i = 1, #l do h = (h * 31 + l:byte(i)) % 2147483647 end
        h = (h * 31 + 10) % 2147483647
    end
    return h
end

local first = Paint()

if mode == "print" then
    for _, s in ipairs(first) do
        print("== " .. s.name .. " (" .. #s.lines .. ")")
        for _, l in ipairs(s.lines) do print(l) end
    end
    os.exit(0)
end
if mode == "golden" then
    print("    " .. flavour .. " = {")
    for _, s in ipairs(first) do
        print(string.format("        %s = { %d, %d },", s.name, #s.lines, Sum(s.lines)))
    end
    print("    },")
    os.exit(0)
end

--------------------------------------------------------------------------------
-- The golden: `tools/run.sh --flavour <f> tools/stylecheck.lua --golden` on
-- 231525d (the parent, before any edit), pasted. Per section: lines, checksum.
-- Wave N2's integrator re-based the clock section only: T93 (merged before T94)
-- draws the clock through UI/ClockView.lua, 8 regions instead of 4; captured with
-- --golden on 546e729 (T92 + T93 with their TOC lines, no T94 code), and equal to
-- what this tree paints, so Flat is still the parent's paint byte for byte.
--------------------------------------------------------------------------------
local GOLDEN = {
    forever = {
        nav = { 29, 1225158578 },
        host = { 52, 441673342 },
        clock = { 8, 1137838505 },
        palette = { 33, 1948568416 },
        text = { 15, 1382467428 },
        fonts = { 12, 1125933103 },
    },
    tbc = {
        nav = { 29, 1015818899 },
        host = { 52, 98457140 },
        clock = { 8, 1079176797 },
        palette = { 33, 1948568416 },
        text = { 15, 1382467428 },
        fonts = { 12, 1125933103 },
    },
}

local Styles = UI.Styles or {}

T.section("loading: nothing styled before PLAYER_LOGIN, nothing applied before CORE_LOGIN")
check("no styled frame is built before PLAYER_LOGIN (the TOC's files register nothing)",
    registry ~= nil and skinnedAtLoad == 0, tostring(skinnedAtLoad) .. " registered at load")
check("UI.SetStyle before CORE_LOGIN raises",
    UI.SetStyle ~= nil and earlyOk == false and tostring(earlyErr):find("CORE_LOGIN", 1, true) ~= nil,
    tostring(earlyErr))
check("at login Flat is applied (UI.STYLE flat, db.ui.style flat, STYLE_CHANGED once)",
    UI.STYLE == "flat" and MD.db and MD.db.ui and MD.db.ui.style == "flat" and changedAtLogin == 1
      and changed[1] == "flat",
    string.format("STYLE %s, saved %s, %d fired", tostring(UI.STYLE), tostring(MD.db and MD.db.ui and MD.db.ui.style),
        changedAtLogin))
check("the regions are registered by role once built (UI.skinned, UI.pixelFrames its old name)",
    registry ~= nil and UI.pixelFrames == UI.skinned and registry[nav.frame] ~= nil
      and registry[nav.frame].role == "window" and registry[btn] ~= nil and registry[btn].role == "button"
      and registry[cb] ~= nil and registry[cb].role == "field" and registry[rail.frame] ~= nil
      and registry[rail.frame].role == "pane" and clock ~= nil and registry[clock] ~= nil,
    registry and string.format("nav %s, button %s, check %s, rail %s, clock %s",
        tostring(registry[nav.frame] and registry[nav.frame].role), tostring(registry[btn] and registry[btn].role),
        tostring(registry[cb] and registry[cb].role), tostring(registry[rail.frame] and registry[rail.frame].role),
        tostring(clock and registry[clock] and registry[clock].role)) or nil)

T.section("Flat: registered, valid, the parent's paint")
local flat = Styles.Get and Styles.Get("flat")
local okFlat, why = false, "no UI.Styles.Validate"
if Styles.Validate and flat then okFlat, why = Styles.Validate(flat) end
check("Flat is registered and validates", flat ~= nil and okFlat == true,
    type(why) == "table" and table.concat(why, "; ") or tostring(why))
local ROLES = { "window", "header", "nav", "pane", "button", "tab", "field", "list", "scroll", "tooltip",
                "clock", "statusbar", "rule" }
local allRoles = flat ~= nil and type(flat.roles) == "table"
for _, r in ipairs(ROLES) do
    if not (allRoles and type(flat.roles[r]) == "table" and flat.roles[r].kind == "pixel") then allRoles = false end
end
check("Flat names every role, its clock role included, each with the pixel painter",
    allRoles and flat.roles.clock.fill == "bg" and flat.roles.clock.edge == "border")
do
    local want = GOLDEN[flavour]
    local bad = {}
    for _, s in ipairs(first) do
        local g = want[s.name]
        if not g or g[1] ~= #s.lines or g[2] ~= Sum(s.lines) then
            bad[#bad + 1] = string.format("%s %d/%d (golden %s/%s)", s.name, #s.lines, Sum(s.lines),
                tostring(g and g[1]), tostring(g and g[2]))
        end
    end
    check("the first Flat paint equals the parent's (nav, regions, clock, palette, tokens, fonts)",
        #bad == 0, #bad > 0 and table.concat(bad, "; ") or nil)
end

T.section("validation refuses a malformed style")
do
    local function Refused(s)
        if not Styles.Validate then return false end
        local okV, problems = Styles.Validate(s)
        return okV == false and type(problems) == "table" and #problems > 0, problems
    end
    local base = { name = "Bad", hint = "x", accent = "class", palette = {}, text = {}, fonts = {}, roles = {}, needs = {} }
    local function With(k, v)
        local s = {}
        for kk, vv in pairs(base) do s[kk] = vv end
        s[k] = v
        return s
    end
    local r1 = Refused(With("roles", { button = { kind = "velvet" } }))
    local r2 = Refused(With("palette", { frame = { 0, 0, 0, 1 } }))
    local r3 = Refused(With("name", "Gr" .. string.char(195, 188) .. "n"))
    local r4 = Refused(With("palette", { hover = { ref = "nowhere", a = 0.1 } }))
    local r5 = Refused(With("roles", { sparkle = { kind = "pixel" } }))
    local r6 = Refused(With("text", { label = "B3B3" }))
    local raised = Styles.Register and not pcall(Styles.Register, "bad", With("roles", { button = { kind = "velvet" } }))
    local twice = Styles.Register and not pcall(Styles.Register, "flat", flat)
    check("an unknown painter, an alias key, a non-ASCII name, a bad ref, an unknown role, a bad hex are refused",
        r1 and r2 and r3 and r4 and r5 and r6,
        string.format("%s %s %s %s %s %s", tostring(r1), tostring(r2), tostring(r3), tostring(r4), tostring(r5),
            tostring(r6)))
    check("Register raises on an invalid style and on a key already registered", raised and twice)
end

--------------------------------------------------------------------------------
-- A test style: every fill moved, a fixed accent, the strips painter on
-- windows and panes, an outlined Arial Narrow everywhere.
--------------------------------------------------------------------------------
local TEST = {
    name = "Test", hint = "stylecheck's own.",
    accent = { 0.2, 0.6, 1 },
    palette = {
        bg = { 0.05, 0.07, 0.09, 0.96 }, pane = { 0.05, 0.07, 0.09, 1 }, nav = { 0.04, 0.05, 0.06, 1 },
        border = { 0.25, 0.25, 0.25, 1 }, button = { 0.061, 0.095, 0.12, 0.6 },
        buttonHover = { 0.3, 0.3, 0.3, 1 }, field = { 0.1, 0.12, 0.16, 1 }, track = { 1, 1, 1, 0.1 },
        hover = { 1, 1, 1, 0.08 }, selected = { ref = "accent", a = 0.2 },
        accentHover = { ref = "accent", a = 0.5 },
    },
    text = { text = "EEEEEE", label = "878787", muted = "696969" },
    fonts = { face = "Fonts\\ARIALN.TTF", num = "Fonts\\ARIALN.TTF", flags = "OUTLINE", shadow = { 0, 0 } },
    roles = {
        window = { kind = "strips", fill = "bg", edge = "border", edgeColor = { 1, 1, 1, 0.1 } },
        pane = { kind = "strips", fill = "pane", edge = "border", edgeColor = { 1, 1, 1, 0.05 } },
    },
    needs = {},
}

local function near(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6 end
local function is(c, r, g, b, a)
    return type(c) == "table" and near(c[1], r) and near(c[2], g) and near(c[3], b) and near(c[4], a)
end

T.section("Flat -> Test -> Flat")
local regOk = Styles.Register and pcall(Styles.Register, "test", TEST)
check("a second style registers and validates", regOk and Styles.Get and Styles.Get("test") ~= nil)

local n0 = #changed
local okSet, setWhy = false, nil
if UI.SetStyle then okSet, setWhy = UI.SetStyle("test") end
local n1 = #changed
local P = UI.PALETTE
do
    local act = nav.buttons[1]
    local left = nav.left
    local strips = nav.frame._skinStrips
    local stripsOk = type(strips) == "table" and #strips == 4
    for _, s in ipairs(strips or {}) do
        if not (s:IsShown() and is(s.color, 1, 1, 1, 0.1)) then stripsOk = false end
    end
    check("Test applied: UI.STYLE, db.ui.style, STYLE_CHANGED once with its key",
        okSet == true and UI.STYLE == "test" and MD.db.ui.style == "test" and n1 - n0 == 1 and changed[n1] == "test",
        tostring(setWhy))
    check("the {ref = accent} fills and the tokens follow Test's accent",
        is(P.selected, 0.2, 0.6, 1, 0.2) and is(P.accentHover, 0.2, 0.6, 1, 0.5) and is(P.hover, 1, 1, 1, 0.08)
          and UI.TEXT.accent.hex == "|cff3399ff" and UI.TEXT.text.hex == "|cffeeeeee" and UI.TEXT.text2 == UI.TEXT.label
          and UI.TEXT.label.hex == "|cff878787" and near(UI.accent[3], 1) and UI.accentHex == "|cff3399ff",
        tostring(UI.TEXT.accent.hex))
    check("the nav frame repaints: the strips edge on its window, its column, its selected group",
        is(nav.frame.bg, 0.05, 0.07, 0.09, 0.96) and stripsOk and nav.frame.backdrop and nav.frame.backdrop.edgeFile == nil
          and is(left.bg, 0.04, 0.05, 0.06, 1) and is(left.border, 0.25, 0.25, 0.25, 1)
          and is(act.bg, 0.2, 0.6, 1, 0.2) and is(nav.buttons[2].bg, 0.061, 0.095, 0.12, 0.6),
        string.format("bg %s, strips %s, left %s, active %s", C(nav.frame.bg), tostring(stripsOk), C(left.bg), C(act.bg)))
    check("a kit button, a check box and a rail repaint (fill, edge; the rail's strips and its scroll bar)",
        is(btn.bg, 0.061, 0.095, 0.12, 0.6) and is(btn.border, 0.25, 0.25, 0.25, 1)
          and is(red.bg, 0.6, 0.1, 0.1, 0.6) and is(cb.bg, 0.1, 0.12, 0.16, 1)
          and is(rail.frame.bg, 0.05, 0.07, 0.09, 1) and type(rail.frame._skinStrips) == "table"
          and is(rail.bar.bg, 1, 1, 1, 0.1),
        string.format("button %s, check %s, rail %s, bar %s", C(btn.bg), C(cb.bg), C(rail.frame.bg), C(rail.bar.bg)))
    check("the clock repaints (its fill)", clock ~= nil and is(clock.bg, 0.05, 0.07, 0.09, 0.96), clock and C(clock.bg))
    local face, size, flags = UI.fontObjects[UI.FONT]:GetFont()
    local cls = UI.fontObjects[UI.FONT_CLASS]
    check("the fonts are re-faced at their sizes, the class fonts in the accent",
        face == "Fonts\\ARIALN.TTF" and size == 13 and flags == "OUTLINE" and type(cls.textColor) == "table" and near(cls.textColor[1], 0.2) and near(cls.textColor[2], 0.6)
          and near(cls.textColor[3], 1),
        tostring(face) .. " " .. tostring(size) .. " " .. tostring(flags))
end

-- a hover at the moment of the switch back: the colour it shows maps onto
-- the same key in the next style
local enter = btn:GetScript("OnEnter")
if enter then enter(btn) end
local n2 = #changed
local okBack = UI.SetStyle and UI.SetStyle("flat")
local n3 = #changed
local hoverKept = is(btn.bg, P.accentHover[1], P.accentHover[2], P.accentHover[3], 0.6)
local leave = btn:GetScript("OnLeave")
if leave then leave(btn) end
local back = Paint()
do
    local bad = {}
    for i, s in ipairs(first) do
        local b = back[i]
        if not b or #b.lines ~= #s.lines then
            bad[#bad + 1] = s.name .. " " .. #s.lines .. " -> " .. tostring(b and #b.lines)
        else
            for k = 1, #s.lines do
                if s.lines[k] ~= b.lines[k] then
                    bad[#bad + 1] = s.name .. " line " .. k .. ": " .. b.lines[k] .. " (was " .. s.lines[k] .. ")"
                    break
                end
            end
        end
    end
    check("Flat back: STYLE_CHANGED once, a hovered button keeps its hover",
        okBack == true and UI.STYLE == "flat" and n3 - n2 == 1 and changed[n3] == "flat" and hoverKept,
        string.format("%d fired, hover kept %s", n3 - n2, tostring(hoverKept)))
    check("Flat back is BYTE-IDENTICAL to the first paint (regions, palette, tokens, fonts)",
        #bad == 0, bad[1])
    local stripsHidden = true
    for _, f in ipairs({ nav.frame, rail.frame, clock }) do
        for _, s in ipairs(f and f._skinStrips or {}) do if s:IsShown() then stripsHidden = false end end
    end
    check("the strips Test made are hidden again", stripsHidden)
end

T.section("refusals")
do
    local before = #changed
    local okU, whyU = false, nil
    if UI.SetStyle then okU, whyU = UI.SetStyle("nosuch") end
    check("an unknown name is refused, naming the styles; nothing changes, nothing fires",
        okU ~= true and type(whyU) == "string" and whyU:find("nosuch", 1, true) ~= nil
          and whyU:find("flat", 1, true) ~= nil and UI.STYLE == "flat" and MD.db.ui.style == "flat"
          and #changed == before,
        tostring(whyU))
end

T.section("the dump line, the per-role fallback, UI.Skin")
do
    local function DumpLine()
        for _, d in ipairs(MD.DumpLines and MD:DumpLines() or {}) do
            if d.key == "style" then return d.fn() end
        end
    end
    -- the dump line appears once a style other than Flat was applied (Test
    -- above), and names the active one
    check("the dump line names the style, the accent and what fell back",
        (DumpLine()) == "style: flat (accent class) fell back: none", tostring((DumpLine())))
    local NEEDY = {
        name = "Needy", hint = "an atlas no client answers for", accent = "gold",
        palette = {}, text = {}, fonts = {},
        roles = { button = { kind = "pixel", fill = "button", edge = "border", edgeColor = { 1, 0, 0, 1 } } },
        needs = { { role = "button", atlas = "Options_List_Hover" } },
    }
    local reg = Styles.Register and pcall(Styles.Register, "needy", NEEDY)
    local okN = UI.SetStyle and UI.SetStyle("needy")
    local line = DumpLine()
    local fellBack = is(btn.border, 0, 0, 0, 1)   -- Flat's button recipe: the `border` edge, not red
    local gold = UI.TEXT.accent.hex == "|cffffd100"
    if UI.SetStyle then UI.SetStyle("flat") end
    check("a role whose art is missing falls back to Flat's recipe and is listed",
        reg and okN == true and fellBack and gold and line == "style: needy (accent style) fell back: button",
        tostring(line))
    -- UI.Skin by role: the role's fill and edge from the style
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    if UI.Skin then UI.Skin(f, "clock") end
    local rec = registry and registry[f]
    check("UI.Skin(region, role) paints the role's fill and edge and registers the role",
        rec ~= nil and rec.role == "clock" and is(f.bg, P.bg[1], P.bg[2], P.bg[3], P.bg[4])
          and is(f.border, 0, 0, 0, 1) and f.backdrop ~= nil and f.backdrop.edgeFile ~= nil)
end

T.section("/st ui style, and /st ui reset in either order")
do
    local said = {}
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) said[#said + 1] = m end }
    local function Run(cmd)
        said = {}
        SlashCmdList.SPELLTUNER(cmd)
        return said
    end
    local s1 = Run("ui style test")
    local switched = UI.STYLE == "test"
    local s2 = Run("ui style Flat")
    local back = UI.STYLE == "flat"
    local s3 = Run("ui style nosuch")
    local s4 = Run("ui style")
    local listsAll = s4[1] ~= nil and s4[1]:find("flat", 1, true) ~= nil and s4[1]:find("test", 1, true) ~= nil
    check("/st ui style <name> switches, an unknown one is refused with the list, a bare one lists",
        switched and back and UI.STYLE == "flat" and #s1 == 1 and #s2 == 1
          and s3[1] ~= nil and s3[1]:find("nosuch", 1, true) ~= nil and listsAll,
        tostring(s3[1]) .. " / " .. tostring(s4[1]))
    local row
    for _, c in ipairs(MD:Commands()) do if c.name == "ui" then row = c end end
    check("the ui verb's help row carries the sub's usage",
        row ~= nil and type(row.usage) == "string" and row.usage:find("style <name>", 1, true) ~= nil, row and row.usage)

    -- the window manager's reset, spied; the verb registered again AFTER the
    -- sub (the other load order) keeps the sub
    local resets = 0
    local savedWin = MD.Win
    MD.Win = setmetatable({ Reset = function() resets = resets + 1 end }, { __index = savedWin })
    local okReset = true
    if flavour == "forever" then
        Run("ui reset")
        okReset = resets == 1
    end
    MD:AddCommand("ui", function(arg)
        if arg == "reset" then MD.Win:Reset() else MD:Print("usage: /st ui reset") end
    end, "/st ui reset", "put every SpellTuner window back at its default place and size")
    Run("ui reset")
    Run("ui style test")
    local styleAfter = UI.STYLE == "test"
    Run("ui style flat")
    MD.Win = savedWin
    check("/st ui reset still resets with ui style registered in either order",
        okReset and resets == (flavour == "forever" and 2 or 1) and styleAfter and UI.STYLE == "flat",
        string.format("%d resets, style after %s", resets, tostring(styleAfter)))
end

--------------------------------------------------------------------------------
-- T100 (docs/SPEC-next.md 5.1, 5.5, X4, X5; section 11's T100 row): the
-- Ellesmere style. The clone (EllesmereUI's house look, its default accent
-- for this client: bronze on Forever, teal elsewhere), the tokens' alpha on
-- white pre-blended into hex against the style's bg (X5), and the follow:
-- MD.EUISkin's getters when its apiVersion is 2, else the clone; with no
-- skin facade the parent's getters (MD.EUIParent); a repaint on
-- EUI_LOOKS_CHANGED and once on EUI_SKIN_READY. Both flavours run every
-- check: the clone is a look of its own on TBC, and the follow is data-driven
-- (the integration that hands MD.EUISkin over is Forever's, T97). Failed
-- first on the parent (25748e3): 0 of these 8 ok on either flavour.
--------------------------------------------------------------------------------
T.section("T100: the Ellesmere style")
do
    local E = UI.Ellesmere
    local ell = Styles.Get and Styles.Get("ellesmere")
    local function Hex2(v) return string.format("%02x", math.floor(v * 255 + 0.5)) end
    -- white at alpha a over the rgb of c, as a token's code
    local function Blend(a, c)
        return "|cff" .. Hex2(a + (1 - a) * c[1]) .. Hex2(a + (1 - a) * c[2]) .. Hex2(a + (1 - a) * c[3])
    end
    local function Fired(fn)
        local before = #changed
        fn()
        return #changed - before, changed[#changed]
    end
    local function DumpLine()
        for _, d in ipairs(MD.DumpLines and MD:DumpLines() or {}) do
            if d.key == "style" then return d.fn() end
        end
    end
    local BRONZE = { 220 / 255, 167 / 255, 127 / 255 }
    local TEAL = { 12 / 255, 210 / 255, 157 / 255 }
    local HOUSE = flavour == "forever" and BRONZE or TEAL
    local PANEL = { 0.05, 0.07, 0.09 }
    local EXPRESSWAY = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
    local function FakeSkin(ver, accent, panel, font, flag)
        local S = { apiVersion = ver, reads = 0 }
        function S.GetAccentColor() S.reads = S.reads + 1; return accent[1], accent[2], accent[3] end
        function S.GetPanelColor() S.reads = S.reads + 1; return panel[1], panel[2], panel[3], panel[4] end
        function S.GetFont() S.reads = S.reads + 1; return font, flag end
        function S.GetStyle() return "eui" end
        return S
    end
    -- the stub keeps no shadow offset: a spy on the body font
    local bodyFont = UI.fontObjects[UI.FONT]
    bodyFont.SetShadowOffset = function(self, x, y) self.shadowX, self.shadowY = x, y end
    local function Face()
        local face, size, flags = bodyFont:GetFont()
        local num = UI.fontObjects[UI.FONT_NUM]:GetFont()
        return face, size, flags, num
    end
    local function NavStrips(a)
        local s = nav.frame._skinStrips
        if type(s) ~= "table" or #s ~= 4 then return false end
        for _, t in ipairs(s) do
            if not (t:IsShown() and is(t.color, 1, 1, 1, a)) then return false end
        end
        return true
    end
    MD.EUISkin, MD.EUIParent = nil, nil

    -- 1. registered, valid, its roles
    local okV, whyV = false, "not registered"
    if ell and Styles.Validate then okV, whyV = Styles.Validate(ell) end
    local roles = ell and ell.roles or {}
    local clockRole = roles.clock or {}
    local resolvedOk = false
    if ell and type(ell.resolve) == "function" and Styles.Validate then
        local okR, eff = pcall(ell.resolve, ell)
        resolvedOk = okR and type(eff) == "table" and (Styles.Validate(eff)) == true
    end
    check("Ellesmere is registered and validates (the clone it resolves to too); strips on windows and panes; its clock role",
        okV == true and resolvedOk and ell.name == "Ellesmere" and ell.accent == "follow"
          and roles.window ~= nil and roles.window.kind == "strips" and is(roles.window.edgeColor, 1, 1, 1, 0.10)
          and roles.pane ~= nil and roles.pane.kind == "strips" and is(roles.pane.edgeColor, 1, 1, 1, 0.05)
          and clockRole.kind == "strips" and clockRole.fill == "bg" and is(clockRole.edgeColor, 1, 1, 1, 0.10)
          and type(clockRole.barFill) == "table" and clockRole.barFill.ref == "accent"
          and near(clockRole.barFill.a, 0.75),
        type(whyV) == "table" and table.concat(whyV, "; ") or tostring(whyV))

    -- 2 + 3. the clone, its pre-blended tokens, and Flat back byte-identical
    local pre = Paint()
    local okE = UI.SetStyle and UI.SetStyle("ellesmere")
    local label, muted = UI.TEXT.label.hex, UI.TEXT.muted.hex
    check("the clone's label is white at 0.53 and muted white at 0.41, pre-blended into hex over bg (X5)",
        okE == true and is(P.bg, PANEL[1], PANEL[2], PANEL[3], 0.96)
          and label == Blend(0.53, PANEL) and label == "|cff8d9092" and muted == Blend(0.41, PANEL)
          and UI.TEXT.text2 == UI.TEXT.label and UI.TEXT.text.hex == "|cffffffff",
        string.format("label %s (want %s), muted %s (want %s)", tostring(label), Blend(0.53, PANEL),
            tostring(muted), Blend(0.41, PANEL)))
    local face, size, flags, num = Face()
    local cloneOk = okE == true and UI.STYLE == "ellesmere" and near(UI.accent[1], HOUSE[1])
        and near(UI.accent[2], HOUSE[2]) and near(UI.accent[3], HOUSE[3])
        and is(P.pane, PANEL[1], PANEL[2], PANEL[3], 1) and is(P.hover, 1, 1, 1, 0.08) and is(P.selected, 1, 1, 1, 0.04)
        and is(P.check, HOUSE[1], HOUSE[2], HOUSE[3], 0.75) and is(P.track, 1, 1, 1, 0.10)
        and is(P.thumb, 1, 1, 1, 0.25)
        and face == "Fonts\\ARIALN.TTF" and num == "Fonts\\ARIALN.TTF" and size == 13 and flags == ""
        and bodyFont.shadowX == 1 and bodyFont.shadowY == -1
        and NavStrips(0.10) and is(nav.frame.bg, PANEL[1], PANEL[2], PANEL[3], 0.96)
        and is(btn.bg, 0.061, 0.095, 0.12, 0.6) and is(btn.border, 1, 1, 1, 0.30)
        and clock ~= nil and is(clock.bg, PANEL[1], PANEL[2], PANEL[3], 0.96)
        and E ~= nil and E.Following ~= nil and E.Following() == nil
    local dumpClone = DumpLine()
    local okF = UI.SetStyle and UI.SetStyle("flat")
    local back = Paint()
    local same = #back == #pre
    local firstBad
    for i, s in ipairs(pre) do
        local b = back[i]
        if not b or #b.lines ~= #s.lines then
            same = false
            firstBad = firstBad or s.name
        else
            for k = 1, #s.lines do
                if s.lines[k] ~= b.lines[k] then
                    same = false
                    firstBad = firstBad or (s.name .. " line " .. k .. ": " .. b.lines[k])
                    break
                end
            end
        end
    end
    check("without S the clone on this flavour (" .. (flavour == "forever" and "bronze" or "teal")
          .. " accent, the house panel, Arial Narrow, strips edges); Flat back is byte-identical",
        cloneOk and dumpClone == "style: ellesmere (accent style) fell back: none" and okF == true and same,
        string.format("clone %s, accent %s, face %s, dump %s; %s", tostring(cloneOk), C(UI.accent), tostring(face),
            tostring(dumpClone), tostring(firstBad)))

    -- 4. a skin facade (apiVersion 2) there before the style is applied (the
    -- other order of X4): its getters; EUI_SKIN_READY then repaints nothing
    local ACC = { 0.2, 0.4, 0.9 }
    local PAN = { 0.10, 0.10, 0.12, 0.9 }
    local S2 = FakeSkin(2, ACC, PAN, EXPRESSWAY, "OUTLINE")
    MD.EUISkin = S2
    local whileFlat = Fired(function() MD:Fire("EUI_SKIN_READY") end)
    local nSet = Fired(function() if UI.SetStyle then UI.SetStyle("ellesmere") end end)
    local fface, _, fflags, fnum = Face()
    local readyAfter = Fired(function() MD:Fire("EUI_SKIN_READY") end)
    local dumpSkin = DumpLine()
    check("with a fake S (apiVersion 2) the accent, panel and font come from its getters; the dump says it follows",
        whileFlat == 0 and nSet == 1 and UI.STYLE == "ellesmere" and S2.reads > 0
          and near(UI.accent[1], 0.2) and near(UI.accent[2], 0.4) and near(UI.accent[3], 0.9)
          and is(P.bg, 0.10, 0.10, 0.12, 0.96) and is(P.pane, 0.10, 0.10, 0.12, 1)
          and is(P.nav, 0.09, 0.09, 0.108, 1) and UI.TEXT.label.hex == Blend(0.53, PAN)
          and fface == EXPRESSWAY and fnum == EXPRESSWAY and fflags == "OUTLINE" and bodyFont.shadowX == 0
          and is(nav.frame.bg, 0.10, 0.10, 0.12, 0.96) and is(P.check, 0.2, 0.4, 0.9, 0.75)
          and E ~= nil and E.Following() == "skin" and readyAfter == 0
          and dumpSkin == "style: ellesmere (accent style) fell back: none; follows EllesmereUI (skin apiVersion 2)",
        string.format("flat %d, set %d, ready %d, accent %s, face %s %s, dump %s", whileFlat, nSet, readyAfter,
            C(UI.accent), tostring(fface), tostring(fflags), tostring(dumpSkin)))

    -- 5. a looks change repaints once (and does nothing under another style)
    ACC[1], ACC[2], ACC[3] = 0.8, 0.2, 0.4
    local nLooks, keyLooks = Fired(function() MD:Fire("EUI_LOOKS_CHANGED") end)
    local looksOk = nLooks == 1 and keyLooks == "ellesmere" and near(UI.accent[1], 0.8) and near(UI.accent[2], 0.2)
        and is(P.check, 0.8, 0.2, 0.4, 0.75) and UI.TEXT.accent.hex == "|cffcc3366"
        and is(nav.frame.bg, 0.10, 0.10, 0.12, 0.96)
    if UI.SetStyle then UI.SetStyle("flat") end
    local nFlat = Fired(function() MD:Fire("EUI_LOOKS_CHANGED") end)
    check("a looks change (EUI_LOOKS_CHANGED) repaints once with the new accent; under Flat it does nothing",
        looksOk and nFlat == 0 and UI.STYLE == "flat",
        string.format("%d then %d fired, accent %s", nLooks, nFlat, C(UI.accent)))

    -- 6. X4: S arriving after the style was applied repaints once
    MD.EUISkin = nil
    if UI.SetStyle then UI.SetStyle("ellesmere") end
    local wasClone = near(UI.accent[1], HOUSE[1]) and near(UI.accent[2], HOUSE[2])
    local S3 = FakeSkin(2, { 0.5, 0.5, 1 }, { 0.2, 0.1, 0.1, 1 }, EXPRESSWAY, "")
    MD.EUISkin = S3
    local nReady, keyReady = Fired(function() MD:Fire("EUI_SKIN_READY") end)
    local followed = near(UI.accent[1], 0.5) and near(UI.accent[3], 1) and is(P.bg, 0.2, 0.1, 0.1, 0.96)
        and is(nav.frame.bg, 0.2, 0.1, 0.1, 0.96)
    local nAgain = Fired(function() MD:Fire("EUI_SKIN_READY") end)
    check("S arriving after SetStyle (EUI_SKIN_READY) repaints once, with its getters; a second ready repaints nothing",
        wasClone and nReady == 1 and keyReady == "ellesmere" and followed and nAgain == 0,
        string.format("clone first %s, %d then %d fired, accent %s", tostring(wasClone), nReady, nAgain,
            C(UI.accent)))

    -- 7. apiVersion 3: the getters unread, the clone, and the dump says why
    local S4 = FakeSkin(3, { 0.5, 0.5, 1 }, { 0.2, 0.1, 0.1, 1 }, EXPRESSWAY, "OUTLINE")
    MD.EUISkin = S4
    MD:Fire("EUI_SKIN_READY")
    local v3face = Face()
    local dump3 = DumpLine()
    check("apiVersion = 3 keeps the clone: its getters unread, the dump says 'skin apiVersion 3: not followed'",
        S4.reads == 0 and near(UI.accent[1], HOUSE[1]) and near(UI.accent[2], HOUSE[2])
          and near(UI.accent[3], HOUSE[3]) and is(P.bg, PANEL[1], PANEL[2], PANEL[3], 0.96)
          and v3face == "Fonts\\ARIALN.TTF" and E ~= nil and E.Following() == nil
          and dump3 == "style: ellesmere (accent style) fell back: none; skin apiVersion 3: not followed",
        string.format("%d reads, accent %s, dump %s", S4.reads, C(UI.accent), tostring(dump3)))

    -- 8. no skin facade: the parent's getters (accent, font), the house panel
    MD.EUISkin = nil
    local preads = 0
    MD.EUIParent = {
        GetAccentColor = function() preads = preads + 1; return 1, 0.5, 0.25 end,
        GetFontPath = function() preads = preads + 1; return EXPRESSWAY end,
    }
    if UI.SetStyle then UI.SetStyle("ellesmere") end
    local pface = Face()
    local parentOk = preads == 2 and near(UI.accent[1], 1) and near(UI.accent[2], 0.5) and near(UI.accent[3], 0.25)
        and is(P.bg, PANEL[1], PANEL[2], PANEL[3], 0.96) and pface == EXPRESSWAY
        and E ~= nil and E.Following() == "parent"
    MD.EUIParent = { GetAccentColor = function() return "teal" end, GetFontPath = function() error("gone") end }
    if UI.SetStyle then UI.SetStyle("ellesmere") end
    local badFace = Face()
    local junkOk = near(UI.accent[1], HOUSE[1]) and near(UI.accent[2], HOUSE[2]) and badFace == "Fonts\\ARIALN.TTF"
    MD.EUIParent = nil
    if UI.SetStyle then UI.SetStyle("flat") end
    check("without S the parent's getters give the accent and font; a getter that raises or answers junk gives the clone's",
        parentOk and junkOk and UI.STYLE == "flat",
        string.format("%d reads, face %s; junk accent %s face %s", preads, tostring(pface), C(UI.accent),
            tostring(badFace)))
end

T.done()
