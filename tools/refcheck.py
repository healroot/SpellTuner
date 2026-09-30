#!/usr/bin/env python3
"""tools/refcheck.py -- the client's spells against talentsforever.com's data.json, offline.

Compares a probe report's spell dump (or a T10 dashboard export, same block format) with
talentsforever.com's data.json: same ranks, same ids, same learn levels, same costs, same cast
lines, and the numbers in the description. Prints every disagreement with both values and the
reference record's provenance (s, src, fx, asis). Nothing here reaches the addon; see
docs/tasks/T8b-refcheck.md.

    python3 tools/refcheck.py --fetch [--refresh]
    python3 tools/refcheck.py <file> [--data PATH] [--class Druid] [--level 9]
    python3 tools/refcheck.py --selftest
"""
import argparse
import json
import os
import re
import sys
import tempfile
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE_DIR = os.path.join(HERE, ".cache")
CACHE_FILE = os.path.join(CACHE_DIR, "talentsforever.json")
DATA_URL = "https://talentsforever.com/data.json"
ATTRIBUTION = "Data from talentsforever.com (https://talentsforever.com)"
USER_AGENT = "SpellTuner-refcheck (one fetch, cached)"
FIXTURE_DIR = os.path.join(HERE, "data", "refcheck-fixture")

CHAR_RE = re.compile(r"^character:\s+.*\s+(\S+)\s+level\s+(\d+)\s*$")
SPELL_RE = re.compile(r"^spell (\d+)\s*$")
FIELD_RES = {
    "name": re.compile(r"^  name: (.*)$"),
    "rank": re.compile(r"^  rank: ?(.*)$"),
    "desc": re.compile(r"^  desc: (.*)$"),
    "cost": re.compile(r"^  cost: (.*)$"),
    "cast": re.compile(r"^  cast: (.*)$"),
}
LEVEL_RE = re.compile(r"^  level: (\d+)\s*$")


def ascii_escape(s):
    # the addon-wide rule is ASCII-only rendered strings; a reference string is free-form
    # JSON text and can carry anything, so everything outside printable ASCII is \u-escaped
    # rather than passed through.
    if s is None:
        return ""
    out = []
    for ch in s:
        code = ord(ch)
        if 32 <= code <= 126:
            out.append(ch)
        else:
            out.append("\\u%04x" % code)
    return "".join(out)


CLIENT_ESC_RE = re.compile(r"\\\\|\\(\d{3})|\|\|")


def unescape_client(s):
    # Review B26 (T50): undoes the probe's Esc (Client/Probe.lua, and the Spells pane's copy
    # of it) in one left-to-right pass -- "\\" is a literal backslash, "\ddd" one byte, "||" a
    # pipe -- so a curly quote is one character again before its key is looked up and its
    # numbers counted (its escape's 226, 128, 156 are not description numbers). The bytes are
    # the client's UTF-8. Printed text goes back through ascii_escape.
    out = bytearray()
    pos = 0
    for m in CLIENT_ESC_RE.finditer(s):
        out += s[pos:m.start()].encode("utf-8")
        tok = m.group(0)
        if tok == "\\\\":
            out += b"\\"
        elif tok == "||":
            out += b"|"
        else:
            code = int(m.group(1))
            if code > 255:
                out += tok.encode("utf-8")
            else:
                out.append(code)
        pos = m.end()
    out += s[pos:].encode("utf-8")
    return out.decode("utf-8", errors="replace")


def numbers_in(s):
    # "numbers are compared position by position after removing thousands commas"
    return re.findall(r"\d+", s.replace(",", ""))


def parse_dump(path):
    """Return (class, level, [spell records in first-seen order]).

    A file may hold several reports; the last block per spell id wins (values are
    overwritten in place) but the record keeps the position of its first appearance, and
    the last character: line anywhere in the file gives the class and level.
    """
    char_class = None
    char_level = None
    order = []
    spells = {}
    cur = None
    with open(path, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()
    for line in lines:
        m = CHAR_RE.match(line)
        if m:
            char_class = m.group(1).capitalize()
            char_level = int(m.group(2))
            continue
        m = SPELL_RE.match(line)
        if m:
            sid = int(m.group(1))
            if sid not in spells:
                order.append(sid)
                spells[sid] = {"id": sid}
            cur = spells[sid]
            continue
        if cur is not None:
            matched = False
            for field, rx in FIELD_RES.items():
                m = rx.match(line)
                if m:
                    cur[field] = unescape_client(m.group(1))
                    matched = True
                    break
            if matched:
                continue
            m = LEVEL_RE.match(line)
            if m:
                cur["level"] = int(m.group(1))
                continue
        # anything else that is not an indented field line ends the current block
        # (a blank line, or an unindented section header such as "== spells ...")
        if line.strip() and not line.startswith("  "):
            cur = None
    return char_class, char_level, [spells[sid] for sid in order]


def load_reference(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def parse_learn_level(lv):
    if not lv:
        return None
    m = re.search(r"(\d+)", lv)
    return int(m.group(1)) if m else None


def compare_spell(rec, data, klass):
    sid = rec["id"]
    name = rec.get("name", "")
    rank = rec.get("rank", "")
    key = "%s|%s|%s" % (klass, name, rank)
    ref = data.get("spell_desc", {}).get(key)
    header_main = ("%s %s %s" % (sid, ascii_escape(name), ascii_escape(rank))).rstrip()

    if ref is None:
        return "missing", "%s  [not in the reference: %s]" % (header_main, ascii_escape(key))

    lines = []

    ref_id = ref.get("id")
    if ref_id is not None and ref_id != sid:
        lines.append("  id: client %d, reference %d" % (sid, ref_id))

    client_desc = rec.get("desc", "")
    ref_desc = ref.get("d") or ""
    client_nums = numbers_in(client_desc)
    ref_nums = numbers_in(ref_desc)
    if len(client_nums) != len(ref_nums):
        lines.append("  desc numbers: client %d, reference %d" % (len(client_nums), len(ref_nums)))
        lines.append('  desc: client "%s"' % ascii_escape(client_desc))
        lines.append('  desc: reference "%s"' % ascii_escape(ref_desc))
    else:
        num_lines = []
        for i, (c, r) in enumerate(zip(client_nums, ref_nums), 1):
            if c != r:
                num_lines.append("  desc number %d: client %s, reference %s" % (i, c, r))
        if num_lines:
            lines.extend(num_lines)
            lines.append('  desc: client "%s"' % ascii_escape(client_desc))
            lines.append('  desc: reference "%s"' % ascii_escape(ref_desc))

    if "level" in rec:
        ref_learned = parse_learn_level(ref.get("lv"))
        if ref_learned is not None and ref_learned != rec["level"]:
            lines.append("  learned: client %d, reference %d" % (rec["level"], ref_learned))

    tooltip_lines = ref.get("l") or []

    if "cost" in rec:
        ref_cost = tooltip_lines[0][0] if len(tooltip_lines) > 0 and len(tooltip_lines[0]) > 0 else None
        if ref_cost is not None and ref_cost != rec["cost"]:
            lines.append("  cost: client %s, reference %s" % (ascii_escape(rec["cost"]), ascii_escape(ref_cost)))

    if "cast" in rec:
        ref_cast = tooltip_lines[1][0] if len(tooltip_lines) > 1 and len(tooltip_lines[1]) > 0 else None
        if ref_cast is not None and ref_cast != rec["cast"]:
            lines.append("  cast: client %s, reference %s" % (ascii_escape(rec["cast"]), ascii_escape(ref_cast)))

    if not lines:
        return "agree", None

    fx = ref.get("fx")
    asis = ref.get("asis")
    if fx or asis:
        parts = []
        if fx:
            parts.append("fx: %s" % ascii_escape(fx))
        if asis:
            parts.append("asis: %s" % ascii_escape(asis))
        lines.append("  " + "   ".join(parts))

    header = "%s  [%s, s=%s, src=%s]" % (
        header_main,
        ascii_escape(key),
        ascii_escape(ref.get("s")),
        ascii_escape(ref.get("src")),
    )
    return "disagree", "\n".join([header] + lines)


def run_compare(dump_path, data, klass_override, level_override):
    klass, level, spells = parse_dump(dump_path)
    if klass_override:
        klass = klass_override.capitalize()
    if level_override is not None:
        level = level_override

    out = ["%s -- generated %s, CC BY 4.0" % (ATTRIBUTION, data.get("generated"))]
    out.append(
        "client: %s level %s; reference: level 60, no gear -- numbers are expected to differ below 60"
        % (klass, level)
    )

    agree = disagree = missing = 0
    for rec in spells:
        status, block = compare_spell(rec, data, klass)
        if status == "agree":
            agree += 1
        elif status == "disagree":
            disagree += 1
            out.append(block)
        else:
            missing += 1
            out.append(block)

    out.append(
        "refcheck: %d spells, %d agree, %d disagree, %d not in the reference"
        % (len(spells), agree, disagree, missing)
    )
    return "\n".join(out) + "\n"


def do_fetch(refresh):
    os.makedirs(CACHE_DIR, exist_ok=True)
    if os.path.exists(CACHE_FILE) and not refresh:
        print(CACHE_FILE)
        return 0
    req = urllib.request.Request(DATA_URL, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=30) as resp:
        body = resp.read()
    with open(CACHE_FILE, "wb") as f:
        f.write(body)
    data = json.loads(body)
    print(ATTRIBUTION)
    print("%d bytes" % len(body))
    print("generated: %s" % data.get("generated"))
    return 0


# Review B26 (T50): a client name and description with curly quotes, as the probe's Esc writes
# them (three "\ddd" escapes per character) and with an escaped literal backslash ("\\"),
# against the reference's own text. Before the escapes were undone the name missed its key and
# the description counted 226, 128, 153 ... as numbers.
ESCAPED_DUMP = "\n".join([
    "character: Tester Realm DRUID level 60",
    "== spells",
    "spell 700",
    r"  name: Nature\226\128\153s Touch",
    "  rank: Rank 1",
    r"  desc: Heals for 10 to 12. \226\128\156Quoted\226\128\157 from C:\\5 on.",
    "  cost: 5 Mana",
    "  cast: Instant",
    "  level: 1",
    "spell 701",
    "  name: Quoted Touch",
    "  rank: Rank 1",
    r"  desc: Heals for 20 to 24. \226\128\156Quoted\226\128\157.",
    "  cost: 5 Mana",
    "  cast: Instant",
    "  level: 1",
    "",
])
ESCAPED_REF = {
    "generated": "selftest",
    "spell_desc": {
        "Druid|Nature\u2019s Touch|Rank 1": {
            "l": [["5 Mana", ""], ["Instant", ""]],
            "d": "Heals for 10 to 12. \u201cQuoted\u201d from C:\\5 on.",
            "s": "beta", "src": "selftest", "lv": "Learned at level 1", "id": 700,
        },
        "Druid|Quoted Touch|Rank 1": {
            "l": [["5 Mana", ""], ["Instant", ""]],
            "d": "Heals for 20 to 24. \u201cQuoted\u201d.",
            "s": "beta", "src": "selftest", "lv": "Learned at level 1", "id": 701,
        },
    },
}
ESCAPED_LAST = "refcheck: 2 spells, 2 agree, 0 disagree, 0 not in the reference"


def selftest_fixture():
    data = load_reference(os.path.join(FIXTURE_DIR, "data.json"))
    dump_path = os.path.join(FIXTURE_DIR, "dump.txt")
    expected_path = os.path.join(FIXTURE_DIR, "expected.txt")
    output = run_compare(dump_path, data, None, None)
    sys.stdout.write(output)
    with open(expected_path, "r", encoding="utf-8") as f:
        expected = f.read()
    if output != expected:
        sys.stderr.write("selftest: MISMATCH against %s\n" % expected_path)
        return False
    return True


def selftest_escapes():
    fd, path = tempfile.mkstemp(suffix=".txt")
    try:
        with os.fdopen(fd, "w", encoding="ascii") as f:
            f.write(ESCAPED_DUMP)
        output = run_compare(path, ESCAPED_REF, None, None)
    finally:
        os.remove(path)
    sys.stdout.write(output)
    agrees = output.rstrip("\n").endswith(ESCAPED_LAST)
    ascii_only = all(32 <= ord(c) <= 126 or c == "\n" for c in output)
    if not (agrees and ascii_only):
        sys.stderr.write("selftest: an escaped curly quote does not agree with its reference\n")
        return False
    return True


def do_selftest():
    results = [selftest_fixture(), selftest_escapes()]
    passed = sum(1 for r in results if r)
    print("selftest: %d of %d ok" % (passed, len(results)))
    return 0 if passed == len(results) else 1


def do_compare(args):
    data_path = args.data
    if not data_path and os.path.exists(CACHE_FILE):
        data_path = CACHE_FILE
    if not data_path:
        print("no reference data: run --fetch, or give --data", file=sys.stderr)
        return 2
    data = load_reference(data_path)
    output = run_compare(args.file, data, args.klass, args.level)
    sys.stdout.write(output)
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("file", nargs="?", help="a probe report or T10 export to check")
    p.add_argument("--fetch", action="store_true", help="download data.json into the cache")
    p.add_argument("--refresh", action="store_true", help="with --fetch, overwrite an existing cache")
    p.add_argument("--data", help="reference data.json path (default: the cache)")
    p.add_argument("--class", dest="klass", help="override the class read from the file")
    p.add_argument("--level", type=int, help="override the level read from the file")
    p.add_argument("--selftest", action="store_true", help="run against the bundled fixture")
    args = p.parse_args(argv)

    if args.selftest:
        return do_selftest()
    if args.fetch:
        return do_fetch(args.refresh)
    if not args.file:
        p.error("a file is required unless --fetch or --selftest is given")
    return do_compare(args)


if __name__ == "__main__":
    sys.exit(main())
