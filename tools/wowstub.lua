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
-- T5: which VALUES the forever profile treats as secret follows the 70009 reports
-- (docs/probe/1.60.1_70009.md, sixth-ninth) rather than a guess -- current health/power
-- always secret, a party member's max health always secret, regen secret only in combat.
-- Run it with tools/run.sh (which builds a Lua 5.1 for you if there is none).
local S = {}
_G.STUB = S

S.now = 0
-- Which .toc GetAddOnMetadata reads its version from. Default is the TBC line
-- (what the sixteen suites load); S.UseProfile("forever") points it at
-- SpellTuner_Mainline.toc instead (T0c: the Forever line that actually loads
-- on the client, Q9).
S.toc = "SpellTuner_TBC.toc"

-- T5: a .toc's load list, in order -- CR stripped, comments and blank lines
-- skipped, backslashes turned into forward slashes. Used by tools/harness.lua
-- so the file list is the TOC's own, not a hand-kept copy of it.
function S.TocFiles(tocName)
    local files = {}
    local f = io.open((S.root or ".") .. "/" .. tocName, "r")
    if not f then return files end
    for line in f:lines() do
        line = line:gsub("\r$", "")
        if line:match("%S") and line:sub(1, 1) ~= "#" then
            files[#files + 1] = (line:gsub("\\", "/"))
        end
    end
    f:close()
    return files
end
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
-- The client's own UnitClass returns the LOCALIZED class name first, the
-- token ("DRUID") second (docs/tasks/T1b Review, re-issue 2) -- every reader
-- in the tree (Engine/Targets.lua, UI/Style.lua, Client/Probe.lua) already
-- takes the second, so this fix changes no TBC suite. A unit can carry its
-- own `localized` override; otherwise it is derived from the token (only the
-- first letter upper-case, which is wrong for e.g. "DEATHKNIGHT" but no test
-- needs more than that).
function UnitClass(u)
    local x = U(u)
    local token = x and x.class or "DRUID"
    local loc = x and x.localized or (token:sub(1, 1) .. token:sub(2):lower())
    return loc, token
end
function UnitLevel(u) return S.level end
function UnitStat(u, i) return S.stats[i] or 0, S.stats[i] or 0, 0, 0 end
function UnitExists(u) return U(u) ~= nil end
function UnitIsUnit(a, b) return a == b end
function UnitAffectingCombat() return false end
function UnitGroupRolesAssigned(u) local x = U(u); return x and x.role or "NONE" end
function GetPartyAssignment() return false end
function GetRealmName() return "Anniversary" end
-- Lead review 1 (T13): S.zoneText wins when a fixture sets it -- MD.API.Has
-- caches the resolved FUNCTION per dotted name forever, so a test cannot
-- swap the global after the first call has already been made; this same
-- function reads a settable field instead, so the cache is never an issue.
function GetRealZoneText() return S.zoneText or "Blood Furnace" end
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
    -- T25: a macro slot may answer a third value (the sub-type, "spell" on
    -- newer retail); unset, exactly the two values every earlier caller saw.
    if a[3] ~= nil then return a[1], a[2], a[3] end
    return a[1], a[2]
end
-- T25: a macro's spell by macro index, from S.macroSpells[index] (nil = the
-- macro casts no spell the client can name).
S.macroSpells = {}
function GetMacroSpell(index)
    return S.macroSpells[index]
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
    -- T12b Facts: exists on the retail engine (EllesmereUI's event list does
    -- not name it -- it is not measured, only assumed present).
    PLAYER_TARGET_CHANGED = true,
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
    -- T0d: a script's own stand-in for "this event is not one the client
    -- accepts here", distinct from S.forbidOnRegister (which fires the
    -- blocked-action event instead of raising) and from FOREVER_EVENTS
    -- (this file's fixed idea of what the client accepts) -- lets a suite
    -- make an ordinary, allowed event raise for one step without touching
    -- either of those.
    if S.profile == "forever" and type(S.raiseOnRegister) == "table" and S.raiseOnRegister[e] then
        error('unknown event "' .. tostring(e) .. '"')
    end
    -- T5, Facts (sixth report, "== events"/"== blocked actions"): the client
    -- does not raise on this one -- RegisterEvent returns normally, then
    -- ADDON_ACTION_FORBIDDEN fires with the unnamed caller ("UNKNOWN()"), and
    -- the event never actually registers. Checked ahead of FOREVER_EVENTS so
    -- it does not also hit the unknown-event raise below.
    if S.profile == "forever" and e == "COMBAT_LOG_EVENT_UNFILTERED" then
        S.forbidden = S.forbidden or {}
        table.insert(S.forbidden, { event = e })
        S.Fire("ADDON_ACTION_FORBIDDEN", S.addonName, "UNKNOWN()")
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
-- T9: chains onto whatever script is already there rather than replacing it
-- (UI/SpellTooltip.lua's TBC precedent, and now UI/SpellTip_Forever.lua) --
-- the client's own HookScript never drops the frame's existing handler.
function FrameMT:HookScript(k, fn)
    local prev = self.scripts[k]
    self.scripts[k] = function(...)
        if prev then prev(...) end
        return fn(...)
    end
end
-- T9: enough of the tooltip widget for UI/SpellTip_Forever.lua's block --
-- lines kept as { left, right } pairs so a harness can read back exactly what
-- was appended, in order.
function FrameMT:AddLine(left) self.lines = self.lines or {}; table.insert(self.lines, { left }) end
function FrameMT:AddDoubleLine(left, right) self.lines = self.lines or {}; table.insert(self.lines, { left, right }) end
function FrameMT:NumLines() return self.lines and #self.lines or 0 end
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
-- T10c: a font string's word wrap, default true (the client's) -- recorded so
-- a harness can assert a cell was told not to wrap.
function FrameMT:SetWordWrap(v) self.wordWrap = v and true or false end
function FrameMT:GetWordWrap() if self.wordWrap == nil then return true end return self.wordWrap end
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
-- T13e: the setter already stores what it was given; the getter just hands
-- it back, same as the real client's StatusBar.
function FrameMT:GetMinMaxValues() return self.minV, self.maxV end
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
-- T29: SetFont is recorded and GetFont hands it back, so a harness can read a
-- font object's face and size (UI/Theme_Forever.lua's fonts and offset); an
-- object never given SetFont answers as before.
function FrameMT:SetFont(path, size, flags) self.fontPath, self.fontSize, self.fontFlags = path, size, flags end -- T29
function FrameMT:GetFont()
    if self.fontSize ~= nil then return self.fontPath, self.fontSize, self.fontFlags end -- T29
    return "font", 12, ""
end
function CreateFont() return Child("Font") end
-- T29: the physical screen (UI.px through MD.API.PhysicalScreenSize); in the
-- 69893 baseline, so the forever profile keeps it. A script sets the fields.
S.physicalWidth, S.physicalHeight = 1920, 1080 -- T29
function GetPhysicalScreenSize() return S.physicalWidth, S.physicalHeight end -- T29
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
        -- T29: the mixin's getters (UI.RestylePixels keeps a frame's current colours)
        f.GetBackdropColor = function(self) if self.bg then return unpack(self.bg) end end -- T29
        f.GetBackdropBorderColor = function(self) if self.border then return unpack(self.border) end end -- T29
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
    -- T12b (m2 line 220): GetSpellBonusHealing() is not plain in combat on
    -- this client. Off by default so no other suite changes; a script that
    -- needs the secret-in-combat behaviour sets this true.
    S.bonusHealingSecretInCombat = false
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

    -- T3: the FrameXML error path. S.errorHandler starts as the client's own
    -- default handler (a stand-in for what geterrorhandler answers before any
    -- addon replaces it), which records every message it is ever handed in
    -- S.clientErrors -- so a consolecheck case can tell whether OUR handler
    -- forwarded a given message without needing to read chat output. Whoever
    -- calls seterrorhandler simply becomes S.errorHandler from then on.
    S.clientErrors = {}
    local function initialErrorHandler(msg)
        S.clientErrors[#S.clientErrors + 1] = msg
    end
    S.errorHandler = initialErrorHandler
    function geterrorhandler() return S.errorHandler end
    function seterrorhandler(h) S.errorHandler = h end
    -- review-core: the REAL stack, one line per level the way the client
    -- prints it (level 1 = the function that called debugstack; C frames as
    -- "[C]", tail calls as "(tail call)"; the top `lines1` and bottom `lines2`
    -- with "..." between), so a capture that names the adapter's frames
    -- instead of the code that raised fails here as it does in the client.
    local dbg = debug -- review-core
    function debugstack(level, lines1, lines2) -- review-core
        level, lines1, lines2 = level or 1, lines1 or 12, lines2 or 10
        local all, l = {}, level + 1
        while true do
            local info = dbg.getinfo(l, "Sln")
            if not info then break end
            local name = info.name and ("'" .. info.name .. "'") or "?"
            if info.what == "C" then
                all[#all + 1] = "[C]: in function " .. name
            elseif info.what == "tail" then
                all[#all + 1] = "(tail call): ?"
            else
                all[#all + 1] = string.format("%s:%d: in function %s", info.short_src,
                    info.currentline or 0, info.name and name or ("<" .. info.short_src .. ":" .. (info.linedefined or 0) .. ">"))
            end
            l = l + 1
        end
        if #all <= lines1 + lines2 then return table.concat(all, "\n") .. "\n" end
        local out = {}
        for i = 1, lines1 do out[#out + 1] = all[i] end
        out[#out + 1] = "..."
        for i = #all - lines2 + 1, #all do out[#out + 1] = all[i] end
        return table.concat(out, "\n") .. "\n"
    end

    function UnitAffectingCombat() return S.inCombat end
    function InCombatLockdown() return S.inCombat end

    -- T5, Facts (sixth-eighth reports): current health and power are secret for
    -- EVERY existing unit, in and out of combat -- unlike the T0c stand-in this
    -- replaces, the player is not exempt. A unit that does not exist answers
    -- nil, the same as the percent-style functions always did.
    local function secretOrNil(u)
        if not U(u) then return nil end
        return S.Secret()
    end
    function UnitHealth(u) return secretOrNil(u) end
    function UnitPower(u, t) return secretOrNil(u) end

    -- T5, Facts (eighth report): maxima are the one split -- the player's own
    -- are plain (Core.lua's own mana pool needs them), a party member's are
    -- secret, in and out of combat either way.
    function UnitHealthMax(u)
        if u == "player" then local x = U(u); return x and x.hpMax or 1 end
        return secretOrNil(u)
    end
    function UnitPowerMax(u, t)
        if u == "player" then return S.manaMax end
        return secretOrNil(u)
    end

    function GetSpellBonusHealing()
        if S.bonusHealingSecretInCombat and S.inCombat then return S.Secret() end
        return S.bonusHealing
    end
    function GetShapeshiftFormID() return nil end

    -- retail 12.x documented shape, NOT observed on Forever -- the probe's == shapes checks it.
    -- Secret in combat like the other stat-ish predicates (ShouldUnitStatsBeSecret's gate).
    S.crit = {}
    function GetSpellCritChance(school)
        if S.inCombat then return S.Secret() end
        return S.crit[school] or 5
    end

    -- T5, Facts (seventh report): plain out of combat, secret both returns in
    -- combat.
    function GetManaRegen()
        if S.inCombat then return S.Secret(), S.Secret() end
        return 69.24, 28.33
    end

    -- Two returns, name and nil, the way the client's UnitName does (a realm
    -- name only on a cross-realm unit) -- T0b's fix for the "Healroot, nil"
    -- join bug needs a second return to have anything to truncate.
    function UnitName(u)
        local x = U(u)
        if x then return x.name, nil end
        return nil
    end

    -- T5: the same always-secret rule as UnitHealth/UnitPower above, for the
    -- rest of the secret-question globals the eighth report read side by side
    -- with them.
    function UnitHealthPercent(u, usePredicted, curve) return secretOrNil(u) end
    function UnitHealthMissing(u) return secretOrNil(u) end
    function UnitPowerPercent(u, powerType) return secretOrNil(u) end
    function UnitGetIncomingHeals(u, healer) return secretOrNil(u) end
    -- T13: plain (Facts) -- answers a fixture's own S.units[u].dead flag
    -- rather than always false, so a script can script a death.
    function UnitIsDeadOrGhost(u)
        local x = U(u)
        return x ~= nil and x.dead == true
    end

    -- T13b: a role set directly on S.roles[u] wins (a script naming a role
    -- without building a whole S.AddUnit fixture); otherwise falls back to
    -- the unit's own .role (S.AddUnit), else "NONE".
    S.roles = S.roles or {}
    function UnitGroupRolesAssigned(u)
        if S.roles[u] ~= nil then return S.roles[u] end
        local x = U(u)
        return (x and x.role) or "NONE"
    end

    -- T13b: UnitGUID(party1) answers a fixed placeholder if the unit was
    -- never given its own guid, so a script does not have to build a whole
    -- S.AddUnit fixture just to prove a GUID is readable.
    local baseUnitGUID = UnitGUID
    function UnitGUID(u)
        local g = baseUnitGUID(u)
        if g then return g end
        if u == "party1" then return "Player-1-00000001" end
        return nil
    end

    -- T11: one own cast succeeding, the way the client would fire it (Facts:
    -- whether the spellID argument itself is readable in combat is UNKNOWN,
    -- so a caller may hand S.Cast a plain id or S.Secret() either way).
    -- unit defaults to "player"; a suite names another unit to prove a cast
    -- on it is ignored.
    function S.Cast(id, unit)
        S.Fire("UNIT_SPELLCAST_SUCCEEDED", unit or "player", "cast-guid", id)
    end

    -- T12: one UNIT_COMBAT event, in the shape Facts give -- (unit, action,
    -- descriptor, amount, school). Overrides the TBC-profile S.Combat above
    -- (which fires the combat log Forever forbids); args are reordered here
    -- for a caller's convenience (amount is the number a fixture actually
    -- varies, descriptor never is) and put back in the client's own order
    -- before firing. A caller may hand either argument S.Secret() to prove
    -- the unreadable case.
    function S.Combat(unit, action, amount, descriptor)
        S.Fire("UNIT_COMBAT", unit, action, descriptor, amount, nil)
    end

    Enum = {
        SpellBookSpellBank = { Player = 0 },
        DamageMeterType = { HealingDone = 1 },
        DamageMeterSessionType = { Overall = 0, Current = 1 },
        -- T7a's own retail-documented values (Spell = the ordinary row every
        -- fixed slot above already answers via itemType = 1); NOT observed
        -- on Forever.
        SpellBookItemType = { Spell = 1, FutureSpell = 2, Flyout = 3, PetAction = 4 },
        -- T9: retail's documented value (FOREVER-PLAN.md sec2.1) -- NOT observed
        -- on Forever (docs/tasks/T9-spell-tooltip.md Facts); T12 checks it.
        -- T25: Macro = 25 is retail's value, UNVERIFIED on Forever
        -- (docs/tasks/T25-macro-tooltip.md Facts; T25a's probe lines).
        TooltipDataType = { Spell = 1, Macro = 25 },
    }

    -- Five slots: two ranks of Rejuvenation (774 rank 1, 1058 rank 2) for the
    -- ranks-per-name count, Healing Touch, a non-heal (Wrath) for the
    -- healing/non-healing split (Q1), and slot 4's row raises on every index
    -- (not secret) for the spellbook-error tally. 774's description reads
    -- S.bonusHealing live, so a probe run after changing it sees a different
    -- number; 1058's is fixed.
    -- T7a: 5185 moved to slot 1 (ahead of 774) -- its own description is the
    -- only fixed one carrying a pipe, and "the first spell whose description
    -- contains heal" (== shapes item 3) needs to land on it out of combat, so
    -- the pipe-escaping shape has something real to show. No existing check
    -- reads the RELATIVE order of these four, only their presence/content.
    local SPELL_SLOTS = { [1] = 5185, [2] = 774, [3] = 5176, [5] = 1058 }
    local ERROR_ROW = setmetatable({}, { __index = function() error("spellbook row unreadable (stub)") end })
    local SPELL_NAMES = { [774] = "Rejuvenation", [5185] = "Healing Touch", [5176] = "Wrath", [1058] = "Rejuvenation" }
    local SPELL_SUBTEXT = { [774] = "Rank 1", [5185] = "Rank 1", [5176] = "Rank 1", [1058] = "Rank 2" }
    -- T7a: the stand-in shapes the == shapes section reads -- cast in ms, cost
    -- in mana, level learned, the family's rank-1 id -- straight from this
    -- task's Facts, not measured on any client.
    local SPELL_CAST = { [774] = 0, [1058] = 0, [5185] = 1500, [5176] = 1500 }
    local SPELL_COST = { [774] = 25, [1058] = 40, [5185] = 25, [5176] = 20 }
    local SPELL_COST_PERCENT = {}
    local SPELL_NO_COST = {}
    local SPELL_LEVEL = { [774] = 4, [1058] = 10, [5185] = 1, [5176] = 1 }
    local SPELL_BASE = { [774] = 774, [1058] = 774, [5185] = 5185, [5176] = 5176 }
    local SPELL_LOWRANK = {}
    -- T7: per-spell overrides for the new AddSpell opts -- default itemType
    -- is 1 (Spell, the shape every fixed slot above already returns);
    -- SPELL_KNOWN default (no entry) is true, so the four fixed spells above
    -- (never passed through AddSpell) keep answering known = true as before.
    local SPELL_ITEMTYPE = {}
    local SPELL_KNOWN = {}
    local SPELL_COSTLIST = {}
    -- T7b: per-spell isPassive override (default false, m2's own General/
    -- Druid rows above all carry isPassive = false in their table literal).
    local SPELL_PASSIVE = {}
    local SPELL_COSTLINE = {} -- review-spells: a tooltip cost line other than "N Mana" ("45 Energy")
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
            -- retail 12.x documented shape, NOT observed on Forever -- the probe's == shapes checks it
            return {
                spellID = id, name = SPELL_NAMES[id], subName = SPELL_SUBTEXT[id],
                itemType = SPELL_ITEMTYPE[id] or 1, isPassive = SPELL_PASSIVE[id] == true, isOffSpec = false,
                skillLineIndex = 2, actionID = id, iconID = 136041,
            }
        end,
        -- retail 12.x documented shape, NOT observed on Forever -- the probe's == shapes checks it
        IsSpellBookItemLowRank = function(slot, bank)
            return SPELL_LOWRANK[SPELL_SLOTS[slot]] == true
        end,
        -- T7: a boolean per spell id, defaulting true (unlike the classic
        -- global IsSpellKnown above, which tracks S.known and answers false
        -- by default -- this table is Forever's own known-ness stand-in).
        IsSpellKnown = function(id)
            if SPELL_KNOWN[id] == false then return false end
            return true
        end,
        -- retail 12.x documented shape, NOT observed on Forever -- the probe's == shapes checks it
        GetNumSpellBookSkillLines = function() return 2 end,
        -- retail 12.x documented shape, NOT observed on Forever -- the probe's == shapes checks it.
        -- numSpellBookItems on the Druid line is the highest slot actually used,
        -- so S.AddSpell (which only ever grows the range) moves it too.
        GetSpellBookSkillLineInfo = function(i)
            if i == 1 then
                return { name = "General", iconID = 1, itemIndexOffset = 0, numSpellBookItems = 0,
                         isGuild = false, shouldHide = false }
            elseif i == 2 then
                local maxSlot = 0
                for slot in pairs(SPELL_SLOTS) do if slot > maxSlot then maxSlot = slot end end
                return { name = "Druid", iconID = 2, itemIndexOffset = 0, numSpellBookItems = maxSlot,
                         isGuild = false, shouldHide = false }
            end
            return nil
        end,
    }
    -- Adds a spell in the first free slot from 6 on -- for tests that need
    -- more spellbook rows than the fixed five above (T0c step 6's elixir
    -- test). descFn follows SPELL_DESC's own shape: a zero-argument function.
    -- opts (T7a, optional): { cast, cost, costPercent, level, base, lowRank, noCost,
    -- itemType, known, costList }.
    local nextFreeSlot = 6
    function S.AddSpell(id, name, rank, descFn, opts)
        opts = opts or {}
        while SPELL_SLOTS[nextFreeSlot] do nextFreeSlot = nextFreeSlot + 1 end
        SPELL_SLOTS[nextFreeSlot] = id
        nextFreeSlot = nextFreeSlot + 1
        SPELL_NAMES[id] = name
        SPELL_SUBTEXT[id] = rank
        SPELL_DESC[id] = descFn
        SPELL_CAST[id] = opts.cast or 0
        SPELL_LEVEL[id] = opts.level or 1
        SPELL_BASE[id] = opts.base or id
        SPELL_LOWRANK[id] = opts.lowRank == true
        -- T7: itemType default (1, "Spell") unless the test names a different
        -- one (a flyout/pet-action row Book must skip, or a future-spell row
        -- whose known-ness falls back to it); known default (true) unless the
        -- test explicitly says the character has not learned it yet.
        SPELL_ITEMTYPE[id] = opts.itemType or 1
        SPELL_PASSIVE[id] = opts.passive == true
        if opts.known == false then SPELL_KNOWN[id] = false end
        SPELL_COSTLINE[id] = opts.costLine -- review-spells
        if opts.costList then
            SPELL_COSTLIST[id] = opts.costList
        elseif opts.noCost then
            SPELL_NO_COST[id] = true
        else
            SPELL_COST[id] = opts.cost or 0
            SPELL_COST_PERCENT[id] = opts.costPercent or 0
        end
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
        -- retail 12.x documented shape, NOT observed on Forever -- the probe's == shapes checks it
        GetSpellInfo = function(id)
            local name = SPELL_NAMES[id]
            if not name then return nil end
            return {
                name = name, iconID = 136041, originalIconID = 136041,
                castTime = SPELL_CAST[id] or 0, minRange = 0, maxRange = 40, spellID = id,
            }
        end,
        -- retail 12.x documented shape, NOT observed on Forever -- the probe's == shapes checks it
        GetSpellPowerCost = function(id)
            if not SPELL_NAMES[id] then return nil end
            if SPELL_COSTLIST[id] then return SPELL_COSTLIST[id] end
            -- == shapes item 5 (m2 lines 252-259, 274-285): every no-cost
            -- spell in the book returned NO VALUES AT ALL, never an empty
            -- list -- `return` with nothing, not `return {}`.
            if SPELL_NO_COST[id] then return end
            local cost = SPELL_COST[id] or 0
            return { {
                type = 0, name = "MANA", cost = cost, minCost = cost,
                costPercent = SPELL_COST_PERCENT[id] or 0, costPerSec = 0,
                requiredAuraID = 0, hasRequiredAura = false,
            } }
        end,
        -- retail 12.x documented shape, NOT observed on Forever -- the probe's == shapes checks it
        GetSpellLevelLearned = function(id) return SPELL_LEVEL[id] end,
        -- retail 12.x documented shape, NOT observed on Forever -- the probe's == shapes checks it
        GetBaseSpell = function(id) return SPELL_BASE[id] end,
    }
    -- retail 12.x documented shape, NOT observed on Forever -- the probe's == shapes checks it.
    -- The description line reuses C_Spell.GetSpellDescription, so it goes secret
    -- in combat for 5185 exactly the way the description itself does.
    -- T25a: S.actionTooltips[slot] = the tooltip data C_TooltipInfo.GetAction(slot)
    -- answers (nil otherwise), for the probe's `macro action` lines.
    S.actionTooltips = {}
    C_TooltipInfo = {
        GetAction = function(slot) return S.actionTooltips[slot] end,
        GetSpellByID = function(id)
            local name = SPELL_NAMES[id]
            if not name then return nil end
            local cost = SPELL_NO_COST[id] and 0 or (SPELL_COST[id] or 0)
            local castMs = SPELL_CAST[id] or 0
            local castText = "Instant"
            if castMs ~= 0 then castText = string.format("%.1f sec cast", castMs / 1000) end
            return {
                type = 1, id = id,
                lines = {
                    { leftText = name, rightText = SPELL_SUBTEXT[id] },
                    { leftText = SPELL_COSTLINE[id] or (cost .. " Mana"), rightText = "40 yd range" }, -- review-spells
                    { leftText = castText, rightText = "" },
                    { leftText = C_Spell.GetSpellDescription(id) },
                },
            }
        end,
    }

    -- T9: retail's TooltipDataProcessor (FOREVER-PLAN.md sec2.1) -- NOT observed
    -- on Forever. Callbacks are kept per Enum.TooltipDataType value, in
    -- registration order, exactly as Client/API_Forever.lua's OnSpellTooltip
    -- registers its own wrapper.
    S.tooltipPostCalls = {}
    TooltipDataProcessor = {
        AddTooltipPostCall = function(dataType, fn)
            S.tooltipPostCalls[dataType] = S.tooltipPostCalls[dataType] or {}
            table.insert(S.tooltipPostCalls[dataType], fn)
        end,
    }
    -- T9: one full tooltip showing -- clears (firing OnTooltipCleared, the
    -- addon's own cue that a previous id no longer applies), then runs every
    -- registered Spell post-call with { type = Spell, id = id }, the same
    -- shape the client hands a processor. Calling a stored post-call
    -- function directly (S.tooltipPostCalls[...]) simulates the client
    -- re-drawing an action button's tooltip WITHOUT a clear in between.
    function S.ShowSpellTooltip(tt, id)
        tt = tt or GameTooltip
        tt.lines = {}
        if tt.scripts.OnTooltipCleared then tt.scripts.OnTooltipCleared(tt) end
        local list = S.tooltipPostCalls[Enum.TooltipDataType.Spell]
        if list then
            for _, fn in ipairs(list) do
                fn(tt, { type = Enum.TooltipDataType.Spell, id = id })
            end
        end
    end

    -- T25: one full macro tooltip showing -- clears, fires OnTooltipCleared,
    -- sets tt:GetOwner() to `owner` (the hovered action button, or nil), then
    -- runs every Macro post-call with `data` exactly as given.
    function S.ShowMacroTooltip(tt, data, owner)
        tt = tt or GameTooltip
        tt.lines = {}
        tt.GetOwner = function() return owner end
        if tt.scripts.OnTooltipCleared then tt.scripts.OnTooltipCleared(tt) end
        local list = S.tooltipPostCalls[Enum.TooltipDataType.Macro]
        if list then
            for _, fn in ipairs(list) do fn(tt, data) end
        end
    end

    -- T28: hooksecurefunc(table, method, hook) / hooksecurefunc(global, hook)
    -- -- the hook runs after the original with the same arguments, and the
    -- original's returns are handed back; S.secureHooks[method] counts them.
    S.secureHooks = {}
    function hooksecurefunc(a, b, c) -- T28
        local tbl, name, hook = a, b, c
        if type(a) == "string" then tbl, name, hook = _G, a, b end
        local orig = tbl[name]
        if type(orig) ~= "function" or type(hook) ~= "function" then
            error("hooksecurefunc: bad argument")
        end
        rawset(tbl, name, function(...)
            local r = (function(...) return { n = select("#", ...), ... } end)(orig(...))
            hook(...)
            return unpack(r, 1, r.n)
        end)
        S.secureHooks[name] = (S.secureHooks[name] or 0) + 1
    end

    -- T28: GameTooltip:SetAction(slot) -- clears (firing OnTooltipCleared),
    -- then runs every Macro post-call with S.actionTooltipData[slot] when a
    -- script set one (the client assigning the showing a Macro data type),
    -- else no post-call at all (a path that fires none, spec 5.5 item 2).
    -- Hooks installed by hooksecurefunc run after this, as in the client.
    S.actionTooltipData = {}
    rawset(GameTooltip, "SetAction", function(tt, slot) -- T28
        tt.lines = {}
        if tt.scripts.OnTooltipCleared then tt.scripts.OnTooltipCleared(tt) end
        local data = S.actionTooltipData[slot]
        local list = S.tooltipPostCalls[Enum.TooltipDataType.Macro]
        if data ~= nil and list then
            for _, fn in ipairs(list) do fn(tt, data) end
        end
    end)

    -- T28: one action-button showing on GameTooltip, through its SetAction
    -- (and so through every hook on it). `data`, when given, is the Macro
    -- data the client hands the post-calls for this showing; the owner is nil
    -- unless `owner` is given, so the hook must use the slot it is handed.
    function S.SetActionTooltip(slot, data, owner) -- T28
        GameTooltip.GetOwner = function() return owner end
        S.actionTooltipData[slot] = data
        GameTooltip:SetAction(slot)
        S.actionTooltipData[slot] = nil
        return GameTooltip
    end

    -- T28: a Macro data whose one line names `id` with a type that is not
    -- the Spell type (`lineType`, default 0) -- the shape ElvUI's own Macro
    -- handler reads without checking the type.
    function S.MacroDataUntyped(id, lineType) -- T28
        return { type = Enum.TooltipDataType.Macro,
            lines = { { tooltipType = lineType or 0, tooltipID = id } } }
    end

    C_Secrets = {
        ShouldAurasBeSecret = function() return S.inCombat end,
        ShouldUnitIdentityBeSecret = function(u)
            if u == nil then error("bad argument #1") end
            return false
        end,
        ["ShouldStub|Piped"] = function() return false end,
        -- T0c/T5: the secret-question predicates. Each raises "bad argument #1"
        -- on a nil first argument, as the client does, except
        -- HasSecretRestrictions which takes none and never raises.
        -- T5, Facts (sixth-seventh reports): true always, not gated on combat --
        -- the beta's restriction is not something combat turns on and off.
        HasSecretRestrictions = function() return true end,
        -- T5, Facts (eighth report, "party1 max health always secret"): party1
        -- was never asked directly, so the stub answers `u ~= "player"`
        -- unconditionally, consistent with what UnitHealthMax(party1) reads.
        ShouldUnitHealthMaxBeSecret = function(u)
            if u == nil then error("bad argument #1") end
            return u ~= "player"
        end,
        -- T5, Facts (sixth report): true -- current power is secret for every
        -- unit (UnitPower above), so the predicate that names it answers true
        -- unconditionally rather than only for the player.
        ShouldUnitPowerBeSecret = function(u, pt)
            if u == nil then error("bad argument #1") end
            return true
        end,
        ShouldUnitPowerMaxBeSecret = function(u, pt)
            if u == nil then error("bad argument #1") end
            return false
        end,
        -- T5, Facts (sixth report): 2, not 0.
        GetPowerTypeSecrecy = function(pt)
            if pt == nil then error("bad argument #1") end
            return 2
        end,
        CanCompareUnitTokens = function(a, b)
            if a == nil or b == nil then error("bad argument #1") end
            return true
        end,
        -- T5, Facts (sixth-seventh reports): added alongside ShouldAurasBeSecret,
        -- same in-combat gate.
        ShouldCooldownsBeSecret = function() return S.inCombat end,
        ShouldUnitStatsBeSecret = function() return S.inCombat end,
    }

    -- T13: a fixture's own S.units[u].auras[i] wins when set (the recorder's
    -- own pre-pull scan); otherwise the fixed player row every earlier suite
    -- already reads. Still raises in combat either way (Facts).
    -- Lead review 1: S.auraCalls counts every call (raised or not), so a
    -- suite can prove a scanner skipped this function entirely rather than
    -- just relying on the pcall wrapper swallowing the raise.
    S.auraCalls = 0
    C_UnitAuras = {
        GetAuraDataByIndex = function(u, i, filter)
            S.auraCalls = S.auraCalls + 1
            if S.inCombat then error("Auras cannot be accessed when secret while tainted") end
            local x = U(u)
            if x and x.auras then return x.auras[i] end
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
    -- T13: what C_DamageMeter answers, pulled into a fixture-settable table
    -- rather than left as inline literals -- the recorder's own suite scripts
    -- S.meter.sources for "own X / others Y" without touching this function.
    -- Defaults are exactly what every earlier suite already saw.
    S.meter = {
        sources = {
            { sourceGUID = "Player-1", isLocalPlayer = true, totalAmount = 1234, amountPerSecond = 41 },
        },
        -- session type (Enum.DamageMeterSessionType's own values) -> rows.
        -- T0c: every row carries combatSpellDetails one level deep (a
        -- stand-in for EllesmereUI's own reading of the field), and the
        -- Overall session lists six spells against Current's one, so the
        -- five-row cap on the dump has something to cap.
        spells = {
            [Enum.DamageMeterSessionType.Overall] = {
                { spellID = 774, totalAmount = 1000, unitName = "Tankname", unitClassFilename = "WARRIOR" },
                { spellID = 5185, totalAmount = 900, unitName = "Tankname", unitClassFilename = "WARRIOR" },
                { spellID = 1058, totalAmount = 800, unitName = "Tankname", unitClassFilename = "WARRIOR" },
                { spellID = 5186, totalAmount = 700, unitName = "Tankname", unitClassFilename = "WARRIOR" },
                { spellID = 8936, totalAmount = 600, unitName = "Tankname", unitClassFilename = "WARRIOR" },
                { spellID = 740, totalAmount = 500, unitName = "Tankname", unitClassFilename = "WARRIOR" },
            },
            [Enum.DamageMeterSessionType.Current] = {
                { spellID = 774, totalAmount = 1000, unitName = "Tankname", unitClassFilename = "WARRIOR" },
            },
        },
    }
    C_DamageMeter = {
        IsDamageMeterAvailable = function() return true end,
        GetCombatSessionFromType = function(st, mt)
            if meterSecretNow() then return S.SecretTable() end
            return { combatSources = S.meter.sources }
        end,
        GetCombatSessionSourceFromType = function(st, mt, guid, cid)
            if meterSecretNow() then return S.SecretTable() end
            local rows = S.meter.spells[st] or {}
            local out = {}
            for _, r in ipairs(rows) do
                out[#out + 1] = { spellID = r.spellID, totalAmount = r.totalAmount,
                    overkillAmount = r.overkillAmount,
                    combatSpellDetails = { unitName = r.unitName, unitClassFilename = r.unitClassFilename,
                        specIconID = 0 } }
            end
            return { combatSpells = out }
        end,
    }

    -- T5: nothing has registered anything yet, so this starts empty and stays
    -- empty unless RegisterEvent's own COMBAT_LOG_EVENT_UNFILTERED branch above
    -- appends to it.
    S.forbidden = {}

    -- T2: sibling LoadOnDemand addon folders. S.RegisterAddOnFolder(name,
    -- relDir) makes one loadable, exactly like a real client where a sibling
    -- is loadable simply by being present on disk -- which is also why this
    -- auto-registers every Modules/<Name>/ folder actually in the checkout
    -- right below, rather than making every test call it by hand.
    S.addOnFolders = {}
    S.addOnLoaded = {}
    S.addOnDisabled = S.addOnDisabled or {}
    S.loadAddOnCalls = {}

    function S.RegisterAddOnFolder(name, relDir)
        S.addOnFolders[name] = relDir
    end

    local function FileExists(path)
        local f = io.open(path, "r")
        if f then f:close(); return true end
        return false
    end

    -- <relDir>/<name>_Mainline.toc if it exists, else <relDir>/<name>.toc
    -- (T0c: the Mainline suffix is what the client actually loads; the plain
    -- .toc is the fallback copy), else nil.
    local function ModuleTocPath(relDir, name)
        local rel = relDir .. "/" .. name .. "_Mainline.toc"
        if FileExists((S.root or ".") .. "/" .. rel) then return rel end
        rel = relDir .. "/" .. name .. ".toc"
        if FileExists((S.root or ".") .. "/" .. rel) then return rel end
        return nil
    end

    -- T13c: the same four top-level folders release.sh is allowed to pull a
    -- missing module entry from, at the repository root.
    local ROOT_RESOLVABLE = { "Engine/", "Spells/", "Data/", "UI/" }

    -- relDir/f if it exists there; else, when f names a file under one of the
    -- four shared folders and it exists at the repository root, that root
    -- path; else relDir/f unchanged, so an entry that resolves nowhere fails
    -- exactly where it always did (loadfile inside LoadModuleFiles).
    local function ResolveModuleFile(relDir, f)
        local modPath = relDir .. "/" .. f
        if FileExists((S.root or ".") .. "/" .. modPath) then return modPath end
        for _, prefix in ipairs(ROOT_RESOLVABLE) do
            if f:sub(1, #prefix) == prefix and FileExists((S.root or ".") .. "/" .. f) then
                return f
            end
        end
        return modPath
    end

    local function ReadTocField(tocRel, field)
        local f = io.open((S.root or ".") .. "/" .. tocRel, "r")
        if not f then return nil end
        local v
        for line in f:lines() do
            local m = line:match("^## " .. field .. ":%s*(.-)%s*$")
            if m then v = m end
        end
        f:close()
        return v
    end

    -- Loads a sibling's own files under ITS OWN addon name, without touching
    -- S.addonName -- S.Load (below) assigns that global, which is read by the
    -- forbid-on-register stand-in for the addon that actually registered an
    -- event, and reassigning it here would misattribute every event the MAIN
    -- addon registers after a module loads.
    --
    -- T13c: one fresh table for the whole addon load, not one per file -- the
    -- real client hands every file of one LoadOnDemand addon the SAME second
    -- vararg (S.Load above already does this for the main addon, passing one
    -- MD through its whole file loop). A fresh table per FILE was
    -- indistinguishable from a fresh table per ADDON as long as a sibling
    -- listed exactly one file (Module.lua); T13c's Ready.lua is the second,
    -- and Module.lua's proxy metatable on that table must still be the table
    -- every later file in this same TOC sees.
    local function LoadModuleFiles(files, addonName)
        local ns = {}
        for _, rel in ipairs(files) do
            local path = S.root .. "/" .. rel
            local chunk, err = loadfile(path)
            if not chunk then error("load " .. rel .. ": " .. tostring(err)) end
            chunk(addonName, ns)
        end
    end

    do
        local dir = (S.root or ".") .. "/Modules"
        local p = io.popen('ls -1 "' .. dir .. '" 2>/dev/null')
        if p then
            for line in p:lines() do
                local name = line:gsub("[\r\n]+$", "")
                if name ~= "" and ModuleTocPath("Modules/" .. name, name) then
                    S.RegisterAddOnFolder(name, "Modules/" .. name)
                end
            end
            p:close()
        end
    end

    -- T5 §5: GetAddOnMetadata (read from OUR toc, S.toc already points at the
    -- Forever line above); IsAddOnLoaded true for our own name or a loaded
    -- sibling. T2: LoadAddOn/IsAddOnLoadOnDemand/GetAddOnInfo for the siblings.
    C_AddOns = {
        GetAddOnMetadata = function(name, field)
            if name ~= S.addonName then return nil end
            local f = io.open((S.root or ".") .. "/" .. S.toc, "r")
            if not f then return nil end
            local v
            for line in f:lines() do
                local m = line:match("^## " .. field .. ":%s*(.-)%s*$")
                if m then v = m; break end
            end
            f:close()
            return v
        end,
        IsAddOnLoaded = function(name)
            return name == S.addonName or S.addOnLoaded[name] == true
        end,
        -- An unregistered name (never seen on disk, or a typo) is MISSING; a
        -- name a test marked disabled is DISABLED; an already-loaded one is a
        -- no-op success; otherwise its own TOC's files load under one shared
        -- table this addon's own files see as MD (T13c).
        --
        -- T13c: a TOC entry may name a file that does not live under the
        -- module's own folder -- a shared file the release build copies in
        -- from the repository root (release.sh) -- so an entry is resolved
        -- under the module folder FIRST and, only if it is not there, at the
        -- repository root under the same four folders release.sh copies from
        -- (Engine/, Spells/, Data/, UI/). Anything else missing still fails
        -- the same way it always has, one level down in LoadModuleFiles.
        LoadAddOn = function(name)
            S.loadAddOnCalls[#S.loadAddOnCalls + 1] = name
            if S.addOnLoaded[name] then return true end
            local relDir = S.addOnFolders[name]
            if not relDir then return false, "MISSING" end
            if S.addOnDisabled[name] then return false, "DISABLED" end
            local tocRel = ModuleTocPath(relDir, name)
            if not tocRel then return false, "MISSING" end
            local files = S.TocFiles(tocRel)
            local resolved = {}
            for _, f in ipairs(files) do
                resolved[#resolved + 1] = ResolveModuleFile(relDir, f)
            end
            LoadModuleFiles(resolved, name)
            S.addOnLoaded[name] = true
            return true
        end,
        IsAddOnLoadOnDemand = function(name)
            local relDir = S.addOnFolders[name]
            if not relDir then return nil end
            local tocRel = ModuleTocPath(relDir, name)
            if not tocRel then return nil end
            return ReadTocField(tocRel, "LoadOnDemand") == "1"
        end,
        GetAddOnInfo = function(name)
            local relDir = S.addOnFolders[name]
            if not relDir then return name, nil, nil, false, "MISSING" end
            local tocRel = ModuleTocPath(relDir, name)
            local title = tocRel and ReadTocField(tocRel, "Title") or nil
            local notes = tocRel and ReadTocField(tocRel, "Notes") or nil
            local loadable, reason = true, nil
            if S.addOnDisabled[name] then loadable, reason = false, "DISABLED" end
            return name, title, notes, loadable, reason
        end,
    }

    -- T5: baseline pruning -- every global FUNCTION this stub leaves defined
    -- that build 69893's real capture never saw is removed, so a suite that
    -- calls a Classic-only global fails here the way it would on Forever
    -- rather than quietly working against a stub that is looser than the
    -- client. Tables/strings/numbers and namespace members are untouched (the
    -- capture does not cover them). Kept regardless of the baseline: the
    -- stub's own test-harness helper, and the two builtins (dofile, loadfile)
    -- every multi-step harness script and S.Load itself keep calling AFTER
    -- this runs -- no addon file ever calls either, so keeping them defined
    -- does not let addon-visible code do anything the real client forbids.
    local KEEP_ANYWAY = { collectgarbage_count = true, dofile = true, loadfile = true }
    local function ReadBaselineFunctions(path)
        local f = io.open(path, "r")
        if not f then return {} end
        local text = f:read("*a")
        f:close()
        local marker = text:find('"functions"', 1, true)
        if not marker then return {} end
        local openBracket = text:find("%[", marker)
        local closeBracket = text:find("%]", openBracket)
        local body = text:sub(openBracket + 1, closeBracket - 1)
        local set = {}
        for name in body:gmatch('"([^"]*)"') do set[name] = true end
        return set
    end
    local baseline = ReadBaselineFunctions((S.root or ".") .. "/tools/data/forever_api.json")
    local pruned = {}
    for k, v in pairs(_G) do
        if type(v) == "function" and not baseline[k] and not KEEP_ANYWAY[k] then
            pruned[#pruned + 1] = k
            _G[k] = nil
        end
    end
    table.sort(pruned)
    S.pruned = pruned
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
