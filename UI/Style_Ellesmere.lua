-- T100 (docs/SPEC-next.md 5.1, 5.5, decision 5, risks X1 / X4 / X5;
-- R-styles.md 4.2, 3.7; R-ellesmere.md 2.2, 3.5): the Ellesmere style, with
-- its `clock` role. Listed by every main TOC right after UI/Styles.lua, which
-- it registers with. Paint only, like every style: fills, tokens, faces and
-- one recipe per role, never a size, an anchor or an inset.
--
-- Two ways to look like EllesmereUI:
--
--   * THE CLONE (everywhere, and always on TBC, where EllesmereUI refuses to
--     run): EllesmereUI 9.3.4's house values, copied -- the panel 0.05 / 0.07
--     / 0.09, white edges at 0.05 (panes) and 0.10 (windows) drawn as strips,
--     its buttons, fields, scroll lane and tooltip, Arial Narrow for text and
--     numbers (Expressway is EllesmereUI's file; SpellTuner ships no font),
--     and EllesmereUI's default accent for the client it runs on: soft bronze
--     #DCA77F on Forever, teal #0CD29D elsewhere (EllesmereUI.lua:24-40).
--
--   * THE FOLLOW (Forever, EllesmereUI loaded): the accent, the panel colour
--     and the font read through EllesmereUI's documented getters at every
--     apply, never cached (SKINNING_API.md). The skin facade `S` is what
--     Integrations/EllesmereUI_Forever.lua (T97) stores as MD.EUISkin from
--     EllesmereUI.RegisterSkin's callback; it is followed only while
--     S.apiVersion is 2 (the documented, additive-only contract) -- any other
--     version keeps the clone and the dump says `skin apiVersion <n>: not
--     followed` (X1). With no facade (BlizzardSkin off, or skinning turned
--     off for SpellTuner) the parent's own getters, GetAccentColor and
--     GetFontPath, through MD.EUIParent (the EllesmereUI table the
--     integration hands over; host globals are named only under
--     Integrations/, tools/apicheck.py rule 11); with neither, the clone. A
--     getter that raises or answers something that is not a colour or a path
--     leaves that one value at the clone's.
--
-- Repaints: on EUI_LOOKS_CHANGED (the integration fires it from
-- S.OnLooksChanged) while this style is active, and once on EUI_SKIN_READY
-- when the facade it announces is not the one the active paint already
-- decided on -- the facade can arrive after CORE_LOGIN applied the style
-- (X4); arriving before, the login's apply follows it and the event repaints
-- nothing. Both through UI.Styles.Refresh: STYLE_CHANGED once, db.ui.style
-- untouched.
--
-- SpellTuner's frames are never handed to S.Shell / S.Panel / S.Button
-- (decision 5): those fade every texture region of a frame to alpha 0
-- (EllesmereUIBlizzardSkin_WindowEngine.lua:412-429), which would hide the
-- clock's bar backing, and two painters would fight over one frame.
--
-- X5, accepted: EllesmereUI draws its secondary text as white at an alpha
-- (label 0.53, muted 0.41); a colour code cannot carry alpha, so each is
-- PRE-BLENDED into a hex against this style's own bg (the clone's or the
-- followed panel colour). Over any other fill -- a hovered or selected row --
-- that text is a few percent off. Regions (fills and edges) keep their real
-- alpha.
--
-- The client is read once, through the adapter: the interface number
-- (MD.API.BuildInfo) against the adapter's own Forever band (MD.API.BANDS),
-- which is how EllesmereUI itself picks its default theme
-- (EllesmereUI_ClientGate.lua: EUI_CLIENT_FOREVER from the interface), so the
-- clone's accent is the host's default for this client. Nothing else here
-- reads the client; nothing branches on UI.STYLE.
local _, MD = ...
local UI = MD.UI

local E = {}
UI.Ellesmere = E

E.API_VERSION = 2              -- the skin facade's contract this follow is written against
E.TESTED_EUI = "9.3.4"         -- the EllesmereUI these values were copied from (2026-09-30)
E.TEAL = { 12 / 255, 210 / 255, 157 / 255 }     -- #0CD29D, "EllesmereUI"
E.BRONZE = { 220 / 255, 167 / 255, 127 / 255 }  -- #DCA77F, "EllesmereUI Forever"
E.PANEL = { 0.05, 0.07, 0.09 }                  -- STYLE.PANEL_BG
E.FONT = "Fonts\\ARIALN.TTF"                    -- the clone's face, text and numbers
E.LABEL_A, E.MUTED_A = 0.53, 0.41               -- white at these alphas (X5)

--------------------------------------------------------------------------------
-- Reading what EllesmereUI says. Foreign tables are indexed and called only
-- inside pcall; every answer is checked before it is used.
--------------------------------------------------------------------------------
local function Unit(v) return type(v) == "number" and v >= 0 and v <= 1 end

local function Field(t, name)
    if type(t) ~= "table" then return nil end
    local ok, v = pcall(function() return t[name] end)
    if ok then return v end
    return nil
end

-- fn's answers, or nothing when it is not a function or raises
local function Ask(t, name)
    local fn = Field(t, name)
    if type(fn) ~= "function" then return nil end
    local res = { pcall(fn) }
    if not res[1] then return nil end
    return unpack(res, 2, 4)
end

local function Colour(r, g, b)
    if Unit(r) and Unit(g) and Unit(b) then return { r, g, b } end
    return nil
end

local function FontPath(p)
    if type(p) == "string" and p ~= "" and not p:find("|", 1, true) then return p end
    return nil
end

-- an outline flag the client takes: "", or upper-case words and commas;
-- EllesmereUI's "NONE" is no outline
local function Flags(f)
    if type(f) ~= "string" or not f:match("^[%u, ]*$") or f == "NONE" then return "" end
    return f
end

local function Version(v)
    if type(v) == "number" and v == v and v > -1e9 and v < 1e9 then
        if v == math.floor(v) then return string.format("%d", v) end
        return string.format("%.2f", v)
    end
    return "unknown"
end

-- EllesmereUI's default accent for the client it runs on: bronze where the
-- interface is in the Forever band, teal on any other client (or none read).
function E.HouseAccent()
    local iface
    if type(MD.API.BuildInfo) == "function" then
        local ok, _, _, _, i = pcall(MD.API.BuildInfo)
        if ok then iface = i end
    end
    local band = type(MD.API.BANDS) == "table" and MD.API.BANDS.forever
    if type(iface) == "number" and type(band) == "table" and iface >= band[1] and iface <= band[2] then
        return E.BRONZE
    end
    return E.TEAL
end

-- E.Source() -> "skin", S | "parent", P | "clone", nil, why. Reads no getter.
function E.Source()
    local S = MD.EUISkin
    if S ~= nil then
        local v = Field(S, "apiVersion")
        if v == E.API_VERSION then return "skin", S end
        return "clone", nil, "skin apiVersion " .. Version(v) .. ": not followed"
    end
    local P = MD.EUIParent
    if type(P) == "table" then return "parent", P end
    return "clone", nil
end

--------------------------------------------------------------------------------
-- The values (5.1's Ellesmere table, R-styles.md 4.2, EllesmereUI 9.3.4)
--------------------------------------------------------------------------------
local function Hex2(v) return string.format("%02X", math.floor(v * 255 + 0.5)) end

-- white at alpha a over the rgb c, as six hex digits (X5)
local function OnWhite(a, c)
    return Hex2(a + (1 - a) * c[1]) .. Hex2(a + (1 - a) * c[2]) .. Hex2(a + (1 - a) * c[3])
end

local function Accent(a) return { ref = "accent", a = a } end

-- The recipes: strips where EllesmereUI's edge alpha differs from its fill
-- (windows white 0.10, panes 0.05, the tooltip 0.18), pixel elsewhere with
-- the edge the house draws. Shared by the clone and the follow: they name
-- palette keys, so a followed panel colour reaches them.
local ROLES = {
    window    = { kind = "strips", fill = "bg",     edge = "border", edgeColor = { 1, 1, 1, 0.10 } },
    header    = { kind = "pixel",  fill = "nav",    edge = "border" },
    nav       = { kind = "pixel",  fill = "nav",    edge = "border" },
    pane      = { kind = "strips", fill = "pane",   edge = "border", edgeColor = { 1, 1, 1, 0.05 } },
    button    = { kind = "pixel",  fill = "button", edge = "border", edgeColor = { 1, 1, 1, 0.30 } },
    tab       = { kind = "pixel",  fill = "button", edge = "border", edgeColor = { 1, 1, 1, 0.30 } },
    field     = { kind = "pixel",  fill = "field",  edge = "border", edgeColor = { 1, 1, 1, 0.20 } },
    list      = { kind = "pixel",  fill = "nav",    edge = "border", edgeColor = { 1, 1, 1, 0.20 } },
    scroll    = { kind = "pixel",  fill = "track",  edge = "border", edgeColor = { 0, 0, 0, 0 } },
    tooltip   = { kind = "strips", fill = "tip",    edge = "border", edgeColor = { 1, 1, 1, 0.18 } },
    -- the clock: strips white 0.10 on the panel colour; `bar` the backing
    -- under its bar (Flat's black), `barFill` the bar's own fill, the accent
    -- at 0.75 -- what the layouts (T98, T104) read from this role
    clock     = { kind = "strips", fill = "bg",     edge = "border", edgeColor = { 1, 1, 1, 0.10 },
                  bar = { 0, 0, 0, 1 }, barFill = Accent(0.75) },
    statusbar = { kind = "pixel",  fill = "track",  edge = "border", edgeColor = { 0, 0, 0, 0 } },
    rule      = { kind = "pixel",  fill = "line",   edge = "border" },
}

-- One complete style table for a panel colour, an accent and a font. Keys
-- left out are Flat's (the cancel / go / info / warn fills, mana, good and
-- bad, disabled: exempt or unnamed by EllesmereUI's palette).
local function Build(accent, panel, face, flags)
    local r, g, b = panel[1], panel[2], panel[3]
    local blackTenth = 0.9 -- black at 0.10 over the panel
    return {
        name = "Ellesmere",
        hint = "EllesmereUI's look: a cool dark panel, faint white edges, its accent.",
        accent = { accent[1], accent[2], accent[3] },
        palette = {
            bg          = { r, g, b, 0.96 },
            pane        = { r, g, b, 1 },
            nav         = { r * blackTenth, g * blackTenth, b * blackTenth, 1 },
            border      = { 1, 1, 1, 0.10 },
            line        = { 1, 1, 1, 0.06 },
            rule        = Accent(1),
            rowAlt      = { 0, 0, 0, 0.20 },
            hover       = { 1, 1, 1, 0.08 },
            selected    = { 1, 1, 1, 0.04 },     -- plus the kit's 2-px accent bar
            button      = { 0.061, 0.095, 0.120, 0.6 },
            buttonHover = { 0.061, 0.095, 0.120, 0.65 },
            field       = { 0.10, 0.12, 0.16, 1 },
            well        = { 0.075, 0.113, 0.141, 0.9 },  -- EllesmereUI's dropdown fill
            track       = { 1, 1, 1, 0.10 },
            thumb       = { 1, 1, 1, 0.25 },
            check       = Accent(0.75),
            tip         = { 0.067, 0.067, 0.067, 0.92 },
        },
        text = {
            text  = "FFFFFF",
            label = OnWhite(E.LABEL_A, panel),
            muted = OnWhite(E.MUTED_A, panel),
        },
        -- EllesmereUI draws a shadow only when there is no outline
        fonts = { face = face, num = face, flags = flags, shadow = flags == "" and { 1, -1 } or { 0, 0 } },
        roles = ROLES,
        needs = {},
    }
end

local following = nil   -- "skin" | "parent" | nil (the clone), as last resolved

-- The registered style's resolve: the table applied, and the dump's note.
local function Resolve()
    local accent, panel, face, flags = E.HouseAccent(), E.PANEL, E.FONT, ""
    local src, host, why = E.Source()
    E.decidedFor = MD.EUISkin
    local note = why
    if src == "skin" then
        accent = Colour(Ask(host, "GetAccentColor")) or accent
        panel = Colour(Ask(host, "GetPanelColor")) or panel
        local path, flag = Ask(host, "GetFont")
        path = FontPath(path)
        if path then face, flags = path, Flags(flag) end
        note = "follows EllesmereUI (skin apiVersion " .. Version(E.API_VERSION) .. ")"
    elseif src == "parent" then
        accent = Colour(Ask(host, "GetAccentColor")) or accent
        face = FontPath((Ask(host, "GetFontPath"))) or face
        note = "follows EllesmereUI (its accent and font)"
    end
    following = src ~= "clone" and src or nil
    return Build(accent, panel, face, flags), note
end

-- E.Following() -> "skin" | "parent" | nil: what the last apply followed.
function E.Following() return following end

-- E.Label(): the Look dropdown's name for it (T102): "Ellesmere (following
-- EllesmereUI)" when a getter source is there now, else "Ellesmere".
function E.Label()
    if E.Source() ~= "clone" then return "Ellesmere (following EllesmereUI)" end
    return "Ellesmere"
end

--------------------------------------------------------------------------------
-- Registered: the clone's table with accent "follow" (5.1's own word for
-- this style) and the resolve that answers what is applied.
--------------------------------------------------------------------------------
UI.ELLESMERE = Build(E.TEAL, E.PANEL, E.FONT, "")
UI.ELLESMERE.accent = "follow"
UI.ELLESMERE.resolve = function() return Resolve() end
UI.Styles.Register("ellesmere", UI.ELLESMERE)

MD:RegisterCallback("EUI_LOOKS_CHANGED", function()
    UI.Styles.Refresh("ellesmere")
end)

MD:RegisterCallback("EUI_SKIN_READY", function()
    if UI.Styles.Active() ~= "ellesmere" or rawequal(E.decidedFor, MD.EUISkin) then return end
    UI.Styles.Refresh("ellesmere")
end)
