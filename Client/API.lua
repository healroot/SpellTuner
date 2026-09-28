-- The one file that touches the client directly, shared by every TOC (T0 of
-- docs/ROADMAP-FOREVER.md). A dotted name may not exist, may exist but be a
-- secret scalar, or may raise partway through -- Has() turns all three into a
-- plain answer so nothing downstream ever sees a raw client value it did not
-- ask for.
local ADDON_NAME, MD = ...
MD.API = MD.API or {}

local cache = {}

-- Walk _G.a.b.c one segment at a time inside ONE pcall (so a raise anywhere
-- in the walk, e.g. indexing a secret table, is caught once) and cache the
-- answer per name.
function MD.API.Has(name)
    local cached = cache[name]
    if cached ~= nil then return cached end

    -- Everything happens inside this one pcall, including classifying the
    -- walked value -- so the caller never sees the raw result and never runs
    -- an ==/~= against it either.
    local ok, result = pcall(function()
        local obj = _G
        for segment in name:gmatch("[^%.]+") do
            -- a non-table here (nil, or a value that ran out before the last
            -- segment) means the path is absent -- never index into it.
            if type(obj) ~= "table" then obj = nil; break end
            obj = obj[segment]
        end

        if type(obj) == "nil" then return false end

        -- Reached with a raw _G lookup, only called if present as a
        -- function -- a secret (of either kind) is answered true, never
        -- handed back raw.
        local isSecretValue = rawget(_G, "issecretvalue")
        if type(isSecretValue) == "function" then
            local ok2, secret = pcall(isSecretValue, obj)
            if ok2 and secret == true then return true end
        end
        local isSecretTable = rawget(_G, "issecrettable")
        if type(isSecretTable) == "function" then
            local ok2, secret = pcall(isSecretTable, obj)
            if ok2 and secret == true then return true end
        end

        if type(obj) == "function" or type(obj) == "table" then
            return obj
        end
        -- a non-nil, non-secret scalar exists, but it is never handed back
        -- raw -- the caller only asked "is it there".
        return true
    end)

    local answer
    if ok then
        answer = result
    else
        answer = false
    end
    cache[name] = answer
    return answer
end

-- Computed once at load. The interface-range comparison is the one piece of
-- flavour logic this shared file carries (CLAUDE.md: shared files reach every
-- client name through Has/pcall; no other flavour check).
local client = "unknown"
do
    local getBuildInfo = MD.API.Has("GetBuildInfo")
    if type(getBuildInfo) == "function" then
        local ok, _, _, _, iface = pcall(getBuildInfo)
        if ok then
            local secret = false
            local isSecret = MD.API.Has("issecretvalue")
            if type(isSecret) == "function" then
                local ok2, s = pcall(isSecret, iface)
                secret = ok2 and s == true
            end
            if not secret and type(iface) == "number" then
                if iface >= 16000 and iface < 20000 then
                    client = "forever"
                elseif iface >= 20000 and iface < 30000 then
                    client = "tbc"
                end
            end
        end
    end
end
MD.API.client = client

-- Packs pcall's own return alongside the count of whatever it wrapped, so a
-- nil in the middle of a client function's return list survives being
-- stored in a table and handed back out (a plain {...} loses trailing nils
-- to the # operator; select("#", ...) never does).
local function Pack(...)
    local n = select("#", ...)
    local t = {}
    for i = 1, n do t[i] = (select(i, ...)) end
    return t, n
end

-- True when either secret predicate says so, each reached through Has (so a
-- client missing one or both never raises) and called under its own pcall
-- (T0b: which of the two a secret TABLE answers is unknown, so both are
-- asked, same as Has's own internal check above).
function MD.API.IsSecret(v)
    local isSecretValue = MD.API.Has("issecretvalue")
    if type(isSecretValue) == "function" then
        local ok, secret = pcall(isSecretValue, v)
        if ok and secret == true then return true end
    end
    local isSecretTable = MD.API.Has("issecrettable")
    if type(isSecretTable) == "function" then
        local ok, secret = pcall(isSecretTable, v)
        if ok and secret == true then return true end
    end
    return false
end

-- The one place a dotted client name is actually called. A missing function
-- is a capability, not a crash; a raise is caught and its message read only
-- if it is a plain, non-secret string; a secret anywhere in the return list
-- makes the whole call secret, because a caller that got the OTHER return
-- values would still have to decide what to do with a mix -- easier and
-- safer for every shared file if one secret return taints the call.
function MD.API.Call(dotted, ...)
    local fn = MD.API.Has(dotted)
    if type(fn) ~= "function" then return nil, "absent" end

    local retvals, retn = Pack(pcall(fn, ...))
    local ok = retvals[1]
    if not ok then
        local msg = retvals[2]
        local safe = "<unreadable error>"
        if type(msg) == "string" and not MD.API.IsSecret(msg) then safe = msg end
        return nil, "error", safe
    end

    for i = 2, retn do
        if MD.API.IsSecret(retvals[i]) then return nil, "secret" end
    end
    return unpack(retvals, 2, retn)
end

-- Installs MD.API[Name] = function(...) return MD.API.Call(dotted, ...) end
-- for each Name = "dotted.client.name" pair, and remembers the binding for
-- Capabilities(). A Name that is already a member of MD.API and was NOT
-- installed by an earlier Bind (Has, Call, client, Bind itself, ...) is left
-- alone and not recorded -- Bind only ever adds or replaces its OWN bindings.
MD.API._bindings = MD.API._bindings or {}
function MD.API.Bind(map)
    for name, dotted in pairs(map) do
        if MD.API[name] == nil or MD.API._bindings[name] then
            MD.API._bindings[name] = dotted
            MD.API[name] = function(...) return MD.API.Call(dotted, ...) end
        end
    end
end

-- One entry per recorded binding, sorted by name -- what tools/adaptercheck.lua
-- and (T3) /st dump print.
function MD.API.Capabilities()
    local list = {}
    for name, dotted in pairs(MD.API._bindings) do
        list[#list + 1] = { name = name, client = dotted, present = (type(MD.API.Has(dotted)) == "function") }
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- Events a flavour file has said this client refuses to register (Forever's
-- combat log, plan §1.2). Nothing forbidden until a flavour file says so.
MD.API._forbidden = MD.API._forbidden or {}
function MD.API.ForbidEvent(event)
    MD.API._forbidden[event] = true
end
function MD.API.CanRegisterEvent(event)
    return not MD.API._forbidden[event]
end

-- The chat frame is an ordinary Lua table handed to every addon, never a
-- secret client value -- but unlike every other name on this file it is a
-- plain global variable the UI (a chat addon, a reload) may reassign after
-- login, and today's TBC MD:Print re-reads it on every call. Has()'s cache
-- is right for functions, which do not move; it would be wrong here, so this
-- one reads _G directly every time rather than going through Has.
function MD.API.Print(text)
    local frame = rawget(_G, "DEFAULT_CHAT_FRAME")
    if type(frame) == "table" then
        pcall(function() frame:AddMessage(text) end)
    end
end

-- This addon's own version, read back through the flavour's AddOnMetadata
-- binding (C_AddOns.GetAddOnMetadata on Forever, the global on TBC) rather
-- than assumed -- nil if that binding is absent or answers anything but a
-- plain string.
function MD.API.AddonVersion()
    if type(MD.API.AddOnMetadata) ~= "function" then return nil end
    local v = MD.API.AddOnMetadata(ADDON_NAME, "Version")
    if type(v) == "string" then return v end
    return nil
end

-- The names every client answers the same way -- the flavour files add the
-- five add-on names (different namespace per client) and Forever's forbidden
-- event on top of this.
MD.API.Bind({
    UnitClass = "UnitClass", UnitName = "UnitName", UnitLevel = "UnitLevel",
    UnitGUID = "UnitGUID", UnitExists = "UnitExists", UnitIsDeadOrGhost = "UnitIsDeadOrGhost",
    UnitAffectingCombat = "UnitAffectingCombat", InCombatLockdown = "InCombatLockdown",
    UnitHealth = "UnitHealth", UnitHealthMax = "UnitHealthMax",
    UnitPower = "UnitPower", UnitPowerMax = "UnitPowerMax", UnitPowerType = "UnitPowerType",
    ManaRegen = "GetManaRegen", RealmName = "GetRealmName", BuildInfo = "GetBuildInfo",
    After = "C_Timer.After", NewTicker = "C_Timer.NewTicker",
    -- T3: error capture (Core_Forever.lua). Both clients carry these three
    -- (the FrameXML error path), so they live in the shared Bind call rather
    -- than a flavour file -- unused on TBC today, same as every other name
    -- here a TBC file happens not to call.
    GetErrorHandler = "geterrorhandler", SetErrorHandler = "seterrorhandler", DebugStack = "debugstack",
})
