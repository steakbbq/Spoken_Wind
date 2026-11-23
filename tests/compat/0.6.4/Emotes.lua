-- Spoken Wind: the emote table. One row per emote:
--   token (the game's EMOTEn_TOKEN) -> sound set folder in Media\, its sounds,
--   and the emote's verb per locale (stems, see Match.lua).
-- Adding an emote = one more row + its Media\<folder>\ files. No code change.
-- Sounds: made by tools/synth.py (original, no packs). Order = /wind test N.
local _, ns = ...

ns.MEDIA = "Interface\\AddOns\\Spoken_Wind\\Media\\"

-- Stems are lower case on purpose: player and NPC names start upper case,
-- so "Fartbag", "Farthing" or a player called "Fart" never match.
local FART_EN = { "%f[%a]farts?%f[%A]" }

ns.EMOTES = {
	FART = {
		folder = "fart",
		-- enUS / enGB checked: "fart" / "farts" in every form (you fart, X farts,
		-- X ... at you, X ... at Y). The rest: best guess, not seen in game yet.
		checked = { enUS = true, enGB = true },
		stems = {
			enUS = FART_EN,
			enGB = FART_EN,
			deDE = { "furz" },
			frFR = { "pète", "%f[%a]pets?%f[%A]" },
			esES = { "pedo" },
			esMX = { "pedo" },
			ptBR = { "peid", "%f[%a]pum%f[%A]" },
			itIT = { "scoregg", "%f[%a]peto%f[%A]" },
			ruRU = { "пук" },
			koKR = { "방귀" },
			zhCN = { "放屁" },
			zhTW = { "放屁" },
		},
		sounds = {
			{ file = "01_squeak", name = "Squeak" },
			{ file = "02_rumble", name = "Rumble" },
			{ file = "03_wet", name = "Wet" },
			{ file = "04_trumpet", name = "Trumpet" },
			{ file = "05_slowsqueak", name = "Slow squeak" },
			{ file = "06_triple", name = "Triple" },
			{ file = "07_brrt", name = "Brrt" },
			{ file = "08_quack", name = "Quack" },
			{ file = "09_balloon", name = "Balloon" },
			{ file = "10_sputter", name = "Sputter" },
			{ file = "11_tuba", name = "Tuba" },
			{ file = "12_pfft", name = "Pfft" },
			{ file = "13_legend", name = "Legend" },
			{ file = "14_question", name = "Question" },
		},
	},
}
