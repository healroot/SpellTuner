#!/usr/bin/env python3
"""tools/buildcoefs.py <data.json> [--out Data/Coefs_Forever.lua]

T132 (docs/tasks/T132-forever-coefficients.md): the share of spell power each
spell rank gets on Forever, read from a talentsforever.com `data.json` export
(`spell_desc[class|spell|rank].co`) and written as a shipped data file,
Data/Coefs_Forever.lua (GENERATED, do not hand edit). talentsforever is the
PRELIMINARY source of truth until verified in game (docs/DECISIONS.md,
2026-10-04; its coefficients the base estimates on the author's word,
2026-10-23).

Recognised: a `co` string whose comma-separated parts are each
    N% of spell power (direct)     -> direct
    N% of spell power (heal)       -> heal
    N% of spell power (per tick)   -> tick
parts of the same kind added up. The site's "(direct)" is the damage part and
"(heal)" the heal part (Holy Shock: 42.9% (direct), 42.9% (heal) -- one or
the other, never both), so the two are kept apart and never summed; the
reader (Spells/Coefficients.lua) picks the slot by the kind it estimates. Any other wording skips the row and is
counted in the file header with the first few phrases -- never guessed.
A row whose text is not the beta client's (`s` other than "beta") is
skipped; so is a row the site carries a note on (`fx`, `asis`), listed.

Not run by make check: run it by hand when the export moves, and commit the
file it writes.
"""
import json
import re
import sys

PART = re.compile(r"^(?P<n>\d+(?:\.\d+)?)% of spell power \((?P<kind>direct|heal|per tick)\)$")
RANK = re.compile(r"^Rank (\d+)$")
FIRST_PHRASES = 5


def parse_co(co):
    """{ direct = x?, heal = h?, tick = y? } (fractions) or None when a part is not recognised."""
    out = {}
    for part in co.split(","):
        m = PART.match(part.strip())
        if not m:
            return None
        kind = m.group("kind")
        slot = "tick" if kind == "per tick" else kind
        out[slot] = out.get(slot, 0.0) + float(m.group("n"))
    # percent to a fraction, rounded so 28.6 is 0.286 and not 0.28600000000000003
    return {k: round(v / 100.0, 6) for k, v in out.items()}


def build(data):
    rows, unknown, notes, notbeta, noid, clash = {}, [], [], 0, [], []
    seen = {}
    for key in sorted(data.get("spell_desc", {})):
        v = data["spell_desc"][key]
        co = v.get("co")
        if not co:
            continue
        if v.get("s") != "beta":
            notbeta += 1
            continue
        if "fx" in v or "asis" in v:
            notes.append("%s (%s)" % (key, "fx" if "fx" in v else "asis"))
            continue
        parsed = parse_co(co)
        if parsed is None:
            unknown.append((key, co))
            continue
        sid = v.get("id")
        if not isinstance(sid, int) or isinstance(sid, bool) or sid <= 0:
            noid.append(key)
            continue
        bits = key.split("|")
        rank = None
        if len(bits) >= 3:
            m = RANK.match(bits[2])
            if m:
                rank = int(m.group(1))
        row = dict(parsed)
        row["name"] = bits[1] if len(bits) >= 2 else key
        row["rank"] = rank
        if sid in seen:
            old = rows.get(sid)
            if old is not None and (old.get("direct"), old.get("heal"), old.get("tick")) != (row.get("direct"), row.get("heal"), row.get("tick")):
                clash.append("%d (%s / %s)" % (sid, seen[sid], key))
                rows.pop(sid, None)
            continue
        seen[sid] = key
        rows[sid] = row
    return rows, unknown, notes, notbeta, noid, clash


def num(v):
    return ("%.6f" % v).rstrip("0").rstrip(".")


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def write(data, rows, unknown, notes, notbeta, noid, clash, out):
    lines = []
    w = lines.append
    w("local _, ST = ...")
    w("")
    w("-" * 80)
    w("-- GENERATED, do not hand edit: the share of spell power each spell rank gets")
    w("-- on Forever (T132), by tools/buildcoefs.py from a talentsforever.com data")
    w("-- export; rebuild it.")
    w("--")
    w("-- PRELIMINARY until verified in game (docs/DECISIONS.md, 2026-10-04 and")
    w("-- 2026-10-23): talentsforever.com's coefficients are the base estimates")
    w("-- until a Forever client shows otherwise; a measured share wins.")
    w("-- %s, generated %s (%s)." % (data.get("attribution", "Data from talentsforever.com (https://talentsforever.com)"),
                                    data.get("generated", "?"), data.get("license", "CC-BY-4.0")))
    w("--")
    w("-- [spell id] = { direct, heal, tick, name, rank }: direct the share of the")
    w("-- direct (damage) part, heal the share of the heal part, tick the share of")
    w("-- each tick; any may be absent. direct and heal are never summed.")
    w("--")
    w("-- Rows read: %d." % len(rows))
    w("-- Skipped, text not the beta client's (s other than beta): %d." % notbeta)
    w("-- Skipped, a note on the row (fx / asis): %d." % len(notes))
    for s in notes:
        w("--   " + s)
    phrases = []
    for _, co in unknown:
        if co not in phrases:
            phrases.append(co)
    w("-- Skipped, wording not recognised: %d row(s), %d phrase(s)%s" % (
        len(unknown), len(phrases), ", the first:" if phrases else "."))
    for p in phrases[:FIRST_PHRASES]:
        w("--   " + p)
    w("-- Skipped, no spell id: %d." % len(noid))
    for s in noid:
        w("--   " + s)
    w("-- Skipped, one id with two different rows: %d." % len(clash))
    for s in clash:
        w("--   " + s)
    w("-" * 80)
    w("")
    w("ST.CoefRules = {")
    for sid in sorted(rows):
        r = rows[sid]
        bits = []
        if "direct" in r:
            bits.append("direct = %s" % num(r["direct"]))
        if "heal" in r:
            bits.append("heal = %s" % num(r["heal"]))
        if "tick" in r:
            bits.append("tick = %s" % num(r["tick"]))
        bits.append("name = %s" % lua_str(r["name"]))
        if r["rank"] is not None:
            bits.append("rank = %d" % r["rank"])
        w("    [%d] = { %s }," % (sid, ", ".join(bits)))
    w("}")
    text = "\n".join(lines) + "\n"
    text.encode("ascii")  # raises on a byte above 127: the file must be ASCII
    with open(out, "w", newline="\n") as f:
        f.write(text)


def main(argv):
    out = "Data/Coefs_Forever.lua"
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
    rows, unknown, notes, notbeta, noid, clash = build(data)
    write(data, rows, unknown, notes, notbeta, noid, clash, out)
    print("%d row(s); skipped: %d not beta, %d noted, %d wording, %d no id, %d clash -> %s" % (
        len(rows), notbeta, len(notes), len(unknown), len(noid), len(clash), out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
