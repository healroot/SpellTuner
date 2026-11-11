#!/usr/bin/env python3
"""tools/buildranks.py <data.json> [--out Data/Ranks_Forever.lua]

Writes Data/Ranks_Forever.lua: every class's ranked spells on Forever, rank by
rank -- the spell id and the level it is learned at -- read from a
talentsforever.com `data.json` export (docs/REFERENCES-FOREVER.md: fetch it
once into tools/.cache/, never per query).

The book (Spells/Book.lua) lists a family's ranks the player has not learned
yet from this table: the id is all it takes from here, the numbers are the
client's own text for that id; the level is the fallback when the client does
not say it.

Only `Class|Name|Rank N` rows of the beta client's text (`s` "beta") with a
plain spell id are kept; everything else is counted in the file's header.

Not run by make check: run it by hand when the export moves, and commit the
file it writes.
"""
import json
import re
import sys

RANK = re.compile(r"^Rank (\d+)$")
LEARNED = re.compile(r"^Learned at level (\d+)$")
CLASS = re.compile(r"^[A-Z][a-z]+$")


def build(data):
    out, notbeta, noid, nolevel, clash, badclass = {}, 0, [], [], [], []
    for key in sorted(data.get("spell_desc", {})):
        bits = key.split("|")
        if len(bits) != 3:
            continue
        m = RANK.match(bits[2])
        if not m:
            continue
        v = data["spell_desc"][key]
        if v.get("s") != "beta":
            notbeta += 1
            continue
        cls, name, rank = bits[0], bits[1], int(m.group(1))
        if not CLASS.match(cls):
            badclass.append(key)
            continue
        sid = v.get("id")
        if not isinstance(sid, int) or isinstance(sid, bool) or sid <= 0:
            noid.append(key)
            continue
        lm = LEARNED.match(v.get("lv") or "")
        level = int(lm.group(1)) if lm else None
        if level is None:
            nolevel.append(key)
        ranks = out.setdefault(cls.upper(), {}).setdefault(name, {})
        if rank in ranks:
            clash.append(key)
            continue
        ranks[rank] = {"id": sid, "level": level, "nt": v.get("nt")}
    return out, notbeta, noid, nolevel, clash, badclass


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def write(data, rows, notbeta, noid, nolevel, clash, badclass, out):
    lines = []
    w = lines.append
    total = sum(len(r) for c in rows.values() for r in c.values())
    w("local _, ST = ...")
    w("")
    w("-" * 80)
    w("-- GENERATED, do not hand edit: every ranked spell's ranks on Forever, the")
    w("-- spell id and the learn level of each, by tools/buildranks.py from a")
    w("-- talentsforever.com data export; rebuild it.")
    w("--")
    w("-- The book (Spells/Book.lua) lists the ranks of a family the player has not")
    w("-- learned yet from here; their numbers are the client's own text for the id.")
    w("-- %s, generated %s (%s)." % (data.get("attribution", "Data from talentsforever.com (https://talentsforever.com)"),
                                    data.get("generated", "?"), data.get("license", "CC-BY-4.0")))
    w("--")
    w("-- ST.FutureRanks[CLASS][spell name][rank] = { id, level [, how] }: how 2 a")
    w("-- tome, quest or drop, 3 comes with the talent (talentsforever's nt).")
    w("--")
    w("-- Ranks read: %d." % total)
    w("-- Skipped, text not the beta client's (s other than beta): %d." % notbeta)
    w("-- Skipped, no spell id: %d." % len(noid))
    for s in noid:
        w("--   " + s)
    w("-- Skipped, a class name not recognised: %d." % len(badclass))
    for s in badclass:
        w("--   " + s)
    w("-- Skipped, the same rank twice: %d." % len(clash))
    for s in clash:
        w("--   " + s)
    w("-- Kept without a learn level: %d." % len(nolevel))
    for s in nolevel:
        w("--   " + s)
    w("-" * 80)
    w("")
    w("ST.FutureRanks = {")
    for cls in sorted(rows):
        w("    %s = {" % cls)
        for name in sorted(rows[cls]):
            parts = []
            for rank in sorted(rows[cls][name]):
                r = rows[cls][name][rank]
                bits = ["id = %d" % r["id"]]
                if r["level"] is not None:
                    bits.append("level = %d" % r["level"])
                if r["nt"] in (2, 3):
                    bits.append("how = %d" % r["nt"])
                parts.append("[%d] = { %s }" % (rank, ", ".join(bits)))
            w("        [%s] = { %s }," % (lua_str(name), ", ".join(parts)))
        w("    },")
    w("}")
    text = "\n".join(lines) + "\n"
    text.encode("ascii")  # raises on a byte above 127: the file must be ASCII
    with open(out, "w", newline="\n") as f:
        f.write(text)
    return total


def main(argv):
    out = "Data/Ranks_Forever.lua"
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
    rows, notbeta, noid, nolevel, clash, badclass = build(data)
    total = write(data, rows, notbeta, noid, nolevel, clash, badclass, out)
    print("%d rank(s) in %d class(es); skipped: %d not beta, %d no id, %d class, %d clash; %d without a level -> %s" % (
        total, len(rows), notbeta, len(noid), len(badclass), len(clash), len(nolevel), out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
