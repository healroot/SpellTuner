-- T94 (docs/SPEC-next.md 2.2, 5.1-5.4, S2 step 1; R-styles.md 3): the style
-- registry. Listed by every main TOC right after UI/Theme_Flat.lua (whose
-- UI.FLAT it registers as "flat") and before any window file.
--
-- T100: a style may carry `resolve(style) -> style, note`, a function run at
-- every apply that answers the table actually applied (validated like any
-- style; a resolve that raises or answers an invalid table applies the
-- registered one) and an optional ASCII note for the dump line. The
-- Ellesmere style (UI/Style_Ellesmere.lua) resolves to its clone or to what
-- EllesmereUI's getters say, read fresh each time (SKINNING_API.md: never
-- cache them).
--
-- A style is PAINT ONLY: fills, text tokens, font faces and one recipe per
-- role (UI.SKIN_ROLES), never a size, an anchor, a pitch, a font size or an
-- inset (2.2), and never a behaviour -- UI.THEMED stays the one "new
-- structure" flag under every style. UI.STYLE is the active style's key, a
-- second, paint-only axis; no pane branches on it (tools/themecheck.lua scans
-- the tree: UI.STYLE is read only by UI/Style.lua, this file and the
-- UI/Style_*.lua style files).
--
--   UI.Styles.Register(key, style)   a valid style under a new key (else raises)
--   UI.Styles.Validate(style)        -> true | false, problems (a list of strings)
--   UI.Styles.Get(key), Keys()       the registered style, every key in order
--   UI.Styles.Recipe(role)           the active style's recipe for a role:
--                                    Flat's where the style names none, or
--                                    where the art it needs is missing (5.2)
--   UI.Styles.Refresh(key)           T100: apply the active style again when
--                                    it is `key` (its resolve may answer
--                                    differently now: EllesmereUI's looks
--                                    changed, its skin facade arrived) ->
--                                    true, STYLE_CHANGED fired once; false,
--                                    nothing done, before CORE_LOGIN or under
--                                    another style. db.ui.style untouched.
--   UI.Styles.Note()                 T100: what the active style's resolve
--                                    said about itself (the dump line's tail)
--   UI.SetStyle(key)                 (also UI.Styles.SetStyle) -> true, or
--                                    false, why for a key nobody registered.
--                                    Captures what every registered region
--                                    shows, writes the palette and the tokens
--                                    in place, re-faces the fonts, repaints
--                                    every region (UI/Style.lua), sets
--                                    UI.STYLE, saves db.ui.style and fires
--                                    STYLE_CHANGED (key) once. Raises before
--                                    CORE_LOGIN: the saved style is applied
--                                    there, before MD_READY builds the clocks.
--
-- db.ui.style (default "flat") is declared by UI/Theme_Flat.lua beside
-- db.ui.fontOffset (db.ui's keys are declared by the theme, the ESC stack and
-- the window manager: tools/defaultscheck.lua). A saved key nobody registers
-- (a style file that did not load) applies Flat for the session and is kept.
--
-- `/st ui style <name>` (and `/md ui style` on TBC, where it creates the `ui`
-- verb) through MD:AddSubcommand, so `/st ui reset` keeps working whatever
-- order the two files load in. The /st dump line through MD:AddDumpLine:
-- `style: <key> (accent <class|style>) fell back: <roles|none>` -- added the
-- first time a style other than Flat is applied or a role falls back, so the
-- dump of a player who never left Flat is byte for byte what it was.
--
-- No client data is read here except through MD.API, and only the presence
-- checks a style's `needs` ask for (5.3: MD.API.AtlasInfo / MD.API.FileID,
-- when a later task binds them; with no answer a plain file is assumed present
-- and every atlas refused).
local _, MD = ...
local UI = MD.UI

local Styles = {}
UI.Styles = Styles

local list, byKey = {}, {}
local active            -- { key, style, fell = { [role] = true } }
local loggedIn = false
local dumpAdded = false


--------------------------------------------------------------------------------
-- Validation
--------------------------------------------------------------------------------
local ROLE_SET = {}
for _, r in ipairs(UI.SKIN_ROLES) do ROLE_SET[r] = true end

local function Ascii(s)
    if type(s) ~= "string" or s == "" then return false end
    for i = 1, #s do
        local b = s:byte(i)
        if b < 32 or b > 126 then return false end
    end
    return not s:find("|", 1, true)
end

local function Unit(v) return type(v) == "number" and v >= 0 and v <= 1 end

-- a fill: r, g, b, a in 0..1, or { ref = "accent", a = n }
local function FillProblem(v)
    if type(v) ~= "table" then return "not a table" end
    if v.ref ~= nil then
        if v.ref ~= "accent" then return "ref '" .. tostring(v.ref) .. "' (only accent)" end
        if v.a ~= nil and not Unit(v.a) then return "ref alpha not 0..1" end
        return nil
    end
    if not (Unit(v[1]) and Unit(v[2]) and Unit(v[3]) and (v[4] == nil or Unit(v[4]))) then
        return "not r, g, b, a in 0..1"
    end
    return nil
end

-- a colour a recipe names: a palette key, or a fill
local function ColourProblem(v, paletteKeys)
    if type(v) == "string" then
        if paletteKeys[v] or UI.STYLE_ALIASES.palette[v] then return nil end
        return "unknown palette key '" .. v .. "'"
    end
    return FillProblem(v)
end

function Styles.Validate(s)
    local problems = {}
    local function bad(fmt, ...) problems[#problems + 1] = string.format(fmt, ...) end
    if type(s) ~= "table" then return false, { "a style is a table" } end
    local flat = UI.FLAT
    if not Ascii(s.name) then bad("name: one line of printable ASCII, no pipe") end
    if s.hint ~= nil and not Ascii(s.hint) then bad("hint: printable ASCII, no pipe") end
    local a = s.accent
    if not (a == "class" or a == "gold" or a == "follow"
            or (type(a) == "table" and Unit(a[1]) and Unit(a[2]) and Unit(a[3]))) then
        bad("accent: class, gold, follow or r, g, b")
    end
    local paletteKeys = flat.palette
    if s.palette ~= nil and type(s.palette) ~= "table" then bad("palette: a table") end
    for k, v in pairs(type(s.palette) == "table" and s.palette or {}) do
        if UI.STYLE_ALIASES.palette[k] then
            bad("palette.%s: an alias of %s, set that instead", tostring(k), UI.STYLE_ALIASES.palette[k])
        elseif not paletteKeys[k] then
            bad("palette.%s: not a key Flat has", tostring(k))
        else
            local p = FillProblem(v)
            if p then bad("palette.%s: %s", k, p) end
        end
    end
    if s.text ~= nil and type(s.text) ~= "table" then bad("text: a table") end
    for k, v in pairs(type(s.text) == "table" and s.text or {}) do
        if UI.STYLE_ALIASES.text[k] then
            bad("text.%s: an alias of %s, set that instead", tostring(k), UI.STYLE_ALIASES.text[k])
        elseif not flat.text[k] then
            bad("text.%s: not a token Flat has", tostring(k))
        elseif not ((type(v) == "string" and v:match("^%x%x%x%x%x%x$"))
                    or (type(v) == "table" and v.ref == "accent")) then
            bad("text.%s: six hex digits or { ref = \"accent\" }", k)
        end
    end
    local f = s.fonts
    if f ~= nil and type(f) ~= "table" then bad("fonts: a table") end
    if type(f) == "table" then
        for _, k in ipairs({ "face", "num", "flags" }) do
            if f[k] ~= nil and type(f[k]) ~= "string" then bad("fonts.%s: a string", k) end
        end
        if f.shadow ~= nil and not (type(f.shadow) == "table" and type(f.shadow[1]) == "number"
                                    and type(f.shadow[2]) == "number") then
            bad("fonts.shadow: { x, y }")
        end
    end
    if s.roles ~= nil and type(s.roles) ~= "table" then bad("roles: a table") end
    for role, r in pairs(type(s.roles) == "table" and s.roles or {}) do
        if not ROLE_SET[role] then
            bad("roles.%s: not a role (%s)", tostring(role), table.concat(UI.SKIN_ROLES, ", "))
        elseif type(r) ~= "table" then
            bad("roles.%s: a table", role)
        else
            if not UI.PAINTERS[r.kind] then bad("roles.%s.kind: no painter '%s'", role, tostring(r.kind)) end
            for _, k in ipairs({ "fill", "edge", "edgeColor" }) do
                if r[k] ~= nil then
                    local p = ColourProblem(r[k], paletteKeys)
                    if p then bad("roles.%s.%s: %s", role, k, p) end
                end
            end
        end
    end
    if s.resolve ~= nil and type(s.resolve) ~= "function" then bad("resolve: a function") end
    if s.needs ~= nil and type(s.needs) ~= "table" then bad("needs: a list") end
    for i, n in ipairs(type(s.needs) == "table" and s.needs or {}) do
        if type(n) ~= "table" or not ROLE_SET[n.role]
           or not ((type(n.atlas) == "string") ~= (type(n.file) == "string")) then
            bad("needs[%d]: { role = <role>, atlas = <name> } or { role = <role>, file = <path> }", i)
        end
    end
    if #problems > 0 then return false, problems end
    return true
end

function Styles.Register(key, s)
    if type(key) ~= "string" or not key:match("^[%l%d_]+$") then
        error("UI.Styles.Register: a key is lower-case letters, digits and _, got '" .. tostring(key) .. "'", 2)
    end
    if byKey[key] then error("UI.Styles.Register: '" .. key .. "' is registered already", 2) end
    local okV, problems = Styles.Validate(s)
    if not okV then
        error("UI.Styles.Register: '" .. key .. "' is not a valid style: " .. table.concat(problems, "; "), 2)
    end
    byKey[key] = s
    list[#list + 1] = key
end

function Styles.Get(key) return byKey[key] end

function Styles.Keys()
    local out = {}
    for i, k in ipairs(list) do out[i] = k end
    return out
end

function Styles.Active() return active and active.key end

--------------------------------------------------------------------------------
-- Recipes and the presence checks
--------------------------------------------------------------------------------
-- A need is present when the client says so: an atlas only when
-- MD.API.AtlasInfo answers for it; a file unless MD.API.FileID answers nil
-- (with no FileID binding the plain Interface\ files are assumed, 5.3).
local function Present(need)
    if need.atlas then
        local fn = MD.API.AtlasInfo
        if type(fn) ~= "function" then return false end
        local okA, info = pcall(fn, need.atlas)
        return okA and info ~= nil
    end
    local fn = MD.API.FileID
    if type(fn) ~= "function" then return true end
    local okF, id = pcall(fn, need.file)
    return okF and id ~= nil
end

local function FellBack(style)
    local fell = {}
    for _, n in ipairs(style.needs or {}) do
        if not Present(n) then fell[n.role] = true end
    end
    return fell
end

function Styles.Recipe(role)
    local flat = byKey.flat
    if active and not active.fell[role] then
        local r = active.style.roles and active.style.roles[role]
        if r then return r end
    end
    return flat and flat.roles[role] or (UI.FLAT and UI.FLAT.roles[role])
end

--------------------------------------------------------------------------------
-- Applying a style
--------------------------------------------------------------------------------
local function DumpLine()
    local a = active
    if not a then return "style: none" end
    local roles = {}
    for r in pairs(a.fell) do roles[#roles + 1] = r end
    table.sort(roles)
    local line = string.format("style: %s (accent %s) fell back: %s", a.key,
        a.style.accent == "class" and "class" or "style", #roles > 0 and table.concat(roles, ", ") or "none")
    if a.note then line = line .. "; " .. a.note end
    return line
end
Styles.DumpLine = DumpLine

function Styles.Note() return active and active.note end

-- T100: the table a style applies as -- its resolve's answer when it has
-- one and that answer is a valid style, else the registered table itself.
local function Resolve(style)
    if type(style.resolve) ~= "function" then return style, nil end
    local okR, eff, note = pcall(style.resolve, style)
    if not okR or type(eff) ~= "table" or not (Styles.Validate(eff)) then
        return style, "resolve failed"
    end
    if type(note) ~= "string" or not Ascii(note) then note = nil end
    return eff, note
end

local function Apply(key, style)
    local captured = UI.CaptureSkins and UI.CaptureSkins()
    local eff, note = Resolve(style)
    active = { key = key, style = eff, note = note, fell = FellBack(eff) }
    UI.ApplyStyleTokens(eff)
    UI.ReFaceFonts(eff)
    if UI.RepaintSkins then UI.RepaintSkins(captured) end
    UI.STYLE = key
    if not dumpAdded and (key ~= "flat" or next(active.fell) ~= nil) then
        dumpAdded = true
        MD:AddDumpLine("style", DumpLine)
    end
end

local function Unknown(key)
    return string.format("unknown style '%s' (styles: %s)", tostring(key), table.concat(list, ", "))
end

function UI.SetStyle(key)
    if not loggedIn then
        error("UI.SetStyle: before CORE_LOGIN -- the saved style is applied there", 2)
    end
    if type(key) == "string" then key = key:lower() end
    local style = byKey[key]
    if not style then return false, Unknown(key) end
    Apply(key, style)
    local db = MD.db
    if type(db) == "table" then
        if type(db.ui) ~= "table" then db.ui = {} end
        db.ui.style = key
    end
    MD:Fire("STYLE_CHANGED", key)
    return true
end
Styles.SetStyle = UI.SetStyle

function Styles.Refresh(key)
    if not loggedIn or not active or active.key ~= key or not byKey[key] then return false end
    Apply(key, byKey[key])
    MD:Fire("STYLE_CHANGED", key)
    return true
end

-- Flat, from UI/Theme_Flat.lua, applied there at load: the active style
-- until the saved one is applied at CORE_LOGIN.
Styles.Register("flat", UI.FLAT)
active = { key = "flat", style = UI.FLAT, fell = {} }
UI.STYLE = "flat"

MD:RegisterCallback("CORE_LOGIN", function()
    loggedIn = true
    local saved = MD.db and type(MD.db.ui) == "table" and MD.db.ui.style
    if type(saved) == "string" and byKey[saved:lower()] then
        UI.SetStyle(saved)
        return
    end
    -- a style nobody registered this session: Flat, the saved key kept
    Apply("flat", byKey.flat)
    MD:Fire("STYLE_CHANGED", "flat")
end)

--------------------------------------------------------------------------------
-- /st ui style (5.4), through the kernel's subcommand seam (2.5)
--------------------------------------------------------------------------------
MD:AddSubcommand("ui", "style", function(rest)
    local name = (rest or ""):match("^(%S+)")
    if not name then
        MD:Print(string.format("style: %s (styles: %s)", tostring(UI.STYLE), table.concat(list, ", ")))
        return
    end
    local okS, why = UI.SetStyle(name)
    if okS then
        local note = active and active.note
        MD:Print(string.format("style: %s - %s%s", UI.STYLE, byKey[UI.STYLE].name,
            note and (" (" .. note .. ")") or ""))
    else
        MD:Print(why)
    end
end, "style <name>", "the look of SpellTuner's windows (no name: list the styles)")
