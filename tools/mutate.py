"""Breaks the addon on purpose, one way at a time; the tests must catch each.
  python -I tools/mutate.py
"""
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "Spoken_Wind"
WORK = ROOT / "build" / "mutant" / "Spoken_Wind"

MUTANTS = [
    ("no cooldown", "Core.lua", "if lastPlay and now - lastPlay < db.cd then", "if false then"),
    ("repeat allowed", "Pick.lua", "if k >= last then k = k + 1 end", ""),
    ("self ignored", "Core.lua", "if mine and not db.self then", "if false then"),
    ("off ignored", "Core.lua", "if not db.on then sums.off", "if false then sums.off"),
    ("any case match", "Emotes.lua", 'local FART_EN = { "%f[%a]farts?%f[%A]" }', 'local FART_EN = { "%f[%a][Ff]arts?%f[%A]" }'),
    ("no word edge", "Emotes.lua", 'local FART_EN = { "%f[%a]farts?%f[%A]" }', 'local FART_EN = { "fart" }'),
    ("channel lost", "Core.lua", "pcall(PlaySoundFile, path, db.ch)", "pcall(PlaySoundFile, path)"),
    ("folder lost", "Core.lua", 'ns.MEDIA .. row.folder .. "\\\\" ..', "ns.MEDIA .."),
    ("prints on emote", "Core.lua", 'Log(("PLAY emo=', 'print("pfft") Log(("PLAY emo='),
    ("no sender strip", "Match.lua", "if a then text = text:sub(1, a - 1) .. text:sub(b + 1) end", ""),
    ("secret not checked", "Match.lua", "if issecretvalue and issecretvalue(text) then return nil end", ""),
    ("cd not clamped", "Core.lua", "db.cd = math.min(CD_MAX, math.floor(n * 10 + 0.5) / 10)", "db.cd = n"),
    ("log not capped", "Core.lua", "while #log > LOG_MAX do", "while false do"),
    ("wrong sound file", "Emotes.lua", '"04_trumpet"', '"04_trumpt"'),
    ("hook added", "Core.lua", 'local ev = CreateFrame("Frame")', 'hooksecurefunc("DoEmote", function() end) local ev = CreateFrame("Frame")'),
    ("one picker for all", "Core.lua", "pickers[token] = p", "pickers.ALL = p"),
    ("first row only", "Match.lua", "for _, token in ipairs(order) do\n\t\tfor _, p", "for _, token in ipairs({ order[1] }) do\n\t\tfor _, p"),
    ("X- key in toc", "Spoken_Wind.toc", "## Version: 0.1.0", "## Version: 0.1.0\n## X-Spoken-Module: wind"),
]


def run():
    return subprocess.run([sys.executable, "-I", str(ROOT / "tools" / "lua.py"), "all", str(WORK)],
                          capture_output=True, text=True).returncode


def main():
    killed = 0
    for name, file, old, new in MUTANTS:
        if WORK.exists():
            shutil.rmtree(WORK)
        shutil.copytree(SRC, WORK)
        p = WORK / file
        s = p.read_text(encoding="utf-8")
        if old not in s:
            print(f"BAD MUTANT (text not found): {name}")
            return 1
        p.write_text(s.replace(old, new, 1), encoding="utf-8")
        rc = run()
        killed += rc != 0
        print(f"{'killed' if rc else 'SURVIVED'}  {name}")
    shutil.rmtree(WORK.parent)
    print(f"{killed}/{len(MUTANTS)} killed")
    return 0 if killed == len(MUTANTS) else 1


if __name__ == "__main__":
    sys.exit(main())
