-- tools/stub_hosts.lua -- fake host addons for the surface suites (T92,
-- docs/SPEC-next.md 2 "Stub extensions live in their own files", 2.3, 6.2).
-- Not a suite: tools/check.sh lists it in NOT_SUITES.
--
--   local H = dofile(here .. "/stub_hosts.lua")
--   local E, DT = H.InstallElvUI()            -- _G.ElvUI, unpack(ElvUI) gives E
--   local lib = H.InstallLDB()                -- _G.LibStub with LibDataBroker-1.1
--   H.Remove()                                -- every global this file set, gone
--
-- None of this is loaded by tools/wowstub.lua, so no suite that does not ask
-- for a host sees one (no existing count moves). Every fake records what was
-- asked of it, so a suite reads back what a surface did:
--
--   * ElvUI: E:GetModule("DataTexts") is DT (nil with { noDataTexts = true }:
--     a half install); DT:RegisterDatatext(...) keeps every call, its eleven
--     arguments by their ElvUI names, in DT.registered (in order) and
--     DT.byName; DT.tooltip records ClearLines / AddLine / AddDoubleLine /
--     Show as one string each in DT.tooltip.log; H.Panel() is a datatext
--     panel whose text keeps what was last set.
--   * LibStub: NewLibrary / GetLibrary (silent or raising) / IterateLibraries
--     and the call form LibStub(major, silent), the shape every addon uses.
--   * LibDataBroker-1.1: NewDataObject(name, t) -> a proxy (nil for a name
--     already taken, as the library answers), GetDataObjectByName,
--     GetNameByDataObject, DataObjectIterator, and the callbacks
--     (RegisterCallback / UnregisterCallback / Fire). A write to a proxy field
--     is DROPPED when it equals what is stored (the library's equal-write
--     suppression), else stored and announced as
--     LibDataBroker_AttributeChanged, _<name>, _<name>_<key> and __<key>, in
--     that order; each announcement is also kept in lib.fired.
--
-- T97 (docs/SPEC-next.md 6.2-6.3, R-ellesmere.md 4.1) adds:
--   * EllesmereUI: H.InstallEllesmere(opts) -> E, the parent addon's public
--     entry points as EllesmereUI 9.3.4 has them -- RegisterSkin (the stub
--     that queues; the first registration under a name wins), the unlock
--     registry (MakeUnlockElement copies ONLY its whitelist, renaming the
--     short savePos/... to the long names, exactly as EllesmereUI.lua
--     2324-2381 does; RegisterUnlockElements stamps the folder and keys the
--     element; RegisterUnlockModeListener / _NotifyUnlockModeListeners) -- each
--     recording its calls in E.calls. opts: noUnlock (no unlock functions),
--     noListener, noSkin (no RegisterSkin), bare (an empty table).
--     E._DispatchSkins(S) is BlizzardSkin's PLAYER_LOGIN drain (each queued
--     callback under pcall); a registration after it runs at once.
--   * H.SkinFacade(opts) -> S: apiVersion (2 unless opts.apiVersion),
--     GetAccentColor / GetPanelColor / GetFont / GetStyle counting every read
--     in S.reads, OnLooksChanged keeping its functions; H.LooksChanged(S) calls
--     them.
--   * H.AddOnMeta(MD, map): C_AddOns.GetAddOnMetadata answers map[name][field]
--     for a host (the version an integration line prints), else the stub's.
--   * The reader, what EllesmereUI's DataBars Broker Plugin block shows
--     (EllesmereUIDataBars/Blocks/LDB.lua): H.LdbBlockText(obj) -- obj.text,
--     else value .. " " .. suffix, colour codes stripped (its default);
--     H.LdbIcon(obj) -- the icon and the iconR/G/B tint it honours;
--     H.LdbTooltip(obj) -- OnTooltipShow into a recording tooltip, the route
--     the block takes when the object has no OnEnter.
local H = {}

local SET = { "ElvUI", "LibStub", "EllesmereUI" }

local function Fmt(v)
    if type(v) == "number" then
        if v == math.floor(v) then return tostring(v) end
        return string.format("%.3f", v)
    end
    return tostring(v)
end

-- A recording tooltip: each call one string, arguments joined by tabs.
function H.Tooltip()
    local tt = { log = {}, shown = false }
    local function Rec(kind, ...)
        local parts = { kind }
        local n = select("#", ...)
        for i = 1, n do parts[#parts + 1] = Fmt((select(i, ...))) end
        tt.log[#tt.log + 1] = table.concat(parts, "\t")
    end
    function tt:ClearLines() Rec("ClearLines"); self.shown = false end
    function tt:AddLine(...) Rec("AddLine", ...) end
    function tt:AddDoubleLine(...) Rec("AddDoubleLine", ...) end
    function tt:Show() Rec("Show"); self.shown = true end
    function tt:Hide() Rec("Hide"); self.shown = false end
    function tt:NumLines() return #self.log end
    return tt
end

-- A datatext panel: panel.text:SetText(s) keeps s (and counts the writes).
function H.Panel()
    local panel = { writes = 0 }
    panel.text = {
        SetText = function(_, s) panel.value = s; panel.writes = panel.writes + 1 end,
        GetText = function() return panel.value end,
    }
    return panel
end

--------------------------------------------------------------------------------
-- ElvUI
--------------------------------------------------------------------------------
local DT_ARGS = { "name", "category", "events", "eventFunc", "updateFunc", "clickFunc",
    "onEnterFunc", "onLeaveFunc", "localizedName", "objectEvent", "applySettings" }

function H.InstallElvUI(opts)
    opts = opts or {}
    local DT = { registered = {}, byName = {}, tooltip = H.Tooltip() }
    function DT:RegisterDatatext(...)
        local rec = { n = select("#", ...) }
        for i, key in ipairs(DT_ARGS) do rec[key] = (select(i, ...)) end
        DT.registered[#DT.registered + 1] = rec
        if rec.name ~= nil then DT.byName[rec.name] = rec end
        return rec
    end
    local E = { modules = {} }
    if not opts.noDataTexts then E.modules.DataTexts = DT end
    function E:GetModule(name, silent)
        local m = self.modules[name]
        if m == nil and not silent and opts.raiseOnMissing then error("module " .. tostring(name) .. " not found") end
        return m
    end
    _G.ElvUI = { E, {}, {}, {}, {} }
    return E, (not opts.noDataTexts) and DT or nil
end

--------------------------------------------------------------------------------
-- LibStub
--------------------------------------------------------------------------------
function H.InstallLibStub()
    if type(_G.LibStub) == "table" and _G.LibStub.isStubHost then return _G.LibStub end
    local LS = { libs = {}, minors = {}, isStubHost = true }
    function LS:NewLibrary(major, minor)
        minor = tonumber(tostring(minor):match("%d+")) or 0
        local old = self.minors[major]
        if old and old >= minor then return nil end
        self.minors[major] = minor
        self.libs[major] = self.libs[major] or {}
        return self.libs[major], old
    end
    function LS:GetLibrary(major, silent)
        if not self.libs[major] and not silent then
            error(("Cannot find a library instance of %q."):format(tostring(major)), 2)
        end
        return self.libs[major], self.minors[major]
    end
    function LS:IterateLibraries() return pairs(self.libs) end
    setmetatable(LS, { __call = LS.GetLibrary })
    _G.LibStub = LS
    return LS
end

--------------------------------------------------------------------------------
-- LibDataBroker-1.1
--------------------------------------------------------------------------------
function H.InstallLDB()
    local LS = H.InstallLibStub()
    local lib = LS:NewLibrary("LibDataBroker-1.1", 4)
    if not lib then return LS:GetLibrary("LibDataBroker-1.1") end

    lib.storage, lib.namestorage, lib.proxies = {}, {}, {}
    lib.fired, lib.listeners = {}, {}

    -- The CallbackHandler shape: lib.RegisterCallback(target, event, fn | method).
    lib.callbacks = {}
    function lib.callbacks:Fire(event, ...)
        lib.fired[#lib.fired + 1] = { event = event, n = select("#", ...), ... }
        local list = lib.listeners[event]
        if not list then return end
        for _, l in ipairs(list) do
            local fn = l.fn
            if type(fn) == "string" then fn = l.target[fn] end
            if type(fn) == "function" then
                if type(l.fn) == "string" then fn(l.target, event, ...) else fn(event, ...) end
            end
        end
    end
    function lib.RegisterCallback(target, event, fn)
        lib.listeners[event] = lib.listeners[event] or {}
        local list = lib.listeners[event]
        list[#list + 1] = { target = target, fn = fn or event }
    end
    function lib.UnregisterCallback(target, event)
        local list = lib.listeners[event]
        if not list then return end
        for i = #list, 1, -1 do if list[i].target == target then table.remove(list, i) end end
    end

    local meta = {
        __index = function(self, key) return lib.storage[self][key] end,
        __newindex = function(self, key, value)
            local store = lib.storage[self]
            if store[key] == value then return end -- equal-write suppression
            store[key] = value
            local name = lib.namestorage[self]
            if not name then return end
            lib.callbacks:Fire("LibDataBroker_AttributeChanged", name, key, value, self)
            lib.callbacks:Fire("LibDataBroker_AttributeChanged_" .. name, name, key, value, self)
            lib.callbacks:Fire("LibDataBroker_AttributeChanged_" .. name .. "_" .. key, name, key, value, self)
            lib.callbacks:Fire("LibDataBroker_AttributeChanged__" .. key, name, key, value, self)
        end,
    }

    function lib:NewDataObject(name, dataobj)
        if self.proxies[name] then return nil end
        if dataobj then
            assert(type(dataobj) == "table", "Invalid dataobj, must be nil or a table")
            local copy = {}
            for k, v in pairs(dataobj) do copy[k] = v end
            dataobj = copy
        else
            dataobj = {}
        end
        local proxy = setmetatable({}, meta)
        self.storage[proxy] = dataobj
        self.namestorage[proxy] = name
        self.proxies[name] = proxy
        self.callbacks:Fire("LibDataBroker_DataObjectCreated", name, proxy)
        return proxy
    end
    function lib:DataObjectIterator() return pairs(self.proxies) end
    function lib:GetDataObjectByName(name) return self.proxies[name] end
    function lib:GetNameByDataObject(obj) return self.namestorage[obj] end

    -- What a proxy holds (a read that does not go through the proxy).
    function lib:Raw(obj) return self.storage[obj] end
    -- The AttributeChanged announcements so far for one object and key.
    function lib:Changes(name, key)
        local n = 0
        for _, f in ipairs(self.fired) do
            if f.event == "LibDataBroker_AttributeChanged" and f[1] == name and (key == nil or f[2] == key) then
                n = n + 1
            end
        end
        return n
    end
    return lib
end

--------------------------------------------------------------------------------
-- EllesmereUI (T97)
--------------------------------------------------------------------------------
-- EllesmereUI.MakeUnlockElement's whitelist (EllesmereUI.lua 2324-2381, 9.3.4):
-- the option name -> the field the unlock module reads. Anything else passed
-- in never reaches the unlock module, silently.
H.UNLOCK_WHITELIST = {
    key = "key", label = "label", group = "group", order = "order",
    getFrame = "getFrame", getSize = "getSize",
    savePos = "savePosition", loadPos = "loadPosition", clearPos = "clearPosition", applyPos = "applyPosition",
    setWidth = "setWidth", setHeight = "setHeight", isHidden = "isHidden", isAnchored = "isAnchored",
    onLiveMove = "onLiveMove", linkedKeys = "linkedKeys", noResize = "noResize",
    linkedDimensions = "linkedDimensions", noInitHook = "noInitHook",
    loadRawPos = "loadRawPosition", saveRawPos = "saveRawPosition",
    noAnchorTarget = "noAnchorTarget", noAnchorTo = "noAnchorTo",
    allowMatchSource = "allowMatchSource", noSizeMatchTarget = "noSizeMatchTarget",
    sizeFixedByLook = "sizeFixedByLook", getSettingSize = "getSettingSize",
    matchUnavailable = "matchUnavailable", keepMoverWhenAnchored = "keepMoverWhenAnchored",
    moverBg = "moverBg", moverTooltip = "moverTooltip", subtitle = "subtitle",
    getBottomExtra = "getBottomExtra", getInsets = "getInsets", getMatchPad = "getMatchPad",
    detachedMover = "detachedMover",
}

function H.InstallEllesmere(opts)
    opts = opts or {}
    local E = { IS_FOREVER = true }
    _G.EllesmereUI = E
    if opts.bare then return E end
    E.calls = { RegisterSkin = {}, MakeUnlockElement = {}, RegisterUnlockElements = {},
        RegisterUnlockModeListener = {} }
    E._skinRegistry = {}
    E._unlockRegisteredElements = {}
    E._unlockModeListeners = {}

    if not opts.noSkin then
        -- the stub in EllesmereUI_SharedHelpers.lua: queues; the first name wins
        function E.RegisterSkin(name, applyFn)
            E.calls.RegisterSkin[#E.calls.RegisterSkin + 1] = name
            if type(name) ~= "string" or name == "" or type(applyFn) ~= "function" then return end
            for i = 1, #E._skinRegistry do
                if E._skinRegistry[i].name == name then return end
            end
            local entry = { name = name, apply = applyFn }
            E._skinRegistry[#E._skinRegistry + 1] = entry
            if E._skinDispatched then pcall(entry.apply, E._skinFacade) end
            return true
        end
        -- BlizzardSkin's PLAYER_LOGIN: every queued callback, under pcall
        function E._DispatchSkins(S)
            E._skinDispatched, E._skinFacade = true, S
            for i = 1, #E._skinRegistry do pcall(E._skinRegistry[i].apply, S) end
        end
    end

    if not opts.noUnlock then
        function E.MakeUnlockElement(o)
            E.calls.MakeUnlockElement[#E.calls.MakeUnlockElement + 1] = o
            local out = {}
            for from, to in pairs(H.UNLOCK_WHITELIST) do out[to] = o[from] end
            return out
        end
        local ALIASES = { savePos = "savePosition", loadPos = "loadPosition",
            clearPos = "clearPosition", applyPos = "applyPosition" }
        function E:RegisterUnlockElements(elements, folder)
            E.calls.RegisterUnlockElements[#E.calls.RegisterUnlockElements + 1] = { elements = elements, folder = folder }
            for _, elem in ipairs(elements) do
                for short, long in pairs(ALIASES) do
                    if elem[short] and not elem[long] then elem[long] = elem[short] end
                end
                if folder and not elem.folder then elem.folder = folder end
                self._unlockRegisteredElements[elem.key] = elem
            end
        end
        if not opts.noListener then
            function E:RegisterUnlockModeListener(owner, listener)
                E.calls.RegisterUnlockModeListener[#E.calls.RegisterUnlockModeListener + 1] = owner
                self._unlockModeListeners[owner] = listener
                if self._unlockModeSessionActive then pcall(listener, true) end
            end
            function E:_NotifyUnlockModeListeners(active, closeAction)
                self._unlockModeSessionActive = active == true
                for _, listener in pairs(self._unlockModeListeners) do
                    pcall(listener, self._unlockModeSessionActive, closeAction)
                end
            end
        end
    end
    return E
end

-- The skin facade S (EllesmereUIBlizzardSkin_SkinAPI.lua): getters counting
-- their reads, OnLooksChanged keeping its functions.
function H.SkinFacade(opts)
    opts = opts or {}
    local S = { apiVersion = opts.apiVersion or 2, reads = {}, looks = {} }
    local function Count(name) S.reads[name] = (S.reads[name] or 0) + 1 end
    function S.GetAccentColor() Count("GetAccentColor"); return 0.05, 0.82, 0.62 end
    function S.GetPanelColor() Count("GetPanelColor"); return 0.03, 0.05, 0.07, 0.95 end
    function S.GetFont() Count("GetFont"); return "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF", "" end
    function S.GetStyle() Count("GetStyle"); return "eui" end
    function S.OnLooksChanged(fn)
        Count("OnLooksChanged")
        if type(fn) == "function" then S.looks[#S.looks + 1] = fn end
    end
    return S
end

-- The user changed EllesmereUI's accent: every OnLooksChanged function runs.
function H.LooksChanged(S)
    for _, fn in ipairs(S.looks) do fn() end
end

-- C_AddOns.GetAddOnMetadata answering for host addons too (map[name][field]),
-- the stub's own answer for anything else; the adapter's cached lookup is
-- forgotten so the next read takes the new function.
function H.AddOnMeta(MD, map)
    local C = _G.C_AddOns
    if type(C) ~= "table" then return end
    local real = C.GetAddOnMetadata
    C.GetAddOnMetadata = function(name, field)
        local m = map[name]
        if m ~= nil then return m[field] end
        if real then return real(name, field) end
    end
    if MD and MD.API and MD.API.Invalidate then MD.API.Invalidate("C_AddOns.GetAddOnMetadata") end
end

--------------------------------------------------------------------------------
-- The reader: what a DataBars Broker Plugin block shows (Blocks/LDB.lua).
--------------------------------------------------------------------------------
local function StripColors(str)
    if not str then return str end
    str = str:gsub("|c%x%x%x%x%x%x%x%x", "")
    str = str:gsub("|cn[%a%d_]+:", "")
    str = str:gsub("|r", "")
    return str
end

function H.LdbBlockText(obj)
    if not obj then return nil end
    local t = obj.text
    if type(t) ~= "string" or t == "" then
        local v = obj.value
        if v == nil then return nil end
        t = tostring(v)
        local suf = obj.suffix
        if type(suf) == "string" and suf ~= "" then t = t .. " " .. suf end
    end
    return StripColors(t)
end

function H.LdbIcon(obj)
    if not obj then return nil end
    local r, g, b = 1, 1, 1
    if type(obj.iconR) == "number" then r, g, b = obj.iconR, obj.iconG or 1, obj.iconB or 1 end
    return obj.icon, r, g, b
end

-- OnTooltipShow into a recording tooltip (pcall'd as the block does); nil
-- when the object has no OnTooltipShow, else the tooltip and whether it ran.
function H.LdbTooltip(obj)
    if not obj or type(obj.OnTooltipShow) ~= "function" then return nil end
    local tt = H.Tooltip()
    tt:ClearLines()
    local okRun = pcall(obj.OnTooltipShow, tt)
    if okRun then tt:Show() end
    return tt, okRun
end

-- Every global this file set, gone (a suite that wants "no host" after a host).
function H.Remove()
    for _, g in ipairs(SET) do _G[g] = nil end
end

return H
