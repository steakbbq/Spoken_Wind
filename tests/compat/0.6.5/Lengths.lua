-- Spoken Wind: sound lengths in ms, one per shipped ogg file.
-- Made by tools/oglen.py from the files (do not edit by hand).
-- The per-person gate keeps a person busy for max(cd, this length) from the play start.
local _, ns = ...

ns.LEN = {
	["01_squeak"] = 840,
	["02_rumble"] = 2770,
	["03_wet"] = 1770,
	["04_trumpet"] = 1520,
	["05_slowsqueak"] = 3070,
	["06_triple"] = 1320,
	["07_brrt"] = 1617,
	["08_quack"] = 870,
	["09_balloon"] = 2400,
	["10_sputter"] = 2070,
	["11_tuba"] = 1270,
	["12_pfft"] = 1420,
	["13_legend"] = 3820,
	["14_question"] = 1120,
}
