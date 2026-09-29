-- T35 (docs/SPEC-forever-ui.md 3.3, docs/tasks/T35-spell-list-model.md): the
-- list of spells the Spells rail shows, one view per family, in the player's
-- own order. Pure: no frames and no client call -- every book it reads is
-- the table Spells/Book.lua built (a family's `key` and `ids` are Book's),
-- and everything it keeps lives in MD.cdb.spellTabs, per character because
-- spellbooks differ by class and level:
--
--   order   = { "Healing Touch", "Rejuvenation" }  -- family keys, your order
--   removed = { ["Moonfire"] = true }              -- never re-added by Reconcile
--   seen    = { ["Healing Touch"] = true }         -- viewed once: no "new" dot
--   ids     = { ["Healing Touch"] = { 5185 } }     -- the rank ids beside a key
--   kind    = "heal"                               -- what the seed took
--   seeded  = true
--
-- The seed runs on first open (Get with a book); the reconcile runs whenever
-- Book rescans after going dirty (BOOK_CHANGED). Forever TOCs only.
local _, MD = ...

MD.Tabs = MD.Tabs or {}
local Tabs = MD.Tabs

-- The one pending removal Undo can put back (3.2: "Wrath removed [Undo]"
-- until the next change). Session memory, tied to the store it came from.
Tabs._undo = nil

--------------------------------------------------------------------------------
-- The store
--------------------------------------------------------------------------------

local function Fresh()
    return { order = {}, removed = {}, seen = {}, ids = {}, seeded = false }
end

-- MD.cdb.spellTabs, created on first use and repaired field by field: it is
-- our own SavedVariables, so a type() check before any index is all it needs.
function Tabs:Store()
    local cdb = MD.cdb
    if type(cdb) ~= "table" then
        Tabs._orphan = Tabs._orphan or Fresh()
        return Tabs._orphan
    end
    local st = cdb.spellTabs
    if type(st) ~= "table" then
        st = Fresh()
        cdb.spellTabs = st
    end
    if type(st.order) ~= "table" then st.order = {} end
    if type(st.removed) ~= "table" then st.removed = {} end
    if type(st.seen) ~= "table" then st.seen = {} end
    if type(st.ids) ~= "table" then st.ids = {} end
    if st.seeded ~= true then st.seeded = false end
    -- A key that is not a string, or a key twice, is dropped: the order is
    -- the rail, and a row per key.
    local clean, have = {}, {}
    for _, key in ipairs(st.order) do
        if type(key) == "string" and not have[key] then
            have[key] = true
            clean[#clean + 1] = key
        end
    end
    if #clean ~= #st.order then st.order = clean end
    return st
end

local function IndexOf(order, key)
    for i, k in ipairs(order) do
        if k == key then return i end
    end
    return nil
end

local function CopyList(list)
    local out = {}
    for i, v in ipairs(list or {}) do out[i] = v end
    return out
end

local function BookOrDefault(book)
    if type(book) == "table" then return book end
    if MD.Book and MD.Book.Get then return MD.Book:Get() end
    return nil
end

local function Families(book)
    return (type(book) == "table" and type(book.families) == "table") and book.families or {}
end

--------------------------------------------------------------------------------
-- What the seed takes (3.3): every family with kind == "heal" that has a
-- known rank, by the lowest learn level of its known ranks; with no heal,
-- the damage families that cost mana; with neither, nothing. A passive
-- family (every rank passive) is never taken: the picker does not list them.
--------------------------------------------------------------------------------

local function KnownRanks(fam)
    local out = {}
    for _, e in ipairs(fam.ranks or {}) do
        if type(e) == "table" and e.known == true then out[#out + 1] = e end
    end
    return out
end

local function AllPassive(fam)
    local any = false
    for _, e in ipairs(fam.ranks or {}) do
        any = true
        if not (type(e) == "table" and e.passive == true) then return false end
    end
    return any
end

-- A known rank that costs mana: an amount or a percent of base mana.
-- Book's "free" costs (none, or Rage / Focus / Energy) are not mana.
local function CostsMana(known)
    for _, e in ipairs(known) do
        local c = e.cost
        if type(c) == "table" and c.free ~= true
            and ((type(c.amount) == "number" and c.amount > 0)
                or (type(c.percent) == "number" and c.percent > 0)) then
            return true
        end
    end
    return false
end

local function LowestLevel(known)
    local low = math.huge
    for _, e in ipairs(known) do
        if type(e.level) == "number" and e.level < low then low = e.level end
    end
    return low
end

-- The families of one kind the seed and the reconcile may take, ordered by
-- learn level, then name.
local function Candidates(book, kind)
    local list = {}
    for key, fam in pairs(Families(book)) do
        if type(fam) == "table" and fam.kind == kind and not AllPassive(fam) then
            local known = KnownRanks(fam)
            if #known > 0 and (kind ~= "damage" or CostsMana(known)) then
                list[#list + 1] = { key = fam.key or key, level = LowestLevel(known) }
            end
        end
    end
    table.sort(list, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        return a.key < b.key
    end)
    local keys = {}
    for i, c in ipairs(list) do keys[i] = c.key end
    return keys
end

-- kind, keys -- what a seed of this book would be.
function Tabs:SeedList(book)
    local heals = Candidates(book, "heal")
    if #heals > 0 then return "heal", heals end
    local damage = Candidates(book, "damage")
    if #damage > 0 then return "damage", damage end
    return nil, {}
end

local function KeepIds(st, key, book)
    local fam = Families(book)[key]
    if type(fam) == "table" and type(fam.ids) == "table" and #fam.ids > 0 then
        st.ids[key] = CopyList(fam.ids)
    end
end

local function ClearUndo()
    Tabs._undo = nil
end

--------------------------------------------------------------------------------
-- The seed, the list, the new dot
--------------------------------------------------------------------------------

-- Once per character: true when it seeded, false when the list already was.
function Tabs:Seed(book)
    local st = Tabs:Store()
    if st.seeded then return false end
    local kind, keys = Tabs:SeedList(book)
    st.order = CopyList(keys)
    st.kind = kind
    for _, key in ipairs(keys) do
        st.seen[key] = true
        KeepIds(st, key, book)
    end
    st.seeded = true
    ClearUndo()
    return true
end

-- A copy of the family keys in the player's order. With a book, the first
-- call seeds the list (the seed runs on first open).
function Tabs:Get(book)
    local st = Tabs:Store()
    if type(book) == "table" and not st.seeded then Tabs:Seed(book) end
    return CopyList(st.order)
end

function Tabs:Has(key)
    return IndexOf(Tabs:Store().order, key) ~= nil
end

-- New: in the list and never viewed (a family the reconcile appended).
function Tabs:IsNew(key)
    local st = Tabs:Store()
    return IndexOf(st.order, key) ~= nil and st.seen[key] ~= true
end

function Tabs:MarkSeen(key)
    if type(key) ~= "string" then return end
    Tabs:Store().seen[key] = true
end

--------------------------------------------------------------------------------
-- Edits: each is one change, and ends the pending Undo (Remove starts one)
--------------------------------------------------------------------------------

-- index, or nil: `at` is the row the family takes (the end when nil),
-- clamped to the list. A family already listed, or one the book does not
-- have, is refused. The player added it, so it is seen, and no longer
-- removed.
function Tabs:Add(key, at, book)
    if type(key) ~= "string" then return nil end
    -- The book first: reading it may rescan, and a rescan reconciles.
    book = BookOrDefault(book)
    local st = Tabs:Store()
    if IndexOf(st.order, key) then return nil end
    if type(Families(book)[key]) ~= "table" then return nil end
    local n = #st.order
    if type(at) ~= "number" then at = n + 1 end
    at = math.max(1, math.min(math.floor(at), n + 1))
    table.insert(st.order, at, key)
    st.removed[key] = nil
    st.seen[key] = true
    KeepIds(st, key, book)
    ClearUndo()
    return at
end

-- index it had, or nil. Recorded in `removed`, so the reconcile never brings
-- it back; Undo can, until the next change.
function Tabs:Remove(key)
    local st = Tabs:Store()
    local i = IndexOf(st.order, key)
    if not i then return nil end
    table.remove(st.order, i)
    st.removed[key] = true
    Tabs._undo = { store = st, key = key, index = i, seen = st.seen[key] }
    return i
end

-- The key a pending Undo would put back, or nil.
function Tabs:UndoKey()
    local u = Tabs._undo
    if u and u.store == Tabs:Store() then return u.key end
    return nil
end

-- The key put back at its old row, or nil: the last removal, once.
function Tabs:Undo()
    local u = Tabs._undo
    local st = Tabs:Store()
    Tabs._undo = nil
    if not u or u.store ~= st or IndexOf(st.order, u.key) then return nil end
    local at = math.max(1, math.min(u.index, #st.order + 1))
    table.insert(st.order, at, u.key)
    st.removed[u.key] = nil
    st.seen[u.key] = u.seen
    return u.key
end

-- The row it ends on, or nil: `to` is that row, clamped to the list.
function Tabs:Move(key, to)
    local st = Tabs:Store()
    local i = IndexOf(st.order, key)
    if not i or type(to) ~= "number" then return nil end
    to = math.max(1, math.min(math.floor(to), #st.order))
    if to ~= i then
        table.remove(st.order, i)
        table.insert(st.order, to, key)
    end
    ClearUndo()
    return to
end

-- "Reset to my heals": the seed again, every removal forgotten.
function Tabs:Reset(book)
    book = BookOrDefault(book)
    local st = Tabs:Store()
    st.seeded = false
    st.removed = {}
    Tabs:Seed(book)
    ClearUndo()
    return CopyList(st.order)
end

--------------------------------------------------------------------------------
-- Resolve and reconcile
--------------------------------------------------------------------------------

-- The family a key names in this book, or "stale" when the book has it no
-- longer (a respec, an alt copied by hand): the list keeps it, greyed. A
-- key the book does not know by name is looked for by the rank ids kept
-- beside it, should the name ever change.
function Tabs:Resolve(key, book)
    book = BookOrDefault(book)
    local families = Families(book)
    local fam = families[key]
    if type(fam) == "table" then return fam end
    local ids = Tabs:Store().ids[key]
    local spells = (type(book) == "table" and type(book.spells) == "table") and book.spells or {}
    if type(ids) == "table" then
        for _, id in ipairs(ids) do
            local e = spells[id]
            if type(e) == "table" and type(e.name) == "string" and type(families[e.name]) == "table" then
                return families[e.name]
            end
        end
    end
    return "stale"
end

-- The keys it appended (a list, maybe empty). Before the seed it does
-- nothing: the seed runs on first open. A key renamed in the book is
-- renamed in place; a stale key stays; the ids beside a present key follow
-- the book (a rank learned since). A newly known family of the seeded kind
-- that is neither listed nor removed is appended once, new until viewed;
-- damage and utility families never join a heal list. A list seeded empty
-- takes the seed's rule again, so the first heal learned is its kind.
function Tabs:Reconcile(book)
    local added = {}
    local st = Tabs:Store()
    if not st.seeded or type(book) ~= "table" then return added end
    local families = Families(book)

    for i, key in ipairs(st.order) do
        if type(families[key]) ~= "table" then
            local fam = Tabs:Resolve(key, book)
            if type(fam) == "table" and type(fam.key) == "string" and not IndexOf(st.order, fam.key) then
                st.order[i] = fam.key
                st.seen[fam.key] = st.seen[key]
                st.seen[key] = nil
                st.ids[key] = nil
            end
        end
    end
    for _, key in ipairs(st.order) do KeepIds(st, key, book) end

    local kind = st.kind
    if kind == nil then
        kind = Tabs:SeedList(book)
        st.kind = kind
    end
    if kind == nil then return added end

    for _, key in ipairs(Candidates(book, kind)) do
        if not IndexOf(st.order, key) and st.removed[key] ~= true then
            st.order[#st.order + 1] = key
            st.seen[key] = nil
            KeepIds(st, key, book)
            added[#added + 1] = key
        end
    end
    return added
end

MD:RegisterCallback("BOOK_CHANGED", function(book)
    if type(MD.cdb) == "table" then Tabs:Reconcile(book) end
end)
