-- Spells/WhatIf_TBC.lua (T122, docs/tasks/T122-what-if.md): the What if's
-- provider on TBC. TBC TOC only, after Engine/DamageMath.lua (the book and
-- RankMath it calls at run time are loaded by then).
--
-- MD.sim is the one table RankMath:Context reads (without opts.live), and
-- THIS FILE IS ITS ONLY WRITER (tools/whatifcheck.lua's source scan): every
-- WHATIF_CHANGED rewrites it from MD.WhatIf's values -- heal, crit, mana,
-- casting, base (mp5, as typed), tree (Form: true for Tree of Life, false
-- for Caster, absent for Live), moonglow (0-3) -- and Clear leaves it empty.
-- It stays set while the what-if is active, so UI/Advisor.lua's "simulation
-- active: not real gear" guard keeps working.
--
-- The what-if book is MD.Book:Get({ whatIf = true }) (Spells/Book_Model.lua,
-- T118's door): RankMath:Compute() under MD.sim, built for the call, never
-- cached, never firing BOOK_CHANGED. The live book (Get()) never reads it.
--
-- Form and Moonglow price costs from SD:StaticCost (RankMath's costCtx), not
-- the client: the RANKS note says so. The class rows (Form, Moonglow) are the
-- druid's book only -- the rank table granted and no class book
-- (RankMath:IsClassBook) -- never an isDruid read.
local _, MD = ...

local WI = MD.WhatIf
if not WI then return end

local KEYS = { "heal", "crit", "mana", "casting", "base", "moonglow" }

local function Sync()
    if type(MD.sim) ~= "table" then MD.sim = {} end
    local sim = MD.sim
    for k in pairs(sim) do sim[k] = nil end
    for _, k in ipairs(KEYS) do
        local v = WI:Get(k)
        if v ~= nil then sim[k] = v end
    end
    local form = WI:Get("form")
    if form == "tree" then sim.tree = true elseif form == "caster" then sim.tree = false end
end

local function DruidBook()
    local RM = MD.RankMath
    if not (RM and MD.ClassProfile and MD.ClassProfile.Can) then return false end
    if not MD.ClassProfile:Can("rankTable") then return false end
    if RM.IsClassBook and RM:IsClassBook() then return false end
    return true
end

local CLASS_ROWS = {
    { key = "form", label = "Form", kind = "choice",
      choices = { { id = "live", text = "Live" }, { id = "caster", text = "Caster" },
                  { id = "tree", text = "Tree of Life" } } },
    { key = "moonglow", label = "Moonglow", min = 0, max = 3, note = "0-3" },
}

local provider = {}

function provider.Live()
    local RM = MD.RankMath
    local out = {}
    if RM and RM.Context then
        local ok, ctx = pcall(RM.Context, RM, { live = true })
        local live = ok and type(ctx) == "table" and ctx.live
        if type(live) == "table" then
            out.heal, out.crit, out.casting, out.base = live.heal, live.crit, live.casting, live.base
        end
    end
    local pool = MD.Book and MD.Book.Pool and MD.Book:Pool()
    if type(pool) == "table" then out.mana = pool.max end
    if MD.InTreeForm then out.form = MD:InTreeForm() and "tree" or "caster" end
    if MD.TalentRank then out.moonglow = MD:TalentRank("Moonglow") end
    return out
end

function provider.Book()
    Sync()
    return MD.Book:Get({ whatIf = true })
end

function provider.classRows()
    if DruidBook() then return CLASS_ROWS end
    return nil
end

function provider.classTitle()
    if not DruidBook() then return nil end
    return (MD.player and MD.player.class) or "DRUID"
end

provider.classNote = nil

function provider.ranksNote()
    if WI:Get("form") ~= nil or WI:Get("moonglow") ~= nil then return "costs from the static table" end
    return nil
end

WI.provider = provider

MD:RegisterCallback("WHATIF_CHANGED", Sync)
