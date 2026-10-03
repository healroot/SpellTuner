-- The spell tooltip hook (v0.14.9; damage spells v0.15.3), TBC only: the
-- SpellTuner block for the exact rank under the mouse, appended to the game's
-- own tooltip wherever it shows a spell -- action bars, the spellbook, a chat
-- link.
--
-- T121 (docs/tasks/T121-one-tooltip-block.md, docs/SPEC-one-ui.md 6): the
-- block is UI/SpellTip.lua's, the one block of both lines, drawn from the TBC
-- book (Spells/Book_Model.lua). This file only hands it the id:
-- MD.SpellTip.OnSpell(tt, id, "spell") keeps every rule -- the setting, the
-- class profile's tooltip cap (T99), the damage setting, once per showing
-- (its own OnTooltipCleared hook), the builder under pcall. Tip:Spell and
-- Tip:Damage are gone. (Moving this hook into Client/API_TBC.lua as
-- MD.API.OnSpellTooltip is a follow-up.)
--
-- The detail key: pressing or releasing the key db.spellTooltipDetail names
-- (Shift by default; Alt, Ctrl; nothing for Always / Never) re-runs the
-- owner's OnEnter while the tooltip shows a block, so the detail lines come
-- and go without moving the mouse.
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

local function OnSetSpell(tt)
    -- T99's gate, asked here before the id is read (OnSpell asks it again,
    -- for Forever's hooks): a class without the tooltip cap adds nothing
    if not (MD.ClassProfile and MD.ClassProfile:Can("tooltip")) then return end
    local id = SpellIDOf(tt)
    if not id or not (MD.SpellTip and MD.SpellTip.OnSpell) then return end
    MD.SpellTip.OnSpell(tt, id, "spell")
end

local function Hook(tt)
    if not tt or not tt.HookScript then return end
    tt:HookScript("OnTooltipSetSpell", OnSetSpell)
end
Hook(GameTooltip)
Hook(_G.ItemRefTooltip)

-- The keys each detail mode answers to (MODIFIER_STATE_CHANGED's names).
local KEYS = {
    SHIFT = { LSHIFT = true, RSHIFT = true },
    ALT = { LALT = true, RALT = true },
    CTRL = { LCTRL = true, RCTRL = true },
}

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("MODIFIER_STATE_CHANGED")
watcher:SetScript("OnEvent", function(_, _, key)
    local mode = MD.SpellTip and MD.SpellTip.DetailMode and MD.SpellTip:DetailMode()
    local keys = mode and KEYS[mode]
    if not (keys and type(key) == "string" and keys[key]) then return end
    if not (GameTooltip:IsShown() and GameTooltip._spellTipId) then return end
    local owner = GameTooltip.GetOwner and GameTooltip:GetOwner()
    local enter = owner and owner.GetScript and owner:GetScript("OnEnter")
    if enter then pcall(enter, owner) end
end)
