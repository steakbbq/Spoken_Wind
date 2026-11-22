# Spoken Wind

![Spoken Wind](release/logo.png)

WoW Forever addon. **Spoken** gave the NPCs a voice. **Spoken Wind** gives one to the players.

For years, heroes of Azeroth typed `/fart` and the world stayed silent. A text line. Nothing else. No more.
Today, every player is finally heard.

**Someone types /fart near you. You hear it.**

- Every player gets a voice. 14 of them, actually.
- 14 original fart sounds, made from scratch (no samples)
- Random pick, never the same one twice in a row
- One sound per 2 s, so spam does not stack
- Your own /fart plays too
- No hooks, no Blizzard frames touched, no chat spam

Not part of the Spoken addons. Just a joke.

## Commands

| Command | Does |
|---|---|
| `/wind` | status |
| `/wind on` / `off` | on or off |
| `/wind test [1-14]` | play one (13 = the Legend) |
| `/wind ch master` / `sfx` / `dialog` | which volume slider |
| `/wind self on` / `off` | your own /fart |
| `/wind cd 0-30` | seconds between sounds |
| `/wind reset` | defaults |

`/spokenwind` works too.

Made for the English client. Other languages: best guess. If one is silent, open an issue or a PR.

## Add an emote

`Spoken_Wind/Emotes.lua` has one row per emote token. Each row points to a sound folder `Media/<folder>/`.
A new emote = one row + its folder. No code change.

## Dev

    python -I tools/synth.py      rebuild the sounds (new bytes each run: ogg serial is random)
    python -I tools/analyze.py    number checks on the decoded oggs + spectrograms
    python -I tools/preview.py    rebuild preview/index.html (hear every sound in a browser)
    python -I tools/lua.py all    compile + Lua tests
    python -I tools/mutate.py     break the code on purpose; the tests must catch all
    python -I tools/stage.py      stage/Spoken_Wind + stage/MANIFEST.md5

`tools/lua.py` needs a LuaJIT `lua51.dll`. Default: the one OBS Studio installs.
Set `LUA51_DLL_DIR` to use another folder.

The log is in `SpokenWindDB.log` (BOOT, PLAY, SKIP, TEST, ERR, SUM lines).

## License

MIT. See `LICENSE`.
