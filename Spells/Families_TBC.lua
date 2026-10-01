-- T84 (C5 of docs/PLAN-refactor-ux.md, section 7.1; mockup M4 layout B and
-- M6): the TBC druid's heal families as the book Spells/Tabs.lua reads, so
-- the spell rail and its list model are one structure on both lines.
--
-- The families are the ones the TBC rank table has (Data/SpellData.lua's
-- familyOrder, the excluded Tranquility and Swiftmend left out), in Book's
-- family shape (Spells/Book.lua): a `key` (SpellData's family id,
-- "HealingTouch"), `name` (its label, "Healing Touch"), `kind = "heal"`,
-- `ids` (every rank's spell id, lowest rank first) and `ranks` -- one entry
-- per rank with `id`, `rank`, `level`, `known` (SpellData's known-rank
-- index), `cost.amount` (the static base cost) and `icon` -- plus `maxKnown`
-- (the highest known entry). `spells` maps each id back to its family key,
-- which is what Tabs:Resolve looks a renamed key up by.
--
-- It installs itself as Tabs.source and is rebuilt on SPELLS_REBUILT, which
-- then runs Tabs:Reconcile -- the job BOOK_CHANGED does on Forever: a family
-- trained since is appended with the new dot (decision 2), a removed one
-- stays removed. Pure but for the icon, read through MD.API.SpellTexture.
-- TBC TOC only, after Spells/Tabs.lua.
local _, MD = ...

local FT = {}
MD.FamiliesTBC = FT

FT._book = nil

local function Icon(id)
    local read = MD.API and MD.API.SpellTexture
    if type(read) ~= "function" then return nil end
    local tex = read(id)
    if type(tex) == "string" or type(tex) == "number" then return tex end
    return nil
end

-- A fresh book from Data/SpellData.lua: { families, order, spells }.
function FT:Build()
    local SD = MD.SpellData
    local book = { families = {}, order = {}, spells = {} }
    -- the table is the druid's: another class lists nothing (and its rail
    -- holds Overview only)
    if not SD or not (MD.player and MD.player.isDruid) then return book end
    local knownSet = SD.knownSet or {}
    for _, key in ipairs(SD.familyOrder or {}) do
        local info = SD.families and SD.families[key]
        local all = SD.all and SD.all[key]
        if info and not info.exclude and all and #all > 0 then
            local fam = { key = key, name = info.label or key, kind = "heal", ids = {}, ranks = {} }
            for i, id in ipairs(all) do
                local s = SD.spells[id] or {}
                local e = { id = id, name = key, rank = s.rank, level = s.level, known = knownSet[id] == true,
                            cost = { amount = s.cost }, icon = Icon(id) }
                fam.ids[i] = id
                fam.ranks[i] = e
                if e.known then fam.maxKnown = e end
                book.spells[id] = e
            end
            book.families[key] = fam
            book.order[#book.order + 1] = key
        end
    end
    return book
end

-- The book, built on first use.
function FT:Get()
    if not FT._book then FT._book = FT:Build() end
    return FT._book
end

-- The seam's TBC source (Spells/Tabs.lua).
function FT.Source()
    return FT:Get()
end

if MD.Tabs then MD.Tabs.source = FT.Source end

-- The known-rank index rebuilt (login, a rank trained): the families follow,
-- and the list reconciles against them. A family appended here is new (the
-- dot) until its view is opened.
MD:RegisterCallback("SPELLS_REBUILT", function()
    FT._book = FT:Build()
    if MD.Tabs and type(MD.cdb) == "table" then MD.Tabs:Reconcile(FT._book) end
end)
