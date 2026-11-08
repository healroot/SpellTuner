-- tools/data/clock-v2-author.lua -- T145b (docs/SPEC-clock-v3.md 4.5): the
-- author's db.clockLook on 2026-11-08, copied from the Forever client's saved
-- variables (_forever_/WTF/Account/<account>/SavedVariables/SpellTuner.lua,
-- written 15:31 after T144) and limited to clockLook. Read by
-- tools/clockstorecheck.lua: it migrates to the exact v3 look of the spec's
-- section 1.5. Data only; never edit it by hand.
return {
["layout"] = "bar",
["over"] = {
["colors"] = {
["manaBar"] = {
0,
0.55,
1,
1,
},
},
["bars"] = {
["bar"] = {
["show"] = "mana",
["fsr"] = 2,
["after"] = "empty",
},
},
["text"] = {
["bar"] = {
["items"] = {
["fsr"] = {
["place"] = "below",
["outline"] = "outline",
["y"] = -1,
["size"] = 10,
},
["rest"] = {
["outline"] = "outline",
["size"] = 10,
},
["time"] = {
["y"] = 1,
["align"] = "right",
["colour"] = "E3E3E3",
["outline"] = "outline",
["size"] = 15,
},
["label"] = {
["y"] = 0,
["x"] = 4,
["place"] = "inside",
["colour"] = "E3E3E3",
["outline"] = "outline",
["size"] = 10,
},
["pct"] = {
["y"] = 0,
["x"] = -4,
["place"] = "inside",
["colour"] = "E3E3E3",
["outline"] = "outline",
["size"] = 10,
},
["mana"] = {
["y"] = 1,
["size"] = 14,
["outline"] = "outline",
["colour"] = "E3E3E3",
},
["mp5"] = {
["y"] = 1,
["size"] = 15,
["outline"] = "outline",
["align"] = "left",
["place"] = "inside",
["on"] = false,
["colour"] = "CDD4D0",
},
["manaMax"] = {
["outline"] = "outline",
["colour"] = "E3E3E3",
["size"] = 12,
},
},
["time"] = "sec",
},
},
["frame"] = {
["bar"] = {
["w"] = 260,
},
},
["bar"] = {
["back"] = {
0.06666666666666667,
0.06666666666666667,
0.06666666666666667,
0.75,
},
},
},
["v"] = 2,
}
