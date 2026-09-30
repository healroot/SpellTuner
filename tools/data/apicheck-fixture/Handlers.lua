-- apicheck.py selftest fixture only (T13a): two handlers that ask IsSecret
-- before a risky use (must pass), two that do not (must be found).
local _, MD = ...

MD:On("UNIT_HEALTH_GOOD", function(unit)
    if MD.API.IsSecret(unit) then return end
    if unit == "player" then
        return
    end
end)

local function OnAuraGood(unit)
    if MD.API.IsSecret(unit) then return end
    if unit == "player" then
        return
    end
end
MD:On("UNIT_AURA_GOOD", OnAuraGood)

MD:On("UNIT_HEALTH_BAD", function(unit)
    if unit == "player" then
        return
    end
end)

local function OnAuraBad(unit)
    if unit == "player" then
        return
    end
end
MD:On("UNIT_AURA_BAD", OnAuraBad)

-- T57: an alias of the param (`local sid = spellID`, the recorder's idiom):
-- asked about under its alias before the use (must pass), and not (must be found).
MD:On("UNIT_SPELLCAST_ALIAS_GOOD", function(unit, castGUID, spellID)
    local sid = spellID
    if MD.API.IsSecret(sid) then sid = -1 end
    if sid == 774 then
        return
    end
end)

MD:On("UNIT_SPELLCAST_ALIAS_BAD", function(unit, castGUID, spellID)
    local sid = spellID
    if sid == 774 then
        return
    end
end)
