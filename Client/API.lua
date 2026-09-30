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

-- T52 (P8, review Q15): forget one name's cached answer, so the next Has walks
-- _G again. For the offline tests, which swap a global after the adapter has
-- already answered for it (the cache is otherwise forever, and the stub had
-- grown settable fields only to route around it). Nothing in the game calls it.
function MD.API.Invalidate(name)
    if type(name) == "string" then cache[name] = nil end
end

-- Computed once at load (T47, docs/DECISIONS.md "the client is the TOC's, the
-- interface is a fallback"). The TOC the client picked says which line this
-- is: every main TOC lists its Client/TOC_<X>.lua first, which sets our own
-- global SPELLTUNER_TOC = "<X>". The interface band decides only when that
-- marker is absent (a tool loading this file on its own), so a launch
-- interface outside 16000-19999 changes nothing. Both tables must equal
-- tools/data/flavours.txt (tools/forevercheck.lua). This is the one piece of
-- flavour logic this shared file carries.
MD.API.MARKERS = { TBC = "tbc", Mainline = "forever", Plain = "forever" }
MD.API.BANDS = { tbc = { 20000, 29999 }, forever = { 16000, 19999 } }

local client = "unknown"
do
    local marker = rawget(_G, "SPELLTUNER_TOC")
    if type(marker) == "string" and MD.API.MARKERS[marker] then
        client = MD.API.MARKERS[marker]
    else
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
                    for name, band in pairs(MD.API.BANDS) do
                        if iface >= band[1] and iface <= band[2] then client = name end
                    end
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

-- T7: a value that is a plain string, number or boolean -- what a "shared
-- file must never index a client table" file is allowed to hold onto.
local function IsPlainScalar(v)
    local t = type(v)
    return t == "string" or t == "number" or t == "boolean"
end

-- One shared walk, one shared secret counter for the whole call (so a table
-- nested three deep still adds to the SAME _secret total the top table
-- reports) -- table.lua below never sees the client's own table, only what
-- this builds.
local function CopyValue(v, depth, counter)
    if type(v) == "table" then
        if MD.API.IsSecret(v) then
            counter.n = counter.n + 1
            return nil
        end
        local out = {}
        for k, val in pairs(v) do
            local kt = type(k)
            if kt == "string" or kt == "number" then
                if MD.API.IsSecret(k) or MD.API.IsSecret(val) then
                    counter.n = counter.n + 1
                elseif IsPlainScalar(val) then
                    out[k] = val
                elseif type(val) == "table" and depth > 1 then
                    out[k] = CopyValue(val, depth - 1, counter)
                end
                -- a function, or a table one level past `depth`, is simply
                -- left out -- that is a depth question, not a secrecy one,
                -- so it is never counted in `counter`.
            end
            -- a key that is not a plain string/number (a table, a boolean, a
            -- secret) is never walked either way -- Book only ever reads a
            -- copy's fields by name/index, so a key it cannot ask for by
            -- name would never be reached regardless.
        end
        return out
    end
    if MD.API.IsSecret(v) then
        counter.n = counter.n + 1
        return nil
    end
    if IsPlainScalar(v) then return v end
    return nil -- a function, or anything else the client might hand back
end

-- T7 (Client/API.lua): a client table the adapter's own table-secrecy check
-- passed through as-is (Call only asks whether the TABLE itself is secret,
-- never its fields) may still carry a secret field several levels down --
-- Copy is what lets a shared file hold onto that table's shape without ever
-- indexing the client's own table to find out. Depth 1 keeps only the
-- table's own scalar fields; depth 2 also copies one level of nested tables
-- (an array of rows), and so on. Never raises: the whole walk runs inside
-- one pcall, same reasoning as Has() and Call() above.
function MD.API.Copy(v, depth)
    depth = depth or 1
    local counter = { n = 0 }
    local ok, result = pcall(CopyValue, v, depth, counter)
    if not ok then return nil, "error" end
    if type(result) == "table" and counter.n > 0 then
        result._secret = counter.n
    end
    return result
end

-- T7: a single plain value at a dotted path (Enum.* members, which are not
-- functions and so never go through Has/Call) -- nil for anything secret, a
-- function, a table, or a path that does not resolve. Not cached: a
-- constant is read once per caller, not remembered forever like Has()'s
-- function/table answers.
function MD.API.Constant(dotted)
    local ok, result = pcall(function()
        local obj = _G
        for segment in dotted:gmatch("[^%.]+") do
            if type(obj) ~= "table" then return nil end
            obj = obj[segment]
        end
        if MD.API.IsSecret(obj) then return nil end
        if IsPlainScalar(obj) then return obj end
        return nil
    end)
    if not ok then return nil end
    return result
end

-- Installs MD.API[Name] = function(...) return MD.API.Call(dotted, ...) end
-- for each Name = "dotted.client.name" pair, and remembers the binding for
-- Capabilities(). A Name that is already a member of MD.API and was NOT
-- installed by an earlier Bind (Has, Call, client, Bind itself, ...) is left
-- alone and not recorded -- Bind only ever adds or replaces its OWN bindings.
-- T7: a map value may instead be `{ client = "<dotted>", copy = n }`, which
-- installs a wrapper that runs every table RESULT through Copy(result, n)
-- before handing it back -- so a caller of a copying binding can never end
-- up holding the client's own table, only ever a copy of it.
MD.API._bindings = MD.API._bindings or {}
function MD.API.Bind(map)
    for name, spec in pairs(map) do
        if MD.API[name] == nil or MD.API._bindings[name] then
            local dotted, copyDepth = spec, nil
            if type(spec) == "table" then
                dotted, copyDepth = spec.client, spec.copy
            end
            MD.API._bindings[name] = dotted
            if copyDepth then
                MD.API[name] = function(...)
                    local retvals, retn = Pack(MD.API.Call(dotted, ...))
                    for i = 1, retn do
                        if type(retvals[i]) == "table" then
                            retvals[i] = MD.API.Copy(retvals[i], copyDepth)
                        end
                    end
                    return unpack(retvals, 1, retn)
                end
            else
                MD.API[name] = function(...) return MD.API.Call(dotted, ...) end
            end
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

-- T11: the one sanctioned path for a secret to leave this file -- straight
-- into a StatusBar's own setters, which the widget toolkit is allowed to
-- call (CLAUDE.md), and which never asks what it was handed. Deliberately
-- bypasses Call/IsSecret: Call would classify each return (a read, however
-- harmless), and this function's whole point is that nothing here ever
-- reads the mana value at all -- it is fetched through Has (cached, no
-- classification of the RETURN, only of the function itself) and handed
-- straight to the bar inside one pcall, the same "one raise, caught once"
-- shape as Has/Call/Copy. UnitPowerMax/UnitPower are shared names (Bind
-- below), so this lives here rather than in a flavour file.
function MD.API.DrawUnitPower(bar, unit, powerType)
    if type(bar) ~= "table" then return false, "absent" end
    local maxFn = MD.API.Has("UnitPowerMax")
    local curFn = MD.API.Has("UnitPower")
    if type(maxFn) ~= "function" or type(curFn) ~= "function" then return false, "absent" end

    local ok = pcall(function()
        local max = maxFn(unit, powerType)
        local cur = curFn(unit, powerType)
        -- Never inspected -- a secret max/cur goes straight into the bar.
        bar:SetMinMaxValues(0, max)
        bar:SetValue(cur)
    end)
    if not ok then return false, "error" end
    return true
end

-- T17c: whether a hidden status bar may be asked for a party member's max
-- health. Whether a bar hands a secret back PLAIN is UNKNOWN until the
-- author's TESTING section 38.3 report (docs/probe/<build>-alpha4-party.md):
-- its line `bar UnitHealthMax(party1): set ok, read plain <n>` switches this on
-- (one word, false -> true); `... read secret` leaves it off. Read at call
-- time, so a test may flip it and must restore it.
MD.API.BAR_READS_MAX = false

local maxBar -- created on first use, never named, never shown, never styled

-- T17c: a unit's max health as a plain number, or nil plus a reason. The
-- client's own answer goes through Has (cached, the return not classified by
-- Call); a plain number is returned as it is; a secret is refused unless
-- BAR_READS_MAX, in which case it is handed -- unread -- to a hidden bar's
-- SetMinMaxValues and the bar's second return is read back and classified
-- before anything compares it. One raise anywhere is "error" and never leaves.
function MD.API.HealthMax(unit)
    local fn = MD.API.Has("UnitHealthMax")
    if type(fn) ~= "function" then return nil, "absent" end

    local gotOk, v = pcall(fn, unit)
    if not gotOk then return nil, "error" end
    if not MD.API.IsSecret(v) then
        if type(v) == "number" then return v end
        return nil, "error"
    end
    if MD.API.BAR_READS_MAX ~= true then return nil, "secret" end

    if not maxBar then
        local cok, bar = pcall(CreateFrame, "StatusBar", nil, UIParent)
        if cok and type(bar) == "table" then maxBar = bar end
    end
    if not maxBar then return nil, "error" end

    -- The bar is shared: a failed set would leave the previous unit's value
    -- behind, so it is reset first and a failed set is never read back.
    local setOk = pcall(function()
        maxBar:SetMinMaxValues(0, 1)
        maxBar:SetMinMaxValues(0, v) -- never inspected: straight into the bar
    end)
    if not setOk then return nil, "error" end

    local readOk, _, maxV = pcall(function()
        local lo, hi = maxBar:GetMinMaxValues()
        return lo, hi
    end)
    if not readOk then return nil, "error" end
    if MD.API.IsSecret(maxV) then return nil, "secret" end
    if type(maxV) == "number" and maxV > 0 then return maxV end
    return nil, "error"
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
    -- T16a (Modules/SpellTuner_Replay/Commands_Forever.lua, UI/ReplayWindow.lua):
    -- the modifier-key predicates, the same global on both clients.
    IsShiftKeyDown = "IsShiftKeyDown", IsAltKeyDown = "IsAltKeyDown", IsControlKeyDown = "IsControlKeyDown",
})
