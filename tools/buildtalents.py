#!/usr/bin/env python3
"""tools/buildtalents.py <data.json> [--out Data/Talents_Forever.lua]

T129 (docs/tasks/T129-forever-talent-casts.md): the permanent cast-time
talents of every class, read from a talentsforever.com `data.json` export and
written as a shipped data file, Data/Talents_Forever.lua (GENERATED, do not
hand edit). talentsforever is the PRELIMINARY source of truth for what a
talent does until it is verified in game (docs/DECISIONS.md, 2026-10-04).

Recognised: only a rank sentence that STARTS
    Reduces the cast(ing) time of (your)? <spell list> (spell(s))? by N sec
optionally followed by "and your <spell> spell by M sec" (Bane: the second
spell gets its own rule). What follows the last amount must be nothing, ".",
or one more clause "(,) and <words>." whose words say nothing about casting
(T129 review m4): "by 0.5 sec while in Shadowform." is refused and named in
the header, never shipped as a permanent rule. Every rank's amount is read from that rank's own
sentence, never multiplied out. A cast-time talent whose sentences do not all
match is skipped and named in the file header; a spell name the class's own
spellbook (or talents, or spell texts) in the same export does not know is
dropped and named too -- never guessed.

T134 (docs/tasks/T134-forever-launch-talents.md): ST.TalentCosts (a percent off
a spell's mana cost, read only by the What if: the client's cost already carries
the talents taken), ST.TalentExpiry (a heal when a HoT runs out, Bloom) and
ST.TalentStats (a percent on Spirit, Living Spirit); the multipliers learn the
amount-healed, periodic and instant-cast sentences. Each refuses what it does not
recognise and names it, as below.

T133 (docs/tasks/T133-forever-share-factors.md): the talent MULTIPLIERS too,
ST.TalentMults[class][talent] = { scope, pctPerRank }, each rank's percent
read from its own sentence. Recognised (after the cast-time clause T129 reads,
"Reduces the cast time of ... by N sec and ", when there is one):
    increases all damage you deal by N%                      scope { kind = "damage" }
    Increases the damage done by your <School> and <School> spells by N%
                                                             scope { kind = "damage", schools }
    Increases the effect(iveness) of (all) your healing spells by N%
    Increases the amount healed by your spells by N%         scope { kind = "heal" }
    Increases the effect of your <Spell> spell by N%         scope { spells = { <Spell> } }
with nothing after the percent but ".". A talent with a sentence that starts
like one of these ("Increases all damage you deal", "Increases the damage done
by your", "Increases the effect", "Increases the amount healed") but is not
one of them -- a condition, a second effect, a school or spell the export does
not know, a rank missing -- is skipped and named in the header, never guessed.

T137 (docs/tasks/T137-forever-talent-planner.md): beside it, Data/TalentTree_Forever.lua
(GENERATED too): ST.TalentTree[class token] = { { name, talents = { { name, row, col,
max, req, icon, desc } } } }, every tree of every class as the export lays it out --
the talent planner's layout and words, never a number the model reads. desc is the
top rank's sentence, folded to ASCII.

Not run by make check: run it by hand when the export moves, and commit the
files it writes.
"""
import json
import os
import re
import sys
import unicodedata

LEAD = re.compile(
    r"^Reduces the cast(?:ing)? time of (?:your )?(?P<spells>.+?)(?: spells?)? by "
    r"(?P<n>\d+(?:\.\d+)?) secs?(?P<rest>.*)$")
AND_YOUR = re.compile(
    r"^ and your (?P<spells>.+?)(?: spells?)? by (?P<n>\d+(?:\.\d+)?) secs?(?P<rest>.*)$")
CAST_WORDS = re.compile(r"cast(?:ing)? time", re.I)
# the one tail accepted after the last amount: a further effect, not a condition
TAIL = re.compile(r"^(?:\.?|,? and (?P<clause>[^.]+)\.)$")
TAIL_CAST = re.compile(r"cast|haste|speed", re.I)


def tail_ok(rest):
    m = TAIL.match(rest)
    if not m:
        return False
    clause = m.group("clause")
    return clause is None or not TAIL_CAST.search(clause)

# T133: the multiplier sentences. NUM is a percent amount.
NUM = r"(?P<n>\d+(?:\.\d+)?)%"
CAST_CLAUSE = re.compile(
    r"^Reduces the cast(?:ing)? time of .+? by \d+(?:\.\d+)? secs? and (?P<rest>.+)$")
MULT_SHAPES = [
    ("damage", re.compile(r"^[Ii]ncreases all damage you deal by " + NUM + r"(?P<rest>.*)$")),
    ("schools", re.compile(r"^[Ii]ncreases the damage done by your (?P<a>[A-Za-z]+) and (?P<b>[A-Za-z]+) "
                           r"spells by " + NUM + r"(?P<rest>.*)$")),
    ("heal", re.compile(r"^[Ii]ncreases the effect(?:iveness)? of (?:all )?your healing spells by "
                        + NUM + r"(?P<rest>.*)$")),
    ("heal", re.compile(r"^[Ii]ncreases the amount healed by your spells by " + NUM + r"(?P<rest>.*)$")),
    ("spell", re.compile(r"^[Ii]ncreases the effect of your (?P<spell>.+?) spell by " + NUM
                         + r"(?P<rest>.*)$")),
    # T134
    ("spell", re.compile(r"^[Ii]ncreases the amount healed by your (?P<spell>.+?) spells? by " + NUM
                         + r"(?P<rest>.*)$")),
    ("periodic", re.compile(r"^[Ii]ncreases the periodic damage and healing done by your spells and "
                            r"abilities by " + NUM + r"(?P<rest>.*)$")),
    ("instant", re.compile(r"^[Ii]ncreases the damage and healing of your instant cast spells by "
                           + NUM + r"(?P<rest>.*)$")),
]
# A candidate multiplier (T133 review M1): any sentence that increases something
# whose object names damage, healing, health, an effect or an amount, by N%. A
# candidate not of a recognised shape is skipped and named, never shipped. The
# object words that are not an amount (a chance, threat, a duration, mana, armor,
# attack power, an area of effect) do not make a candidate.
MULT_VERB = re.compile(r"\b[Ii]ncreases?\b")
MULT_OBJECT = re.compile(r"\b(?:damage|heal(?:ing|ed|s)?|health|effect(?:iveness)?|amount)\b"
                         r"(?P<obj>[^%.]*?) by \d+(?:\.\d+)?%")
MULT_NOT_AMOUNT = re.compile(r"threat|duration|\b[Mm]ana\b|[Aa]rmor|[Aa]ttack [Pp]ower")


def mult_candidate(sentence):
    """True when the sentence raises damage, healing or an effect by a percent."""
    text = mult_text(sentence).replace("area of effect", "area")
    if not MULT_VERB.search(text):
        return False
    for m in MULT_OBJECT.finditer(text):
        # "critical effect chance" is a chance; "damage and critical strike
        # chance of your Moonfire" still raises the damage
        if m.group("obj").startswith(" chance") or MULT_NOT_AMOUNT.search(m.group(0)):
            continue
        return True
    return False
SCHOOLS = {"Arcane", "Fire", "Frost", "Holy", "Nature", "Shadow", "Physical"}


def mult_text(sentence):
    """The sentence past T129's cast-time clause, when it has one."""
    m = CAST_CLAUSE.match(sentence)
    if m:
        return m.group("rest")
    return sentence


def parse_mult(sentence, known):
    """(scope, pct) or (None, why) when the sentence is not a recognised multiplier."""
    text = mult_text(sentence)
    for shape, rx in MULT_SHAPES:
        m = rx.match(text)
        if not m:
            continue
        if m.group("rest") not in ("", "."):
            return None, "text after the percent not recognised"
        pct = float(m.group("n"))
        if shape == "damage":
            return {"kind": "damage"}, pct
        if shape == "heal":
            return {"kind": "heal"}, pct
        if shape == "schools":
            a, b = m.group("a"), m.group("b")
            if a not in SCHOOLS or b not in SCHOOLS:
                return None, "not a school"
            return {"kind": "damage", "schools": [a, b]}, pct
        if shape == "periodic":
            return {"periodic": True}, pct
        if shape == "instant":
            return {"instant": True}, pct
        spells = split_spells(m.group("spell"))
        for spell in spells:
            if spell not in known:
                return None, "spell %s not in the export" % spell
        return {"spells": spells}, pct
    return None, "sentence not recognised"


# T134: a percent off a spell's mana cost. The list is spell names, or the words
# "healing" / "damaging" (a kind). A second clause that names no cost is allowed
# ("and improves your chance to hit by 5%"); any other shape is skipped and named.
COST_CANDIDATE = re.compile(r"\b[Mm]ana cost\b")
COST_SHAPE = re.compile(r"^[Rr]educes the [Mm]ana cost of your (?P<list>.+?) spells? by " + NUM
                        + r"(?P<rest>.*)$")
COST_ITS = re.compile(r"^[Rr]educes the cast(?:ing)? time of your (?P<list>.+?) spells? by "
                      r"\d+(?:\.\d+)? secs? and its [Mm]ana cost by " + NUM + r"(?P<rest>.*)$")
COST_TAIL = re.compile(r"^(?: and (?P<clause>[^.]+))?\.?$")


def parse_cost(sentence, known):
    """(scope, pct) or (None, why)."""
    m = COST_SHAPE.match(sentence) or COST_ITS.match(sentence)
    if not m:
        return None, "sentence not recognised"
    tail = COST_TAIL.match(m.group("rest"))
    if not tail or (tail.group("clause") and COST_CANDIDATE.search(tail.group("clause"))):
        return None, "text after the percent not recognised"
    pct = float(m.group("n"))
    words = m.group("list")
    if words == "healing":
        return {"kind": "heal"}, pct
    if words == "damaging":
        return {"kind": "damage"}, pct
    spells = split_spells(words)
    for spell in spells:
        if spell not in known:
            return None, "spell %s not in the export" % spell
    return {"spells": spells}, pct


# T134: a heal when a spell runs out: "When your A or B spell expires due to its
# duration, the target is instantly healed for an amount equal to N% of your Spirit."
EXPIRY_CANDIDATE = re.compile(r"\bexpires? due to its duration\b")
EXPIRY_SHAPE = re.compile(r"^When your (?P<list>.+?) spell expires due to its duration, the target is "
                          r"instantly healed for an amount equal to " + NUM + r" of your Spirit\.")


def parse_expiry(sentence, known):
    m = EXPIRY_SHAPE.match(sentence)
    if not m:
        return None, "sentence not recognised"
    spells = [x.strip() for x in m.group("list").split(" or ")]
    for spell in spells:
        if spell not in known:
            return None, "spell %s not in the export" % spell
    return {"spells": spells, "stat": "Spirit"}, float(m.group("n"))


# T134: a percent on Spirit: "Increases your Spirit by N%." Only that sentence:
# a proc, a party buff or a duration is not a permanent stat and is named.
STAT_CANDIDATE = re.compile(r"\b[Ii]ncreases your (?:total )?(?:Spirit|Intellect) by\b")
# 2026-11-11: Intellect too (Heart of the Wild, Mental Strength, ...); a tail that
# only applies in a form ("In addition, while in Bear Form ...") is not the stat's
STAT_SHAPE = re.compile(r"^[Ii]ncreases your (?:total )?(?P<stat>Spirit|Intellect) by " + NUM
                        + r"\.?(?: In addition, while in [^.]*\.?)?$")


def parse_stat(sentence, known):
    m = STAT_SHAPE.match(sentence)
    if not m:
        return None, "sentence not recognised"
    return {"stat": m.group("stat")}, float(m.group("n"))


# 2026-11-11: a talent that raises the crit chance -- of every spell, of the
# healing spells, of the spells of named schools, or of named spells. Every other
# shape (a condition, a proc, a form, melee only) is named and skipped.
CRIT_CANDIDATE = re.compile(r"critical (?:strike|effect) chance|chance to get a critical strike")
CRIT_ALL = [
    re.compile(r"^Increases your critical strike chance with spells and melee attacks by " + NUM + r"\.?$"),
    re.compile(r"^Improves your chance to get a critical strike with all spells and attacks by " + NUM + r"\.?$"),
]
CRIT_SCOPED = re.compile(r"^Increases the (?:damage and )?critical (?:strike|effect) chance of your "
                         r"(?P<list>.+?) spells? by " + NUM + r"\.?$")
SCHOOLS = ("Arcane", "Fire", "Frost", "Holy", "Nature", "Shadow")


def split_list(text):
    return [x.strip() for x in re.split(r",\s*(?:and\s+)?|\s+and\s+", text) if x.strip()]


def parse_crit(sentence, known):
    for shape in CRIT_ALL:
        m = shape.match(sentence)
        if m:
            return {"all": True}, float(m.group("n"))
    m = CRIT_SCOPED.match(sentence)
    if not m:
        return None, "sentence not recognised"
    names = split_list(m.group("list"))
    if names == ["healing"]:
        return {"kind": "heal"}, float(m.group("n"))
    if all(n in SCHOOLS for n in names):
        return {"schools": names}, float(m.group("n"))
    for n in names:
        if n not in known:
            return None, "spell %s not in the export" % n
    return {"spells": names}, float(m.group("n"))


# 2026-11-11: a bigger crit -- "Increases the critical strike damage (healing)
# bonus of your Arcane and Nature (Holy) spells by N%": the bonus over a normal
# hit (x1.5 -> 0.5) grows by N%. Melee, totems and forms are named and skipped.
CRITBONUS_CANDIDATE = re.compile(r"critical strike (?:damage|healing) bonus")
CRITBONUS_SHAPE = re.compile(r"^Increases the critical strike (?P<kind>damage|healing) bonus of your "
                             r"(?P<list>.+?) spells by " + NUM + r"\.?$")


def parse_critbonus(sentence, known):
    m = CRITBONUS_SHAPE.match(sentence)
    if not m:
        return None, "sentence not recognised"
    names = split_list(m.group("list"))
    if not all(n in SCHOOLS for n in names):
        return None, "not a list of schools"
    kind = "heal" if m.group("kind") == "healing" else "damage"
    return {"kind": kind, "schools": names}, float(m.group("n"))


# 2026-11-11: +healing (or +spell damage) from a share of your Intellect:
# Natural Instinct, Mental Quickness, Champion of the Light. The clause is read
# wherever it stands in the sentence; the rest of the sentence is another effect.
STATBONUS_CANDIDATE = re.compile(r"of your Intellect")
STATBONUS_SHAPE = re.compile(r"(?:[Ii]ncreases your )?spell (?P<what>healing|damage and healing|damage) by "
                             r"(?:up to )?" + NUM + r" of your Intellect")


def parse_statbonus(sentence, known):
    m = STATBONUS_SHAPE.search(sentence)
    if not m:
        return None, "sentence not recognised"
    what = m.group("what")
    kinds = {"healing": ["heal"], "damage": ["damage"], "damage and healing": ["heal", "damage"]}[what]
    return {"stat": "Intellect", "kinds": kinds}, float(m.group("n"))


# T136: a longer spell: "Increases the duration of your A and B spells by N sec, your C
# spell by M sec, and your D spell by K sec." Every clause read, or the talent is
# named and skipped (a stun, a debuff on you, a second effect).
DUR_CANDIDATE = re.compile(r"\bduration of your\b")
DUR_LEAD = re.compile(r"^Increases the duration of your (?P<list>.+?) spells? by (?P<n>\d+(?:\.\d+)?) sec"
                      r"(?P<rest>.*)$")
DUR_MORE = re.compile(r"^,? (?:and )?your (?P<list>.+?) spells? by (?P<n>\d+(?:\.\d+)?) sec(?P<rest>.*)$")


def parse_duration(sentence, known):
    """[(spells, secs), ...] or (None, why)."""
    m = DUR_LEAD.match(sentence)
    if not m:
        return None, "sentence not recognised"
    groups = []
    while True:
        spells = split_spells(m.group("list"))
        for spell in spells:
            if spell not in known:
                return None, "spell %s not in the export" % spell
        groups.append((spells, float(m.group("n"))))
        rest = m.group("rest")
        if rest in ("", "."):
            return groups, None
        m = DUR_MORE.match(rest)
        if not m:
            return None, "text after the seconds not recognised"


def build_durations(data):
    """{ token: { rule: { talent, ranks, spells, secPerRank } } }, skipped."""
    table, skipped = {}, []
    for cls in sorted(data["talents"]):
        token = CLASS_TOKENS.get(cls)
        if token is None:
            continue
        known = known_names(data, cls)
        table.setdefault(token, {})
        for tree in data["talents"][cls]["trees"]:
            for t in tree["talents"]:
                desc = t.get("desc") or []
                if isinstance(desc, dict):
                    desc = [desc[k] for k in sorted(desc, key=lambda k: int(k))]
                if not any(DUR_CANDIDATE.search(s or "") for s in desc):
                    continue
                parsed = [parse_duration(s or "", known) for s in desc]
                bad = [why for groups, why in parsed if groups is None]
                if bad:
                    skipped.append("%s: %s (%s)" % (cls, t["name"], bad[0]))
                    continue
                if len(desc) != t.get("max"):
                    skipped.append("%s: %s (not one sentence per rank)" % (cls, t["name"]))
                    continue
                shapes = {repr([g[0] for g in groups]) for groups, _ in parsed}
                if len(shapes) != 1:
                    skipped.append("%s: %s (spells differ by rank)" % (cls, t["name"]))
                    continue
                first = parsed[0][0]
                rising = True
                for gi in range(len(first)):
                    secs = [groups[gi][1] for groups, _ in parsed]
                    if any(s <= 0 for s in secs) or any(b <= a for a, b in zip(secs, secs[1:])):
                        rising = False
                if not rising:
                    skipped.append("%s: %s (seconds not rising by rank)" % (cls, t["name"]))
                    continue
                for gi, (spells, _) in enumerate(first):
                    name = t["name"] if len(first) == 1 else "%s (%s)" % (t["name"], ", ".join(spells))
                    table[token][name] = {"talent": t["name"], "ranks": t["max"], "spells": spells,
                                          "secPerRank": [groups[gi][1] for groups, _ in parsed]}
    return table, skipped


def build_table(data, candidate, parse):
    """{ token: { talent: { scope, pctPerRank } } }, skipped: one per talent with rising percents."""
    table, skipped = {}, []
    for cls in sorted(data["talents"]):
        token = CLASS_TOKENS.get(cls)
        if token is None:
            continue
        known = known_names(data, cls)
        table.setdefault(token, {})
        for tree in data["talents"][cls]["trees"]:
            for t in tree["talents"]:
                desc = t.get("desc") or []
                if isinstance(desc, dict):
                    desc = [desc[k] for k in sorted(desc, key=lambda k: int(k))]
                if not any(candidate.search(s or "") for s in desc):
                    continue
                parsed = [parse(s or "", known) for s in desc]
                bad = [why for scope, why in parsed if scope is None]
                if bad:
                    skipped.append("%s: %s (%s)" % (cls, t["name"], bad[0]))
                    continue
                if len(desc) != t.get("max"):
                    skipped.append("%s: %s (not one sentence per rank)" % (cls, t["name"]))
                    continue
                if len({repr(sorted(scope.items())) for scope, _ in parsed}) != 1:
                    skipped.append("%s: %s (scope differs by rank)" % (cls, t["name"]))
                    continue
                pcts = [pct for _, pct in parsed]
                if any(p <= 0 for p in pcts) or any(b <= a for a, b in zip(pcts, pcts[1:])):
                    skipped.append("%s: %s (percent not rising by rank)" % (cls, t["name"]))
                    continue
                table[token][t["name"]] = {"scope": parsed[0][0], "pctPerRank": pcts}
    return table, skipped


def build_mults(data):
    mults, skipped = {}, []
    for cls in sorted(data["talents"]):
        token = CLASS_TOKENS.get(cls)
        if token is None:
            continue
        known = known_names(data, cls)
        mults.setdefault(token, {})
        for tree in data["talents"][cls]["trees"]:
            for t in tree["talents"]:
                desc = t.get("desc") or []
                if isinstance(desc, dict):
                    desc = [desc[k] for k in sorted(desc, key=lambda k: int(k))]
                if not any(mult_candidate(s or "") for s in desc):
                    continue
                parsed = [parse_mult(s or "", known) for s in desc]
                bad = [why for scope, why in parsed if scope is None]
                if bad:
                    skipped.append("%s: %s (%s)" % (cls, t["name"], bad[0]))
                    continue
                if len(desc) != t.get("max"):
                    skipped.append("%s: %s (not one sentence per rank)" % (cls, t["name"]))
                    continue
                scopes = {repr(sorted(scope.items())) for scope, _ in parsed}
                if len(scopes) != 1:
                    skipped.append("%s: %s (scope differs by rank)" % (cls, t["name"]))
                    continue
                pcts = [pct for _, pct in parsed]
                if any(p <= 0 for p in pcts) or any(b <= a for a, b in zip(pcts, pcts[1:])):
                    skipped.append("%s: %s (percent not rising by rank)" % (cls, t["name"]))
                    continue
                mults[token][t["name"]] = {"scope": parsed[0][0], "pctPerRank": pcts}
    return mults, skipped


CLASS_TOKENS = {
    "Warrior": "WARRIOR", "Paladin": "PALADIN", "Hunter": "HUNTER", "Rogue": "ROGUE",
    "Priest": "PRIEST", "Shaman": "SHAMAN", "Mage": "MAGE", "Warlock": "WARLOCK",
    "Druid": "DRUID",
}


def split_spells(text):
    text = text.replace(", and ", ", ").replace(" and ", ", ")
    return [s.strip() for s in text.split(",") if s.strip()]


def parse_sentence(sentence):
    """[(spells, amount), ...] or None when the sentence is not recognised."""
    m = LEAD.match(sentence)
    if not m:
        return None
    parts = [(split_spells(m.group("spells")), float(m.group("n")))]
    rest = m.group("rest")
    m2 = AND_YOUR.match(rest)
    if m2:
        parts.append((split_spells(m2.group("spells")), float(m2.group("n"))))
        rest = m2.group("rest")
    if not tail_ok(rest):
        return None
    return parts


def known_names(data, cls):
    names = set()
    book = data.get("spellbooks", {}).get(cls) or {}
    for row in book.get("general", []) or []:
        names.add(row[0])
    for tab in book.get("tabs", []) or []:
        for row in tab.get("spells", []) or []:
            names.add(row[0])
    for key in data.get("spell_desc", {}) or {}:
        bits = key.split("|")
        if len(bits) >= 2 and bits[0] == cls:
            names.add(bits[1])
    for tree in data["talents"][cls]["trees"]:
        for t in tree["talents"]:
            names.add(t["name"])
    return names


def num(v):
    s = ("%.2f" % v).rstrip("0").rstrip(".")
    return s


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def build(data):
    rules, skipped, dropped = {}, [], []
    for cls in sorted(data["talents"]):
        token = CLASS_TOKENS.get(cls)
        if token is None:
            skipped.append("%s (unknown class)" % cls)
            continue
        known = known_names(data, cls)
        rules.setdefault(token, {})
        for tree in data["talents"][cls]["trees"]:
            for t in tree["talents"]:
                desc = t.get("desc") or []
                if isinstance(desc, dict):
                    desc = [desc[k] for k in sorted(desc, key=lambda k: int(k))]
                if not any(CAST_WORDS.search(s or "") for s in desc):
                    continue
                parsed = [parse_sentence(s or "") for s in desc]
                if not desc or any(p is None for p in parsed) or len(desc) != t.get("max"):
                    # a sentence of the recognised lead whose tail is refused is named as such
                    tails = [s for s, p in zip(desc, parsed) if p is None and LEAD.match(s or "")]
                    note = " (text after the amount not recognised)" if tails else ""
                    skipped.append("%s: %s%s" % (cls, t["name"], note))
                    continue
                shapes = {tuple(tuple(sp) for sp, _ in p) for p in parsed}
                if len(shapes) != 1:
                    skipped.append("%s: %s (spells differ by rank)" % (cls, t["name"]))
                    continue
                for i, (spells, _) in enumerate(parsed[0]):
                    keep = [s for s in spells if s in known]
                    for s in spells:
                        if s not in known:
                            dropped.append("%s: %s (%s)" % (cls, t["name"], s))
                    if not keep:
                        continue
                    amounts = [p[i][1] for p in parsed]
                    name = t["name"] if i == 0 else "%s (%s)" % (t["name"], ", ".join(keep))
                    rules[token][name] = {"talent": t["name"], "ranks": t["max"], "spells": keep,
                                          "castPerRank": amounts}
    return rules, skipped, dropped


def lua_scope(scope):
    parts = []
    if scope.get("all"):
        parts.append("all = true")
    if "kind" in scope:
        parts.append("kind = %s" % lua_str(scope["kind"]))
    if "kinds" in scope:
        parts.append("kinds = { %s }" % ", ".join(lua_str(x) for x in scope["kinds"]))
    if "schools" in scope:
        parts.append("schools = { %s }" % ", ".join(lua_str(x) for x in scope["schools"]))
    if "spells" in scope:
        parts.append("spells = { %s }" % ", ".join(lua_str(x) for x in scope["spells"]))
    if scope.get("periodic"):
        parts.append("periodic = true")
    if scope.get("instant"):
        parts.append("instant = true")
    if "stat" in scope:
        parts.append("stat = %s" % lua_str(scope["stat"]))
    return "{ " + ", ".join(parts) + " }"


def write(data, rules, skipped, dropped, out, mults=None, mskipped=None, extra=None, durations=None):
    durations, dskipped = durations or ({}, [])
    mults = mults or {}
    mskipped = mskipped or []
    extra = extra or []
    lines = []
    w = lines.append
    w("local _, ST = ...")
    w("")
    w("-" * 80)
    w("-- The permanent cast-time talents, per class (T129). GENERATED by")
    w("-- tools/buildtalents.py from a talentsforever.com data export -- do not hand")
    w("-- edit; rebuild it.")
    w("--")
    w("-- PRELIMINARY until verified in game (docs/DECISIONS.md, 2026-10-04):")
    w("-- talentsforever.com is the source of truth for what a talent does until a")
    w("-- Forever client shows otherwise.")
    w("-- %s, generated %s (%s)." % (data.get("attribution", "Data from talentsforever.com (https://talentsforever.com)"),
                                    data.get("generated", "?"), data.get("license", "CC-BY-4.0")))
    w("--")
    w("-- [class token][rule] = { talent, ranks, spells, castPerRank }: castPerRank[r] is the")
    w("-- seconds rank r takes off each named spell's cast, read from rank r's own")
    w("-- sentence. Talents are matched by NAME (the export carries no spell ids).")
    w("-- A rule other than the talent's first part is named \"<talent> (<spells>)\".")
    w("--")
    w("-- Cast-time talents skipped (a sentence not of the recognised shape --")
    w("-- procs, charges, percentages, other words):")
    for s in sorted(skipped):
        w("--   " + s)
    if not skipped:
        w("--   none")
    w("-- Spell names dropped (not in the class's spellbook in the export):")
    for s in sorted(dropped):
        w("--   " + s)
    if not dropped:
        w("--   none")
    w("--")
    w("-- T133: ST.TalentMults[class token][talent] = { scope, pctPerRank }: rank r")
    w("-- multiplies what the scope names (kind \"damage\" / \"heal\", schools, spells")
    w("-- by name) by 1 + pctPerRank[r] / 100, read from rank r's own sentence.")
    w("-- %d multiplier talent(s) skipped (a sentence that raises damage, healing, an" % len(mskipped))
    w("-- effect or an amount by a percent but is not of a recognised shape --")
    w("-- conditions, second effects, other words; named, never guessed):")
    for s in sorted(mskipped):
        w("--   " + s)
    if not mskipped:
        w("--   none")
    w("--")
    w("-- T134: ST.TalentCosts: rank r takes pctPerRank[r] percent off the mana cost of")
    w("-- what the scope names (read by the What if only: the client's cost already")
    w("-- carries the talents taken). ST.TalentExpiry: when a named spell runs its whole")
    w("-- duration the target is healed for pctPerRank[r] percent of scope.stat.")
    w("-- ST.TalentStats: rank r raises scope.stat by pctPerRank[r] percent.")
    w("-- ST.TalentCrit (2026-11-11): rank r adds pctPerRank[r] points of crit chance to")
    w("-- what the scope names (all: every spell, kind heal, schools, spells by name).")
    w("-- ST.TalentCritBonus: rank r makes a crit's bonus over a hit pctPerRank[r] percent")
    w("-- bigger for the scope's kind and schools. ST.TalentStatBonus: rank r adds")
    w("-- pctPerRank[r] percent of scope.stat to the bonus of each of scope.kinds.")
    w("-- T136: ST.TalentDurations[class token][rule] = { talent, ranks, spells, secPerRank }:")
    w("-- rank r makes each named spell last secPerRank[r] seconds longer (read by the What")
    w("-- if only: the client's text already carries the talents taken). Skipped:")
    for s in sorted(dskipped):
        w("--   " + s)
    if not dskipped:
        w("--   none")
    for global_name, _, tskipped in extra:
        w("-- %s skipped (named, never guessed):" % global_name)
        for s in sorted(tskipped):
            w("--   " + s)
        if not tskipped:
            w("--   none")
    w("-" * 80)
    w("")
    w("ST.TalentRules = {")
    for token in sorted(rules):
        w("    %s = {" % token)
        for name in sorted(rules[token]):
            r = rules[token][name]
            w("        [%s] = {" % lua_str(name))
            w("            talent = %s," % lua_str(r["talent"]))
            w("            ranks = %d," % r["ranks"])
            w("            spells = { %s }," % ", ".join(lua_str(s) for s in r["spells"]))
            w("            castPerRank = { %s }," % ", ".join(num(v) for v in r["castPerRank"]))
            w("        },")
        w("    },")
    w("}")
    w("")
    w("ST.TalentMults = {")
    for token in sorted(mults):
        w("    %s = {" % token)
        for name in sorted(mults[token]):
            m = mults[token][name]
            w("        [%s] = {" % lua_str(name))
            w("            scope = %s," % lua_scope(m["scope"]))
            w("            pctPerRank = { %s }," % ", ".join(num(v) for v in m["pctPerRank"]))
            w("        },")
        w("    },")
    w("}")
    for global_name, table, _ in extra:
        w("")
        w("ST.%s = {" % global_name)
        for token in sorted(table):
            w("    %s = {" % token)
            for name in sorted(table[token]):
                m = table[token][name]
                w("        [%s] = {" % lua_str(name))
                w("            scope = %s," % lua_scope(m["scope"]))
                w("            pctPerRank = { %s }," % ", ".join(num(v) for v in m["pctPerRank"]))
                w("        },")
            w("    },")
        w("}")
    w("")
    w("ST.TalentDurations = {")
    for token in sorted(durations):
        w("    %s = {" % token)
        for name in sorted(durations[token]):
            r = durations[token][name]
            w("        [%s] = {" % lua_str(name))
            w("            talent = %s," % lua_str(r["talent"]))
            w("            ranks = %d," % r["ranks"])
            w("            spells = { %s }," % ", ".join(lua_str(s) for s in r["spells"]))
            w("            secPerRank = { %s }," % ", ".join(num(v) for v in r["secPerRank"]))
            w("        },")
        w("    },")
    w("}")
    text = "\n".join(lines) + "\n"
    text.encode("ascii")  # raises on a byte above 127: the file must be ASCII
    with open(out, "w", newline="\n") as f:
        f.write(text)


ASCII_FOLD = {"\u2018": "'", "\u2019": "'", "\u201c": '"', "\u201d": '"', "\u2013": "-", "\u2014": "-",
              "\u2026": "...", "\u00a0": " "}


def ascii_text(s):
    for a, b in ASCII_FOLD.items():
        s = s.replace(a, b)
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode("ascii")
    return re.sub(r"\s+", " ", s).strip()


def write_tree(data, out):
    """T137: every class's trees, as laid out, for the planner."""
    lines = []
    w = lines.append
    w("local _, ST = ...")
    w("")
    w("-" * 80)
    w("-- The talent trees, per class (T137). GENERATED by tools/buildtalents.py from a")
    w("-- talentsforever.com data export -- do not hand edit; rebuild it.")
    w("-- %s, generated %s (%s)." % (data.get("attribution", "Data from talentsforever.com (https://talentsforever.com)"),
                                    data.get("generated", "?"), data.get("license", "CC-BY-4.0")))
    w("--")
    w("-- ST.TalentTree[class token] = { { name, talents = { { name, row, col, max, req, icon,")
    w("-- desc } } } }: the layout the talent planner draws (UI/TalentPlanner.lua) and its")
    w("-- words; desc is the top rank's sentence. Nothing here is a number the model reads:")
    w("-- what a talent does to a spell is Data/Talents_Forever.lua's. PRELIMINARY until")
    w("-- verified in game.")
    w("-" * 80)
    w("")
    w("ST.TalentTree = {")
    for cls in sorted(data["talents"]):
        token = CLASS_TOKENS.get(cls)
        if token is None:
            continue
        w("    %s = {" % token)
        for tree in data["talents"][cls]["trees"]:
            w("        { name = %s, talents = {" % lua_str(ascii_text(tree["name"])))
            for t in sorted(tree["talents"], key=lambda x: (x["row"], x["col"])):
                desc = t.get("desc") or []
                if isinstance(desc, dict):
                    desc = [desc[k] for k in sorted(desc, key=lambda k: int(k))]
                parts = ["name = %s" % lua_str(ascii_text(t["name"])), "row = %d" % t["row"], "col = %d" % t["col"],
                         "max = %d" % t["max"]]
                if t.get("req"):
                    parts.append("req = %s" % lua_str(ascii_text(t["req"])))
                if t.get("icon"):
                    parts.append("icon = %s" % lua_str(ascii_text(t["icon"])))
                if desc:
                    parts.append("desc = %s" % lua_str(ascii_text(desc[-1] or "")))
                w("            { %s }," % ", ".join(parts))
            w("        } },")
        w("    },")
    w("}")
    text = "\n".join(lines) + "\n"
    text.encode("ascii")
    with open(out, "w", newline="\n") as f:
        f.write(text)


def main(argv):
    out = "Data/Talents_Forever.lua"
    args = []
    i = 1
    while i < len(argv):
        if argv[i] == "--out":
            out = argv[i + 1]
            i += 2
            continue
        args.append(argv[i])
        i += 1
    if len(args) != 1:
        print(__doc__)
        return 2
    with open(args[0], encoding="utf-8") as f:
        data = json.load(f)
    rules, skipped, dropped = build(data)
    mults, mskipped = build_mults(data)
    costs, cskipped = build_table(data, COST_CANDIDATE, parse_cost)
    expiry, eskipped = build_table(data, EXPIRY_CANDIDATE, parse_expiry)
    stats, sskipped = build_table(data, STAT_CANDIDATE, parse_stat)
    crits, crskipped = build_table(data, CRIT_CANDIDATE, parse_crit)
    critbonus, cbskipped = build_table(data, CRITBONUS_CANDIDATE, parse_critbonus)
    statbonus, sbskipped = build_table(data, STATBONUS_CANDIDATE, parse_statbonus)
    durations, dskipped = build_durations(data)
    write(data, rules, skipped, dropped, out, mults, mskipped, [
        ("TalentCosts", costs, cskipped),
        ("TalentExpiry", expiry, eskipped),
        ("TalentStats", stats, sskipped),
        ("TalentCrit", crits, crskipped),
        ("TalentCritBonus", critbonus, cbskipped),
        ("TalentStatBonus", statbonus, sbskipped),
    ], (durations, dskipped))
    tree_out = os.path.join(os.path.dirname(out) or ".", "TalentTree_Forever.lua")
    write_tree(data, tree_out)
    n = sum(len(v) for v in rules.values())
    nm = sum(len(v) for v in mults.values())
    print("%d rule(s), %d skipped, %d name(s) dropped; %d multiplier(s), %d skipped; "
          "%d cost(s), %d skipped; %d expiry, %d skipped; %d stat(s), %d skipped; "
          "%d duration(s), %d skipped -> %s"
          % (n, len(skipped), len(dropped), nm, len(mskipped),
             sum(len(v) for v in costs.values()), len(cskipped),
             sum(len(v) for v in expiry.values()), len(eskipped),
             sum(len(v) for v in stats.values()), len(sskipped),
             sum(len(v) for v in durations.values()), len(dskipped), out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
