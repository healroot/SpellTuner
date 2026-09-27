-- The one file that touches the client directly, shared by every TOC (T0 of
-- docs/ROADMAP-FOREVER.md). A dotted name may not exist, may exist but be a
-- secret scalar, or may raise partway through -- Has() turns all three into a
-- plain answer so nothing downstream ever sees a raw client value it did not
-- ask for.
local _, MD = ...
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
