-- T89 (docs/SPEC-next.md 2.1, S1 step 1): the class profile registry.
--
-- A profile says, for one class on one line, what the rest of the addon
-- needs to know about that class's healing: which spellbook names make up a
-- family and the engine's key for it, the kit type the engine models that
-- family with, the HoT slots, what a Swiftmend eats, the planner's lists, the
-- mana cooldowns and the in-5SR regen talent -- names, types and rule choices,
-- never a spell number on Forever (the numbers come from the client's own
-- text through Spells/Book.lua; on TBC from Data/SpellData.lua, the verified
-- source, which the TBC profile only points at).
--
-- Two readers, two profiles (2.1):
--   * MD.ClassProfile is the LOGGED-IN player's, chosen by MD.Profiles.Select at
--     CORE_LOGIN. Read only by the UI (gates, words), the live kit builders and
--     the recorders. (The spec calls it MD.Profile; that name is taken on TBC
--     by Diagnostics_TBC.lua's MD:Profile(), the /md profile report, which a
--     field of that name would replace.)
--   * Everything that runs on a kit reads MD.Profiles.ForKit(kit) -- the
--     kit's own profile, the druid's when the kit carries none (every kit and
--     recording made before this file is a druid's) -- so tools/import.lua
--     replays any character's recording on any machine.
--   * A module-level constant derived from a profile (SP.BINDABLE,
--     MC.byClass.DRUID, Kit_Forever's FAMILY_KEY, ...) is derived at FILE LOAD
--     from MD.Profiles.Require("DRUID") BY NAME -- never from MD.ClassProfile, which
--     does not exist yet at file load and names whoever logged in.
--
-- Pure: no client call, no frame, no MD.API. Loaded right after Core.lua and
-- the flavour core on every main TOC, before any Data/Profile_* file (which
-- registers into it) and before every file that derives from it.
local _, MD = ...

MD.Profiles = MD.Profiles or {}
local P = MD.Profiles

-- class token -> registered profile
P.byClass = P.byClass or {}

--------------------------------------------------------------------------------
-- The shape (Engine/Kit.lua's style: a declared field table, a validator that
-- refuses anything undeclared, a builder-side check that raises).
--------------------------------------------------------------------------------
-- A profile's own fields and their types.
P.FIELDS = {
    class = "string",          -- the class token; Register sets it
    label = "string",          -- how the class is named in a sentence ("Druid")
    critSchool = "number",     -- MD.API.SpellCritChance's school (Nature 4, Holy 2)
    caps = "table",            -- capability -> true (MD.ClassProfile:Can)
    families = "table",        -- family key -> definition (P.FAMILY_FIELDS)
    order = "table",           -- family keys, the line's own dashboard order
    hotSlots = "table",        -- family keys; slot n = SM.HOT_INDEX's n
    planner = "table",         -- the planner's choices (P.PLANNER_FIELDS)
    manaCooldowns = "table",   -- list of { key, short, id, name, duration, value }
    regen = "table",           -- { inFsrTalent = { talentName, fractionPerRank } }
    -- T106 (docs/SPEC-next.md 4.3): the class's healing spells the engine does
    -- not model, by the spellbook's names (a totem, a next-cast modifier, a
    -- heal the parser refuses) -- the coach card names any a fight cast
    -- (SimPlanner's SP.Unmodelled). Never a family: a named family is modelled.
    unmodelled = "table",
}

-- Required on every registered profile (the generic one carries only caps).
P.REQUIRED = { "class", "label", "caps", "families" }

-- A family's definition.
P.FAMILY_FIELDS = {
    names = "table",           -- the spellbook's own English names (list of strings)
    kit = "string",            -- the Engine/Kit.lua Kit.TYPES entry the engine models it as
    hot = "boolean",           -- it leaves a HoT on the target
    eats = "table",            -- the families it consumes, in the order it tries them
    cooldown = "number",       -- seconds of its own cooldown
    exclude = "boolean",       -- the line's own "not planned / not on the dashboard" mark
}

-- The planner's fields: which rule set, and its ordered family lists.
P.PLANNER_FIELDS = {
    rules = "string",          -- the threshold rules' name ("druid"); nil = solver only
    bindable = "table",        -- SP.BINDABLE: the families a rule can bind
    hotRule = "table",         -- SP.HOT_RULE: the families rule 4 may reach for
    families = "table",        -- SV.FAMILIES: the solver's candidates, in its order
}

-- A mana cooldown's fields (Engine/ManaCooldowns.lua resolves `value` -- a
-- named value model -- so a profile file never does regen arithmetic).
P.COOLDOWN_FIELDS = {
    key = "string", short = "string", id = "number", name = "string",
    duration = "number", value = "string",
}

local function Say(problems, fmt, ...)
    problems[#problems + 1] = string.format(fmt, ...)
end

local function IsList(t)
    if type(t) ~= "table" then return false end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n == #t
end

-- A list of distinct non-empty strings.
local function CheckNames(problems, where, list)
    if not IsList(list) then
        Say(problems, "%s is not a list", where)
        return
    end
    local seen = {}
    for i, v in ipairs(list) do
        if type(v) ~= "string" or v == "" then
            Say(problems, "%s[%d] is not a name", where, i)
        elseif seen[v] then
            Say(problems, "%s names %s twice", where, v)
        end
        seen[v] = true
    end
end

local function CheckFields(problems, where, t, fields)
    for k, v in pairs(t) do
        local want = fields[k]
        if want == nil then
            Say(problems, "%s.%s is not a declared field", where, tostring(k))
        elseif type(v) ~= want then
            Say(problems, "%s.%s is a %s, not a %s", where, tostring(k), type(v), want)
        end
    end
end

local function Contains(list, v)
    for _, x in ipairs(list or {}) do if x == v then return true end end
    return false
end

--------------------------------------------------------------------------------
-- P.Validate(p, types) -> true | false, problems
--
-- problems is a list of ASCII sentences. `types` is the kit types a family's
-- `kit` must name (default: Engine/Kit.lua's Kit.TYPES when it has loaded --
-- it is listed after this file on the TBC TOC and lives in the Replay module
-- on Forever, so at registration the kit names are checked only as strings;
-- tools/profilecheck.lua checks them against Kit.TYPES).
--------------------------------------------------------------------------------
function P.Validate(p, types)
    local problems = {}
    if type(p) ~= "table" then
        Say(problems, "the profile is a %s, not a table", type(p))
        return false, problems
    end
    if types == nil then types = MD.Kit and MD.Kit.TYPES end
    CheckFields(problems, "profile", p, P.FIELDS)
    for _, k in ipairs(P.REQUIRED) do
        if p[k] == nil then Say(problems, "profile has no %s", k) end
    end

    if type(p.caps) == "table" then
        for cap, v in pairs(p.caps) do
            if type(cap) ~= "string" or v ~= true then
                Say(problems, "caps.%s is not `true`", tostring(cap))
            end
        end
    end

    local families = type(p.families) == "table" and p.families or {}
    for key, def in pairs(families) do
        local where = "families." .. tostring(key)
        if type(key) ~= "string" then Say(problems, "%s: the key is not a string", where) end
        if type(def) ~= "table" then
            Say(problems, "%s is not a table", where)
        else
            CheckFields(problems, where, def, P.FAMILY_FIELDS)
            if def.names == nil then Say(problems, "%s has no names", where)
            else CheckNames(problems, where .. ".names", def.names) end
            if type(def.kit) ~= "string" then
                Say(problems, "%s has no kit type", where)
            elseif types ~= nil and types[def.kit] == nil then
                Say(problems, "%s.kit %s is not a Kit.TYPES entry", where, def.kit)
            end
            if def.eats ~= nil then
                CheckNames(problems, where .. ".eats", def.eats)
                for _, eaten in ipairs(type(def.eats) == "table" and def.eats or {}) do
                    local e = families[eaten]
                    if e == nil or e.hot ~= true then
                        Say(problems, "%s eats %s, which is not a HoT family", where, tostring(eaten))
                    end
                end
            end
            if def.cooldown ~= nil and type(def.cooldown) == "number"
                and not (def.cooldown > 0 and def.cooldown < math.huge) then
                Say(problems, "%s.cooldown is %s", where, tostring(def.cooldown))
            end
        end
    end

    -- A name belongs to one family only (the name -> key map is a function).
    local owner = {}
    for key, def in pairs(families) do
        if type(def) == "table" and IsList(def.names) then
            for _, name in ipairs(def.names) do
                if owner[name] and owner[name] ~= key then
                    Say(problems, "the name %s is in %s and %s", tostring(name), owner[name], tostring(key))
                end
                owner[name] = key
            end
        end
    end

    if p.unmodelled ~= nil then
        CheckNames(problems, "unmodelled", p.unmodelled)
        for _, name in ipairs(IsList(p.unmodelled) and p.unmodelled or {}) do
            if owner[name] then
                Say(problems, "unmodelled names %s, which is in the family %s", tostring(name), owner[name])
            end
        end
    end
    if p.order ~= nil then
        CheckNames(problems, "order", p.order)
        for _, key in ipairs(IsList(p.order) and p.order or {}) do
            if families[key] == nil then Say(problems, "order names %s, which is not a family", tostring(key)) end
        end
    end
    if p.hotSlots ~= nil then
        CheckNames(problems, "hotSlots", p.hotSlots)
        for _, key in ipairs(IsList(p.hotSlots) and p.hotSlots or {}) do
            local def = families[key]
            if def == nil or def.hot ~= true then
                Say(problems, "hotSlots names %s, which is not a HoT family", tostring(key))
            end
        end
    end
    if type(p.planner) == "table" then
        CheckFields(problems, "planner", p.planner, P.PLANNER_FIELDS)
        -- The lists are the RULES' (Engine/SimPlanner.lua, Engine/SimSolver.lua,
        -- written for the TBC druid) and may name a family this line lacks
        -- (Lifebloom on Forever): the rules skip a family the kit does not
        -- carry, as they always have. So they are checked as names only.
        for _, k in ipairs({ "bindable", "hotRule", "families" }) do
            if p.planner[k] ~= nil then CheckNames(problems, "planner." .. k, p.planner[k]) end
        end
        if IsList(p.planner.hotRule) and IsList(p.planner.bindable) then
            for _, key in ipairs(p.planner.hotRule) do
                if not Contains(p.planner.bindable, key) then
                    Say(problems, "planner.hotRule names %s, which is not bindable", tostring(key))
                end
            end
        end
    end
    if p.manaCooldowns ~= nil then
        if not IsList(p.manaCooldowns) then
            Say(problems, "manaCooldowns is not a list")
        else
            for i, c in ipairs(p.manaCooldowns) do
                local where = "manaCooldowns[" .. i .. "]"
                if type(c) ~= "table" then
                    Say(problems, "%s is not a table", where)
                else
                    CheckFields(problems, where, c, P.COOLDOWN_FIELDS)
                    for k in pairs(P.COOLDOWN_FIELDS) do
                        if c[k] == nil then Say(problems, "%s has no %s", where, k) end
                    end
                end
            end
        end
    end
    if type(p.regen) == "table" then
        for k, v in pairs(p.regen) do
            if k ~= "inFsrTalent" then
                Say(problems, "regen.%s is not a declared field", tostring(k))
            elseif type(v) ~= "table" or type(v[1]) ~= "string" or type(v[2]) ~= "number" then
                Say(problems, "regen.inFsrTalent is not { talentName, fraction }")
            end
        end
    end
    return #problems == 0, (#problems > 0) and problems or nil
end

--------------------------------------------------------------------------------
-- The methods every profile answers (generic included), through a metatable so
-- they are never fields the validator would see.
--------------------------------------------------------------------------------
local Profile = {}
Profile.__index = Profile

-- T99 (docs/SPEC-next.md 2.1, 4.4): a capability that also needs a live
-- answer where the line provides one. `coach` is also "the live kit prices at
-- least one heal": on Forever the kit is built in the LoadOnDemand Replay
-- module, which provides the answer as MD.KitLive (Kit_Forever.lua, T96).
-- With no provider the capability is the class's alone -- unless the line
-- DECLARED the module that would provide it (MD:DeclareModule, which only
-- Core_Forever.lua calls: a value the flavour installs, never a client check),
-- in which case that module is off.
P.LIVE = {
    coach = { provider = "KitLive", module = "SpellTuner_Replay" },
}

-- The declared module row (Core.lua's MD.modules), or nil: none on TBC.
local function DeclaredModule(name)
    for _, m in ipairs(MD.modules or {}) do
        if m.name == name then return m end
    end
    return nil
end

-- MD.ClassProfile:Can(cap) -> true | false, why. The one replacement for the
-- MD.player.isDruid gates (T99 moved the 23 of them here). why:
--   "class"  -- this class's profile does not grant it;
--   "kit"    -- granted, but the live kit prices no heal (MD.KitLive's answer);
--   "module" -- granted, but the module that answers for the live kit is off
--               (the caller keeps that module's own placeholder).
-- The class comes first, so a class that is not modelled is told so whether
-- or not a module is on.
function Profile:Can(cap)
    if not (self.caps and self.caps[cap] == true) then return false, "class" end
    local live = P.LIVE[cap]
    if live then
        local fn = MD[live.provider]
        if type(fn) == "function" then
            local ok, answer, why = pcall(fn)
            if not ok then return false, "kit" end
            if answer ~= true then return false, (why == "module") and "module" or "kit" end
        elseif DeclaredModule(live.module) then
            return false, "module"
        end
    end
    return true
end

-- p:Family(nameOrKey) -> key, def: a family key, or one of a family's
-- spellbook names, to that family; nil when the profile has neither.
function Profile:Family(nameOrKey)
    local families = self.families
    if type(families) ~= "table" or nameOrKey == nil then return nil end
    if families[nameOrKey] then return nameOrKey, families[nameOrKey] end
    for key, def in pairs(families) do
        for _, name in ipairs(def.names or {}) do
            if name == nameOrKey then return key, def end
        end
    end
    return nil
end

-- p:FamilyKeys() -> { [spellbook name] = family key }, a fresh table: what a
-- reader of the spellbook (Kit_Forever, Stream_Forever) maps names with.
function Profile:FamilyKeys()
    local names, keyOf = {}, {}
    for key, def in pairs(self.families or {}) do
        for _, name in ipairs(def.names or {}) do
            names[#names + 1] = name
            keyOf[name] = key
        end
    end
    -- Inserted in name order, so the map is built the same way on every run.
    table.sort(names)
    local out = {}
    for _, name in ipairs(names) do out[name] = keyOf[name] end
    return out
end

-- p:KitTypes() -> { [family key] = kit type }, a fresh table.
function Profile:KitTypes()
    local out = {}
    for key, def in pairs(self.families or {}) do out[key] = def.kit end
    return out
end

-- p:HotIndex() -> { [family] = slot }, a fresh table from hotSlots (slot n is
-- the n-th entry, so the druid's order keeps SM.HOT_INDEX's numbers).
function Profile:HotIndex()
    local out = {}
    for slot, key in ipairs(self.hotSlots or {}) do out[key] = slot end
    return out
end

--------------------------------------------------------------------------------
-- The generic profile: any class with no profile file of its own. It answers
-- exactly what such a class gets today -- the mana clock on both lines; on
-- Forever also the spell tooltip block and the rank table, which Spells/Book.lua
-- already reads for any class. What a LINE adds for every class is a value that
-- line's profile file installs (P.LineCaps), never a client check here
-- (tools/apicheck.py rule 10).
--------------------------------------------------------------------------------
P.generic = setmetatable({ class = "*", label = "", caps = { clock = true }, families = {} }, Profile)

local lineCapsSet = false
-- P.LineCaps(caps): the capabilities this line grants every class, added to the
-- generic profile once. A second call raises (two files claiming the line).
function P.LineCaps(caps)
    if lineCapsSet then error("SpellTuner: Profiles.LineCaps called twice", 2) end
    if type(caps) ~= "table" then error("SpellTuner: Profiles.LineCaps needs a table", 2) end
    lineCapsSet = true
    for cap, v in pairs(caps) do
        if v == true then P.generic.caps[cap] = true end
    end
end

--------------------------------------------------------------------------------
-- The registry
--------------------------------------------------------------------------------
-- P.Register(class, p): a Data/Profile_* file's one call. A second
-- registration for one class raises (MD:Provide's rule); a profile that fails
-- P.Validate raises too, naming the first problems -- it is the file's bug, and
-- nothing downstream should derive from it.
local SHOWN = 3
function P.Register(class, p)
    if type(class) ~= "string" or class == "" then
        error("SpellTuner: Profiles.Register needs a class token", 2)
    end
    if P.byClass[class] ~= nil then
        error("SpellTuner: a second profile for " .. class, 2)
    end
    if type(p) ~= "table" then
        error("SpellTuner: the profile for " .. class .. " is not a table", 2)
    end
    if p.class == nil then p.class = class end
    if p.class ~= class then
        error("SpellTuner: the profile registered for " .. class .. " says it is "
            .. tostring(p.class), 2)
    end
    local ok, problems = P.Validate(p)
    if not ok then
        local shown = {}
        for i = 1, math.min(SHOWN, #problems) do shown[i] = problems[i] end
        local more = (#problems > SHOWN) and string.format(" (and %d more)", #problems - SHOWN) or ""
        error("SpellTuner: the profile for " .. class .. " fails Profiles.Validate: "
            .. table.concat(shown, "; ") .. more, 2)
    end
    P.byClass[class] = setmetatable(p, Profile)
    return p
end

-- P.Get(class) -> the registered profile, else the generic one (never nil).
function P.Get(class)
    return P.byClass[class] or P.generic
end

-- P.Require(class, who) -> the registered profile; raises naming `who` when
-- the class has none. For a file deriving a module-level constant at load:
-- the generic profile has nothing to derive from, and a missing profile is a
-- load-order mistake (the TOC lists the profile file after its reader).
function P.Require(class, who)
    local p = P.byClass[class]
    if p == nil then
        error(string.format("SpellTuner: %s needs the %s profile, which is not registered "
            .. "(Spells/Profiles.lua and Data/Profile_* load before it)", tostring(who or "a file"),
            tostring(class)), 2)
    end
    return p
end

-- P.ForKit(kit) -> the kit's own profile: Get(kit.profile), the druid's when
-- the kit names none (every kit made before profiles was a druid's). What the
-- engine reads; never MD.ClassProfile.
function P.ForKit(kit)
    local class = type(kit) == "table" and kit.profile or nil
    if type(class) ~= "string" then class = "DRUID" end
    return P.Get(class)
end

-- P.Select(class): MD.ClassProfile = Get(class) -- the logged-in player's. Called at
-- CORE_LOGIN (below), after Core.lua's DetectProfile set MD.player.class.
function P.Select(class)
    MD.ClassProfile = P.Get(class)
    return MD.ClassProfile
end

MD:RegisterCallback("CORE_LOGIN", function()
    P.Select(MD.player and MD.player.class)
end)

--------------------------------------------------------------------------------
-- T99 (docs/SPEC-next.md 4.4): the gates' words. "Druid-only in v1" became,
-- wherever a capability is refused, "<subject>: not modelled for <Class> yet"
-- -- a wording change for non-druids only: the druid's profiles grant every
-- capability a druid had, so a druid never sees these. ASCII, no pipe.
--------------------------------------------------------------------------------
-- The two class tokens a plain title case would spell wrong.
P.CLASS_WORDS = { DEATHKNIGHT = "Death Knight", DEMONHUNTER = "Demon Hunter" }

-- P.ClassLabel(class) -> how a sentence names the class: a registered
-- profile's label, else the token title-cased ("PRIEST" -> "Priest"), else
-- "your class" (no class read yet). class defaults to the logged-in player's.
function P.ClassLabel(class)
    if class == nil then class = MD.player and MD.player.class end
    local reg = P.byClass[class]
    if reg and type(reg.label) == "string" and reg.label ~= "" then return reg.label end
    if type(class) ~= "string" or not class:match("^%u+$") or class == "UNKNOWN" then
        return "your class"
    end
    return P.CLASS_WORDS[class] or (class:sub(1, 1) .. class:sub(2):lower())
end

-- The module a live capability's provider lives in, as the Modules pane names it.
local function ModuleLabel(cap)
    local live = P.LIVE[cap]
    local m = live and DeclaredModule(live.module)
    return m and m.label or "Replay"
end

-- P.Refusal(cap, why, subject, class) -> the sentence for Can(cap)'s `why`:
--   "class"  -> "<subject>: not modelled for <Class> yet"
--   "kit"    -> "<subject>: no heal in your spellbook is modelled yet"
--   "module" -> "<subject>: needs the <Label> module" (the module placeholder's
--               own words, UI/Dashboard_Forever.lua)
-- subject defaults to the capability's name. No full stop: a chat caller adds it.
function P.Refusal(cap, why, subject, class)
    subject = subject or tostring(cap)
    if why == "module" then
        return string.format("%s: needs the %s module", subject, ModuleLabel(cap))
    elseif why == "kit" then
        return subject .. ": no heal in your spellbook is modelled yet"
    end
    return string.format("%s: not modelled for %s yet", subject, P.ClassLabel(class))
end

-- P.RefusalNote(cap, why) -> the short note a menu row carries beside a
-- refused item (Review's row menu): "not modelled", or the module's words.
function P.RefusalNote(cap, why)
    if why == "module" then return "needs the " .. ModuleLabel(cap) .. " module" end
    return "not modelled"
end
