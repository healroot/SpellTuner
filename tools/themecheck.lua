-- tools/run.sh tools/themecheck.lua
--
-- T29 (docs/SPEC-forever-ui.md 4.1-4.3, section 9's T29 row): the Forever theme --
-- UI/Theme_Forever.lua (the palette, UI.TEXT, the fonts, UI.ApplyFonts, the
-- font offset clamped to -2..+2, UI.Pitch, UI.PIXEL, UI.LIST_STRATA), the
-- additive half in UI/Style.lua (UI.px, StylizeFrame under UI.PIXEL and its
-- weak registry, UI.RestylePixels), MD.API.PhysicalScreenSize and the
-- db.ui defaults in Core_Forever.lua. The TBC TOC does not list the theme, and
-- tools/navui.lua / tools/dashui.lua hold TBC's look.
--
-- T69 (P25, docs/PLAN-refactor-ux.md, review A20): the colour tokens are always
-- present and one flag says whether the theme is on. Under tbc this suite loads
-- UI/Style.lua (and the files whose theme test it converted) without the theme
-- and holds: UI.THEMED false, TBC's tokens equal to the literals the shared
-- files carried, Review's small font GameFontHighlightSmall, every UI.Hex /
-- UI.RGB / UI.Fill token named in the tree present. Under forever: UI.THEMED
-- true, the legacy tokens mapped onto 4.1's, no gate on UI.TEXT left in a UI file.
--
-- T74 (P30, docs/PLAN-refactor-ux.md, review A20, U1, U3): the kit's primitives
-- read the palette and their edges are pixels. Under tbc (+1) a kit button, a
-- check box and an edit box paint the literals they always did, with today's
-- 1-unit edges, nothing registered. Under forever (+3) a button's edge is
-- UI.px(1) and registered; a nav frame's active group is the `selected` fill
-- with a 2-px accent bar on the left (its view tab's at the bottom), hover laid
-- over it, never the hover colour; UI.RestylePixels re-lays a button's edge and
-- its bar.
--
-- T75 (P31, docs/PLAN-refactor-ux.md, review U14, U26, U30, U31): the kit's
-- layout and sizes. Under tbc (+1) UI.H and the two Arial Narrow fonts are in
-- the kit, ungated. Under forever (+6) UI.H; the header title between the back
-- button and the x; a sheet's 20x20 x, with a title-row button laid left of
-- it; a check box's click area measured from its label when it shows; a
-- mask's optional line of text; the resize grip as three 1-px Line regions.
HARNESS_FLAVOUR = { "forever", "tbc" }

local here = arg[0]:match("^(.*)/[^/]+$")

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-72s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
end

local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua")
arg[0] = a0

local S = _G.STUB

local function near(a, b, eps) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < (eps or 1e-6) end

--------------------------------------------------------------------------------
-- T69 (P25): shared by both flavours -- the token shape, and scans of the tree
--------------------------------------------------------------------------------
local TOKENS = { "accent", "text", "text2", "label", "muted", "disabled", "mana", "good", "bad" }
-- TBC's disagreeing literals, each under a named legacy token (P25); the theme
-- maps each onto a 4.1 token. Unifying them is P34's question to the author.
local LEGACY = { dominated = "muted", note = "text2", tipGold = "accent" }

local function shaped(c)
    return type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number"
        and type(c[3]) == "number" and type(c.hex) == "string" and c.hex:match("^|cff%x%x%x%x%x%x$") ~= nil
end

-- every shipped Lua file under UI/ and the module folders
local function UIFiles()
    local out = {}
    local p = io.popen("cd '" .. (S.root or ".") .. "' && ls UI/*.lua Modules/*/*.lua Modules/*/*/*.lua 2>/dev/null")
    for line in p:lines() do out[#out + 1] = line end
    p:close()
    return out
end
local function Read(rel)
    local f = io.open((S.root or ".") .. "/" .. rel, "r")
    if not f then return "" end
    local s = f:read("*a"); f:close()
    return s
end

-- every UI.Hex("x") / UI.RGB("x") / UI.Fill("x") literal in the tree names a
-- token the current tables carry (a typo would paint white, silently)
local function TokenScan(UI)
    local missing, seen = {}, 0
    for _, rel in ipairs(UIFiles()) do
        for fn, tok in Read(rel):gmatch("UI%.(%a+)%(\"([%w_]+)\"%)") do
            if fn == "Hex" or fn == "RGB" then
                seen = seen + 1
                if not shaped(UI.TEXT[tok]) then missing[#missing + 1] = rel .. ":" .. fn .. ":" .. tok end
            elseif fn == "Fill" then
                seen = seen + 1
                if type(UI.PALETTE[tok]) ~= "table" then missing[#missing + 1] = rel .. ":Fill:" .. tok end
            end
        end
    end
    return missing, seen
end

if S.flavour == "tbc" then
    ----------------------------------------------------------------------------
    -- T69 (P25), TBC: the kit without the theme -- the flag off, the old literals
    ----------------------------------------------------------------------------
    local FrameMT = getmetatable(CreateFrame("Frame"))
    local makeFS = FrameMT.CreateFontString
    FrameMT.CreateFontString = function(self, name, layer, template)
        local fs = makeFS(self, name, layer, template)
        fs.template = template
        return fs
    end
    S.Load({ "UI/Style.lua", "UI/Tip.lua", "UI/Tip_TBC.lua", "UI/Dashboard_Review.lua" }, "SpellTuner", MD)
    local UI = MD.UI

    check("tbc: UI.THEMED is false with UI/Style.lua alone", UI.THEMED == false, tostring(UI.THEMED))

    local T = UI.TEXT or {}
    local all = true
    for _, k in ipairs(TOKENS) do if not shaped(T[k]) then all = false end end
    for k in pairs(LEGACY) do if not shaped(T[k]) then all = false end end
    check("tbc: UI.TEXT is present, every 4.1 and legacy token shaped", all)

    local function hex(k) return shaped(T[k]) and T[k].hex:lower() or tostring(T[k] and T[k].hex) end
    check("tbc: the tokens hold the literals the shared files carried",
        all and hex("accent") == "|cffffcc00" and hex("text") == "|cffffffff" and hex("muted") == "|cff888888"
          and hex("disabled") == "|cff555555" and hex("dominated") == "|cff8a8a8a" and hex("note") == "|cffffcc00"
          and near(T.accent[1], 1) and near(T.accent[2], 0.8) and near(T.accent[3], 0)
          and near(T.tipGold[1], 1) and near(T.tipGold[2], 0.82) and near(T.tipGold[3], 0),
        "accent=" .. hex("accent") .. " muted=" .. hex("muted") .. " disabled=" .. hex("disabled")
          .. " dominated=" .. hex("dominated") .. " note=" .. hex("note"))
    check("tbc: UI.Hex / UI.RGB / UI.Fill read the tokens",
        all and UI.Hex and UI.Hex("muted") == T.muted.hex and UI.RGB and select(2, UI.RGB("tipGold")) == T.tipGold[2]
          and UI.Fill and near(select(4, UI.Fill("selected")), 0.28))

    local P = UI.PALETTE or {}
    local A = UI.accent
    local function is(c, r, g, b, a) return type(c) == "table" and near(c[1], r, 0.002) and near(c[2], g, 0.002)
        and near(c[3], b, 0.002) and near(c[4], a, 0.002) end
    check("tbc: the palette keeps its window fills and carries the table's old ones",
        is(P.frame, 0.1, 0.1, 0.1, 0.9) and is(P.header, 0.115, 0.115, 0.115, 1) and is(P.pane, 0.13, 0.13, 0.13, 1)
          and is(P.border, 0, 0, 0, 1) and is(P.rowAlt, 1, 1, 1, 0.03) and is(P.line, 42 / 255, 42 / 255, 42 / 255, 1)
          and is(P.hover, A[1], A[2], A[3], 0.12) and is(P.selected, A[1], A[2], A[3], 0.28)
          and is(P.suggested, A[1], A[2], A[3], 0.10))

    -- Review's small text: the kit's font under the theme only
    local parent = CreateFrame("Frame")
    parent:SetSize(760, 420)
    local small, kit = 0, 0
    local before = #S.allFrames
    MD.DashboardParts.CreateReview(parent, 760)
    for i = before + 1, #S.allFrames do
        local f = S.allFrames[i]
        if f.kind == "FontString" and f.template == "GameFontHighlightSmall" then small = small + 1 end
        if f.kind == "FontString" and f.template == UI.FONT_SMALL then kit = kit + 1 end
    end
    check("tbc: Review's small text is GameFontHighlightSmall, never the kit's",
        small >= 3 and kit == 0, small .. " GameFontHighlightSmall, " .. kit .. " UI.FONT_SMALL")

    local missing, seen = TokenScan(UI)
    check("tbc: every UI.Hex / UI.RGB / UI.Fill token in the tree is in TBC's tables",
        seen > 0 and #missing == 0, #missing > 0 and table.concat(missing, " ") or (seen .. " reads"))

    -- T74 (P30): the primitives read tokens that hold their old literals
    local host = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    local ah = UI.CreateButton(host, "Go", "accent-hover", { 60, 20 })
    local red = UI.CreateButton(host, "x", "red", { 20, 20 })
    local plain = UI.CreateButton(host, "Plain", nil, { 60, 20 })
    local cb = UI.CreateCheckButton(host, "Tick")
    local eb = UI.CreateEditBox(host, 60, 20)
    local bd, cbd = ah.backdrop or {}, cb.backdrop or {}
    local function same(c, r, g, b, a) return type(c) == "table" and near(c[1], r) and near(c[2], g)
        and near(c[3], b) and near(c[4], a) end
    local regs = 0
    for fr in pairs(UI.pixelFrames or {}) do
        if fr == ah or fr == cb or fr == eb then regs = regs + 1 end
    end
    if cb.GetScript and cb:GetScript("OnDisable") then cb:GetScript("OnDisable")(cb) end
    local offLabel = cb.label and cb.label.textColor
    check("tbc: a kit button, check box and edit box paint the old literals, 1-unit edges",
        same(ah.color, 0.115, 0.115, 0.115, 1) and same(ah.hoverColor, A[1], A[2], A[3], 0.6)
          and same(ah.bg, 0.115, 0.115, 0.115, 1) and same(ah.border, 0, 0, 0, 1)
          and same(red.color, 0.6, 0.1, 0.1, 0.6) and same(red.hoverColor, 0.6, 0.1, 0.1, 1)
          and same(plain.color, 0.115, 0.115, 0.115, 1) and same(plain.hoverColor, 0.23, 0.23, 0.23, 1)
          and bd.edgeSize == 1 and type(bd.insets) == "table" and bd.insets.left == 1
          and cbd.edgeSize == 1 and cbd.insets == nil and same(cb.bg, 0.115, 0.115, 0.115, 0.9)
          and same(eb.bg, 0.115, 0.115, 0.115, 0.9) and regs == 0 and ah.selBar == nil
          and offLabel and near(offLabel[1], 0.4) and near(offLabel[3], 0.4),
        string.format("button %s/%s edge %s, check edge %s, %d registered", tostring(ah.color and ah.color[1]),
            tostring(ah.hoverColor and ah.hoverColor[4]), tostring(bd.edgeSize), tostring(cbd.edgeSize), regs))

    -- T75 (P31, review U26): the size scale and the two number fonts are the
    -- kit's, ungated (additive: no TBC caller reads them)
    local H = UI.H or {}
    local function face(name)
        local o = name and UI.fontObjects and UI.fontObjects[name]
        if not o then return nil end
        return o:GetFont()
    end
    local np, ns = face(UI.FONT_NUM)
    local sp, ss = face(UI.FONT_NUM_SMALL)
    check("tbc: T75: UI.H and the two Arial Narrow fonts are in the kit",
        H.button == 20 and H.small == 18 and H.row == 20 and H.toolbar == 22
          and np == "Fonts\\ARIALN.TTF" and ns == 13 and sp == "Fonts\\ARIALN.TTF" and ss == 11,
        string.format("H %s/%s/%s/%s, num %s %s, small %s %s", tostring(H.button), tostring(H.small),
            tostring(H.row), tostring(H.toolbar), tostring(np), tostring(ns), tostring(sp), tostring(ss)))

    print(string.format("%d ok, %d failed", ok, #fails))
    os.exit(#fails > 0 and 1 or 0)
end

local UI = MD.UI

--------------------------------------------------------------------------------
-- 1. The theme is on the Forever TOCs, right after UI/Style.lua, and not on TBC's
--------------------------------------------------------------------------------
do
    local function after(toc)
        local files = S.TocFiles(toc)
        for i, f in ipairs(files) do
            if f == "UI/Theme_Forever.lua" then return files[i - 1] == "UI/Style.lua" end
        end
        return false
    end
    local inTbc = false
    for _, f in ipairs(S.TocFiles("SpellTuner_TBC.toc")) do
        if f:find("Theme_Forever", 1, true) then inTbc = true end
    end
    check("the theme follows UI/Style.lua in both Forever TOCs and not in TBC's",
        after("SpellTuner_Mainline.toc") and after("SpellTuner.toc") and not inTbc)
end

--------------------------------------------------------------------------------
-- 2. UI.TEXT: every token of 4.1, each { r, g, b, hex = "|cffrrggbb" }, no gold
--------------------------------------------------------------------------------
do
    local T = UI.TEXT
    local all, shaped = type(T) == "table", true
    for _, k in ipairs(TOKENS) do
        local c = all and T[k]
        if type(c) ~= "table" then all = false
        elseif not (type(c[1]) == "number" and type(c[2]) == "number" and type(c[3]) == "number"
                    and type(c.hex) == "string" and c.hex:match("^|cff%x%x%x%x%x%x$")) then
            shaped = false
        end
    end
    check("UI.TEXT carries every text token of 4.1", all)
    check("each UI.TEXT token is r, g, b plus an ASCII |cffrrggbb hex", all and shaped)

    local gold = false
    for k, c in pairs(type(T) == "table" and T or {}) do
        if type(c) == "table" then
            local hex = type(c.hex) == "string" and c.hex:lower() or ""
            if hex:find("ffcc00", 1, true) or hex:find("ffd100", 1, true) then gold = k end
            if near(c[1], 1, 0.01) and near(c[2], 0.82, 0.01) and near(c[3], 0, 0.01) then gold = k end
            if near(c[1], 1, 0.01) and near(c[2], 0.8, 0.01) and near(c[3], 0, 0.01) then gold = k end
        end
    end
    check("Blizzard gold is absent from UI.TEXT", all and gold == false, gold and ("token " .. tostring(gold)) or nil)

    local a = all and T.accent
    check("UI.TEXT.accent is the class colour (druid ff7c0a, as 4.1)",
        a and near(a[1], UI.accent[1]) and near(a[2], UI.accent[2]) and near(a[3], UI.accent[3])
          and a.hex:lower() == "|cffff7c0a",
        a and a.hex or nil)
    check("the text tokens' values (text2 b3b3b3, muted 7a7a7a, mana 4d99ff, bad e0605a)",
        all and T.text.hex:lower() == "|cffffffff" and T.text2.hex:lower() == "|cffb3b3b3"
          and T.label.hex:lower() == "|cff9d9d9d" and T.muted.hex:lower() == "|cff7a7a7a"
          and T.disabled.hex:lower() == "|cff4d4d4d" and T.mana.hex:lower() == "|cff4d99ff"
          and T.good.hex:lower() == "|cff5ccb6e" and T.bad.hex:lower() == "|cffe0605a")
end

--------------------------------------------------------------------------------
-- 2b. T69 (P25): one flag, the legacy tokens on 4.1's, no gate left on UI.TEXT
--------------------------------------------------------------------------------
check("forever: the theme sets UI.THEMED", UI.THEMED == true, tostring(UI.THEMED))
do
    local T = UI.TEXT or {}
    local same = true
    for k, to in pairs(LEGACY) do
        local a, b = T[k], T[to]
        if not (shaped(a) and shaped(b) and a.hex == b.hex and near(a[1], b[1]) and near(a[2], b[2])
                and near(a[3], b[3])) then same = false end
    end
    check("forever: dominated, note and tipGold read muted, text2 and accent", same)
    check("forever: UI.Hex / UI.RGB / UI.Fill read the theme",
        UI.Hex and UI.Hex("muted") == "|cff7a7a7a" and UI.RGB and near(select(3, UI.RGB("mana")), 1)
          and UI.Fill and near(select(4, UI.Fill("hover")), 0.12))

    -- a token read is a colour, never a gate (plan section 2): no file under UI/
    -- or the modules tests UI.TEXT to decide anything
    local gates = {}
    for _, rel in ipairs(UIFiles()) do
        local n = 0
        for line in (Read(rel) .. "\n"):gmatch("([^\n]*)\n") do
            n = n + 1
            local code = line:gsub("%-%-.*$", "")
            if code:find("UI%.TEXT and") or code:find("UI%.TEXT ~= nil") or code:find("UI%.TEXT == nil")
               or code:find("if UI%.TEXT then") or code:find("not UI%.TEXT") or code:find("UI%.TEXT or") then
                gates[#gates + 1] = rel .. ":" .. n
            end
        end
    end
    check("forever: no UI file gates on UI.TEXT (UI.THEMED is the switch)", #gates == 0,
        #gates > 0 and table.concat(gates, " ") or nil)

    local missing, seen = TokenScan(UI)
    check("forever: every UI.Hex / UI.RGB / UI.Fill token in the tree is in the theme's tables",
        seen > 0 and #missing == 0, #missing > 0 and table.concat(missing, " ") or (seen .. " reads"))
end

--------------------------------------------------------------------------------
-- 3. UI.PALETTE: the 4.1 fills, the kit's own keys following them
--------------------------------------------------------------------------------
do
    local P = UI.PALETTE
    local function is(c, r, g, b, a) return type(c) == "table" and near(c[1], r, 0.002) and near(c[2], g, 0.002)
        and near(c[3], b, 0.002) and near(c[4], a, 0.002) end
    local A = UI.accent
    check("UI.PALETTE holds 4.1's fills (bg 0.96, pane, nav, line, rowAlt, mask, border)",
        is(P.bg, 22 / 255, 22 / 255, 22 / 255, 0.96) and is(P.pane, 28 / 255, 28 / 255, 28 / 255, 1)
        and is(P.nav, 0.115, 0.115, 0.115, 1) and is(P.line, 42 / 255, 42 / 255, 42 / 255, 1)
        and is(P.rowAlt, 1, 1, 1, 0.03) and is(P.mask, 38 / 255, 38 / 255, 38 / 255, 0.7)
        and is(P.border, 0, 0, 0, 1))
    check("the accent fills: rule 0.6, hover 0.12, selected 0.28, suggested 0.10; close as Cell",
        is(P.rule, A[1], A[2], A[3], 0.6) and is(P.hover, A[1], A[2], A[3], 0.12)
        and is(P.selected, A[1], A[2], A[3], 0.28) and is(P.suggested, A[1], A[2], A[3], 0.10)
        and is(P.close, 0.6, 0.1, 0.1, 0.6) and is(P.closeHover, 0.6, 0.1, 0.1, 1))
    check("the kit's window and header keys follow bg and nav",
        is(P.frame, 22 / 255, 22 / 255, 22 / 255, 0.96) and is(P.header, 0.115, 0.115, 0.115, 1))
end

--------------------------------------------------------------------------------
-- 4. Fonts: built once, Friz for text, Arial Narrow for numbers, 4.2's sizes
--------------------------------------------------------------------------------
local function font(name)
    local o = UI.fontObjects and UI.fontObjects[name]
    if not o then return nil end
    local path, size, flags = o:GetFont()
    return path, size, flags
end
local FRIZ = (GameFontNormal:GetFont())
do
    local want = {
        { "FONT_TITLE", 14, FRIZ }, { "FONT_HEAD", 16, FRIZ }, { "FONT_BIG", 18, FRIZ },
        { "FONT", 13, FRIZ }, { "FONT_SMALL", 11, FRIZ },
        { "FONT_NUM", 13, "Fonts\\ARIALN.TTF" }, { "FONT_NUM_SMALL", 11, "Fonts\\ARIALN.TTF" },
    }
    local bad = {}
    for _, w in ipairs(want) do
        local name = UI[w[1]]
        local path, size, flags = font(name or "?")
        if type(name) ~= "string" or path ~= w[3] or size ~= w[2] or flags ~= "" then
            bad[#bad + 1] = w[1] .. "=" .. tostring(path) .. "/" .. tostring(size)
        end
    end
    check("the fonts of 4.2 are built with their faces and sizes, no outline", #bad == 0,
        #bad > 0 and table.concat(bad, " ") or nil)
end

--------------------------------------------------------------------------------
-- 5. The font offset: clamped to -2..+2, every font follows, pitches grow with it
--------------------------------------------------------------------------------
do
    local got = UI.ApplyFonts and UI.ApplyFonts(4)
    local _, head = font(UI.FONT_HEAD or "?")
    local _, num = font(UI.FONT_NUM or "?")
    local _, cls = font(UI.FONT_CLASS or "?")
    check("an offset of +4 is clamped to +2 and every font grows by 2",
        got == 2 and head == 18 and num == 15 and cls == 15,
        string.format("got=%s head=%s num=%s class=%s", tostring(got), tostring(head), tostring(num), tostring(cls)))
    local p2 = UI.Pitch and UI.Pitch(20)
    local lo = UI.ApplyFonts and UI.ApplyFonts(-9)
    local pm2 = UI.Pitch and UI.Pitch(20)
    local _, small = font(UI.FONT_SMALL or "?")
    local zero = UI.ApplyFonts and UI.ApplyFonts(0)
    local p0 = UI.Pitch and UI.Pitch(20)
    check("UI.Pitch(20) is 20 at -2, 20 at 0 and 22 at +2",
        p2 == 22 and pm2 == 20 and p0 == 20 and lo == -2 and small == 9 and zero == 0,
        string.format("+2:%s -2:%s 0:%s small@-2=%s", tostring(p2), tostring(pm2), tostring(p0), tostring(small)))
end

--------------------------------------------------------------------------------
-- 6. db.ui: the defaults, and a saved +4 clamped at login and written back
--------------------------------------------------------------------------------
do
    local u = MD.db and MD.db.ui
    check("db.ui defaults: fontOffset 0, scale 1, combat hide, escStack on, win {}",
        type(u) == "table" and u.fontOffset == 0 and u.scale == 1 and u.combat == "hide"
          and u.escStack == true and type(u.win) == "table")
    if type(u) == "table" then
        u.fontOffset = 4
        MD:Fire("CORE_LOGIN")
    end
    local _, size = font(UI.FONT or "?")
    check("a saved offset of +4 comes back +2 at login, applied to the fonts",
        type(u) == "table" and u.fontOffset == 2 and size == 15 and UI.Pitch and UI.Pitch(20) == 22,
        string.format("saved=%s FONT=%s", tostring(u and u.fontOffset), tostring(size)))
    if type(u) == "table" then u.fontOffset = 0 end
    if UI.ApplyFonts then UI.ApplyFonts(0) end
end

--------------------------------------------------------------------------------
-- 7. UI.PIXEL, UI.LIST_STRATA, MD.API.PhysicalScreenSize
--------------------------------------------------------------------------------
check("the theme sets UI.PIXEL and UI.LIST_STRATA = FULLSCREEN_DIALOG",
    UI.PIXEL == true and UI.LIST_STRATA == "FULLSCREEN_DIALOG")
do
    local w, h = nil, nil
    if MD.API.PhysicalScreenSize then w, h = MD.API.PhysicalScreenSize() end
    check("MD.API.PhysicalScreenSize answers the physical screen through the adapter",
        w == 1920 and h == 1080, tostring(w) .. "x" .. tostring(h))
end

--------------------------------------------------------------------------------
-- 8. UI.px at effective scales 0.64 / 0.71 / 1 on a 1080-line screen
--------------------------------------------------------------------------------
local function scaled(s)
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f.GetEffectiveScale = function() return s end
    return f
end
do
    local bad = {}
    for _, s in ipairs({ 0.64, 0.71, 1 }) do
        local want = (768 / 1080) / s
        local got = UI.px and UI.px(1, scaled(s))
        if not near(got, want) then bad[#bad + 1] = s .. ":" .. tostring(got) end
        local got3 = UI.px and UI.px(3, scaled(s))
        if not near(got3, 3 * want) then bad[#bad + 1] = s .. "x3:" .. tostring(got3) end
    end
    check("UI.px(n, frame) = n * 768 / physicalHeight / effective scale at 0.64, 0.71 and 1",
        #bad == 0, #bad > 0 and table.concat(bad, " ") or nil)

    local saved = S.physicalHeight
    S.physicalHeight = 0
    local zero = UI.px and UI.px(1, scaled(0.71))
    S.physicalHeight = saved
    check("UI.px with no usable screen height is n itself", zero == 1, tostring(zero))
end

--------------------------------------------------------------------------------
-- 9. StylizeFrame under UI.PIXEL: a px edge and insets, recorded; RestylePixels
--------------------------------------------------------------------------------
do
    local f = scaled(0.71)
    UI.StylizeFrame(f, { 0.2, 0.3, 0.4, 0.5 }, { 0, 0, 0, 1 })
    local e = (768 / 1080) / 0.71
    local bd = f.backdrop or {}
    check("StylizeFrame under UI.PIXEL uses UI.px(1) for the edge and the insets",
        near(bd.edgeSize, e) and type(bd.insets) == "table" and near(bd.insets.left, e)
          and near(bd.insets.right, e) and near(bd.insets.top, e) and near(bd.insets.bottom, e),
        tostring(bd.edgeSize))
    local mode = UI.pixelFrames and getmetatable(UI.pixelFrames) and getmetatable(UI.pixelFrames).__mode
    check("the styled frame is in a weak-keyed registry",
        UI.pixelFrames ~= nil and UI.pixelFrames[f] ~= nil and mode == "k")

    -- A hover recoloured it after styling: a restyle keeps the colour it has now.
    f:SetBackdropColor(0.9, 0.1, 0.1, 1)
    f.GetEffectiveScale = function() return 1 end
    S.physicalHeight = 1440
    local n = UI.RestylePixels and UI.RestylePixels()
    local e2 = 768 / 1440
    local bd2 = f.backdrop or {}
    check("UI.RestylePixels re-applies a new edge and insets to a registered frame",
        type(n) == "number" and n >= 1 and near(bd2.edgeSize, e2) and type(bd2.insets) == "table"
          and near(bd2.insets.left, e2), tostring(bd2.edgeSize))
    check("a restyle keeps the frame's current fill and border colours",
        type(n) == "number" and f.bg and near(f.bg[1], 0.9) and near(f.bg[4], 1) and f.border and near(f.border[4], 1))
    S.physicalHeight = 1080

    -- The TBC path: without UI.PIXEL today's backdrop, and nothing recorded.
    UI.PIXEL = nil
    local g = scaled(0.71)
    UI.StylizeFrame(g)
    local bg = g.backdrop or {}
    UI.PIXEL = true
    check("without UI.PIXEL StylizeFrame is today's 1-unit edge and records nothing",
        bg.edgeSize == 1 and bg.insets == nil and (UI.pixelFrames == nil or UI.pixelFrames[g] == nil))
end

--------------------------------------------------------------------------------
-- 10. T74 (P30, review A20, U1, U3): the primitives' pixel edges and the one
-- selection language
--------------------------------------------------------------------------------
do
    local e = (768 / 1080) / 0.71
    local host = scaled(0.71)
    local b = UI.CreateButton(host, "Go", "accent-hover", { 60, 20 })
    b.GetEffectiveScale = function() return 0.71 end
    -- styled when made: the stub's frames all answer scale 1, so restyle once at 0.71
    if UI.RestylePixels then UI.RestylePixels() end
    local bd = b.backdrop or {}
    check("T74: a kit button's edge and insets are UI.px(1), registered for restyling",
        near(bd.edgeSize, e) and type(bd.insets) == "table" and near(bd.insets.left, e)
          and near(bd.insets.bottom, e) and UI.pixelFrames[b] ~= nil
          and near(b.bg and b.bg[1], 0.115) and near(b.border and b.border[4], 1),
        tostring(bd.edgeSize))

    -- a nav frame: the active group is selected + a left bar, hover laid over
    local groups = {
        { id = "a", text = "Spells", views = { { id = "one", text = "One" }, { id = "two", text = "Two" } } },
        { id = "b", text = "Reports", views = { { id = "three", text = "Three" } } },
    }
    local nav = UI.CreateNavFrame("SpellTuner", "MDThemeNavTest", 700, 400, groups,
        function(_, _, content) return CreateFrame("Frame", nil, content) end)
    nav:Select("a", "one")
    local act, other = nav.buttons[1], nav.buttons[2]
    local tab = nav.viewButtons[1]
    local P, A = UI.PALETTE, UI.accent
    local function fill(f) return f and f.bg end
    local sel = P.selected
    local actFill = fill(act)
    local barOk = act.selBar and act.selBar:IsShown() and act.selBar.side == "left"
        and near(act.selBar.w, UI.px(2, act)) and act.selBar.color and near(act.selBar.color[1], A[1])
        and not (other.selBar and other.selBar:IsShown())
    local tabOk = tab and tab.selBar and tab.selBar:IsShown() and tab.selBar.side == "bottom"
        and near(tab.selBar.h, UI.px(2, tab)) and near(fill(tab) and fill(tab)[4], sel[4])
    -- hover on the inactive group: the hover layer, the fill stays its own
    local enter, leave = other:GetScript("OnEnter"), other:GetScript("OnLeave")
    if enter then enter(other) end
    local otherHover = other.selHover and other.selHover:IsShown()
        and near(fill(other) and fill(other)[4], other.color[4])
    if leave then leave(other) end
    local otherLeft = other.selHover and not other.selHover:IsShown()
    -- hover kept on the active one: scripts there, the fill stays selected
    local aEnter = act:GetScript("OnEnter")
    if aEnter then aEnter(act) end
    local activeHover = aEnter ~= nil and act.selHover and act.selHover:IsShown()
        and near(fill(act) and fill(act)[4], sel[4])
    if act:GetScript("OnLeave") then act:GetScript("OnLeave")(act) end
    check("T74: the active nav group is selected + a 2-px left bar, never the hover fill",
        actFill and near(actFill[1], sel[1]) and near(actFill[4], sel[4]) and not near(actFill[4], 0.6)
          and barOk and tabOk and otherHover and otherLeft and activeHover,
        string.format("fill %s, bar %s, tab %s, hover other %s / active %s", tostring(actFill and actFill[4]),
            tostring(barOk), tostring(tabOk), tostring(otherHover), tostring(activeHover)))

    -- a UI scale change: RestylePixels re-lays the button's edge and the bar
    act.GetEffectiveScale = function() return 1 end
    S.physicalHeight = 1440
    local n = UI.RestylePixels and UI.RestylePixels()
    local e2 = 768 / 1440
    local abd = act.backdrop or {}
    check("T74: UI.RestylePixels re-lays a kit button's edge and its selection bar",
        type(n) == "number" and near(abd.edgeSize, e2) and near(abd.insets and abd.insets.left, e2)
          and near(act.selBar and act.selBar.w, 2 * e2) and near(fill(act) and fill(act)[4], sel[4]),
        string.format("edge %s, bar %s", tostring(abd.edgeSize), tostring(act.selBar and act.selBar.w)))
    S.physicalHeight = 1080
end

--------------------------------------------------------------------------------
-- 11. T75 (P31, review U14, U26, U30, U31): the kit's layout and sizes under
-- the theme -- the size scale, the header title between the back button and
-- the x, a sheet's x, a check box's click area measured from its label, a
-- mask's line of text. The stub's opt-in geometry records the points.
--------------------------------------------------------------------------------
do
    local H = UI.H or {}
    check("T75: UI.H is the kit's size scale (button 20, small 18, row 20, toolbar 22)",
        H.button == 20 and H.small == 18 and H.row == 20 and H.toolbar == 22,
        string.format("%s/%s/%s/%s", tostring(H.button), tostring(H.small), tostring(H.row), tostring(H.toolbar)))

    S.Geometry(true)
    local function pt(f, i)
        if not f or not f.GetNumPoints or f:GetNumPoints() < (i or 1) then return {} end
        return { f:GetPoint(i or 1) }
    end

    -- the header title: 24 clear of each edge with no back button, between
    -- the back button and the x once it shows
    local w = UI.CreateMovableFrame("SpellTuner", nil, 400, 300, nil, nil, true, { back = "< SpellTuner" })
    local h = w.header
    local function lay()
        local l, r = pt(h.text, 1), pt(h.text, 2)
        return l[1] == "LEFT" and l[2] == h and l[4], r[1] == "RIGHT" and r[2] == h.closeBtn and r[3] == "LEFT" and r[4]
    end
    local l0, r0 = lay()
    h.backBtn:Show()
    local l1, r1 = lay()
    h.backBtn:Hide()
    local l2 = lay()
    check("T75: the header title sits between the back button and the x",
        l0 == 24 and r0 == -4 and l1 == 88 and r1 == -4 and l2 == 24 and h.text:GetWordWrap() == false,
        string.format("left %s -> %s -> %s, right %s / %s", tostring(l0), tostring(l1), tostring(l2),
            tostring(r0), tostring(r1)))

    -- a sheet: the 20x20 x at the right of its title row, hiding it; a
    -- title-row button anchored to the sheet's top right goes left of the x
    local host = CreateFrame("Frame", nil, UIParent)
    local sheet = UI.CreateSheet(host, host, 300, 200, "T")
    local x = sheet.closeBtn
    local done = UI.CreateButton(sheet, "Done", "accent-hover", { 50, 18 })
    done:SetPoint("TOPRIGHT", sheet, "TOPRIGHT", -2, -2)
    local xp, dp = pt(x), pt(done)
    sheet:Show()
    local open = sheet:IsShown() and sheet.mask:IsShown()
    if x and x:GetScript("OnClick") then x:GetScript("OnClick")(x) end
    check("T75: a sheet has a 20x20 x that hides it; a title-row button goes left of it",
        x ~= nil and x:GetWidth() == 20 and x:GetHeight() == 20 and xp[1] == "TOPRIGHT" and xp[2] == sheet
          and dp[1] == "TOPRIGHT" and dp[2] == x and dp[3] == "TOPLEFT" and dp[4] == -2 and dp[5] == -2
          and open and not sheet:IsShown() and not sheet.mask:IsShown(),
        string.format("x %s, done -> %s %s", tostring(x ~= nil), tostring(dp[2] == x), tostring(dp[3])))

    -- a check box: its click area is the label's width, measured again when it shows
    local text = "Close one window per ESC"
    local cb = UI.CreateCheckButton(host, text)
    local hit
    cb.SetHitRectInsets = function(_, l, r, t, b) hit = { l, r, t, b } end
    cb.label.fontSize = 15 -- the font offset moved (+2) after the box was made
    cb:Hide(); cb:Show()
    local want = -(#text * 6 * 15 / 12) - 5
    check("T75: a check box's click area is measured from its label when it shows",
        type(cb.Measure) == "function" and hit ~= nil and near(hit[2], want) and hit[1] == 0,
        string.format("right inset %s, want %s", tostring(hit and hit[2]), tostring(want)))

    -- a mask with a line of text, and one without
    local m1 = UI.CreateMask(host, nil, "Coaching...")
    local m0 = UI.CreateMask(host)
    check("T75: a mask carries an optional line of text",
        m1.text ~= nil and m1.text:GetText() == "Coaching..." and m0.text == nil,
        tostring(m1.text and m1.text:GetText()))
    S.Geometry(false)

    -- the resize grip on the client's Line regions: the stub's frames make
    -- none, so this check lends them a recording CreateLine for one window
    local FM = getmetatable(UIParent)
    local had = rawget(FM, "CreateLine")
    FM.CreateLine = function(self)
        local l = self:CreateTexture()
        l.SetStartPoint = function(me, p, rel, x, y) me.from = { p, rel, x, y } end
        l.SetEndPoint = function(me, p, rel, x, y) me.to = { p, rel, x, y } end
        l.SetThickness = function(me, t) me.thickness = t end
        return l
    end
    local rw = UI.CreateMovableFrame("SpellTuner", nil, 400, 300, nil, nil, true, { resizable = true })
    FM.CreateLine = had
    local g = rw.resizeGrip
    local lines = g and g.lines or {}
    local good = #lines == 3
    for i, l in ipairs(lines) do
        local d = ({ 4, 8, 12 })[i]
        if l.kind ~= "line" or not near(l.thickness, UI.px(1, g)) or not l.from or not l.to
            or l.from[2] ~= g or l.from[3] ~= -d - 2 or l.from[4] ~= 2
            or l.to[3] ~= -2 or l.to[4] ~= d + 2 then good = false end
    end
    check("T75: the grip is three 1-px Line regions where the client makes them",
        good, string.format("%d lines, first %s", #lines, tostring(lines[1] and lines[1].kind)))
end

--------------------------------------------------------------------------------
print(string.format("%d ok, %d failed", ok, #fails))
if #fails > 0 then os.exit(1) end
