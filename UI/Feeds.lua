-- UI/Feeds.lua (T92, docs/SPEC-next.md 2.3, S3 step 1; R-arch.md 5): the
-- feeds, on both main TOCs, after UI/Tip.lua.
--
-- A FEED is one piece of information to show: a text, the face behind it, a
-- tooltip and a click. A SURFACE is a place that shows feeds -- the ElvUI
-- datatexts (Integrations/Surface_ElvUI.lua), later the LibDataBroker objects
-- (Integrations/Surface_LDB.lua, T97). Before T92 every surface built its own
-- text; now each asks the feed, so they can never say different things.
--
--   ST.Feeds.Register(key, def)   a second registration of a key raises;
--                                  def.Text is required
--     def = { label, icon,
--             Text(ctx)    -> string. ASCII; colour codes allowed, no bare
--                             pipe. ctx = { valueHex = "|cffRRGGBB" (the
--                             host's value colour) | nil, plain = bool (no
--                             colour code at all: a host that strips them),
--                             compact = reserved for T97's broker setting },
--             Face()       -> the clock face (Engine/ClockFace.lua), for a
--                             surface that colours by tone,
--             Tooltip()    -> UI/Tip.lua's line model,
--             Click(button)   left: the window; right: Settings }
--   ST.Feeds.Get(key), ST.Feeds.List()  (keys, in registration order; a copy)
--   ST.Feeds.Text(key, ctx)  the feed's text, never raising into a host: a
--                             feed that raises, or answers nothing, gives its
--                             label; ctx.plain strips any colour code left
--   ST.Feeds.Face(key), ST.Feeds.Tooltip(key)  the same guard
--   ST.Feeds.Click(key, button)  refused in combat (answers false; decision
--                             17, Forever's T70 rule), else true
--   ST:Fire("FEED_CHANGED", key)  from the 0.5 s tick, only when the feed's
--                             text (ctx {}) is not what the last tick saw;
--                             the tick is registered at MD_READY, so it runs
--                             after every file's own tick has moved the state
--
-- Two feeds:
--   clock -- ClockFace.LineString of the line's own face
--            (ST.ClockFace.Current: TBC's ST:GetClockFace, Forever's pool);
--            byte for byte TBC's ST:GetDisplayString. The tooltip is the
--            minimap button's lines (ST.MinimapLines). T114: the words
--            follow Line's slots -- ST.ClockLook().texts.line (the resolved
--            text of the Line layout, whatever layout is on screen) handed
--            to LineString; no provider, no texts: today's string.
--   regen -- the CURRENT regen: the casting rate inside the five-second rule,
--            the full rate outside it. "Regen: 123", " (5SR)" in the rule;
--            plain "Regen 123", "Regen 123 (5SR)"; "--" without a reading.
--            On the line with a modelled pool (ST.Pool, Forever) the rates
--            are the pool's last plain readings (ST.Pool:LastRegen()) and the
--            rule the model's own last spend -- in combat the client's rate
--            is secret, so the number is the last plain one, marked "~". ST.Regen
--            is never read there, and a secret never reaches a string. On TBC
--            the rates are Engine/RegenModel.lua's, read live, as the datatext
--            always read them (the face's mp5 is the last tick's, up to 0.5 s
--            behind the rule it would be shown beside).
-- Which line is which is a namespace the line installs (ST.Pool), never a
-- client test (CLAUDE.md, apicheck rule 10).
local _, ST = ...

ST.Feeds = ST.Feeds or {}
local Feeds = ST.Feeds

local ICON = "Interface\\Icons\\Spell_Shadow_Manaburn" -- the minimap button's

local defs, order = {}, {}
Feeds.errors = {} -- key -> how many times its def raised (for a dump; never shown)

function Feeds.Register(key, def)
    if type(key) ~= "string" or key == "" then
        error("SpellTuner: Feeds.Register needs a key", 2)
    end
    if defs[key] ~= nil then
        error("SpellTuner: a second feed named " .. key, 2)
    end
    if type(def) ~= "table" or type(def.Text) ~= "function" then
        error("SpellTuner: feed " .. key .. " needs a Text function", 2)
    end
    defs[key] = def
    order[#order + 1] = key
    return def
end

function Feeds.Get(key) return defs[key] end

function Feeds.List()
    local out = {}
    for i = 1, #order do out[i] = order[i] end
    return out
end

local function Strip(s)
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- def[name](...) under pcall; a raise is counted and logged, never re-raised
-- (a host calls these from its own OnUpdate).
local function Call(key, def, name, ...)
    local fn = def[name]
    if type(fn) ~= "function" then return false end
    local ok, a = pcall(fn, ...)
    if not ok then
        Feeds.errors[key] = (Feeds.errors[key] or 0) + 1
        if ST.Debug then ST:Debug("other", "feed %s %s raised: %s", key, name, tostring(a)) end
        return false
    end
    return true, a
end

function Feeds.Text(key, ctx)
    local def = defs[key]
    if not def then return "" end
    ctx = ctx or {}
    local ok, s = Call(key, def, "Text", ctx)
    if not ok or type(s) ~= "string" or s == "" then s = def.label or key end
    if ctx.plain then s = Strip(s) end
    return s
end

function Feeds.Face(key)
    local def = defs[key]
    if not def then return nil end
    local ok, face = Call(key, def, "Face")
    if ok and type(face) == "table" then return face end
    return nil
end

function Feeds.Tooltip(key)
    local def = defs[key]
    if not def then return {} end
    local ok, lines = Call(key, def, "Tooltip")
    if ok and type(lines) == "table" then return lines end
    return {}
end

function Feeds.Click(key, button)
    local def = defs[key]
    if not def or ST.inCombat then return false end
    Call(key, def, "Click", button)
    return true
end

--------------------------------------------------------------------------------
-- FEED_CHANGED: once per tick per feed whose text moved.
--------------------------------------------------------------------------------
local last = {}
function Feeds.Poll()
    for i = 1, #order do
        local key = order[i]
        local s = Feeds.Text(key, {})
        if s ~= last[key] then
            last[key] = s
            ST:Fire("FEED_CHANGED", key)
        end
    end
end
ST:RegisterCallback("MD_READY", function() ST:OnTick(Feeds.Poll) end)

--------------------------------------------------------------------------------
-- The shared parts of both feeds.
--------------------------------------------------------------------------------
local function CurrentFace()
    local CF = ST.ClockFace
    local current = CF and CF.Current
    if type(current) ~= "function" then return nil end
    return current()
end

local function ClockTooltip()
    if ST.MinimapLines then return ST.MinimapLines() end
    return { { l = "SpellTuner", c = "accent" } }
end

local function OpenOnClick(button)
    if button == "RightButton" then
        if ST.OpenDashboardSettings then ST:OpenDashboardSettings() end
    elseif ST.ToggleDashboard then
        ST:ToggleDashboard()
    end
end

--------------------------------------------------------------------------------
-- clock
--------------------------------------------------------------------------------
-- T114: Line's resolved text from the clock look (ST:Provide "ClockLook",
-- under pcall as Integrations/Surface_LDB.lua reads it), or nil.
local function LineText()
    local provide = ST.ClockLook
    if type(provide) ~= "function" then return nil end
    local ok, look = pcall(provide)
    if not ok or type(look) ~= "table" or type(look.texts) ~= "table" then return nil end
    local line = look.texts.line
    if type(line) ~= "table" then return nil end
    return line
end
Feeds.LineText = LineText

Feeds.Register("clock", {
    label = "SpellTuner",
    icon = ICON,
    Face = CurrentFace,
    Text = function(ctx)
        local face = CurrentFace()
        if not face then return "" end
        return ST.ClockFace.LineString(face, ctx.valueHex, LineText())
    end,
    Tooltip = ClockTooltip,
    Click = OpenOnClick,
})

--------------------------------------------------------------------------------
-- regen
--------------------------------------------------------------------------------
-- A rate as a plain number, or nil (a secret, a missing reading).
local function Plain(v)
    if v == nil or (ST.API and ST.API.IsSecret and ST.API.IsSecret(v)) then return nil end
    if type(v) ~= "number" or v ~= v then return nil end
    return v
end

-- The reading: { mp5, fsr = in the rule, modelled = the last plain reading }
-- or nil.
local function RegenReading()
    if not (ST.player and ST.player.usesMana) then return nil end
    local rate, inFsr, modelled
    local pool = ST.Pool
    if pool then
        -- Forever: the modelled pool's own rates and rule
        local model = pool.model
        if not model then return nil end
        local base, casting = pool:LastRegen()
        base, casting = Plain(base), Plain(casting)
        local t, lastSpend = Plain(model.t), Plain(model.lastSpend)
        inFsr = (t ~= nil and lastSpend ~= nil and t < lastSpend + 5) or false
        if inFsr then rate = casting else rate = base end
        modelled = ST.inCombat == true
    else
        local RM = ST.Regen
        if not RM then return nil end
        rate = Plain(RM:Current())
        inFsr = RM:InFSR() and true or false
        modelled = false
    end
    if rate == nil then return nil end
    return { mp5 = math.floor(rate * 5 + 0.5), fsr = inFsr, modelled = modelled }
end
Feeds.RegenReading = RegenReading

Feeds.Register("regen", {
    label = "SpellTuner Regen",
    icon = ICON,
    Face = CurrentFace,
    Text = function(ctx)
        local r = RegenReading()
        local mark = (r and r.modelled) and "~" or ""
        if ctx.plain then
            if not r then return "Regen --" end
            return "Regen " .. mark .. r.mp5 .. (r.fsr and " (5SR)" or "")
        end
        local hex = ctx.valueHex or "|cffffffff"
        if not r then return "Regen: " .. hex .. "--|r" end
        return "Regen: " .. hex .. mark .. r.mp5 .. "|r" .. (r.fsr and " |cffffaa33(5SR)|r" or "")
    end,
    Tooltip = ClockTooltip,
    Click = OpenOnClick,
})
