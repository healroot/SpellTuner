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
local H = {}

local SET = { "ElvUI", "LibStub" }

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

-- Every global this file set, gone (a suite that wants "no host" after a host).
function H.Remove()
    for _, g in ipairs(SET) do _G[g] = nil end
end

return H
