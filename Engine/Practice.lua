-- Practice (v0.15.0, docs/SPEC-v0.15.md): heal a fight YOU play, in real time,
-- and get a recording out of it that the Review tab, the replay window and the
-- coach take exactly as they take a dungeon pull.
--
-- Three parts, no frames:
--   * a SETUP -- who is in the group, how much health they have, and what
--     damage each of them takes (a steady rate, spikes, randomness) plus
--     group-wide AoE -- turned into a damage timeline by a seeded generator;
--   * a SESSION -- Engine/SimModel.lua's own loop, run inside a coroutine and
--     paced to the wall clock (`opts.pace`), with a plan whose Decide reads the
--     player's queued input instead of rules. One engine: what you play is
--     what the replay reproduces, to the float;
--   * the RECORDING -- the session written down in Engine/FightRecorder.lua's
--     stream format (v = 2), kept in cdb.practice and addressed as "p1".
--
-- What the practice fight is NOT: it is not a model of any real encounter.
-- Every default in PR.ROLES is a placeholder with its provenance, and the
-- setup panel says so. It is a way to rehearse decisions, and a recording the
-- coach can answer.
local _, MD = ...

local PR = {}
MD.Practice = PR

PR.MAX_KEPT = 8
PR.QUEUE = 0.4          -- the client's spell queue window: a press this close to
                        -- the end of a cast or the GCD goes off when it ends
PR.POLL = 0.05          -- how often the engine asks for input while idle
PR.MAX_DUR = 600

--------------------------------------------------------------------------------
-- Defaults. PLACEHOLDERS, like everything in Data/SimPresets.lua: one healer's
-- impression of a TBC group, written as fractions of max health so they mean
-- the same thing at level 64 and 70.
--   dps         steady damage per second, as a fraction of max health
--   swing       seconds between the hits that deliver it (0 = a smooth 1s tick)
--   spike       one big hit, as a fraction of max health
--   spikeEvery  average seconds between spikes (0 = none)
--   jitter      0..1, how far hit sizes and intervals wander from the average
--------------------------------------------------------------------------------
PR.ROLES = {
    TANK   = { label = "Tank",   role = "TANK",    dps = 0.035, swing = 1.8, spike = 0.25, spikeEvery = 20, jitter = 0.3 },
    HEALER = { label = "Healer", role = "HEALER",  dps = 0,     swing = 0,   spike = 0.15, spikeEvery = 45, jitter = 0.5 },
    MELEE  = { label = "Melee",  role = "DAMAGER", dps = 0.003, swing = 3,   spike = 0.20, spikeEvery = 35, jitter = 0.5 },
    RANGED = { label = "Ranged", role = "DAMAGER", dps = 0,     swing = 0,   spike = 0.20, spikeEvery = 40, jitter = 0.5 },
}
PR.ROLE_ORDER = { "TANK", "HEALER", "MELEE", "RANGED" }

-- who is in the group, by size; the first HEALER slot is you
PR.GROUPS = {
    { id = "1",  label = "Solo",    slots = { "HEALER" } },
    { id = "2",  label = "Duo",     slots = { "TANK", "HEALER" } },
    { id = "5",  label = "Party",   slots = { "TANK", "HEALER", "MELEE", "RANGED", "RANGED" } },
    { id = "10", label = "Raid 10", slots = { "TANK", "TANK", "HEALER", "HEALER", "HEALER",
                                              "MELEE", "MELEE", "RANGED", "RANGED", "RANGED" } },
    { id = "25", label = "Raid 25", slots = { "TANK", "TANK", "TANK", "HEALER", "HEALER", "HEALER",
                                              "HEALER", "HEALER", "HEALER", "MELEE", "MELEE", "MELEE",
                                              "MELEE", "MELEE", "MELEE", "MELEE", "RANGED", "RANGED",
                                              "RANGED", "RANGED", "RANGED", "RANGED", "RANGED",
                                              "RANGED", "RANGED" } },
}

-- a class per slot kind, for the frame colour only
local CLASSES = {
    TANK = { "WARRIOR", "PALADIN", "DRUID" },
    HEALER = { "PRIEST", "SHAMAN", "PALADIN", "DRUID" },
    MELEE = { "ROGUE", "WARRIOR", "SHAMAN", "PALADIN" },
    RANGED = { "MAGE", "WARLOCK", "HUNTER", "PRIEST" },
}

-- Same shape as Data/SimPresets.lua's placeholder: a level 70 tank around 10k,
-- cloth around 6k, scaled linearly below 70.
local function DefaultHP(level, kind)
    local base = (kind == "TANK") and 10000 or 6000
    return math.floor(base * math.min(1, (level or 70) / 70))
end

function PR.DefaultSetup(groupID, level)
    level = level or (MD.player and MD.player.level) or 70
    local group
    for _, g in ipairs(PR.GROUPS) do if g.id == groupID then group = g end end
    group = group or PR.GROUPS[3]
    local setup = { group = group.id, dur = 120, startHp = 1.0, otherHealing = 0,
                    aoe = { size = 0.10, every = 25, jitter = 0.3 }, targets = {} }
    local count, you = {}, false
    for i, kind in ipairs(group.slots) do
        count[kind] = (count[kind] or 0) + 1
        local r = PR.ROLES[kind]
        local isYou = (kind == "HEALER" and not you)
        if isYou then you = true end
        local classes = CLASSES[kind]
        setup.targets[i] = {
            kind = kind, role = r.role,
            name = isYou and ((MD.API.UnitName and MD.API.UnitName("player")) or "You")
                or (r.label .. (count[kind] > 1 and (" " .. count[kind]) or "")),
            class = isYou and "DRUID" or classes[(count[kind] - 1) % #classes + 1],
            you = isYou or nil,
            maxHP = DefaultHP(level, kind),
            dps = r.dps, swing = r.swing, spike = r.spike, spikeEvery = r.spikeEvery, jitter = r.jitter,
        }
    end
    return setup
end

-- a role's defaults onto every target of that kind (the setup panel's "apply
-- to all tanks"), leaving name, class and health alone
function PR.ApplyRole(setup, kind, values)
    for _, tg in ipairs(setup.targets) do
        if tg.kind == kind then
            for _, k in ipairs({ "dps", "swing", "spike", "spikeEvery", "jitter" }) do
                if values[k] ~= nil then tg[k] = values[k] end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Bindings: what a press casts. A press is the key or mouse button with its
-- modifiers in the client's own spelling ("ALT-BUTTON5", "SHIFT-1"), made while
-- hovering a frame -- the mouseover healing the author plays with. A binding
-- names a family and a rank (nil = the highest you know), so it follows a new
-- rank the day it is trained.
--
-- The defaults are the author's own Cell click-casting, read from their
-- SavedVariables on 2026-09-17: Button5 "Main overtime" (Lifebloom on a
-- friendly mouseover), Alt-Button5 "rej/moofire" (Rejuvenation), Shift-Button5
-- "efficient Rej" (Rejuvenation Rank 5). Left and right click target and open
-- the menu in Cell, so they are free here and carry the two heals those macros
-- do not: Regrowth and Swiftmend. Shift-left is Healing Touch.
--------------------------------------------------------------------------------
PR.DEFAULT_BINDS = {
    { key = "BUTTON5",       family = "Lifebloom" },
    { key = "ALT-BUTTON5",   family = "Rejuvenation" },
    { key = "SHIFT-BUTTON5", family = "Rejuvenation", rank = 5 },
    { key = "BUTTON1",       family = "Regrowth" },
    { key = "BUTTON2",       family = "Swiftmend" },
    { key = "SHIFT-BUTTON1", family = "HealingTouch" },
}

-- the client's names for mouse buttons, as a binding spells them
PR.MOUSE = { LeftButton = "BUTTON1", RightButton = "BUTTON2", MiddleButton = "BUTTON3",
             Button4 = "BUTTON4", Button5 = "BUTTON5" }

-- The client the file is running on, read the one way a shared file may.
local function OnForever()
    return MD.API and MD.API.client == "forever"
end

-- T24: is this list exactly PR.DEFAULT_BINDS (same length, and in order the
-- same key, family and rank)? On Forever those are the TBC author's Cell
-- bindings, which 0.16.0 wrote into SavedVariables the first time the panel
-- was opened.
local function IsShippedDefaults(list)
    if #list ~= #PR.DEFAULT_BINDS then return false end
    for i, d in ipairs(PR.DEFAULT_BINDS) do
        local b = list[i]
        if type(b) ~= "table" or b.key ~= d.key or b.family ~= d.family or b.rank ~= d.rank then
            return false
        end
    end
    return true
end

function PR.Binds()
    local db = MD.db
    local forever = OnForever()
    if db and type(db.practiceBinds) == "table" then
        -- only an exact copy of the shipped defaults is dropped, once; any
        -- other list is the player's own and is kept whole
        if forever and IsShippedDefaults(db.practiceBinds) then
            db.practiceBinds = {}
            if MD.Debug then
                MD:Debug("other", "practice: the shipped TBC default bindings were saved on this client; dropped")
            end
        end
        return db.practiceBinds
    end
    local out = {}
    if not forever then
        for i, b in ipairs(PR.DEFAULT_BINDS) do out[i] = { key = b.key, family = b.family, rank = b.rank } end
    end
    if db then db.practiceBinds = out end
    return out
end

-- modifiers in the order the client writes them
function PR.Mods(alt, ctrl, shift)
    return (alt and "ALT-" or "") .. (ctrl and "CTRL-" or "") .. (shift and "SHIFT-" or "")
end

-- Forever's own kit (Modules/SpellTuner_Replay/Kit_Forever.lua) fills
-- MD.SpellData's tables (spells/families/known/all/maxRank) lazily, the
-- first time anything calls MD.RankMath:SpellKit() -- TBC's own Data/
-- SpellData.lua carries every one of those as a table from load, always
-- (SD.maxRank = {} at file scope, populated later by a scan, never nil). The
-- bindings list (below) reads them before a session ever starts one, so it
-- warms the kit itself, once -- a no-op on TBC, where SD.maxRank is never
-- nil and this guard is always false.
function PR.EnsureKit()
    local SD = MD.SpellData
    if not SD.maxRank and MD.RankMath and MD.RankMath.SpellKit then
        MD.RankMath:SpellKit({ live = true })
    end
end

-- T24: is the bind's family in the player's own spellbook? Forever's kit
-- lists a family in SD.all only when the book has it. TBC's static table
-- has every family, so it is always true there.
function PR.InBook(bind)
    if not OnForever() then return true end
    if not bind or not bind.family then return false end
    PR.EnsureKit()
    local all = MD.SpellData.all
    local ranks = all and all[bind.family]
    return type(ranks) == "table" and #ranks > 0
end

-- T24: the first family this player has a known rank of -- the engine's own
-- order, then Swiftmend -- else nil.
function PR.FirstFamily()
    PR.EnsureKit()
    local SD = MD.SpellData
    if not SD.known then return nil end
    local order = {}
    for _, f in ipairs(SD.familyOrder or {}) do order[#order + 1] = f end
    order[#order + 1] = "Swiftmend"
    for _, f in ipairs(order) do
        local known = SD.known[f]
        if type(known) == "table" and #known > 0 then return f end
    end
    return nil
end

-- A binding's spell id: that rank if you know it, else your highest. A bind
-- whose family is not in the spellbook (Forever) casts nothing.
function PR.SpellFor(bind)
    local SD = MD.SpellData
    if not bind or not bind.family then return nil end
    if not PR.InBook(bind) then return nil end
    if not SD.known or not SD.maxRank then return nil end
    if bind.rank then
        for _, id in ipairs(SD.known[bind.family] or {}) do
            if SD.spells[id].rank == bind.rank then return id end
        end
    end
    return SD.maxRank[bind.family]
end

function PR.BindFor(key)
    for _, b in ipairs(PR.Binds()) do
        -- a row with no spell picked yet (T24: a new row on a character with no
        -- family to offer) is not a binding: the press is left to the client
        if b.key == key and b.family then return b, PR.SpellFor(b) end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Importing bindings from the addon you actually play with.
--
-- Cell and Clique both store "this press casts that spell" and practice wants
-- the same thing, so it is read rather than retyped. Neither is a dependency:
-- the tables are read if they are there, once, when the button is pressed --
-- nothing here runs at load or during a fight.
--
-- What cannot be imported is REPORTED, never guessed: a press bound to
-- targeting or the unit menu, the mouse wheel (practice has no wheel binding),
-- a spell this addon does not model, and a macro whose first heal cannot be
-- read. The report is what the window prints.
--------------------------------------------------------------------------------

-- "Rejuvenation(Rank 5)", "Healing Touch", "Rejuvenation" -> family, rank
function PR.ParseSpellText(text)
    if type(text) ~= "string" then return nil end
    local name, rank = text:match("^%s*(.-)%s*%(%s*[Rr]ank%s*(%d+)%s*%)%s*$")
    if not name then name = text:match("^%s*(.-)%s*$") end
    if not name or name == "" then return nil end
    local SD = MD.SpellData
    for family, info in pairs(SD.families) do
        if name == (info.label or family) or name == family then
            if SD.known[family] or SD.all[family] then return family, tonumber(rank) end
            return nil
        end
    end
    return nil
end

function PR.SpellFromID(id)
    local s = MD.SpellData.spells[tonumber(id) or 0]
    if not s then return nil end
    return s.family, s.rank
end

-- The first healing spell a macro casts. A conditional macro names several --
-- "[known:33763,@mouseover,help]Lifebloom;[@mouseover,help]Rejuvenation;..." --
-- and the first one this addon models is the one the binding is FOR.
function PR.MacroSpell(body)
    if type(body) ~= "string" then return nil end
    for line in body:gmatch("[^\r\n]+") do
        local rest = line:match("^%s*/cast%s+(.+)$") or line:match("^%s*/use%s+(.+)$")
        if rest then
            rest = rest:gsub("!", "")
            for clause in (rest .. ";"):gmatch("(.-);") do
                local spell = clause:gsub("%b[]", ""):gsub("^%s+", ""):gsub("%s+$", "")
                if spell ~= "" then
                    local family, rank = PR.ParseSpellText(spell)
                    if family then return family, rank end
                end
            end
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- T19: what the importers read is checked, not assumed. Another add-on's table
-- is indexed only under pcall and only after type(); a shape the importer does
-- not recognise is refused with what it expected and what it found.
--------------------------------------------------------------------------------

-- Reversible ASCII escaping, the same rule as Client/Probe.lua's Esc (this file's
-- own copy, T19): \ -> \\, | -> ||, then every byte outside printable ASCII -> \ddd.
local function Esc(s)
    if type(s) ~= "string" then s = tostring(s) end
    local step1 = s:gsub("\\", "\\\\")
    local step2 = step1:gsub("|", "||")
    local step3 = step2:gsub("[^ -~]", function(c) return string.format("\\%03d", c:byte()) end)
    return step3
end

local function Safe(t, k)
    if type(t) ~= "table" then return nil end
    local ok, v = pcall(function() return t[k] end)
    if ok then return v end
    return nil
end

local function TypeName(v)
    if v == nil then return "absent" end
    return type(v)
end

-- the top-level keys of a table, sorted, escaped, at most `limit` of them
local function KeysOf(t, limit)
    if type(t) ~= "table" then return "" end
    local keys = {}
    pcall(function() for k in pairs(t) do keys[#keys + 1] = k end end)
    table.sort(keys, function(a, b)
        local sa, sb = tostring(a), tostring(b)
        if sa ~= sb then return sa < sb end
        return type(a) < type(b)
    end)
    local out = {}
    for i, k in ipairs(keys) do
        if i > (limit or 20) then out[#out + 1] = "..."; break end
        out[#out + 1] = Esc(tostring(k))
    end
    return table.concat(out, ", ")
end

-- one value as text, `depth` levels of table deep, escaped
local function Dump(v, depth)
    local t = type(v)
    if t == "string" then return '"' .. Esc(v) .. '"' end
    if t == "number" or t == "boolean" or t == "nil" then return tostring(v) end
    if t ~= "table" then return "<" .. t .. ">" end
    if depth <= 1 then return "{...}" end
    local parts, n = {}, 0
    for i, x in ipairs(v) do
        n = i
        if i > 20 then parts[#parts + 1] = "..."; break end
        parts[#parts + 1] = Dump(x, depth - 1)
    end
    local keys = {}
    for k in pairs(v) do
        if not (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)) then keys[#keys + 1] = k end
    end
    table.sort(keys, function(a, b)
        local sa, sb = tostring(a), tostring(b)
        if sa ~= sb then return sa < sb end
        return type(a) < type(b)
    end)
    for _, k in ipairs(keys) do
        if #parts >= 20 then parts[#parts + 1] = "..."; break end
        parts[#parts + 1] = Esc(tostring(k)) .. "=" .. Dump(v[k], depth - 1)
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

-- what an entry that is not the expected shape looks like, for an error text
local function Found(entryIndex, e)
    if type(e) == "table" then
        local keys = KeysOf(e, 10)
        return "entry " .. entryIndex .. " = table with keys: " .. (keys ~= "" and keys or "none")
    end
    return "entry " .. entryIndex .. " = " .. Esc(tostring(e)) .. " (" .. type(e) .. ")"
end

local function MacroBody(name)
    local _, _, body = MD.API.MacroInfo(name)
    if type(body) == "string" then return body end
    return nil
end

-- Cell's attribute key -> ours. "alt-type5" -> "ALT-BUTTON5", "type-altR" ->
-- "ALT-R" (Cell/Modules/ClickCastings/ClickCastings.lua, GetAttributeKey).
function PR.CellKey(attr)
    if type(attr) ~= "string" or attr == "notBound" then return nil end
    local mods, dash, key = attr:match("^(.*)type(%-?)(.+)$")
    if not key then return nil end
    local alt, ctrl, shift
    if dash == "-" then
        if key == "SCROLLUP" or key == "SCROLLDOWN" then return nil, "the mouse wheel" end
        -- the modifiers are glued to the key: "altR", "altctrlF"
        local rest = key
        while true do
            local m = rest:match("^(alt)") or rest:match("^(ctrl)") or rest:match("^(shift)")
            if not m then break end
            if m == "alt" then alt = true elseif m == "ctrl" then ctrl = true else shift = true end
            rest = rest:sub(#m + 1)
        end
        if rest == "" then return nil end
        key = rest:upper()
    else
        local n = tonumber(key)
        if not n then return nil end
        key = "BUTTON" .. n
    end
    for m in (mods or ""):gmatch("([^-]+)") do
        if m == "alt" then alt = true elseif m == "ctrl" then ctrl = true elseif m == "shift" then shift = true end
    end
    return PR.Mods(alt, ctrl, shift) .. key
end

-- The list Cell would actually use: the common one, or this spec's. Returns
-- list, source -- or nil, <reason> when Cell has something there but not in a
-- shape this reads (nil, nil when Cell is simply not loaded).
local function CellPick()
    local db = rawget(_G, "CellCharacterDB")
    if db == nil then return nil, nil end
    if type(db) ~= "table" then return nil, "expected CellCharacterDB to be a table - found " .. type(db) end
    local cc = Safe(db, "clickCastings")
    if cc == nil then
        return nil, "expected CellCharacterDB.clickCastings to be a table - found nothing (CellCharacterDB has keys: " ..
            KeysOf(db, 10) .. ")"
    end
    if type(cc) ~= "table" then return nil, "expected CellCharacterDB.clickCastings to be a table - found " .. type(cc) end
    if Safe(cc, "useCommon") then
        local common = Safe(cc, "common")
        if type(common) == "table" then return common, "Cell (common bindings)" end
        return nil, "expected clickCastings.common to be a table (useCommon is set) - found " .. TypeName(common)
    end
    local i = (MD.API.Specialization and MD.API.Specialization()) or 1
    local bySpec = Safe(cc, i)
    if type(bySpec) == "table" then return bySpec, "Cell (spec " .. tostring(i) .. ")" end
    local first = Safe(cc, 1)
    if type(first) == "table" then return first, "Cell (spec 1)" end
    return nil, "expected clickCastings.common (with useCommon) or clickCastings[<spec>] to be a table - found keys: " ..
        KeysOf(cc, 10)
end

-- CellPick, and the list itself must be a list of { attribute, kind, action }
local function CellList()
    local list, source = CellPick()
    if not list then return nil, source end
    local n = 0
    for _ in ipairs(list) do n = n + 1 end
    if n == 0 then
        if next(list) ~= nil then
            return nil, "expected " .. source .. " to be a list of { attribute, kind, action } entries - found a table with keys: " ..
                KeysOf(list, 10)
        end
        return list, source
    end
    for _, e in ipairs(list) do
        if type(e) == "table" and type(Safe(e, 1)) == "string" then return list, source end
    end
    return nil, 'expected each click-casting entry to be { attribute, kind, action } with a string attribute such as "type1" - found ' ..
        Found(1, list[1])
end

-- Returns a fresh binding list and a report: { source, added, skipped = { "..." } }.
-- Nothing is written; the window decides whether to keep it.
function PR.ImportCell()
    local list, source = CellList()
    if not list then
        return nil, { source = "Cell", error = source or "Cell is not loaded, or it has no click-castings." }
    end
    local out, report = {}, { source = source, added = 0, skipped = {} }
    for _, entry in ipairs(list) do
      if type(entry) ~= "table" then
        report.skipped[#report.skipped + 1] = "entry: not a table (" .. type(entry) .. ")"
      else
        local key, why = PR.CellKey(entry[1])
        local kind, action = entry[2], entry[3]
        local family, rank
        if key and kind == "spell" then
            family, rank = PR.SpellFromID(action)
            if not family then family, rank = PR.ParseSpellText(action) end
            why = why or (not family and ("not a heal this addon models (" .. tostring(action) .. ")"))
        elseif key and kind == "macro" then
            family, rank = PR.MacroSpell(MacroBody(action))
            why = why or (not family and ('macro "' .. tostring(action) .. '" casts no heal this addon models'))
        elseif key then
            why = why or ((kind == "custom" or kind == "item") and (kind .. " binding")
                or ("bound to " .. tostring(kind == nil and action or kind)))
        end
        if family then
            out[#out + 1] = { key = key, family = family, rank = rank }
            report.added = report.added + 1
        elseif why then
            report.skipped[#report.skipped + 1] = tostring(PR.CellKey(entry[1]) or entry[1]) .. ": " .. why
        end
      end
    end
    return out, report
end

-- Clique keeps its binds under whichever of these this version uses. The key is
-- already the client's spelling ("ALT-BUTTON5"), so only the spell is read.
-- Returns binds -- or nil, <reason> (nil, nil when Clique is simply not there).
local function CliquePick()
    local reason
    local C = rawget(_G, "Clique")
    if type(C) == "table" then
        local profile = Safe(Safe(C, "db"), "profile")
        local binds = Safe(profile, "binds")
        if type(binds) == "table" then return binds end
        if binds ~= nil then reason = reason or ("expected Clique.db.profile.binds to be a table - found " .. type(binds)) end
    end
    for _, name in ipairs({ "CliqueDB3", "CliqueDB" }) do
        local db = rawget(_G, name)
        if db ~= nil then
            local profiles = Safe(db, "profiles")
            if type(profiles) ~= "table" then
                reason = reason or ("expected " .. name .. ".profiles to be a table - found " .. TypeName(profiles))
            else
                local key = (MD.API.UnitName and MD.API.UnitName("player") or "") ..
                    " - " .. (MD.API.RealmName and MD.API.RealmName() or "")
                local p = Safe(profiles, key)
                if p == nil then
                    -- any profile, the first by name so the answer does not depend on table order
                    local names = {}
                    pcall(function() for k in pairs(profiles) do names[#names + 1] = k end end)
                    table.sort(names, function(a, b) return tostring(a) < tostring(b) end)
                    if names[1] ~= nil then p = Safe(profiles, names[1]) end
                end
                local binds = Safe(p, "binds")
                if type(binds) == "table" then return binds end
                reason = reason or ("expected " .. name .. ".profiles[<name>].binds to be a table - found " ..
                    (type(p) == "table" and ("a profile with keys: " .. KeysOf(p, 10)) or TypeName(p)))
            end
        end
    end
    return nil, reason
end

-- CliquePick, and the binds must be a list of { key, type, ... }
local function CliqueBinds()
    local binds, reason = CliquePick()
    if not binds then return nil, reason end
    local n = 0
    for _ in ipairs(binds) do n = n + 1 end
    if n == 0 then
        if next(binds) ~= nil then
            return nil, "expected the Clique binds to be a list of { key, type, ... } binds - found a table with keys: " ..
                KeysOf(binds, 10)
        end
        return binds
    end
    for _, b in ipairs(binds) do
        if type(b) == "table" and type(Safe(b, "key")) == "string" and type(Safe(b, "type")) == "string" then
            return binds
        end
    end
    return nil, "expected each Clique bind to be { key = <string>, type = <string>, ... } - found " .. Found(1, binds[1])
end

function PR.ImportClique()
    local binds, reason = CliqueBinds()
    if not binds then
        return nil, { source = "Clique", error = reason or "Clique is not loaded, or it has no bindings." }
    end
    local out, report = {}, { source = "Clique", added = 0, skipped = {} }
    for _, b in ipairs(binds) do
      if type(b) ~= "table" then
        report.skipped[#report.skipped + 1] = "bind: not a table (" .. type(b) .. ")"
      else
        local key = b.key
        local family, rank, why
        if type(key) ~= "string" or key == "" then
            key = nil
        elseif key:find("MOUSEWHEEL") then
            key, why = nil, "the mouse wheel"
        end
        if key then
            if b.type == "spell" then
                family, rank = PR.ParseSpellText(b.spell)
                why = not family and ("not a heal this addon models (" .. tostring(b.spell) .. ")") or nil
            elseif b.type == "macro" then
                family, rank = PR.MacroSpell(b.macrotext or MacroBody(b.macro))
                why = not family and "the macro casts no heal this addon models" or nil
            else
                why = "bound to " .. tostring(b.type)
            end
        end
        if family then
            out[#out + 1] = { key = key:upper(), family = family, rank = rank }
            report.added = report.added + 1
        elseif why then
            report.skipped[#report.skipped + 1] = tostring(b.key) .. ": " .. why
        end
      end
    end
    return out, report
end

--------------------------------------------------------------------------------
-- Importing the game's own keybindings (v0.15.2).
--
-- The author's healing is mouseover MACROS on action bars, bound to keys and
-- mouse buttons -- nothing Cell or Clique knows about. So: walk every binding
-- the client has, follow it to the action-bar slot it presses, and read what is
-- in that slot.
--
-- Following a binding to a slot takes three shapes, in this order:
--   ACTIONBUTTON<n>                 the main bar, slot n
--   MULTIACTIONBAR<b>BUTTON<n>      Blizzard's four extra bars, at their fixed
--                                   page offsets
--   anything with a FRAME behind it  (ELVUIBAR2BUTTON9 -> ElvUI_Bar2Button9,
--                                   "CLICK BT4Button13:LeftButton" -> that
--                                   frame): the frame's own `action` attribute
--                                   says which slot it presses, which is how
--                                   every bar addon answers the question
-- What is in the slot is a spell (its id IS the rank) or a macro (read for the
-- first heal it casts, exactly as a Cell macro binding is).
--------------------------------------------------------------------------------
local MULTIBAR_BASE = { [1] = 61, [2] = 49, [3] = 25, [4] = 13 }   -- BottomLeft, BottomRight, Right, Right2

local function FrameSlot(name)
    local f = name and _G[name]
    if not f or type(f.GetAttribute) ~= "function" then return nil end
    local ok, slot = pcall(f.GetAttribute, f, "action")
    if ok then return tonumber(slot) end
    return nil
end

function PR.SlotForCommand(command)
    if type(command) ~= "string" then return nil end
    local n = command:match("^ACTIONBUTTON(%d+)$")
    if n then return tonumber(n) end
    local bar, btn = command:match("^MULTIACTIONBAR(%d)BUTTON(%d+)$")
    if bar and MULTIBAR_BASE[tonumber(bar)] then
        return MULTIBAR_BASE[tonumber(bar)] + tonumber(btn) - 1
    end
    local ebar, ebtn = command:match("^ELVUIBAR(%d+)BUTTON(%d+)$")
    if ebar then
        local slot = FrameSlot("ElvUI_Bar" .. ebar .. "Button" .. ebtn)
        if slot then return slot end
    end
    local clicked = command:match("^CLICK%s+(.-):")
    if clicked then
        local slot = FrameSlot(clicked)
        if slot then return slot end
    end
    -- last chance: some bars name their binding after their frame
    return FrameSlot(command)
end

-- What an action-bar slot casts: family, rank, and how it picks its target.
function PR.SlotSpell(slot)
    if not slot then return nil end
    local kind, id = MD.API.ActionInfo(slot)
    if type(kind) ~= "string" then return nil end
    if kind == "spell" then
        local family, rank = PR.SpellFromID(id)
        if family then return family, rank, "spell" end
        return nil, nil, nil, "not a heal this addon models"
    elseif kind == "macro" then
        local body = MacroBody(id)
        local family, rank = PR.MacroSpell(body)
        if family then
            return family, rank, (body and body:find("@mouseover")) and "mouseover" or "macro"
        end
        return nil, nil, nil, "the macro casts no heal this addon models"
    end
    return nil, nil, nil, kind .. " binding"
end

-- One GetBinding row -> its command and the keys the client agrees are bound to
-- that command. GetBinding's shape moved between clients (a category was added),
-- so the keys are the returns that the client agrees are bound to this command
-- rather than the ones at a fixed position.
local function BindingKeys(r)
    local command = r[1]
    local keys = {}
    for j = 2, (r.n or #r) do
        local v = r[j]
        if type(v) == "string" and v ~= "" and MD.API.BindingAction(v) == command then
            keys[#keys + 1] = v
        end
    end
    return command, keys
end

-- GetBinding(i) with every return kept, a trailing nil included
local function PackBinding(i)
    local function pack(...) return { n = select("#", ...), ... } end
    return pack(MD.API.Binding(i))
end

-- Every binding the client has, as practice bindings.
function PR.ImportKeybinds()
    local n = MD.API.BindingCount()
    if type(n) ~= "number" then
        return nil, { source = "your keybindings", error = "this client does not expose its bindings." }
    end
    if n >= 1 then
        local first = PackBinding(1)
        if type(first[1]) ~= "string" then
            return nil, { source = "your keybindings",
                error = "expected GetBinding(1) to return a command name string first - found " ..
                    Esc(tostring(first[1])) .. " (" .. type(first[1]) .. ") among " .. tostring(first.n) .. " returns" }
        end
    end
    local out, report = {}, { source = "your keybindings", added = 0, skipped = {}, notes = {} }
    local seen = {}
    for i = 1, n do
        local command, keys = BindingKeys(PackBinding(i))
        if #keys > 0 then
            local slot = PR.SlotForCommand(command)
            if slot then
                local family, rank, how, why = PR.SlotSpell(slot)
                for _, key in ipairs(keys) do
                    local k = key:upper()
                    if k:find("MOUSEWHEEL") then
                        if family then report.skipped[#report.skipped + 1] = k .. ": the mouse wheel" end
                    elseif family and not seen[k] then
                        seen[k] = true
                        out[#out + 1] = { key = k, family = family, rank = rank }
                        report.added = report.added + 1
                        if how ~= "mouseover" then
                            report.notes[#report.notes + 1] = k ..
                                ": casts on your target in game, on the frame you hover here"
                        end
                    elseif why then
                        report.skipped[#report.skipped + 1] = k .. ": " .. why
                    end
                end
            end
        end
    end
    return out, report
end

--------------------------------------------------------------------------------
-- T19: /st binds check. One escaped block: what the three import sources look
-- like on this client, in the shapes the importers read, and whether each
-- importer recognised them. Only reads; nothing is imported or stored.
--------------------------------------------------------------------------------
local function ReasonCounts(skipped)
    local counts, order = {}, {}
    for _, line in ipairs(skipped or {}) do
        local reason = line:match("^.-: (.*)$") or line
        if not counts[reason] then order[#order + 1] = reason; counts[reason] = 0 end
        counts[reason] = counts[reason] + 1
    end
    table.sort(order)
    local parts = {}
    for _, r in ipairs(order) do parts[#parts + 1] = Esc(r) .. " x" .. counts[r] end
    return table.concat(parts, "; ")
end

local function ImporterLine(fn)
    local ok, list, rep = pcall(fn)
    if not ok then return "importer: raised: " .. Esc(tostring(list)) end
    if not list then
        return "importer: not recognised: " .. (rep and rep.error or "no reason given")
    end
    local skipped = rep and rep.skipped and #rep.skipped or 0
    local line = string.format("importer: recognised: %d bindings, %d skipped", #list, skipped)
    if skipped > 0 then line = line .. " (" .. ReasonCounts(rep.skipped) .. ")" end
    return line
end

local function Shown(v)
    if type(v) == "string" then return '"' .. Esc(v) .. '"' end
    return Esc(tostring(v))
end

-- first element of a list, else the value under its first key, as depth-3 text
local function FirstOf(t)
    if type(t) ~= "table" then return "none" end
    local ok, text = pcall(function()
        if t[1] ~= nil then return Dump(t[1], 3) end
        local keys = {}
        for k in pairs(t) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        if keys[1] == nil then return "none" end
        return Esc(tostring(keys[1])) .. " = " .. Dump(t[keys[1]], 3)
    end)
    if ok then return text end
    return "unreadable"
end

function PR.BindsReport()
    local out = {}
    local function add(line) out[#out + 1] = line end

    local _, build = MD.API.BuildInfo()
    local name = MD.API.UnitName("player")
    local realm = MD.API.RealmName()
    add(string.format("=== SpellTuner binds check  build %s  %s-%s  %s ===",
        Esc(build == nil and "unknown" or tostring(build)),
        Esc(name == nil and "?" or tostring(name)),
        Esc(realm == nil and "?" or tostring(realm)),
        date("%Y-%m-%d %H:%M:%S")))

    ---------------------------------------------------------------------------
    add("== keybindings")
    local n, why = MD.API.BindingCount()
    if type(n) ~= "number" then
        add("count: absent" .. (why and (" (" .. Esc(why) .. ")") or ""))
        n = 0
    else
        add("count: " .. n)
    end
    for i = 1, math.min(n, 5) do
        local r = PackBinding(i)
        local parts = {}
        for j = 1, r.n do parts[j] = Shown(r[j]) end
        add("binding " .. i .. " = " .. table.concat(parts, ", "))
    end
    local bound, resolved, spells, macros = 0, 0, 0, 0
    local firstResolved = {}
    for i = 1, n do
        local command, keys = BindingKeys(PackBinding(i))
        for _, key in ipairs(keys) do
            bound = bound + 1
            local slot = PR.SlotForCommand(command)
            if slot then
                resolved = resolved + 1
                local kind, id = MD.API.ActionInfo(slot)
                local what = "empty"
                if kind == "spell" then
                    spells = spells + 1
                    local sp = MD.SpellData and MD.SpellData.spells and MD.SpellData.spells[tonumber(id) or 0]
                    what = "spell " .. Esc(tostring(id)) .. (sp and (" (" .. Esc(tostring(sp.family)) .. ")") or "")
                elseif kind == "macro" then
                    macros = macros + 1
                    local mname = MD.API.MacroInfo(id)
                    what = "macro " .. (type(mname) == "string" and ('"' .. Esc(mname) .. '"') or Esc(tostring(id)))
                elseif kind ~= nil then
                    what = Esc(tostring(kind))
                end
                if #firstResolved < 10 then
                    firstResolved[#firstResolved + 1] = string.format("  %s -> %s -> slot %s -> %s",
                        Esc(key), Esc(tostring(command)), Esc(tostring(slot)), what)
                end
            end
        end
    end
    add(string.format("bound: %d keys; resolved to a slot: %d; to a spell: %d; to a macro: %d",
        bound, resolved, spells, macros))
    add("first 10 resolved:" .. (#firstResolved == 0 and " none" or ""))
    for _, l in ipairs(firstResolved) do add(l) end
    do
        local ok, list, rep = pcall(PR.ImportKeybinds)
        if not ok then
            add("importer: raised: " .. Esc(tostring(list)))
        elseif not list then
            add("importer: not recognised: " .. (rep and rep.error or "no reason given"))
        else
            local skipped = #rep.skipped
            local line = string.format("importer: %d bindings imported, %d skipped", #list, skipped)
            if skipped > 0 then line = line .. " (" .. ReasonCounts(rep.skipped) .. ")" end
            add(line)
        end
    end

    ---------------------------------------------------------------------------
    add("== Cell")
    local cdb = rawget(_G, "CellCharacterDB")
    add("CellCharacterDB: " .. TypeName(cdb))
    local cc = Safe(cdb, "clickCastings")
    if type(cc) == "table" then
        add("clickCastings: table, keys: " .. KeysOf(cc, 20))
    else
        add("clickCastings: " .. TypeName(cc))
    end
    local picked = CellPick()
    add("first entry: " .. FirstOf(picked or cc))
    add(ImporterLine(PR.ImportCell))

    ---------------------------------------------------------------------------
    add("== Clique")
    local C = rawget(_G, "Clique")
    local cliqueBinds = Safe(Safe(Safe(C, "db"), "profile"), "binds")
    local function DbLine(dbName)
        local db = rawget(_G, dbName)
        local line = dbName .. ": " .. TypeName(db)
        if type(db) == "table" then line = line .. " (profiles: " .. TypeName(Safe(db, "profiles")) .. ")" end
        return line
    end
    add("Clique: " .. TypeName(C) .. "; Clique.db.profile.binds: " .. TypeName(cliqueBinds) ..
        "; " .. DbLine("CliqueDB3") .. "; " .. DbLine("CliqueDB"))
    add("first bind: " .. FirstOf((CliquePick())))
    add(ImporterLine(PR.ImportClique))

    return table.concat(out, "\n")
end

-- Take an imported list ON TOP of what is there (v0.15.4, the author's call:
-- "I don't want to get rid of all existing, I want to add on top, override on
-- collision"). A key already bound is re-pointed to the imported spell, in its
-- own row; a new key is appended; every binding the import does not mention is
-- left alone. Inside the import the later entry wins a clash.
-- Returns: how many were added, how many replaced, how many changed nothing.
function PR.ApplyImport(list)
    if not list then return 0, 0, 0 end
    local binds = PR.Binds()
    local byKey = {}
    for i, b in ipairs(binds) do
        if b.key and b.key ~= "" then byKey[b.key] = i end
    end
    -- the import's own last word per key, in the order it gave them
    local last, order = {}, {}
    for _, b in ipairs(list) do
        if b.key and b.key ~= "" then
            if not last[b.key] then order[#order + 1] = b.key end
            last[b.key] = b
        end
    end
    local added, replaced, same = 0, 0, 0
    for _, key in ipairs(order) do
        local b = last[key]
        local i = byKey[key]
        if i then
            local old = binds[i]
            if old.family == b.family and old.rank == b.rank then
                same = same + 1
            else
                old.family, old.rank = b.family, b.rank
                replaced = replaced + 1
            end
        else
            binds[#binds + 1] = { key = key, family = b.family, rank = b.rank }
            byKey[key] = #binds
            added = added + 1
        end
    end
    MD.db.practiceBinds = binds
    return added, replaced, same
end

--------------------------------------------------------------------------------
-- The damage timeline. Deterministic in the seed: the same setup and seed is
-- the same fight, which is what lets a session be played again.
--------------------------------------------------------------------------------
local function Rng(seed)
    local state = ((seed or 1) * 2654435761) % 2147483647
    if state == 0 then state = 1 end
    return function()
        state = (state * 1103515245 + 12345) % 2147483648
        return state / 2147483648
    end
end

-- a value that wanders `jitter` either side of `mean`, never below zero
local function Wander(r, mean, jitter)
    local v = mean * (1 + (jitter or 0) * (2 * r() - 1))
    return v > 0 and v or 0
end

function PR.BuildDamage(setup, seed)
    local SM = MD.SimModel
    local K = SM.K
    local r = Rng(seed)
    local dur = setup.dur or 120
    local raw = {}
    local function push(t, ti, amt, kind, x)
        if t > 0 and t <= dur and amt >= 1 then
            raw[#raw + 1] = { t = t, tgt = ti, amt = math.floor(amt + 0.5), kind = kind or K.DMG, x = x or 0 }
        end
    end
    local OPEN = 1.5    -- nobody is hit the instant the pull starts
    for ti, tg in ipairs(setup.targets) do
        local maxHP = tg.maxHP or 1
        local jit = tg.jitter or 0
        if (tg.dps or 0) > 0 then
            local every = (tg.swing or 0) > 0 and tg.swing or 1
            local t = OPEN + every * r()
            while t <= dur do
                push(t, ti, Wander(r, tg.dps * maxHP * every, jit))
                t = t + Wander(r, every, jit * 0.2)
                if every <= 0 then break end
            end
        end
        if (tg.spike or 0) > 0 and (tg.spikeEvery or 0) > 0 then
            local t = OPEN + Wander(r, tg.spikeEvery, jit)
            while t <= dur do
                push(t, ti, Wander(r, tg.spike * maxHP, jit))
                t = t + math.max(2, Wander(r, tg.spikeEvery, jit))
            end
        end
    end
    local aoe = setup.aoe
    if aoe and (aoe.size or 0) > 0 and (aoe.every or 0) > 0 then
        local t = OPEN + Wander(r, aoe.every, aoe.jitter)
        while t <= dur do
            for ti, tg in ipairs(setup.targets) do
                push(t, ti, Wander(r, aoe.size * (tg.maxHP or 1), (aoe.jitter or 0) * 0.5))
            end
            t = t + math.max(3, Wander(r, aoe.every, aoe.jitter))
        end
    end
    -- other healers: a share of every hit comes back as somebody else's heal,
    -- a second or two later. Written as foreign heals, which the engine lands
    -- (and overheals) like any other.
    local share = setup.otherHealing or 0
    if share > 0 then
        local n = #raw
        for i = 1, n do
            local e = raw[i]
            if e.kind == K.DMG then
                push(e.t + 1 + 2 * r(), e.tgt, e.amt * share, K.FHEAL, 0)
            end
        end
    end
    table.sort(raw, function(a, b)
        if a.t ~= b.t then return a.t < b.t end
        if a.kind ~= b.kind then return a.kind < b.kind end
        return a.tgt < b.tgt
    end)
    local ev = { t = {}, kind = {}, tgt = {}, amt = {}, x = {} }
    for i, e in ipairs(raw) do
        ev.t[i], ev.kind[i], ev.tgt[i], ev.amt[i], ev.x[i] = e.t, e.kind, e.tgt, e.amt, e.x
    end
    return ev
end

--------------------------------------------------------------------------------
-- A session
--------------------------------------------------------------------------------
local Session = {}
Session.__index = Session

-- The scenario the engine runs. The healer is THIS character: pool, regen and
-- the spell kit are read live, exactly what a recording made now would carry.
local function BuildScenario(setup, seed, kit)
    local RM = MD.Regen
    local dur = math.min(PR.MAX_DUR, math.max(10, setup.dur or 120))
    setup.dur = dur
    local targets = {}
    for i, tg in ipairs(setup.targets) do
        local maxHP = math.max(1, tg.maxHP or 1)
        targets[i] = { name = tg.name, role = tg.role, maxHP = maxHP,
                       hp0 = math.floor(maxHP * (tg.startHp or setup.startHp or 1) + 0.5), tracked = true }
    end
    local sampleT, hpT = {}, {}
    for t = 0, dur, 2 do sampleT[#sampleT + 1] = t end
    for t = 0, dur, 5 do hpT[#hpT + 1] = t end
    local pool = (MD.API.UnitPowerMax and MD.API.UnitPowerMax("player", 0)) or 0
    local apiBase, apiCasting, energize
    if RM then
        apiBase, apiCasting, energize = RM.apiBase or 0, RM.apiCasting or 0, RM:Unreported()
    else
        -- R4 (review 2026-09-29): MD.Regen is Engine/RegenModel.lua, on the TBC
        -- TOC only. Without it (Forever) the rates are the client's own
        -- GetManaRegen through the adapter -- plain out of combat, which is
        -- where a session starts -- as UI/Clock_Forever.lua reads them. A
        -- secret or absent answer leaves them 0, as before. Nothing unreported
        -- is modelled on Forever, so energize stays 0.
        apiBase, apiCasting, energize = 0, 0, 0
        if MD.API.ManaRegen then
            local base, casting = MD.API.ManaRegen()
            if type(base) == "number" and type(casting) == "number" then
                apiBase, apiCasting = base, casting
            end
        end
    end
    return {
        dur = dur, pool = pool,
        initial = { mana = pool, apiBase = apiBase, apiCasting = apiCasting,
                    form = (MD.InTreeForm and MD:InTreeForm()) and "tree" or "caster",
                    energize = energize or 0 },
        targets = targets, ev = PR.BuildDamage(setup, seed),
        floor = (MD.db and MD.db.simFloor) or 0.30, grace = 6,
        sampleT = sampleT, hpSampleT = hpT, kit = kit, synthetic = true,
    }
end

-- setup: PR.DefaultSetup's shape. opts.seed (default: the clock), opts.onError
-- (msg, spellID, target), opts.kit (tests)
function PR.New(setup, opts)
    opts = opts or {}
    local SM = MD.SimModel
    local seed = opts.seed or ((time and time()) or 1)
    local kit = opts.kit or MD.RankMath:SpellKit({ live = true })
    -- A player waits through the real cast bar, not the Nature's Grace average
    -- the planner uses for throughput. The session's own copy of the kit, so the
    -- shared one is untouched; a recording replays from its cast SUCCESS times,
    -- so the replay does not depend on this.
    do
        local copy = { crit = kit.crit }
        for form, list in pairs(kit) do
            if type(list) == "table" then
                copy[form] = {}
                for id, e in pairs(list) do
                    local c = {}
                    for k, v in pairs(e) do c[k] = v end
                    if c.castBase and (c.type == "direct" or c.type == "hybrid") then c.cast = c.castBase end
                    copy[form][id] = c
                end
            end
        end
        kit = copy
    end
    local s = setmetatable({
        setup = setup, seed = seed, kit = kit, opts = opts,
        clock = 0, speed = 1, paused = false, state = "ready",
        queue = {}, own = {}, errors = 0, startedAt = (time and time()) or 0,
    }, Session)
    s.scenario = BuildScenario(setup, seed, kit)
    s.pool = s.scenario.pool

    local plan = {
        name = "you", noReaction = true, poll = PR.POLL,
        BindCount = function() return 0 end,
        Decide = function(_, S, t, mana, form) return s:Decide(S, t, mana, form) end,
    }
    s.plan = plan
    local runOpts = {
        critMode = "ev",
        trace = { dt = opts.dt or 0.1 },
        pace = function(nt, S, mana, form, busyUntil)
            s.S, s.mana, s.form, s.busyUntil = S, mana, form, busyUntil
            while s.clock < nt do
                if s.stopping then return false end
                coroutine.yield()
            end
            if s.stopping then return false end
            return true
        end,
        onCast = function(_, t, spellID, ti, mana)
            s:Note(t, SM.K.OWNCAST, ti, s.lastCost or -1, spellID)
        end,
        onHeal = function(t, ti, amount, _, family, spellID, periodic, crit)
            if family == "foreign" or not spellID then return end
            s:Note(t, periodic and SM.K.OWNTICK or SM.K.OWNHEAL, ti, amount,
                spellID + (crit and 100000 or 0))
        end,
    }
    s.runOpts = runOpts
    s.co = coroutine.create(function()
        local r = SM:Run(s.scenario, plan, runOpts)
        s.trace = r.trace
        s.deathsAt = {}
        for i = 1, (r.deaths and r.deaths.n or 0) do s.deathsAt[i] = { r.deaths.tgt[i], r.deaths.t[i] } end
        return r
    end)
    return s
end

-- The trace the engine is writing right now, for the window to paint.
function Session:LiveTrace()
    return self.trace or (self.runOpts.trace and self.runOpts.trace.built)
end

function Session:Note(t, kind, tgt, amt, x)
    local o = self.own
    o[#o + 1] = { t = t, kind = kind, tgt = tgt or -1, amt = amt or 0, x = x or 0, seq = #o + 1 }
end

function Session:Error(msg, spellID, ti)
    self.errors = self.errors + 1
    self.lastError, self.lastErrorAt = msg, self.clock
    if self.opts.onError then self.opts.onError(msg, spellID, ti) end
end

-- The player pressed something. Nothing is decided here: the press waits in
-- the queue for the engine's next decision, where the game's own rules apply.
function Session:Cast(spellID, ti)
    if self.state ~= "running" then return false end
    -- the client answers a press made while a cast or the GCD still has more
    -- than the queue window to run AT ONCE, not when it ends
    if (self.busyUntil or 0) - self.clock > PR.QUEUE then
        self:Error("Another action is in progress", spellID, ti)
        return false
    end
    local q = self.queue
    -- one press at a time, like the client: a newer press replaces a queued one
    for i = #q, 1, -1 do q[i] = nil end
    q[1] = { spellID = spellID, target = ti, at = self.clock }
    return true
end

-- The plan's Decide: the queued press, if the game would allow it now.
function Session:Decide(S, t, mana, form)
    local q = self.queue
    local inp = q[1]
    if not inp then return nil end
    if inp.at > t + 1e-9 then return nil end          -- pressed after this instant: next poll
    q[1] = nil
    if t - inp.at > PR.QUEUE + PR.POLL then
        self:Error("Another action is in progress", inp.spellID, inp.target)
        return nil
    end
    local SM = MD.SimModel
    local e = self.kit[form] and self.kit[form][inp.spellID]
    local ti = inp.target
    if not e then self:Error("You can't cast that here", inp.spellID, ti); return nil end
    if e.dataMissing then self:Error("Not modelled yet", inp.spellID, ti); return nil end
    if not ti or ti < 1 or ti > (S.nT or 0) then self:Error("No target", inp.spellID, ti); return nil end
    if S.dead[ti] then self:Error("Target is dead", inp.spellID, ti); return nil end
    if (e.cost or 0) > mana then self:Error("Not enough mana", inp.spellID, ti); return nil end
    if not SM.Ready(S, inp.spellID, t) then self:Error("Spell is not ready yet", inp.spellID, ti); return nil end
    if e.type == "instant" then
        local row = S.hots[ti]
        local rg = row and row[SM.HOT_INDEX.Regrowth]
        local rj = row and row[SM.HOT_INDEX.Rejuvenation]
        if not ((rg and rg.active) or (rj and rj.active)) then
            self:Error("Nothing to consume", inp.spellID, ti)
            return nil
        end
    end
    self.lastCost = e.cost
    if not (e.type == "hot" or e.type == "lifebloom" or e.type == "instant") then
        self:Note(t, SM.K.CASTSTART, ti, 0, inp.spellID)
    end
    return inp.spellID, ti, 0
end

function Session:Start()
    if self.state ~= "ready" then return end
    self.state = "running"
    self:Resume()
end

function Session:Resume()
    local ok, r = coroutine.resume(self.co)
    if not ok then
        self.state = "failed"
        self.failure = r
        MD:Debug("sim", "practice session failed: %s", tostring(r))
        return
    end
    if coroutine.status(self.co) == "dead" then
        self.result = r
        self:Finish()
    end
end

-- Real time in, engine time out. `elapsed` is wall seconds since the last call.
function Session:Update(elapsed)
    if self.state ~= "running" or self.paused then return end
    if elapsed > 0.25 then elapsed = 0.25 end      -- a hitch is a pause, not a skip
    self.clock = self.clock + elapsed * (self.speed or 1)
    if self.clock > self.scenario.dur then self.clock = self.scenario.dur end
    self:Resume()
end

function Session:SetPaused(on) if self.state == "running" then self.paused = on and true or false end end
function Session:SetSpeed(x) self.speed = math.max(0.25, math.min(1, x or 1)) end

-- End it now; what has happened is kept.
function Session:Stop()
    if self.state ~= "running" then return end
    self.stopping = true
    self:Resume()
end

--------------------------------------------------------------------------------
-- The recording. The stream a dungeon pull would have produced, built from what
-- the engine did: the damage that landed, every cast, cast start and heal as
-- the combat log would have carried it, mana every 2s and health every 5s.
--------------------------------------------------------------------------------
function Session:Finish()
    if self.state == "done" then return self.rec end
    self.state = "done"
    local SM = MD.SimModel
    local K = SM.K
    local sc = self.scenario
    local S = self.S
    local endT = math.min(self.clock, sc.dur)
    if endT <= 0 or not S then return nil end

    local roster, tracked = {}, {}
    for i, tg in ipairs(self.setup.targets) do
        roster[i] = { name = tg.name, class = tg.class, role = tg.role, roleSource = "practice",
                      maxHP = sc.targets[i].maxHP,
                      guid = tg.you and MD.player and MD.player.guid or nil }
        tracked[i] = i
    end

    -- the timeline: what happened TO the group, then what the healer did, in
    -- the engine's own order at equal timestamps (the group's events first)
    local rows = {}
    local sev = sc.ev
    for i = 1, #sev.t do
        if sev.t[i] <= endT then
            rows[#rows + 1] = { t = sev.t[i], kind = sev.kind[i], tgt = sev.tgt[i], amt = sev.amt[i],
                                x = sev.x[i], order = 0, seq = i }
        end
    end
    local deaths = {}
    for i = 1, S.deaths.n do
        local t = S.deaths.t[i]
        if t <= endT then
            rows[#rows + 1] = { t = t, kind = K.DIED, tgt = S.deaths.tgt[i], amt = 0, x = 0, order = 2, seq = i }
            deaths[#deaths + 1] = { S.deaths.tgt[i], t }
        end
    end
    local spent, casts, names = 0, 0, {}
    for _, o in ipairs(self.own) do
        if o.t <= endT then
            rows[#rows + 1] = { t = o.t, kind = o.kind, tgt = o.tgt, amt = o.amt, x = o.x, order = 1, seq = o.seq }
            if o.kind == K.OWNCAST then
                casts = casts + 1
                if o.amt > 0 then spent = spent + o.amt end
                local sd = MD.SpellData.spells[o.x]
                if sd and not names[o.x] then names[o.x] = sd.family .. " r" .. sd.rank end
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.t ~= b.t then return a.t < b.t end
        if a.order ~= b.order then return a.order < b.order end
        return a.seq < b.seq
    end)
    local ev = { t = {}, kind = {}, tgt = {}, amt = {}, x = {} }
    for i, e in ipairs(rows) do
        ev.t[i], ev.kind[i], ev.tgt[i], ev.amt[i], ev.x[i] = e.t, e.kind, e.tgt, e.amt, e.x
    end

    -- health every 5s from the engine's own samples, plus the moment it ended
    local hp = { t = {}, hp = {}, max = {} }
    for i = 1, #tracked do hp.hp[i], hp.max[i] = {}, {} end
    for k, t in ipairs(sc.hpSampleT) do
        if t <= endT and S.hpCurve[1] and S.hpCurve[1][k] then
            hp.t[#hp.t + 1] = t
            for i = 1, #tracked do
                local n = #hp.t
                hp.hp[i][n] = S.hpCurve[i][k]
                hp.max[i][n] = sc.targets[i].maxHP
            end
        end
    end
    if hp.t[#hp.t] ~= endT then
        local n = #hp.t + 1
        hp.t[n] = endT
        for i = 1, #tracked do
            hp.hp[i][n] = S.dead[i] and 0 or S.hp[i]
            hp.max[i][n] = sc.targets[i].maxHP
        end
    end

    local mana = { t = {}, v = {}, base = {}, cast = {} }
    for k, t in ipairs(sc.sampleT) do
        if t <= endT and S.manaCurve[k] then
            local n = #mana.t + 1
            mana.t[n], mana.v[n] = t, S.manaCurve[k]
            mana.base[n], mana.cast[n] = sc.initial.apiBase, sc.initial.apiCasting
        end
    end

    local known = {}
    for family, id in pairs(MD.SpellData.maxRank or {}) do known[family] = id end
    local initial = {}
    for k, v in pairs(sc.initial) do initial[k] = v end
    initial.known = known
    initial.auras, initial.buffs = {}, {}

    local foreign, own = 0, 0
    for i = 1, #ev.t do
        if ev.kind[i] == K.FHEAL then foreign = foreign + ev.amt[i]
        elseif ev.kind[i] == K.OWNHEAL or ev.kind[i] == K.OWNTICK then own = own + ev.amt[i] end
    end

    local g
    for _, x in ipairs(PR.GROUPS) do if x.id == self.setup.group then g = x end end
    if casts == 0 then
        -- nothing was played: not a fight worth a slot
        self.rec = nil
        MD:Debug("sim", "practice ended after %.0fs with no casts: not kept", endT)
        if self.opts.onFinish then self.opts.onFinish(nil) end
        return nil
    end
    local rec = {
        v = 2, id = self.startedAt, t0 = 0, dur = endT, pool = sc.pool,
        zone = "Practice: " .. (g and g.label or "custom"), encounter = "Practice",
        roster = roster, tracked = tracked, ev = ev, n = #ev.t,
        hp = hp, mana = mana, initial = initial, precasts = {}, deaths = deaths,
        names = names, ownCasts = casts, spent = spent,
        foreignShare = (own + foreign) > 0 and foreign / (own + foreign) or 0,
        truncated = false, pinned = false,
        -- what makes it practice: the setup and seed that reproduce the fight,
        -- and whether it was played to the end
        practice = { seed = self.seed, setup = PR.CopySetup(self.setup), finished = endT >= sc.dur - 1e-6,
                     errors = self.errors },
    }
    -- Forever: the kit this fight was played with, so the offline tools
    -- (tools/import.lua) replay and coach it with the character's own spells
    -- rather than the stub's. Kit_Forever.lua's; TBC has no KitSnapshot (its
    -- kit is rebuilt offline from cdb.profile), so nothing changes there.
    if MD.RankMath and MD.RankMath.KitSnapshot then rec.kit = MD.RankMath.KitSnapshot(self.kit) end
    self.rec = rec
    if MD.cdb and not self.opts.noStore then PR.Store(rec) end
    MD:Debug("sim", "practice recorded: %.0fs, %d events, %d casts, %d mana, %d dead",
        endT, rec.n, casts, spent, #deaths)
    if self.opts.onFinish then self.opts.onFinish(rec) end
    return rec
end

function PR.CopySetup(setup)
    local out = {}
    for k, v in pairs(setup) do
        if type(v) ~= "table" then out[k] = v end
    end
    out.aoe = {}
    for k, v in pairs(setup.aoe or {}) do out.aoe[k] = v end
    out.targets = {}
    for i, tg in ipairs(setup.targets or {}) do
        local c = {}
        for k, v in pairs(tg) do c[k] = v end
        out.targets[i] = c
    end
    return out
end

--------------------------------------------------------------------------------
-- Keeping them. The newest PR.MAX_KEPT, apart from the ring of real fights so a
-- practice evening never pushes a dungeon pull out.
--------------------------------------------------------------------------------
function PR.Store(rec)
    MD.cdb.practice = MD.cdb.practice or {}
    local list = MD.cdb.practice
    list[#list + 1] = rec
    table.sort(list, function(a, b) return (a.id or 0) > (b.id or 0) end)
    while #list > PR.MAX_KEPT do list[#list] = nil end
end

function PR.List()
    local list = {}
    for _, r in ipairs(MD.cdb and MD.cdb.practice or {}) do list[#list + 1] = r end
    table.sort(list, function(a, b) return (a.id or 0) > (b.id or 0) end)
    return list
end

function PR.Get(n) return PR.List()[n or 1] end
