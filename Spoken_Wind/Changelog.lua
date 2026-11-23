-- Spoken Wind: the changelog (Options -> AddOns -> Spoken Wind -> Changelog).
-- Newest first. A new version = one new row at the top. Terse: labels, no sentences.
-- Tests: the top row = the toc Version.
local _, ns = ...

ns.CHANGELOG = {
	{ v = "0.8.4", "New look for every window", "Credits page", "Fart button: whispers left", "Right-click Fart = /say", "Artifact tier is now Shartifact" },
	{ v = "0.7.1", "Rare Classic farts, 1 in 200", "Fix: error spam on hidden auras" },
	{ v = "0.7.0", "Race voices: 74 per race and body", "Collection pages per voice" },
	{ v = "0.6.6", "Random farts: 1 per hour", "Wake-up fart", "/wind random off" },
	{ v = "0.6.5", "Fart button" },
	{ v = "0.6.4", "Board tab", "All players", "Rarity rows", "/wind board off" },
	{ v = "0.6.3", "Collection tab", "5 new achievements", "Click a sound = play", "One sound per person" },
	{ v = "0.6.2.1", "Toast text centered", "Toast click = window", "Earned first by rarity" },
	{ v = "0.6.2", "Heard count", "Farts · Heard · People", "Achievements window", "17 Social achievements" },
	{ v = "0.6.1", "Pair test: /wind pair", "Bigger toast + sound" },
	{ v = "0.6.0", "Same fart for all", "Sync wait 0-300ms" },
	{ v = "0.5.0", "15 reward emotes", "Rewards button" },
	{ v = "0.4.1", "Bigger icons", "Clearer Machine Gun", "Cooldown 1s", "Dev: 1 secret" },
	{ v = "0.4.0", "15 achievements", "Toasts", "Icons by the author" },
	{ v = "0.3.0", "Fart log" },
	{ v = "0.2.1", "Test: dev only" },
	{ v = "0.2.0", "Cooldown per person", "Options page", "Changelog" },
	{ v = "0.1.0", "First release", "14 toots", "/wind commands" },
}

-- Credits (Options -> AddOns -> Spoken Wind -> Credits). author = the toc ## Author.
-- { name, class token }: the name shows in its class color. Testers: only the names they asked for,
-- spelled as in the game, first tester first. inspired = the "Inspired by" text, shown as is (approved
-- text: no word changes without a new OK).
ns.CREDITS = {
	author = { "Hals Dunngold", "HUNTER" },
	testers = { { "Bumm Farto", "PRIEST" }, { "Chrissy Walnutz", "WARRIOR" } },
	inspired = "I really like the Spoken addon. It gives the NPCs a voice, so I started thinking about which emotes I could make sound effects for. I landed on /fart, because a fart addon with way too much effort put into it felt perfect. Spoken Wind isn't made by the Spoken team. And no, I don't have a fart fetish.",
}
