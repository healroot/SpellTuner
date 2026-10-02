-- T111 (docs/SPEC-next.md 4.2 P5, decision 8 (b)): the priest's profile on the
-- TBC line -- the rank table and the spell tooltip only. The TBC coach stays
-- the druid's (decision 8): no `coach`, `practice`, `simulate` or `advisor`,
-- and no planner.
--
-- Names and kit types only -- never a spell number. Every number comes from
-- the client's own text: Spells/Book_TBC.lua walks the spellbook, reads each
-- rank's description through Spells/Parse.lua (the TBC client prints each
-- rank's base heal at the player's level), its cost and cast from the client,
-- and Engine/RankMath.lua puts the TBC rules (coefficients by shape, the
-- downrank penalty, the priest's talents -- RankMath.CLASS_RULES, every one
-- VERIFY) on top. The names are the TBC client's own English names (checked
-- against the TBC tooltips of every rank, tools/tbcclasscheck.lua's fixture).
--
-- Not a family, so not on the rank table (each a heal the rank math has no
-- shape for: an absorb, a heal on the caster alone, a heal on a later hit, a
-- totem-like object, a next-cast modifier):
--   Power Word: Shield, Desperate Prayer, Prayer of Mending, Holy Nova,
--   Lightwell, Inner Focus, Power Infusion.
local _, MD = ...

MD.Profiles.Register("PRIEST", {
    label = "Priest",
    critSchool = 2,                -- Holy (GetSpellCritChance's school; VERIFY)
    caps = { clock = true, tooltip = true, rankTable = true },
    families = {
        LesserHeal      = { names = { "Lesser Heal" },       kit = "direct" },
        Heal            = { names = { "Heal" },              kit = "direct" },
        GreaterHeal     = { names = { "Greater Heal" },      kit = "direct" },
        FlashHeal       = { names = { "Flash Heal" },        kit = "direct" },
        -- a HoT; ticks every 3 s (VERIFY: the text gives the total and the
        -- duration only)
        Renew           = { names = { "Renew" },             kit = "hot", hot = true },
        -- the caster's party (Prayer of Healing) or the target's party
        -- (Circle of Healing), each healed by the text's amount; the table
        -- shows one target's numbers (decision 12)
        PrayerOfHealing = { names = { "Prayer of Healing" }, kit = "group" },
        CircleOfHealing = { names = { "Circle of Healing" }, kit = "group" },
        -- the target and the caster
        BindingHeal     = { names = { "Binding Heal" },      kit = "selfAndTarget" },
    },
    -- The rank table's order (the TBC book's familyOrder).
    order = { "GreaterHeal", "Heal", "FlashHeal", "LesserHeal", "Renew",
              "PrayerOfHealing", "CircleOfHealing", "BindingHeal" },
    hotSlots = { "Renew" },
    unmodelled = { "Power Word: Shield", "Desperate Prayer", "Prayer of Mending", "Holy Nova",
                   "Lightwell", "Inner Focus", "Power Infusion" },
})
