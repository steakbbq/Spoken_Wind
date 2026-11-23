# Spoken Wind

![Spoken Wind](release/logo.png)

A WoW Forever addon. Spoken gave the NPCs voice acting, so I figured the players deserved some too. Spoken Wind plays a fart sound whenever someone near you types /fart.

It's not part of the Spoken addons. The Spoken team had nothing to do with this, so please don't blame them.

## Features

### Hearing farts

When someone near you types /fart, you hear it. Everyone nearby with the addon hears the same sound, and it works even if the person who farted doesn't have Spoken Wind. It's not perfect, but it gets it right almost every time.

### 1337 farts

Every race has its own farts, with a separate set for each body type. That's 74 per voice across 18 voices, plus 5 Shartifact farts on top. They have rarities like loot, from Poor up to Legendary (1 in 500), and Shartifact is 1 in 5000.

### Achievements

There are 34 achievements, and a lot of them are about farting with other people. You get Standing Ovation when one of your farts is heard by 10 people at once, Household Name when 100 different players have heard you, and In Sync for farting together with your group or guild. Hear a Legendary fart from every race and you get Every Wind That Blows. There are also some for two people farting in the same second, someone farting right after you, farting late at night, and a few secret ones I'm not going to spoil. 15 of the achievements unlock a new emote you can use.

### Collection and Board

Every fart you hear gets saved to your Collection, one page per voice, and you can click any of them to play it again. If you hear all 1337 you get The Complete Works (good luck). The Board shows the top 10 most heard and top listeners from the players you've met.

### Random farts

This is on by default. Your character farts on their own about once an hour, and when they get out of a sleeping bag. Every once in a while, waking up turns into a full fart attack. If you don't want that, type `/wind random off` or turn off Random farts in Options > AddOns > Spoken Wind.

### Other stuff

- Spam protection, so someone spamming /fart only plays one sound at a time
- The same person won't play the same fart twice in a row
- You hear your own /fart too
- There's a Fart button if you want one-click farting
- A fart log in Options shows who farted, when, and which sound. It stays on your PC.
- Doesn't touch any Blizzard frames, just one small hook on the emote

## What it sends

Spoken Wind talks to other copies of itself with hidden addon messages (prefix `SpWind`), which never show up in chat. They go to your party or raid, your guild, and /say when you're in an instance. There's one message when you fart, so everyone hears the same sound, and one "heard it" reply when you hear a fart that came with a message. That's how the "heard by" counts work. The Board gets its numbers the same way, but only from party and guild, when you fart and every 5 to 6 minutes, and never in combat. If you don't want to be on other people's Boards, type `/wind board off`.

The pair test (`/wind pair`) only talks to the one player you picked. It whispers them, or uses your party or raid channel if you're in a group with them.

If you use the Fart button on a player, it first checks in the background if they have the addon. If they don't, a whisper icon shows up, and if you click that it sends them one whisper about Spoken Wind. Nothing gets whispered unless you click it. If you right-click the Fart button, it says the same thing once in /say, for when there's a bunch of people around. You can do that once every 5 minutes.

The only things that show up in chat are the reward emotes, that whisper or /say line, random farts and fart attacks, and one very rare surprise. There's no account ID in any of it, and nothing that links your characters together.

## Commands

| Command | What it does |
|---|---|
| `/wind` | show status |
| `/wind on` / `off` | turn the sounds on or off |
| `/wind random on` / `off` / `status` | random farts (on by default) |
| `/wind ach` | open achievements, collection and board |
| `/wind ch master` / `sfx` / `dialog` | pick which volume slider it uses |
| `/wind self on` / `off` | hear your own /fart |
| `/wind cd 0-30` | seconds between sounds from the same person (default 1) |
| `/wind wait 0-300` | ms to wait for a group or guild message (default 150) |
| `/wind board off` / `on` / `status` | off takes you off other people's boards |
| `/wind pair [name]` / `pair off` | test with a friend that you both hear the same farts |
| `/wind reset` | reset everything to default |

`/spokenwind` works too. All the same settings, the fart log, the changelog and the credits are in Options > AddOns > Spoken Wind.

It's made for the English client. Other languages should mostly work, but if it's silent for you, open an issue or a PR.

## Adding an emote

`Spoken_Wind/Emotes.lua` has one row per emote token, and each row points to a sound folder in `Media/<folder>/`. If you want another emote to make noise, add a row and its folder. You don't need to change any code.

## Building and testing

These are the tools I use. They're all Python.

    python -I tools/synth.py      rebuilds the synth farts in Media/fart (the ogg bytes change every run, the serial is random)
    python -I tools/analyze.py    checks the decoded oggs and draws spectrograms
    python -I tools/preview.py    rebuilds preview/index.html so you can listen to the synth farts in a browser
    python -I tools/lua.py all    compiles everything and runs the Lua tests, the sound length table and the board sim
    python -I tools/mutate.py     breaks the code on purpose, one change at a time, and checks that the tests catch it
    python -I tools/stage.py      builds stage/Spoken_Wind and stage/MANIFEST.md5
    python -I tools/release.py    checks the version, builds the zip and uploads it to CurseForge
    python tools/icons.py [dir]   cuts the icon sheets into Media/ach/*.tga and ring.tga (needs Pillow, numpy, scipy)

`tools/lua.py` needs a LuaJIT `lua51.dll`. By default it uses the one OBS Studio installs. Set `LUA51_DLL_DIR` if yours is somewhere else.

Releases go through GitHub Actions. Pushing a tag like `v0.7.1` runs the tests, builds the zip and uploads it to CurseForge, with the text from that version's section in `CHANGELOG.md`. Running the workflow by hand does a dry run and uploads nothing.

If something breaks, the log is in `SpokenWindDB.log` in your SavedVariables (BOOT, PLAY, SKIP, ACH, REWARD, DEX, ERR and SUM lines), and the sync lines are in `SpokenWindDB.sync`. Pasting those into an issue helps me a lot.

## Credits

Spoken Wind is made by Hals Dunngold (that's me).

Big thanks to my testers, who try every new version before it comes out:

- Bumm Farto
- Chrissy Walnutz

## License

MIT. See `LICENSE`. The fonts in `Spoken_Wind/Media/Fonts` (Lato, Barlow and DejaVu Sans) aren't covered by that. They keep their own licenses, which are in the same folder.
