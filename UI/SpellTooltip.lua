-- The spell tooltip hook (v0.14.9; damage spells v0.15.3): SpellTuner's numbers for the exact rank
-- under the mouse, appended to the game's own tooltip wherever it shows a spell
-- -- action bars, the spellbook, a chat link. The lines are MD.Tip:Spell
-- (UI/Tooltip.lua); this file only decides WHEN to add them.
--
-- Rules it keeps:
--   * Druid only, and only for a spell Data/SpellData.lua has a row for.
--     T99 (docs/SPEC-next.md 4.4): "druid only" is the class profile's
--     `tooltip` capability, which only the druid's profile grants on TBC.
--   * Once per tooltip. OnTooltipSetSpell can fire more than once for one
--     showing, and an action button re-sets its tooltip on a timer; the id is
--     remembered until OnTooltipCleared, which every re-set goes through.
--   * Never break the game's tooltip: the builder runs under pcall.
--   * Holding or releasing Shift re-runs the owner's OnEnter so the derivation
--     appears without moving the mouse.
local _, MD = ...

-- 2.5.x returns (name, spellID); older builds returned (name, rank[, id]).
-- The id is the one number among the returns.
local function SpellIDOf(tt)
    if not tt.GetSpell then return nil end
    local r = { pcall(tt.GetSpell, tt) }
    if not r[1] then return nil end
    local id
    for i = 2, #r do
        if type(r[i]) == "number" then id = r[i] end
    end
    return id
end

-- The tooltip's own description, as the client drew it: every left-hand line
-- after the name. Read BEFORE anything is appended.
local function Description(tt)
    local name = tt.GetName and tt:GetName()
    if not (name and tt.NumLines) then return nil end
    local parts = {}
    for i = 2, tt:NumLines() do
        local fs = _G[name .. "TextLeft" .. i]
        local text = fs and fs.GetText and fs:GetText()
        if type(text) == "string" and text ~= "" then parts[#parts + 1] = text end
    end
    return table.concat(parts, " ")
end

-- v0.15.3: a damage spell. The rank's base damage comes out of the text the
-- client just drew; Engine/DamageMath.lua does the rest.
local function DamageLines(tt, id, shift)
    local DM = MD.DamageMath
    local name = DM and GetSpellInfo and GetSpellInfo(id)
    local family = DM and DM.Family(name)
    if not family then return nil end
    local base = DM.Parse(family, Description(tt))
    if not base then return nil end
    return MD.Tip:Damage(DM.Compute(id, family, base), shift)
end

function MD:SpellTooltipAppend(tt)
    if MD.db and MD.db.spellTooltip == false then return end
    if not (MD.ClassProfile and MD.ClassProfile:Can("tooltip")) then return end
    local id = SpellIDOf(tt)
    if not id then return end
    local isHeal = MD.SpellData and MD.SpellData.spells[id]
    if not isHeal and MD.db and MD.db.spellTooltipDamage == false then return end
    if tt.mdSpellID == id then return end
    tt.mdSpellID = id
    local shift = IsShiftKeyDown and IsShiftKeyDown() or false
    local ok, lines
    if isHeal then
        ok, lines = pcall(MD.Tip.Spell, MD.Tip, id, shift)
    else
        ok, lines = pcall(DamageLines, tt, id, shift)
    end
    if not ok then
        MD:Debug("other", "spell tooltip for %s failed: %s", tostring(id), tostring(lines))
        return
    end
    if lines and #lines > 0 then
        tt:AddLine(" ")
        MD.Tip:Render(tt, lines)
        tt:Show()   -- resize to the new lines
    end
end

local function Hook(tt)
    if not tt or not tt.HookScript then return end
    tt:HookScript("OnTooltipSetSpell", function(self) MD:SpellTooltipAppend(self) end)
    tt:HookScript("OnTooltipCleared", function(self) self.mdSpellID = nil end)
end
Hook(GameTooltip)
Hook(_G.ItemRefTooltip)

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("MODIFIER_STATE_CHANGED")
watcher:SetScript("OnEvent", function(_, _, key)
    if key ~= "LSHIFT" and key ~= "RSHIFT" then return end
    if not (GameTooltip:IsShown() and GameTooltip.mdSpellID) then return end
    local owner = GameTooltip.GetOwner and GameTooltip:GetOwner()
    local enter = owner and owner.GetScript and owner:GetScript("OnEnter")
    if enter then pcall(enter, owner) end
end)
