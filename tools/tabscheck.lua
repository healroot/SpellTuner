-- tools/run.sh tools/tabscheck.lua
--
-- T35 (docs/SPEC-forever-ui.md 3.3, docs/tasks/T35-spell-list-model.md): the
-- list of spells the Spells rail shows, Spells/Tabs.lua -- pure, no frames.
-- The seed (known heals by learn level; damage that costs mana without
-- heals; empty with neither), the reconcile (a newly known family of the
-- seeded kind appended once, never a removed one, never a damage or utility
-- family into a heal list), a family the book no longer has kept and
-- resolved as "stale", the family key and ids Book gives, Add / Remove /
-- Move / Undo / Reset, and cdb.spellTabs initialised at login. Forever only.
HARNESS_FLAVOUR = "forever"

local here = arg[0]:match("^(.*)/[^/]+$")

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-72s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
end

-- A block that raises (on the old code: MD.Tabs is nil) is one failed
-- assertion with the error, not a crashed suite.
local function block(name, fn)
    local good, err = pcall(fn)
    if not good then check(name, false, "raised: " .. tostring(err)) end
end

local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua")
arg[0] = a0

local S = _G.STUB
local Book = MD.Book
local Tabs = MD.Tabs

local function Join(list)
    local out = {}
    for i, v in ipairs(list or {}) do out[i] = tostring(v) end
    return table.concat(out, ",")
end

--------------------------------------------------------------------------------
-- A book built by Book's own grouping from synthetic entries: the family key,
-- ids, kind and ranks exactly as Book:GroupFamilies makes them, without the
-- stub's spellbook. spec: { name, rank, level, known, kind = "heal" |
-- "damage" | nil, cost = n | nil, power = "Rage", free = true, passive }.
--------------------------------------------------------------------------------
local nextId = 70000
local function MakeBook(specs)
    local spells = {}
    for slot, sp in ipairs(specs) do
        nextId = nextId + 1
        local id = sp.id or nextId
        local parsed
        if sp.kind == "heal" then
            parsed = { heal = { min = 10, max = 12 } }
        elseif sp.kind == "damage" then
            parsed = { damage = { min = 10, max = 12 } }
        end
        local cost
        if sp.free then
            cost = { free = true }
        elseif sp.power then
            cost = { free = true, power = sp.power, powerAmount = sp.cost or 10 }
        elseif sp.cost then
            cost = { amount = sp.cost }
        end
        spells[id] = {
            id = id, slot = slot, name = sp.name, rank = sp.rank or 1,
            known = (sp.known ~= false), level = sp.level, parsed = parsed,
            cost = cost, passive = sp.passive == true,
        }
    end
    local families, order = Book:GroupFamilies(spells)
    for _, name in ipairs(order) do Book:Rows(families[name], {}) end
    return { families = families, order = order, spells = spells, read = {} }
end

-- A fresh store for each case: the list lives in MD.cdb.spellTabs.
local function FreshStore()
    MD.cdb.spellTabs = nil
    return Tabs:Store()
end

-- The druid at level 10: two heals, a heal not learned yet (Regrowth), a
-- damage spell, a utility spell, and a passive that heals.
local DRUID = {
    { name = "Rejuvenation", rank = 1, level = 4, kind = "heal", cost = 25 },
    { name = "Rejuvenation", rank = 2, level = 10, kind = "heal", cost = 40 },
    { name = "Healing Touch", rank = 1, level = 1, kind = "heal", cost = 25 },
    { name = "Healing Touch", rank = 2, level = 8, kind = "heal", cost = 55 },
    { name = "Regrowth", rank = 1, level = 12, kind = "heal", cost = 80, known = false },
    { name = "Wrath", rank = 1, level = 1, kind = "damage", cost = 20 },
    { name = "Mark of the Wild", rank = 1, level = 1, cost = 20 },
    { name = "Natural Mending", rank = 1, level = 1, kind = "heal", free = true, passive = true },
}

--------------------------------------------------------------------------------
-- 1: Book gives every family its key and the ids of its ranks
--------------------------------------------------------------------------------
block("Book gives every family its key and the ids of its ranks", function()
    local book = Book:Scan()
    local ht, rj = book.families["Healing Touch"], book.families["Rejuvenation"]
    check("Book gives every family its key and the ids of its ranks",
        ht.key == "Healing Touch" and rj.key == "Rejuvenation"
            and Join(ht.ids) == "5185" and Join(rj.ids) == "774,1058",
        "HT key=" .. tostring(ht.key) .. " ids=" .. Join(ht.ids) .. "; Rejuvenation ids=" .. Join(rj.ids))
end)

--------------------------------------------------------------------------------
-- 2: cdb.spellTabs is there after login, empty and not seeded
--------------------------------------------------------------------------------
block("cdb.spellTabs initialised at login: empty, not seeded", function()
    local st = MD.cdb.spellTabs
    check("cdb.spellTabs initialised at login: empty, not seeded",
        type(st) == "table" and type(st.order) == "table" and #st.order == 0
            and type(st.removed) == "table" and type(st.seen) == "table"
            and type(st.ids) == "table" and st.seeded == false,
        "spellTabs=" .. type(st) .. " seeded=" .. tostring(st and st.seeded))
end)

--------------------------------------------------------------------------------
-- 3: the seed is every known heal, by the lowest learn level of its known
-- ranks -- no heal not learned yet, no damage, no utility, no passive
--------------------------------------------------------------------------------
block("the seed is the known heals by learn level", function()
    FreshStore()
    local book = MakeBook(DRUID)
    local seeded = Tabs:Seed(book)
    local st = MD.cdb.spellTabs
    check("the seed is the known heals by learn level",
        seeded == true and Join(Tabs:Get()) == "Healing Touch,Rejuvenation" and st.seeded == true
            and st.kind == "heal",
        "order=" .. Join(Tabs:Get()) .. " kind=" .. tostring(st.kind))
    check("a seeded family is not new, and its rank ids are kept beside its key",
        not Tabs:IsNew("Healing Touch") and not Tabs:IsNew("Rejuvenation")
            and Join(st.ids["Rejuvenation"]) == Join(book.families["Rejuvenation"].ids),
        "ids=" .. Join(st.ids["Rejuvenation"]))

    -- The seed runs once: an edited list is not re-seeded.
    Tabs:Remove("Rejuvenation")
    local again = Tabs:Seed(book)
    Tabs:Get(book)
    check("the seed runs once: an edited list is not seeded again",
        again == false and Join(Tabs:Get(book)) == "Healing Touch",
        "order=" .. Join(Tabs:Get(book)))
end)

--------------------------------------------------------------------------------
-- 4: Get on a store that was never seeded seeds it (the first open)
--------------------------------------------------------------------------------
block("the first Get with a book seeds the list", function()
    FreshStore()
    local before = Join(Tabs:Get())
    local after = Join(Tabs:Get(MakeBook(DRUID)))
    check("the first Get with a book seeds the list",
        before == "" and after == "Healing Touch,Rejuvenation",
        "before=" .. before .. " after=" .. after)
end)

--------------------------------------------------------------------------------
-- 5/6: no heal -- the damage families that cost mana; neither -- empty
--------------------------------------------------------------------------------
block("with no heal the seed is the damage that costs mana", function()
    FreshStore()
    Tabs:Seed(MakeBook({
        { name = "Frostbolt", rank = 1, level = 4, kind = "damage", cost = 25 },
        { name = "Fireball", rank = 1, level = 1, kind = "damage", cost = 30 },
        { name = "Heroic Strike", rank = 1, level = 1, kind = "damage", power = "Rage", cost = 15 },
        { name = "Shoot", rank = 1, level = 1, kind = "damage", free = true },
        { name = "Arcane Intellect", rank = 1, level = 1, cost = 60 },
    }))
    check("with no heal the seed is the damage that costs mana, by learn level",
        Join(Tabs:Get()) == "Fireball,Frostbolt" and MD.cdb.spellTabs.kind == "damage",
        "order=" .. Join(Tabs:Get()) .. " kind=" .. tostring(MD.cdb.spellTabs.kind))

    FreshStore()
    Tabs:Seed(MakeBook({
        { name = "Heroic Strike", rank = 1, level = 1, kind = "damage", power = "Rage", cost = 15 },
        { name = "Battle Stance", rank = 1, level = 1, free = true },
    }))
    check("with neither the list is empty, and seeded",
        #Tabs:Get() == 0 and MD.cdb.spellTabs.seeded == true,
        "order=" .. Join(Tabs:Get()))
end)

--------------------------------------------------------------------------------
-- 7-9: the reconcile
--------------------------------------------------------------------------------
block("the reconcile appends a newly known heal once, as new", function()
    FreshStore()
    Tabs:Seed(MakeBook(DRUID))
    Tabs:Move("Rejuvenation", 1)   -- the player's own order survives it

    local learned = {}
    for i, sp in ipairs(DRUID) do learned[i] = sp end
    learned[5] = { name = "Regrowth", rank = 1, level = 12, kind = "heal", cost = 80 }  -- trained
    learned[#learned + 1] = { name = "Moonfire", rank = 1, level = 4, kind = "damage", cost = 25 }
    learned[#learned + 1] = { name = "Thorns", rank = 1, level = 6, cost = 35 }
    local book = MakeBook(learned)

    local added = Tabs:Reconcile(book)
    local once = Join(Tabs:Get())
    local added2 = Tabs:Reconcile(book)
    check("the reconcile appends a newly known heal once, as new",
        Join(added) == "Regrowth" and once == "Rejuvenation,Healing Touch,Regrowth"
            and #added2 == 0 and Join(Tabs:Get()) == once and Tabs:IsNew("Regrowth"),
        "added=" .. Join(added) .. " order=" .. once .. " second=" .. Join(added2))
    check("the reconcile never adds a damage or a utility family to a heal list",
        not Tabs:Has("Moonfire") and not Tabs:Has("Thorns") and not Tabs:Has("Wrath")
            and not Tabs:Has("Mark of the Wild"),
        "order=" .. Join(Tabs:Get()))

    Tabs:MarkSeen("Regrowth")
    check("a family viewed once is no longer new", not Tabs:IsNew("Regrowth"))

    Tabs:Remove("Regrowth")
    local added3 = Tabs:Reconcile(book)
    check("the reconcile never re-adds a removed family",
        #added3 == 0 and not Tabs:Has("Regrowth") and MD.cdb.spellTabs.removed["Regrowth"] == true,
        "added=" .. Join(added3) .. " order=" .. Join(Tabs:Get()))
end)

block("the reconcile does nothing before the seed", function()
    FreshStore()
    local added = Tabs:Reconcile(MakeBook(DRUID))
    check("the reconcile does nothing before the seed (the seed runs on first open)",
        #added == 0 and #Tabs:Get() == 0 and MD.cdb.spellTabs.seeded == false,
        "order=" .. Join(Tabs:Get()))
end)

block("a list seeded empty takes its kind from the first heal learned", function()
    FreshStore()
    Tabs:Seed(MakeBook({ { name = "Battle Stance", rank = 1, level = 1, free = true } }))
    local added = Tabs:Reconcile(MakeBook({
        { name = "Battle Stance", rank = 1, level = 1, free = true },
        { name = "Lesser Heal", rank = 1, level = 1, kind = "heal", cost = 30 },
        { name = "Smite", rank = 1, level = 1, kind = "damage", cost = 20 },
    }))
    check("a list seeded empty takes the seed's rule when a heal is learned",
        Join(added) == "Lesser Heal" and MD.cdb.spellTabs.kind == "heal",
        "added=" .. Join(added) .. " kind=" .. tostring(MD.cdb.spellTabs.kind))
end)

--------------------------------------------------------------------------------
-- 10-11: a family the book no longer has stays; a renamed one resolves by id
--------------------------------------------------------------------------------
block("a family the book no longer has stays in the list, stale", function()
    FreshStore()
    Tabs:Seed(MakeBook(DRUID))
    Tabs:Add("Wrath", nil, MakeBook(DRUID))
    local respec = {}
    for _, sp in ipairs(DRUID) do if sp.name ~= "Wrath" then respec[#respec + 1] = sp end end
    local book = MakeBook(respec)
    Tabs:Reconcile(book)
    check("a family the book no longer has stays in the list, stale",
        Join(Tabs:Get()) == "Healing Touch,Rejuvenation,Wrath" and Tabs:Resolve("Wrath", book) == "stale"
            and type(Tabs:Resolve("Healing Touch", book)) == "table"
            and Tabs:Resolve("Healing Touch", book).key == "Healing Touch",
        "order=" .. Join(Tabs:Get()) .. " Wrath=" .. tostring(Tabs:Resolve("Wrath", book)))
end)

block("a renamed family resolves through its ids and keeps its place", function()
    FreshStore()
    local book = MakeBook({
        { id = 81001, name = "Healing Touch", rank = 1, level = 1, kind = "heal", cost = 25 },
        { id = 81002, name = "Rejuvenation", rank = 1, level = 4, kind = "heal", cost = 25 },
    })
    Tabs:Seed(book)
    local renamed = MakeBook({
        { id = 81001, name = "Healing Touch (new)", rank = 1, level = 1, kind = "heal", cost = 25 },
        { id = 81002, name = "Rejuvenation", rank = 1, level = 4, kind = "heal", cost = 25 },
    })
    local fam = Tabs:Resolve("Healing Touch", renamed)
    local added = Tabs:Reconcile(renamed)
    check("a renamed family resolves through its ids and keeps its place",
        type(fam) == "table" and fam.key == "Healing Touch (new)" and #added == 0
            and Join(Tabs:Get()) == "Healing Touch (new),Rejuvenation",
        "resolved=" .. tostring(type(fam) == "table" and fam.key or fam) .. " order=" .. Join(Tabs:Get()))
end)

--------------------------------------------------------------------------------
-- 12-15: Add, Remove, Undo, Move, Reset
--------------------------------------------------------------------------------
block("Add inserts at a row, once, and only a family the book has", function()
    FreshStore()
    local book = MakeBook(DRUID)
    Tabs:Seed(book)
    local at = Tabs:Add("Wrath", 2, book)
    local dup = Tabs:Add("Wrath", nil, book)
    local missing = Tabs:Add("Starfire", nil, book)
    check("Add inserts at a row, once, and only a family the book has",
        at == 2 and dup == nil and missing == nil
            and Join(Tabs:Get()) == "Healing Touch,Wrath,Rejuvenation" and not Tabs:IsNew("Wrath")
            and Join(MD.cdb.spellTabs.ids["Wrath"]) == Join(book.families["Wrath"].ids),
        "order=" .. Join(Tabs:Get()) .. " at=" .. tostring(at))
end)

block("Remove records the family as removed; Undo puts it back where it was", function()
    FreshStore()
    local book = MakeBook(DRUID)
    Tabs:Seed(book)
    Tabs:Add("Wrath", nil, book)
    local idx = Tabs:Remove("Rejuvenation")
    local st = MD.cdb.spellTabs
    local pending = Tabs:UndoKey()
    check("Remove records the family as removed",
        idx == 2 and st.removed["Rejuvenation"] == true and Join(Tabs:Get()) == "Healing Touch,Wrath"
            and pending == "Rejuvenation",
        "idx=" .. tostring(idx) .. " order=" .. Join(Tabs:Get()) .. " undo=" .. tostring(pending))

    local back = Tabs:Undo()
    local again = Tabs:Undo()
    check("Undo puts it back where it was, once, and forgets the removal",
        back == "Rejuvenation" and again == nil and Join(Tabs:Get()) == "Healing Touch,Rejuvenation,Wrath"
            and st.removed["Rejuvenation"] == nil and Tabs:UndoKey() == nil,
        "order=" .. Join(Tabs:Get()) .. " again=" .. tostring(again))

    Tabs:Remove("Wrath")
    Tabs:Move("Rejuvenation", 1)
    check("Undo lasts until the next change",
        Tabs:UndoKey() == nil and Tabs:Undo() == nil and not Tabs:Has("Wrath"),
        "order=" .. Join(Tabs:Get()))

    Tabs:Add("Wrath", nil, book)
    check("adding a removed family back forgets that it was removed",
        st.removed["Wrath"] == nil and Tabs:Has("Wrath"))
end)

block("Move puts a family at a row, clamped", function()
    FreshStore()
    local book = MakeBook(DRUID)
    Tabs:Seed(book)
    Tabs:Add("Wrath", nil, book)
    local a = Tabs:Move("Wrath", 1)
    local o1 = Join(Tabs:Get())
    local b = Tabs:Move("Wrath", 99)
    local o2 = Join(Tabs:Get())
    local c = Tabs:Move("Starfire", 1)
    check("Move puts a family at a row, clamped to the list",
        a == 1 and o1 == "Wrath,Healing Touch,Rejuvenation" and b == 3
            and o2 == "Healing Touch,Rejuvenation,Wrath" and c == nil,
        o1 .. " / " .. o2)
end)

block("Reset gives the seed back and forgets every removal", function()
    FreshStore()
    local book = MakeBook(DRUID)
    Tabs:Seed(book)
    Tabs:Add("Wrath", 1, book)
    Tabs:Remove("Healing Touch")
    Tabs:Reset(book)
    local st = MD.cdb.spellTabs
    check("Reset gives the seed back and forgets every removal",
        Join(Tabs:Get()) == "Healing Touch,Rejuvenation" and next(st.removed) == nil
            and Tabs:UndoKey() == nil and st.seeded == true,
        "order=" .. Join(Tabs:Get()))
end)

--------------------------------------------------------------------------------
-- 16: through the real book -- a heal learned after the seed shows up at the
-- next scan that follows the book going dirty (SPELLS_CHANGED)
--------------------------------------------------------------------------------
block("a heal learned after the seed is appended when the book rescans", function()
    FreshStore()
    Book:MarkDirty()
    Tabs:Get(Book:Get())
    local seeded = Join(Tabs:Get())
    S.AddSpell(8936, "Regrowth", "Rank 1",
        function() return "Heals a friendly target for 84 to 98." end,
        { cast = 2000, cost = 80, level = 12 })
    S.AddSpell(8921, "Moonfire", "Rank 1",
        function() return "Causes 9 to 12 Arcane damage to the target." end,
        { cast = 0, cost = 25, level = 4 })
    S.Fire("SPELLS_CHANGED")
    Book:Get()
    check("a heal learned after the seed is appended when the book rescans",
        seeded == "Healing Touch,Rejuvenation" and Join(Tabs:Get()) == "Healing Touch,Rejuvenation,Regrowth"
            and Tabs:IsNew("Regrowth") and not Tabs:Has("Moonfire"),
        "seeded=" .. seeded .. " now=" .. Join(Tabs:Get()))
end)

--------------------------------------------------------------------------------
print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL: " .. f) end
os.exit(#fails == 0 and 0 or 1)
