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
