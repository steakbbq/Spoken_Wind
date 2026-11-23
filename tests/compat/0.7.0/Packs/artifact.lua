-- Spoken Wind, the 1337 set: the ARTIFACT block (#1333-#1337). Made by tools/artifact_sharts.py. Do not edit by hand.
-- The Artifact tier: the rarest tier (above legendary). 5 farts for all races and both body types,
--   so a row has no race and no body.
-- rows: one per sound file. key = the file name in sounds\ without .ogg; it is stable for ever (the collection key).
--   num = the collection number. tier = artifact. ms = the length of the file in milliseconds, measured from the ogg.
--   slot = the name of the place in the tier (the same as name). Lines that belong to a place use the slot.
-- final = true: the player picked these 5 on the page and pressed Done.
-- No chance numbers are in this file. README.txt has the numbers of the picking page.
-- Loaded as an addon file it fills ns.SW1337_ARTIFACT. loadfile(path)() gives the same table.
local _, ns = ...
local T = {
	tier = "artifact",
	final = true,
	shared = true,
	first = 1333,
	last = 1337,
	rows = {
		{ key = "artifact_never_trust_it", num = 1333, name = "Never Trust It", slot = "Never Trust It", tier = "artifact", ms = 4970 },
		{ key = "artifact_surprise_splat", num = 1334, name = "Surprise Splat", slot = "Surprise Splat", tier = "artifact", ms = 4834 },
		{ key = "artifact_final_sputter", num = 1335, name = "The Final Sputter", slot = "The Final Sputter", tier = "artifact", ms = 4380 },
		{ key = "artifact_floodgate", num = 1336, name = "Floodgate", slot = "Floodgate", tier = "artifact", ms = 4870 },
		{ key = "artifact_the_stutter", num = 1337, name = "The Stutter", slot = "The Stutter", tier = "artifact", ms = 4741 },
	},
}
if ns then ns.SW1337_ARTIFACT = T end
return T
