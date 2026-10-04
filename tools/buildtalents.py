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
spell gets its own rule). Every rank's amount is read from that rank's own
sentence, never multiplied out. A cast-time talent whose sentences do not all
match is skipped and named in the file header; a spell name the class's own
spellbook (or talents, or spell texts) in the same export does not know is
dropped and named too -- never guessed.

Not run by make check: run it by hand when the export moves, and commit the
file it writes.
"""
import json
import re
import sys

LEAD = re.compile(
    r"^Reduces the cast(?:ing)? time of (?:your )?(?P<spells>.+?)(?: spells?)? by "
    r"(?P<n>\d+(?:\.\d+)?) secs?(?P<rest>.*)$")
AND_YOUR = re.compile(
    r"^ and your (?P<spells>.+?)(?: spells?)? by (?P<n>\d+(?:\.\d+)?) secs?(?P<rest>.*)$")
CAST_WORDS = re.compile(r"cast(?:ing)? time", re.I)

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
                    skipped.append("%s: %s" % (cls, t["name"]))
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


def write(data, rules, skipped, dropped, out):
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
    text = "\n".join(lines) + "\n"
    text.encode("ascii")  # raises on a byte above 127: the file must be ASCII
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
    write(data, rules, skipped, dropped, out)
    n = sum(len(v) for v in rules.values())
    print("%d rule(s), %d skipped, %d name(s) dropped -> %s" % (n, len(skipped), len(dropped), out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
