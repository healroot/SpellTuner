-- tools/run.sh tools/tabscheck.lua
--
-- T35 (docs/SPEC-forever-ui.md 3.3, docs/tasks/T35-spell-list-model.md): the
-- list of spells the Spells rail shows, Spells/Tabs.lua -- pure, no frames.
-- The seed (known heals by learn level; damage that costs mana without
-- heals; empty with neither), the reconcile (a newly known family of the
-- seeded kind appended once, never a removed one, never a damage or utility
-- family into a heal list), a family the book no longer has kept and
-- resolved as "stale", the family key and ids Book gives, Add / Remove /
-- Move / Undo / Reset, and cdb.spellTabs initialised at login. T84 (C5) and
-- T118: under tbc, six checks of the list over MD.Book (Spells/Book_Model.lua, below).
HARNESS_FLAVOUR = { "forever", "tbc" }

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
-- "damage" | "both" (T110) | nil, cost = n | nil, power = "Rage", free = true, passive }.
--------------------------------------------------------------------------------
local nextId = 70000
local function MakeBook(specs)
    local spells = {}
    for slot, sp in ipairs(specs) do
        nextId = nextId + 1
        local id = sp.id or nextId
        local parsed
        if sp.kind == "both" then -- T110: an either-or spell (Holy Shock): a heal family, altKind damage
            parsed = { heal = { min = 10, max = 12 }, damage = { min = 20, max = 24 } }
        elseif sp.kind == "heal" then
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

--------------------------------------------------------------------------------
-- T84 (C5 of docs/PLAN-refactor-ux.md, section 7.1): the list on TBC.
-- T118 (docs/tasks/T118-tbc-book.md): its book is MD.Book on both lines now
-- -- TBC's is Spells/Book_Model.lua, refreshed on SPELLS_REBUILT, firing
-- BOOK_CHANGED, which runs the reconcile, as on Forever -- through the one
-- seam, Tabs.source, left at its default. The rules are the Forever ones
-- above; a family marked noSeed (Tranquility, Swiftmend) is in the book but
-- never seeded or reconciled in, only added by hand; Resolve finds a family
-- by its entries' `family`. Six checks, then the suite ends (the Forever half
-- needs Spells/Book.lua's grouping).
--------------------------------------------------------------------------------
if S.flavour == "tbc" then
    local SD = MD.SpellData
    local LIFEBLOOM = {}
    for _, id in ipairs(SD.all.Lifebloom) do LIFEBLOOM[id] = true end
    -- every rank known (a level 70 druid), or every rank but Lifebloom's
    local function Train(withLifebloom)
        S.level = 70
        wipe(S.known)
        for id in pairs(SD.spells) do
            if withLifebloom or not LIFEBLOOM[id] then S.known[id] = true end
        end
        SD:BuildKnown() -- fires SPELLS_REBUILT: the book refreshed, BOOK_CHANGED, the list reconciled
    end

    block("tbc: a level 70 druid's book seeds Healing Touch, Rejuvenation, Regrowth and Lifebloom", function()
        Train(true)
        FreshStore()
        local book = Tabs.source()
        local order = Join(Tabs:Get(book))
        local ht = book.families.HealingTouch
        local shape = ht and ht.key == "HealingTouch" and ht.name == "Healing Touch" and ht.kind == "heal"
            and #ht.ids == #SD.all.HealingTouch and ht.ranks[1].id == ht.ids[1] and ht.ranks[1].known == true
            and type(ht.ranks[1].level) == "number" and type(ht.ranks[1].cost.amount) == "number"
            and ht.maxKnown == ht.ranks[#ht.ranks] and ht.ranks[1].family == "HealingTouch"
        local tq, sm = book.families.Tranquility, book.families.Swiftmend
        check("tbc: a level 70 druid's book seeds Healing Touch, Rejuvenation, Regrowth and Lifebloom",
            order == "HealingTouch,Rejuvenation,Regrowth,Lifebloom" and shape
                and Join(book.order) == "HealingTouch,Lifebloom,Rejuvenation,Regrowth,Tranquility,Swiftmend"
                and tq ~= nil and tq.noSeed == true and sm ~= nil and sm.noSeed == true
                and MD.cdb.spellTabs.kind == "heal" and not Tabs:IsNew("Lifebloom"),
            "order=" .. order .. " shape=" .. tostring(shape) .. " book=" .. Join(book.order))
    end)

    block("tbc: a removed family stays removed across SPELLS_REBUILT", function()
        Train(true)
        FreshStore()
        Tabs:Get(Tabs.source())
        Tabs:Remove("Regrowth")
        Train(true)
        Train(true)
        check("tbc: a removed family stays removed across SPELLS_REBUILT",
            Join(Tabs:Get()) == "HealingTouch,Rejuvenation,Lifebloom" and not Tabs:Has("Regrowth")
                and MD.cdb.spellTabs.removed.Regrowth == true,
            "order=" .. Join(Tabs:Get()))
    end)

    block("tbc: a family trained later is appended with the new dot", function()
        Train(false)
        FreshStore()
        local seeded = Join(Tabs:Get(Tabs.source()))
        local known = Tabs.source().families.Lifebloom.maxKnown
        Train(true) -- Lifebloom trained: SPELLS_REBUILT refreshes the book, BOOK_CHANGED reconciles
        check("tbc: a family trained later is appended with the new dot",
            seeded == "HealingTouch,Rejuvenation,Regrowth" and known == nil
                and Join(Tabs:Get()) == "HealingTouch,Rejuvenation,Regrowth,Lifebloom"
                and Tabs:IsNew("Lifebloom") and not Tabs:IsNew("Regrowth")
                and Tabs.source().families.Lifebloom.maxKnown ~= nil,
            "seeded=" .. seeded .. " now=" .. Join(Tabs:Get()))
    end)

    -- One seam on both lines: TBC installs nothing, the default reads MD.Book.
    block("tbc: the source is the default one, MD.Book:Get(), as on Forever", function()
        local default = Tabs.source == Tabs.BookSource and MD.Book ~= nil and Tabs.source() == MD.Book:Get()
        check("tbc: the source is the default one, MD.Book:Get(), as on Forever", default,
            "source default=" .. tostring(Tabs.source == Tabs.BookSource) .. " book=" .. tostring(MD.Book ~= nil))
    end)

    block("tbc: noSeed families are never seeded or reconciled in, but can be added", function()
        Train(true)
        FreshStore()
        local seeded = Join(Tabs:Get(Tabs.source()))
        Train(true)
        local reconciled = Join(Tabs:Get())
        local at = Tabs:Add("Swiftmend")
        check("tbc: noSeed families are never seeded or reconciled in, but can be added",
            seeded == "HealingTouch,Rejuvenation,Regrowth,Lifebloom" and reconciled == seeded
                and at == 5 and Join(Tabs:Get()) == seeded .. ",Swiftmend",
            "seeded=" .. seeded .. " reconciled=" .. reconciled .. " add=" .. tostring(at))
    end)

    -- A key the book no longer has, found again through an id it stored: the
    -- entry names its family by `family` (TBC's key), not by its name.
    block("tbc: Resolve finds a renamed family by its entries' family key", function()
        local entry = { id = 5185, name = "Healing Touch", family = "HealingTouch" }
        local fam = { key = "HealingTouch", name = "Healing Touch", kind = "heal", ids = { 5185 }, ranks = { entry } }
        local fake = { families = { HealingTouch = fam }, order = { "HealingTouch" }, spells = { [5185] = entry } }
        local store = FreshStore()
        store.order = { "OldKey" }
        store.ids = { OldKey = { 5185 } }
        local got, why = Tabs:Resolve("OldKey", fake)
        FreshStore()
        check("tbc: Resolve finds a renamed family by its entries' family key", got == fam,
            "got=" .. tostring(got and got.key) .. " " .. tostring(why))
    end)

    print(string.format("\n%d ok, %d failed", ok, #fails))
    for _, f in ipairs(fails) do print("  FAIL: " .. f) end
    os.exit(#fails == 0 and 0 or 1)
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
-- T110 (docs/SPEC-next.md 4.2 P6): the list seeded by role. Forever's talent
-- API answers nothing readable, so the role is read off the book: a talent's
-- own spell (Tabs.ROLE_TALENTS, talentsforever's talent list per tree) says
-- heal or damage, more wins, a tie or none says nothing (the old seed).
--------------------------------------------------------------------------------

-- A level 60 shadow priest: heals known, but Mind Flay, Shadowform and
-- Vampiric Embrace in the book.
local SHADOW = {
    { name = "Lesser Heal", rank = 1, level = 1, kind = "heal", cost = 30 },
    { name = "Renew", rank = 1, level = 8, kind = "heal", cost = 30 },
    { name = "Smite", rank = 1, level = 1, kind = "damage", cost = 20 },
    { name = "Shadow Word: Pain", rank = 1, level = 4, kind = "damage", cost = 25 },
    { name = "Mind Blast", rank = 1, level = 10, kind = "damage", cost = 50 },
    { name = "Mind Flay", rank = 1, level = 20, kind = "damage", cost = 45 },
    { name = "Shadowform", rank = 1, level = 40, cost = 100 },
    { name = "Vampiric Embrace", rank = 1, level = 30, cost = 40 },
    { name = "Power Word: Fortitude", rank = 1, level = 1, cost = 60 },
}

block("T110: a shadow priest's list seeds damage; a holy priest's heals, Holy Nova among them", function()
    FreshStore()
    local book = MakeBook(SHADOW)
    local role, said = Tabs:BookRole(book)
    Tabs:Seed(book)
    local order = Join(Tabs:Get())
    local r, src = Tabs:Role(book)
    local shadow = role == "damage" and Join(said) == "Mind Flay,Shadowform,Vampiric Embrace"
        and order == "Smite,Shadow Word: Pain,Mind Blast,Mind Flay" and MD.cdb.spellTabs.kind == "damage"
        and r == "damage" and src == "talents"

    FreshStore()
    local holy = MakeBook({
        { name = "Lesser Heal", rank = 1, level = 1, kind = "heal", cost = 30 },
        { name = "Smite", rank = 1, level = 1, kind = "damage", cost = 20 },
        { name = "Holy Nova", rank = 1, level = 20, kind = "both", cost = 185 },
        { name = "Binding Heal", rank = 1, level = 40, kind = "heal", cost = 300 },
        { name = "Mind Flay", rank = 1, level = 20, kind = "damage", cost = 45 },
    })
    local hrole = Tabs:BookRole(holy)
    Tabs:Seed(holy)
    local horder = Join(Tabs:Get())
    check("T110: a shadow priest's list seeds damage; a holy priest's heals, Holy Nova among them",
        shadow and hrole == "heal" and horder == "Lesser Heal,Holy Nova,Binding Heal"
            and holy.families["Holy Nova"].altKind == "damage",
        "shadow role=" .. tostring(role) .. " said=" .. Join(said) .. " order=" .. order
            .. " Role=" .. tostring(r) .. "/" .. tostring(src) .. "; holy role=" .. tostring(hrole)
            .. " order=" .. horder)
end)

block("T110: a damage list takes an either-or heal; a tie seeds heals; Reset is heals; the list's kind is the fallback", function()
    -- a Retribution paladin with Holy Shock: damage 2 (Seal of Command,
    -- Repentance) to heal 1 (Holy Shock)
    local ret = MakeBook({
        { name = "Holy Light", rank = 1, level = 1, kind = "heal", cost = 35 },
        { name = "Flash of Light", rank = 1, level = 20, kind = "heal", cost = 35 },
        { name = "Holy Shock", rank = 1, level = 40, kind = "both", cost = 225 },
        { name = "Exorcism", rank = 1, level = 20, kind = "damage", cost = 85 },
        { name = "Seal of Command", rank = 1, level = 20, cost = 65 },
        { name = "Repentance", rank = 1, level = 40, cost = 60 },
    })
    FreshStore()
    Tabs:Seed(ret)
    local seeded = Join(Tabs:Get())
    local reset = Join(Tabs:Reset(ret))
    local resetKind = MD.cdb.spellTabs.kind

    -- one each: no role, the old seed (heals), and Role falls back on it
    local tie = MakeBook({
        { name = "Holy Light", rank = 1, level = 1, kind = "heal", cost = 35 },
        { name = "Holy Shock", rank = 1, level = 40, kind = "both", cost = 225 },
        { name = "Exorcism", rank = 1, level = 20, kind = "damage", cost = 85 },
        { name = "Seal of Command", rank = 1, level = 20, cost = 65 },
    })
    FreshStore()
    local before = Tabs:Role(tie)
    local tieRole = Tabs:BookRole(tie)
    Tabs:Seed(tie)
    local tieOrder = Join(Tabs:Get())
    local r, src = Tabs:Role(tie)
    -- a talent not known (an untrained rank) says nothing
    local untrained = MakeBook({
        { name = "Holy Light", rank = 1, level = 1, kind = "heal", cost = 35 },
        { name = "Exorcism", rank = 1, level = 20, kind = "damage", cost = 85 },
        { name = "Seal of Command", rank = 1, level = 20, cost = 65, known = false },
    })
    check("T110: a damage list takes an either-or heal; a tie seeds heals; Reset is heals; the list's kind is the fallback",
        seeded == "Exorcism,Holy Shock" and reset == "Holy Light,Flash of Light,Holy Shock" and resetKind == "heal"
            and before == nil and tieRole == nil and tieOrder == "Holy Light,Holy Shock"
            and r == "heal" and src == "list" and Tabs:BookRole(untrained) == nil,
        "seeded=" .. seeded .. " reset=" .. reset .. "/" .. tostring(resetKind) .. " before=" .. tostring(before)
            .. " tie=" .. tostring(tieRole) .. " " .. tieOrder .. " Role=" .. tostring(r) .. "/" .. tostring(src))
end)

-- Every talent name the map holds for a class with a committed book is a
-- spell of that book (tools/data/books/, talentsforever's export), so a
-- misspelt name cannot sit in the map unseen.
block("T110: every role talent of the priest, paladin and shaman is a spell of their book", function()
    local missing, count = {}, 0
    for class, file in pairs({ PRIEST = "priest", PALADIN = "paladin", SHAMAN = "shaman" }) do
        local data = dofile(here .. "/data/books/" .. file .. "_forever.lua")
        local names = {}
        for _, row in ipairs(data.spells) do names[row.name] = true end
        for _, role in ipairs({ "heal", "damage" }) do
            for _, name in ipairs(Tabs.ROLE_TALENT_TREES[class][role]) do
                count = count + 1
                if not names[name] then missing[#missing + 1] = class .. ":" .. name end
                if Tabs.ROLE_TALENTS[name] ~= role then missing[#missing + 1] = "role:" .. name end
            end
        end
    end
    check("T110: every role talent of the priest, paladin and shaman is a spell of their book",
        #missing == 0 and count == 23, "count=" .. count .. " missing=" .. Join(missing))
end)

--------------------------------------------------------------------------------
print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL: " .. f) end
os.exit(#fails == 0 and 0 or 1)
