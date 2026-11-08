-- Integrations/Media_LSM.lua (T139, docs/tasks/T139-clock-bar-look.md): the
-- bar textures other addons registered with LibSharedMedia-3.0 (ElvUI,
-- EllesmereUI, ...), for the clock's Texture list. Every main TOC.
--
-- The library is BORROWED: LibStub's LibSharedMedia-3.0, which a host loaded
-- (CLAUDE.md "Host libraries borrowed, never shipped"; host globals only
-- under Integrations/, apicheck rule 11). Nothing is registered with it and
-- nothing is shipped: no host, no list, and a texture picked earlier falls
-- back to Flat (UI/ClockView.lua names why).
--
--   ST.Media.Bars()        -> { { name, path } } sorted by name, or {} (no host)
--   ST.Media.Fetch(name)   -> path, or nil
--   ST.Media.why           why the list is empty, or nil
local _, ST = ...

local Media = {}
ST.Media = Media

local function Lib()
    local LS = LibStub
    if type(LS) ~= "table" then return nil, "no LibStub (no ElvUI or EllesmereUI loaded)" end
    local okG, get = pcall(function() return LS.GetLibrary end)
    if not okG or type(get) ~= "function" then return nil, "LibStub without GetLibrary" end
    local okL, lib = pcall(get, LS, "LibSharedMedia-3.0", true)
    if not okL or type(lib) ~= "table" then return nil, "no LibSharedMedia-3.0 loaded" end
    if type(lib.List) ~= "function" or type(lib.Fetch) ~= "function" then return nil, "LibSharedMedia without List / Fetch" end
    return lib
end

function Media.Fetch(name)
    if type(name) ~= "string" or name == "" then return nil end
    local lib = Lib()
    if not lib then return nil end
    local ok, path = pcall(lib.Fetch, lib, "statusbar", name, true)
    if ok and type(path) == "string" and path ~= "" then return path end
    return nil
end

function Media.Bars()
    local lib, why = Lib()
    Media.why = why
    if not lib then return {} end
    local ok, names = pcall(lib.List, lib, "statusbar")
    if not ok or type(names) ~= "table" then
        Media.why = "LibSharedMedia did not list its bar textures"
        return {}
    end
    local out = {}
    for _, name in ipairs(names) do
        if type(name) == "string" then
            local path = Media.Fetch(name)
            if path then out[#out + 1] = { name = name, path = path } end
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

--------------------------------------------------------------------------------
-- T140 (docs/tasks/T140-ellesmere-bar-look.md): EllesmereUI's own bar
-- textures. EllesmereUI keeps them out of LibSharedMedia, but publishes the
-- catalogue its own dropdowns read: EllesmereUI.BuildBarTextureTables() ->
-- paths, names, order. Read here only (a host global: apicheck rule 11),
-- every call under pcall, nothing copied or shipped: without EllesmereUI the
-- list is empty and a texture picked earlier draws Flat (UI/ClockView.lua).
--
--   ST.Media.Ellesmere()          -> { { key, name, path } } in EllesmereUI's order, or {}
--   ST.Media.FetchEllesmere(key)  -> path, or nil
--   ST.Media.EllesmereMana()      -> { r, g, b } EllesmereUI's mana colour, or nil
--------------------------------------------------------------------------------
local function EUITables()
    local E = rawget(_G, "EllesmereUI")
    if type(E) ~= "table" then return nil, "EllesmereUI is not loaded" end
    local build = E.BuildBarTextureTables
    if type(build) ~= "function" then return nil, "this EllesmereUI has no texture catalogue" end
    local ok, tex, names, order = pcall(build, false)
    if not ok or type(tex) ~= "table" or type(order) ~= "table" then
        return nil, "EllesmereUI's texture catalogue did not answer"
    end
    return tex, names, order
end

function Media.Ellesmere()
    local tex, names, order = EUITables()
    if not tex then Media.euiWhy = names; return {} end
    Media.euiWhy = nil
    local out = {}
    for _, k in ipairs(order) do
        local path = tex[k]
        if type(k) == "string" and type(path) == "string" and path ~= "" then
            local name = type(names) == "table" and names[k]
            out[#out + 1] = { key = k, name = type(name) == "string" and name or k, path = path }
        end
    end
    return out
end

function Media.FetchEllesmere(key)
    if type(key) ~= "string" or key == "" then return nil end
    local tex = EUITables()
    local path = tex and tex[key]
    if type(path) == "string" and path ~= "" then return path end
    return nil
end

function Media.EllesmereMana()
    local E = rawget(_G, "EllesmereUI")
    if type(E) ~= "table" or type(E.GetPowerColor) ~= "function" then return nil end
    local ok, c = pcall(E.GetPowerColor, "MANA")
    if not ok or type(c) ~= "table" then return nil end
    local r, g, b = c.r, c.g, c.b
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return nil end
    return { r, g, b }
end
