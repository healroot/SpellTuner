-- Minimal WoW-client stub: just enough of the API for the non-UI half of
-- SpellTuner to load and run outside the game, so Engine/SimModel.lua can be
-- exercised without logging in. Values mirror the BF-1 log's druid (level 64,
-- 7009 mana pool) so the numbers mean something.
--
-- This is NOT a fake client. It answers the handful of calls the engine path
-- makes and nothing else: anything it gets wrong shows up as a failing
-- assertion, not as a silently different answer. Rules it deliberately keeps:
--   * GetSpellPowerCost returns nil, so costs come from Data/SpellData.lua's
--     static table and the talent maths -- deterministic, and it exercises the
--     fallback path the live client normally hides.
--   * Frames only register events and run OnUpdate; nothing draws.
-- The forever profile's secret stand-in (S.Secret, S.SecretTable) raises on arithmetic, < <=,
-- secret-vs-secret ==, index, newindex, call, .. and tostring. It CANNOT raise on == or ~=
-- against a plain value, #, truthiness or use as a table key (Lua 5.1 gives a table no hook
-- for them), yet the client raises on ==, #, and table keys -- so a suite passing here does
-- not prove the code never does one of those to a secret. See the comment on SECRET_MT.
-- Run it with tools/run.sh (which builds a Lua 5.1 for you if there is none).
local S = {}
_G.STUB = S

S.now = 0
-- Which .toc GetAddOnMetadata reads its version from. Default is the TBC line
-- (what the sixteen suites load); S.UseProfile("forever") points it at
-- SpellTuner_Mainline.toc instead (T0c: the Forever line that actually loads
-- on the client, Q9).
S.toc = "SpellTuner_TBC.toc"
function GetTime() return S.now end
-- The sub-frame clock the search slices on. In the client this advances inside
-- a frame while GetTime() does not, which is the whole reason it is used.
function debugprofilestop() return os.clock() * 1000 end
function time() return 1757000000 end
function date(fmt, t) return os.date(fmt, t or 1757000000) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function strsplit(sep, s) return s end
function GetAddOnMetadata()
    local f = io.open((S.root or ".") .. "/" .. S.toc, "r")
    if f then
        for line in f:lines() do local v = line:match("^## Version: (.+)$"); if v then f:close(); return v end end
        f:close()
    end
    return "0.0.0"
end
function GetLocale() return "enUS" end

S.mana, S.manaMax = 7009, 7009
S.stats = { [4] = 425, [5] = 380 } -- Int, Spirit
S.level = 64

-- Unit model. Only what the engine path reads: a token -> one table. Party
-- slots can be added by a harness script (see tools/reccheck.lua).
S.units = {
    player = { guid = "Player-1", name = "Penek", class = "DRUID", role = "HEALER",
               hp = 5000, hpMax = 5000 },
}
S.unitOrder = { "player" }
function S.AddUnit(token, t)
    S.units[token] = t
    S.unitOrder[#S.unitOrder + 1] = token
    return t
end
local function U(u) return S.units[u] end

function UnitPower(u, t) return S.mana end
function UnitPowerMax(u, t) return S.manaMax end
function UnitPowerType(u) return 0 end
function UnitHealth(u) local x = U(u); return x and x.hp or 0 end
function UnitHealthMax(u) local x = U(u); return x and x.hpMax or 1 end
function UnitGUID(u) local x = U(u); return x and x.guid or nil end
function UnitName(u) local x = U(u); return x and x.name or nil end
function UnitClass(u) local x = U(u); return x and x.class or "DRUID", x and x.class or "DRUID" end
function UnitLevel(u) return S.level end
function UnitStat(u, i) return S.stats[i] or 0, S.stats[i] or 0, 0, 0 end
function UnitExists(u) return U(u) ~= nil end
function UnitIsUnit(a, b) return a == b end
function UnitAffectingCombat() return false end
function UnitGroupRolesAssigned(u) local x = U(u); return x and x.role or "NONE" end
function GetPartyAssignment() return false end
function GetRealmName() return "Anniversary" end
function GetRealZoneText() return "Blood Furnace" end
function IsInRaid() return false end
function GetNumGroupMembers() return #S.unitOrder end
function GetRaidRosterInfo() return nil end
function InCombatLockdown() return false end
function UnitAura() return nil end
-- Buffs on the player, by name, in the order the client would return them.
-- MD:HasBuff walks UnitBuff until it returns nil, so an empty list means no
-- buffs -- which is what every suite but tools/runcheck.lua wants.
S.buffs = {}
function UnitBuff(u, i) return S.buffs[i] end
S.inInstance = false
function IsInInstance() return S.inInstance, S.inInstance and "party" or "none" end

function GetManaRegen() return 69.24, 28.33 end
function GetSpellBonusHealing() return 450 end
function GetSpellCritChance() return 15 end
function GetInventoryItemID() return nil end
function GetItemInfo() return nil end
function GetSpellCooldown() return 0, 0, 1 end
-- Live costs: nil for the druid healing table (so Data/SpellData.lua's static
-- maths is exercised), a real answer for the spells that table does not know --
-- which is exactly the split the live client produces.
S.liveCosts = { [9885] = 445, [26992] = 400, [2782] = 135, [33891] = 332, [17116] = 0 }
function GetSpellPowerCost(id)
    local c = S.liveCosts[id]
    if c then return { { type = 0, cost = c } } end
    return nil
end
function IsSpellKnown(id) return S.known[id] == true end
function IsPlayerSpell(id) return S.known[id] == true end
function GetSpellTexture(id) return "Interface\\Icons\\Spell_" .. tostring(id) end
function GetSpellInfo(id)
    if type(id) == "number" then return S.spellNames[id] or ("Spell" .. id) end
    return nil
end
-- macros, for the binding import (v0.15.1): name -> body, as the client answers
S.macros = {}
-- by name (Cell stores macro names) or by index (an action slot holds one)
S.macroOrder = {}
function GetMacroInfo(which)
    local name = which
    if type(which) == "number" then name = S.macroOrder[which] end
    local m = name and S.macros[name]
    if not m then return nil end
    return name, "Interface\\Icons\\INV_Misc_QuestionMark", m
end

-- keybindings and action bars, for the binding import (v0.15.2).
-- S.bindings = { { command, key1, key2 }, ... }; S.actions[slot] = { kind, id }
S.bindings, S.actions = {}, {}
function GetNumBindings() return #S.bindings end
function GetBinding(i)
    local b = S.bindings[i]
    if not b then return nil end
    return b[1], b[2], b[3]
end
function GetBindingAction(key)
    for _, b in ipairs(S.bindings) do
        if b[2] == key or b[3] == key then return b[1] end
    end
    return ""
end
function GetActionInfo(slot)
    local a = S.actions[slot]
    if not a then return nil end
    return a[1], a[2]
end

function GetNumTalentTabs() return 3 end
function GetNumTalents() return 0 end
function GetTalentInfo() return nil end
-- Scripted combat log: S.Combat(subevent, ...) sets the payload and fires the
-- event, exactly as the client would.
S.clog = { 0, "NONE" }
function CombatLogGetCurrentEventInfo() return unpack(S.clog, 1, S.clogN or #S.clog) end
function S.Combat(...)
    S.clog = { ... }
    S.clogN = select("#", ...)
    S.Fire("COMBAT_LOG_EVENT_UNFILTERED")
end
-- modifier keys: a harness sets S.shift to click as if the key were held
S.shift = false
function IsShiftKeyDown() return S.shift == true end
function IsControlKeyDown() return S.ctrlDown == true end
function IsAltKeyDown() return S.altDown == true end
function GetWeaponEnchantInfo() return false end
function IsUsableSpell() return true end
function GetItemCount() return 0 end
function GetItemCooldown() return 0, 0 end
function GetContainerNumSlots() return 0 end
function GetContainerItemID() return nil end
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
function collectgarbage_count() return collectgarbage("count") end

S.spellNames = setmetatable({}, { __index = function(_, k) return "Spell" .. tostring(k) end })
S.known = {}

_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) print(m) end }
_G.SlashCmdList = {}
_G.UIParent = nil   -- set to a frame once CreateFrame exists (below)
_G.C_Timer = {
    After = function(_, fn) S.timers = S.timers or {}; table.insert(S.timers, fn) end,
    NewTicker = function(period, fn)
        S.tickers = S.tickers or {}
        table.insert(S.tickers, { period = period, fn = fn, acc = 0 })
        return { Cancel = function() end }
    end,
}
_G.C_Spell = nil

-- The Forever profile's client raises on registering an unknown event (T0
-- plan §1.1). This is the allowed set for the probe: every EVENTS entry it
-- registers except the combat log (whose registration outcome is itself a
-- finding, T0c: moved off the load path entirely), plus the frame-lifecycle
-- events every addon fires through, plus (T0c) the two blocked-action events
-- the probe now listens for from load.
-- Gated on S.profile so the TBC suites, which register other events, are
-- unaffected.
local FOREVER_EVENTS = {
    UNIT_SPELLCAST_SENT = true, UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_SUCCEEDED = true,
    UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_FAILED = true, UNIT_HEALTH = true,
    UNIT_MAXHEALTH = true, UNIT_POWER_UPDATE = true, UNIT_AURA = true, UNIT_FLAGS = true,
    UNIT_COMBAT = true, GROUP_ROSTER_UPDATE = true, PLAYER_REGEN_DISABLED = true,
    PLAYER_REGEN_ENABLED = true, SPELLS_CHANGED = true, PLAYER_TALENT_UPDATE = true,
    TRAIT_CONFIG_UPDATED = true, DAMAGE_METER_COMBAT_SESSION_UPDATED = true,
    ADDON_RESTRICTION_STATE_CHANGED = true, ADDON_ACTION_FORBIDDEN = true, ADDON_ACTION_BLOCKED = true,
    ADDON_LOADED = true, PLAYER_LOGIN = true, PLAYER_ENTERING_WORLD = true, PLAYER_LOGOUT = true,
}

-- Frames: only what the engine files touch (event registration and OnUpdate).
local frames = {}
local FrameMT = {}
FrameMT.__index = FrameMT
local function noop() end
-- Unknown METHODS are no-ops (WoW's are UpperCamelCase); unknown lowercase
-- keys are plain nil so a frame can carry state fields like any table.
-- The backdrop mixin is the one thing the fallback must NOT invent: it comes
-- from "BackdropTemplate" since 2.5.x, and a frame created without the template
-- errors in game the moment UI.StylizeFrame touches it. CreateFrame installs
-- these three on templated frames only.
local NO_FALLBACK = { SetBackdrop = true, SetBackdropColor = true, SetBackdropBorderColor = true }
setmetatable(FrameMT, { __index = function(_, k)
    if NO_FALLBACK[k] then return nil end
    if type(k) == "string" and k:match("^%u") then return noop end
    return nil
end })
function FrameMT:RegisterEvent(e)
    -- Recorded in every profile, before anything can forbid or raise, so a
    -- test can see exactly which events (and in what order) a frame tried to
    -- register even when the attempt never took (T0c). No TBC suite reads it.
    self.attempts = self.attempts or {}
    table.insert(self.attempts, e)
    -- A stand-in for the suspicion that a client-forbidden RegisterEvent
    -- fires ADDON_ACTION_FORBIDDEN rather than raising (T0c Facts) -- set by a
    -- script via S.forbidOnRegister[e] = "<functionName>", not a fact about
    -- the client. Checked before the unknown-event raise below, so a
    -- forbidden COMBAT_LOG_EVENT_UNFILTERED (never added to FOREVER_EVENTS)
    -- does not also raise.
    if S.profile == "forever" and type(S.forbidOnRegister) == "table" and S.forbidOnRegister[e] then
        S.Fire("ADDON_ACTION_FORBIDDEN", S.addonName, S.forbidOnRegister[e])
        return
    end
    if S.profile == "forever" and not FOREVER_EVENTS[e] then
        error('unknown event "' .. tostring(e) .. '"')
    end
    self.events[e] = true
end
function FrameMT:UnregisterEvent(e) self.events[e] = nil end
function FrameMT:SetScript(k, fn) self.scripts[k] = fn end
function FrameMT:GetScript(k) return self.scripts[k] end
function FrameMT:IsShown() return self.shown == true end
-- Visible means shown AND every parent shown, which is what the eye sees: the
-- client hides a whole subtree when it hides a frame, and a harness that only
-- knows IsShown cannot tell that a hidden panel's buttons are gone (v0.11.5).
function FrameMT:IsVisible()
    local f, guard = self, 0
    while f and guard < 50 do
        if f.shown ~= true then return false end
        f, guard = f.parentFrame, guard + 1
    end
    return true
end
function FrameMT:SetParent(p) self.parentFrame = p end
function FrameMT:GetParent() return self.parentFrame end
-- Show/Hide fire OnShow/OnHide, as the client does: a window that populates
-- itself in OnShow (the dashboard) would otherwise open empty under the stub.
function FrameMT:Show()
    local was = self.shown
    self.shown = true
    if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function FrameMT:Hide()
    local was = self.shown
    self.shown = false
    if was and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function FrameMT:SetSize(w, h) self.w, self.h = w, h end
function FrameMT:SetWidth(w) self.w = w end
function FrameMT:SetHeight(h) self.h = h end
function FrameMT:GetWidth() return self.w or 100 end
function FrameMT:GetHeight() return self.h or 20 end
function FrameMT:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function FrameMT:GetFrameLevel() return 1 end
function FrameMT:GetScale() return 1 end
function FrameMT:GetEffectiveScale() return 1 end
function FrameMT:GetAlpha() return 1 end
function FrameMT:GetLeft() return 0 end
function FrameMT:GetRight() return self.w or 100 end
function FrameMT:GetTop() return self.h or 20 end
function FrameMT:GetBottom() return 0 end
-- Enough of a widget for the UI files to load and paint: font strings and
-- textures are frames too (every unknown method is a no-op), text and values
-- are stored so a harness can read back what was painted.
local function Child(kind, parent)
    local c = setmetatable({ events = {}, scripts = {}, kind = kind, parentFrame = parent,
                             shown = true }, FrameMT)
    -- font strings and textures go into the same registry as frames, so a
    -- harness can read back every string a pane painted (tools/reviewui.lua)
    frames[#frames + 1] = c
    return c
end
function FrameMT:CreateFontString() return Child("FontString", self) end
function FrameMT:CreateTexture() return Child("Texture", self) end
function FrameMT:GetFontString() self.fs = self.fs or Child("FontString", self); return self.fs end
function FrameMT:SetText(t) self.text = t end
-- SetFormattedText was falling through to the no-op fallback, so every string
-- written with it was invisible to the harnesses -- including their bare-pipe
-- scans (v0.11.1)
function FrameMT:SetFormattedText(fmt, ...)
    local ok, out = pcall(string.format, fmt, ...)
    self.text = ok and out or tostring(fmt)
end
function FrameMT:GetText() return self.text or "" end
function FrameMT:GetStringWidth() return 40 end
function FrameMT:GetStringHeight() return 12 end
-- the addon prefers Show/Hide (older clients), but it does use SetShown in
-- places and the stub has to see through it either way
function FrameMT:SetShown(v) if v then self:Show() else self:Hide() end end
function FrameMT:SetValue(v) self.value = v end
function FrameMT:GetValue() return self.value or 0 end
function FrameMT:SetMinMaxValues(a, b) self.minV, self.maxV = a, b end
function FrameMT:SetChecked(v) self.checked = v and true or false end
function FrameMT:GetChecked() return self.checked == true end
-- Was a no-op through the fallback; no TBC suite reads the field, but T0b's
-- "the copy box has no letter cap" does.
function FrameMT:SetMaxLetters(n) self.maxLetters = n end
function FrameMT:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
function FrameMT:SetStatusBarColor(r, g, b) self.barColor = { r, g, b } end
function FrameMT:SetTextColor(r, g, b) self.textColor = { r, g, b } end
-- enabled state is stored (not a no-op) so a harness can read back which
-- buttons a pane turned off and why
function FrameMT:Enable() self.enabled = true end
function FrameMT:Disable() self.enabled = false end
function FrameMT:IsEnabled() return self.enabled ~= false end
_G.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
_G.tinsert = table.insert
_G.UISpecialFrames = {}
_G.PlaySound = noop
-- font objects are frames too; GetFont is the one call the kit makes at load
function FrameMT:GetFont() return "font", 12, "" end
function CreateFont() return Child("Font") end
_G.GameFontNormal = CreateFont()
_G.GameFontNormalSmall = CreateFont()
_G.GameFontHighlightSmall = CreateFont()
_G.RAID_CLASS_COLORS = {
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, DRUID = { r = 1, g = 0.49, b = 0.04 },
    MAGE = { r = 0.41, g = 0.8, b = 0.94 }, WARLOCK = { r = 0.58, g = 0.51, b = 0.79 },
    PALADIN = { r = 0.96, g = 0.55, b = 0.73 }, PRIEST = { r = 1, g = 1, b = 1 },
}

function CreateFrame(kind, name, parent, tmpl)
    -- a new frame is SHOWN in the client; the kit's CreateFrame hides the ones
    -- that should start hidden
    local f = setmetatable({ events = {}, scripts = {}, kind = kind, frameName = name,
                             parentFrame = parent, shown = true }, FrameMT)
    -- The backdrop mixin is NOT on every frame since 2.5.x: it comes from
    -- "BackdropTemplate", and calling SetBackdrop without it is a live error.
    -- The stub used to hand it to everything through the no-op fallback, so the
    -- harness could not see the one frame in UI/SimWindow.lua that was missing
    -- the template until the author opened the tab in game (v0.11.10).
    if type(tmpl) == "string" and tmpl:find("BackdropTemplate") then
        f.SetBackdrop = function(self, bd) self.backdrop = bd end
        f.SetBackdropColor = function(self, r, g, b, a) self.bg = { r, g, b, a } end
        f.SetBackdropBorderColor = function(self, r, g, b, a) self.border = { r, g, b, a } end
    end
    frames[#frames + 1] = f
    -- a named frame is a global in the client, and addon code looks itself up
    -- that way (tinsert(UISpecialFrames, "SpellTunerDashboard"), _G[name])
    if name then _G[name] = f end
    return f
end

-- every frame ever created, so a harness can find the rows a pane painted
S.allFrames = frames

_G.UIParent = CreateFrame("Frame")
_G.GameTooltip = CreateFrame("GameTooltip")

function S.Fire(event, ...)
    for _, f in ipairs(frames) do
        if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
    end
end

function S.Tick(dt)
    S.now = S.now + dt
    for _, f in ipairs(frames) do
        if f.scripts.OnUpdate then f.scripts.OnUpdate(f, dt) end
    end
    for _, tk in ipairs(S.tickers or {}) do
        tk.acc = tk.acc + dt
        while tk.acc >= tk.period do tk.acc = tk.acc - tk.period; tk.fn() end
    end
end

-- Switches the stub's globals to the Forever profile (T0). Called once, by a
-- probecheck-style script, before any addon file loads. "forever" is the only
-- name for now -- the full "only what exists" stub is M1's T5, not this task;
-- everything the TBC profile defines above stays unless named here.
function S.UseProfile(name)
    if name ~= "forever" then return end
    S.profile = "forever"
    S.toc = "SpellTuner_Mainline.toc"
    S.inCombat = false
    S.bonusHealing = 0
    S.bonusDamage = {}
    S.descShift = 0
    function GetSpellBonusDamage(school) return S.bonusDamage[school] or 0 end

    -- plan §1.1-1.2: gone on Forever.
    CombatLogGetCurrentEventInfo = nil
    GetSpellInfo = nil
    UnitAura = nil
    UnitBuff = nil
    GetTalentInfo = nil
    GetItemInfo = nil

    -- A secret value, measured under Lua 5.1 (lead, 2026-09-27):
    --   raises here: arithmetic, unary minus, < <= (against anything), secret-vs-secret ==,
    --   index, newindex, call, .., tostring;
    --   passes silently here: == or ~= against a plain value, #, truthiness (if v then), use as a
    --   table key, type().
    -- On the client (plan 1.2): comparison, #, table key and call raise; type() works
    -- (EllesmereUI); truthiness is UNKNOWN. So the stub is LOOSER than the client on ==, ~=, #
    -- and table keys, and nothing a metatable can do in Lua 5.1 closes that gap. __concat and
    -- __tostring are stricter than the client, which yields a secret string that raises later.
    local function secretRaise() error("attempt to use a secret value (stub)") end
    local SECRET_MT = {
        __add = secretRaise, __sub = secretRaise, __mul = secretRaise, __div = secretRaise,
        __mod = secretRaise, __pow = secretRaise, __unm = secretRaise, __concat = secretRaise,
        __lt = secretRaise, __le = secretRaise, __eq = secretRaise, __len = secretRaise,
        __index = secretRaise, __newindex = secretRaise, __call = secretRaise, __tostring = secretRaise,
    }
    function S.Secret() return setmetatable({}, SECRET_MT) end
    function issecretvalue(v) return rawequal(getmetatable(v), SECRET_MT) end

    -- A stand-in for a secret TABLE, same raising behaviour, its own marker --
    -- the client's actual split between issecretvalue and issecrettable is
    -- UNKNOWN (T0b Facts), so this is only "the same shape, a different flag".
    local SECRETTABLE_MT = {
        __add = secretRaise, __sub = secretRaise, __mul = secretRaise, __div = secretRaise,
        __mod = secretRaise, __pow = secretRaise, __unm = secretRaise, __concat = secretRaise,
        __lt = secretRaise, __le = secretRaise, __eq = secretRaise, __len = secretRaise,
        __index = secretRaise, __newindex = secretRaise, __call = secretRaise, __tostring = secretRaise,
    }
    function S.SecretTable() return setmetatable({}, SECRETTABLE_MT) end
    function issecrettable(v) return rawequal(getmetatable(v), SECRETTABLE_MT) end

    -- plan §1.5: a stand-in build number, not the real beta's.
    function GetBuildInfo() return "1.60.1", "70009", "Sep 20 2026", 16001 end
    WOW_PROJECT_ID = 1
    WOW_PROJECT_MAINLINE = 1

    function UnitAffectingCombat() return S.inCombat end
    function InCombatLockdown() return S.inCombat end
    -- A stand-in that exercises the secret path -- NOT a claim about what Q2
    -- (party health readable in combat) actually answers on Forever.
    function UnitHealth(u)
        if S.inCombat and u ~= "player" then return S.Secret() end
        local x = U(u); return x and x.hp or 0
    end
    function UnitHealthMax(u)
        if S.inCombat and u ~= "player" then return S.Secret() end
        local x = U(u); return x and x.hpMax or 1
    end

    function GetSpellBonusHealing() return S.bonusHealing end
    function GetShapeshiftFormID() return nil end

    -- Two returns, name and nil, the way the client's UnitName does (a realm
    -- name only on a cross-realm unit) -- T0b's fix for the "Healroot, nil"
    -- join bug needs a second return to have anything to truncate.
    function UnitName(u)
        local x = U(u)
        if x then return x.name, nil end
        return nil
    end

    -- T0c: the secret-question globals. Same in-combat-and-not-player gate as
    -- UnitHealth/UnitHealthMax above -- a stand-in, not a claim about Q2/Q5.
    function UnitHealthPercent(u, usePredicted, curve)
        if S.inCombat and u ~= "player" then return S.Secret() end
        local x = U(u)
        if not x then return nil end
        return x.hp / x.hpMax * 100
    end
    function UnitHealthMissing(u)
        if S.inCombat and u ~= "player" then return S.Secret() end
        local x = U(u)
        if not x then return nil end
        return x.hpMax - x.hp
    end
    function UnitPowerPercent(u, powerType)
        if u == "player" then return S.mana / S.manaMax * 100 end
        return nil
    end
    function UnitGetIncomingHeals(u, healer)
        if U(u) then return 0 end
        return nil
    end
    function UnitIsDeadOrGhost(u) return false end

    Enum = {
        SpellBookSpellBank = { Player = 0 },
        DamageMeterType = { HealingDone = 1 },
        DamageMeterSessionType = { Overall = 0, Current = 1 },
    }

    -- Five slots: two ranks of Rejuvenation (774 rank 1, 1058 rank 2) for the
    -- ranks-per-name count, Healing Touch, a non-heal (Wrath) for the
    -- healing/non-healing split (Q1), and slot 4's row raises on every index
    -- (not secret) for the spellbook-error tally. 774's description reads
    -- S.bonusHealing live, so a probe run after changing it sees a different
    -- number; 1058's is fixed.
    local SPELL_SLOTS = { [1] = 774, [2] = 5185, [3] = 5176, [5] = 1058 }
    local ERROR_ROW = setmetatable({}, { __index = function() error("spellbook row unreadable (stub)") end })
    local SPELL_NAMES = { [774] = "Rejuvenation", [5185] = "Healing Touch", [5176] = "Wrath", [1058] = "Rejuvenation" }
    local SPELL_SUBTEXT = { [774] = "Rank 1", [5185] = "Rank 1", [5176] = "Rank 1", [1058] = "Rank 2" }
    -- T0c: 774's amount also carries S.descShift, a stand-in for a description
    -- that moved with a level-up rather than with bonus healing (reads exactly
    -- as before at descShift 0). 5176's amount carries S.bonusDamage[4]
    -- (Nature), a stand-in for the elixir test -- also unchanged at 0.
    local SPELL_DESC = {
        [774] = function() return "Heals the target for " .. (32 + S.bonusHealing + S.descShift) .. " over 12 sec." end,
        [5185] = function() return "Heals a friendly target for 40 to 55.|nIt is \226\128\156quoted\226\128\157." end,
        [5176] = function()
            local n = S.bonusDamage[4] or 0
            return "Causes " .. (13 + n) .. " to " .. (16 + n) .. " Nature damage to the target."
        end,
        [1058] = function() return "Heals the target for 56 over 12 sec." end,
    }
    C_SpellBook = {
        GetSpellBookItemInfo = function(slot, bank)
            if slot == 4 then return ERROR_ROW end
            local id = SPELL_SLOTS[slot]
            if not id then return nil end
            return { spellID = id }
        end,
    }
    -- Adds a spell in the first free slot from 6 on -- for tests that need
    -- more spellbook rows than the fixed five above (T0c step 6's elixir
    -- test). descFn follows SPELL_DESC's own shape: a zero-argument function.
    local nextFreeSlot = 6
    function S.AddSpell(id, name, rank, descFn)
        while SPELL_SLOTS[nextFreeSlot] do nextFreeSlot = nextFreeSlot + 1 end
        SPELL_SLOTS[nextFreeSlot] = id
        nextFreeSlot = nextFreeSlot + 1
        SPELL_NAMES[id] = name
        SPELL_SUBTEXT[id] = rank
        SPELL_DESC[id] = descFn
    end
    C_Spell = {
        GetSpellName = function(id) return SPELL_NAMES[id] end,
        GetSpellSubtext = function(id) return SPELL_SUBTEXT[id] end,
        GetSpellDescription = function(id)
            -- 5185's description goes secret in combat only -- a stand-in to
            -- exercise "an unreadable description is not counted as changed";
            -- the other ids are unaffected by combat.
            if id == 5185 and S.inCombat then return S.Secret() end
            local f = SPELL_DESC[id]
            if f then return f() end
            return nil
        end,
    }

    C_Secrets = {
        ShouldAurasBeSecret = function() return S.inCombat end,
        ShouldUnitIdentityBeSecret = function(u)
            if u == nil then error("bad argument #1") end
            return false
        end,
        ["ShouldStub|Piped"] = function() return false end,
        -- T0c: the secret-question predicates. Each raises "bad argument #1"
        -- on a nil first argument, as the client does, except
        -- HasSecretRestrictions which takes none and never raises.
        HasSecretRestrictions = function() return S.inCombat end,
        ShouldUnitHealthMaxBeSecret = function(u)
            if u == nil then error("bad argument #1") end
            return S.inCombat and u ~= "player"
        end,
        ShouldUnitPowerBeSecret = function(u, pt)
            if u == nil then error("bad argument #1") end
            return false
        end,
        ShouldUnitPowerMaxBeSecret = function(u, pt)
            if u == nil then error("bad argument #1") end
            return false
        end,
        GetPowerTypeSecrecy = function(pt)
            if pt == nil then error("bad argument #1") end
            return 0
        end,
        CanCompareUnitTokens = function(a, b)
            if a == nil or b == nil then error("bad argument #1") end
            return true
        end,
    }

    C_UnitAuras = {
        GetAuraDataByIndex = function(u, i, filter)
            if S.inCombat then error("Auras cannot be accessed when secret while tainted") end
            if u == "player" and i == 1 then
                return { name = "Mark of the Wild", spellId = 1126, duration = 1800 }
            end
            return nil
        end,
    }

    C_SpecializationInfo = {
        GetTalentInfo = function(a, b)
            if type(a) == "number" then
                error("bad argument #1 to 'GetTalentInfo' (table expected, got number)")
            end
            -- What the client answered at level 8 (T0c Facts): nil below the
            -- level talents start at, the row otherwise.
            if S.level < 10 then return nil end
            return { name = "Improved Wrath", rank = 0 }
        end,
    }
    -- C_Traits and C_ClassTalents stay undefined -- the absent path (Q6).
    C_Traits = nil
    C_ClassTalents = nil

    -- Secret exactly while in combat, unless a script has explicitly said the
    -- beta does not secret this one (S.meterSecretInCombat = false) -- the
    -- default (nil) keeps the T0 in-combat-is-secret behaviour.
    local function meterSecretNow()
        return S.inCombat and S.meterSecretInCombat ~= false
    end
    C_DamageMeter = {
        IsDamageMeterAvailable = function() return true end,
        GetCombatSessionFromType = function(st, mt)
            if meterSecretNow() then return S.SecretTable() end
            return { combatSources = {
                { sourceGUID = "Player-1", isLocalPlayer = true, totalAmount = 1234, amountPerSecond = 41 },
            } }
        end,
        GetCombatSessionSourceFromType = function(st, mt, guid, cid)
            if meterSecretNow() then return S.SecretTable() end
            -- T0c: every row carries combatSpellDetails one level deep (a
            -- stand-in for EllesmereUI's own reading of the field), and the
            -- Overall session lists six spells against Current's one, so the
            -- five-row cap on the dump has something to cap.
            local function row(id, amount)
                return { spellID = id, totalAmount = amount,
                    combatSpellDetails = { unitName = "Tankname", unitClassFilename = "WARRIOR", specIconID = 0 } }
            end
            if st == Enum.DamageMeterSessionType.Overall then
                return { combatSpells = {
                    row(774, 1000), row(5185, 900), row(1058, 800),
                    row(5186, 700), row(8936, 600), row(740, 500),
                } }
            end
            return { combatSpells = { row(774, 1000) } }
        end,
    }
end

-- Installs C_ClassTalents/C_Traits (T0b) -- called explicitly by a script that
-- wants to test the branch where they answer, since UseProfile("forever")
-- itself still leaves them undefined (the absent path stays the default).
function S.AddTraits()
    C_ClassTalents = { GetActiveConfigID = function() return 7 end }
    C_Traits = { GetConfigInfo = function(id)
        if id == 7 then return { ID = 7, name = "Stub loadout", type = 1 } end
        return nil
    end }
end

function S.Load(files, addonName, MD)
    -- Read by FrameMT:RegisterEvent's forbid stand-in (S.Fire("ADDON_ACTION_FORBIDDEN", S.addonName, ...)),
    -- which needs the addon name before any file has registered anything.
    S.addonName = addonName
    for _, rel in ipairs(files) do
        local path = S.root .. "/" .. rel
        local chunk, err = loadfile(path)
        if not chunk then error("load " .. rel .. ": " .. tostring(err)) end
        chunk(addonName, MD)
    end
end
