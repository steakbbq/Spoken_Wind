"""Sound lengths in ms, read from the shipped ogg files (build time, no guessing).
  python -I tools/oglen.py            -> writes Spoken_Wind/Lengths.lua
  python -I tools/oglen.py check [D]  -> exit 1 when D/Lengths.lua does not match D/Media/**/*.ogg (D = Spoken_Wind)
Race packs (0.7.0): Media/<pack>/*.ogg with a Packs/<pack>.lua carry their own ms (the pack rows); Lengths.lua has the rest.
Ogg Vorbis: the sample rate from the identification header; length = the last page's granule position / rate.
The key is the file name without .ogg (as the sound row's `file`, and the Collection key)."""
import pathlib
import re
import struct
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "Spoken_Wind"

HEAD = ("-- Spoken Wind: sound lengths in ms, one per shipped ogg file.\n"
        "-- Made by tools/oglen.py from the files (do not edit by hand).\n"
        "-- The per-person gate keeps a person busy for max(cd, this length) from the play start.\n"
        "local _, ns = ...\n\n"
        "ns.LEN = {\n")


def ms_of(path):
    """Length of one Ogg Vorbis file in ms (whole number)."""
    b = path.read_bytes()
    if b[:4] != b"OggS":
        raise ValueError("%s: not an ogg file" % path.name)
    v = b.find(b"\x01vorbis")
    if v < 0 or v > 64:
        raise ValueError("%s: no vorbis header" % path.name)
    rate = struct.unpack_from("<I", b, v + 12)[0]
    p = b.rfind(b"OggS")
    while p >= 0 and (b[p + 4] != 0 or p + 27 > len(b)):   # a real page header: version 0
        p = b.rfind(b"OggS", 0, p)
    granule = struct.unpack_from("<q", b, p + 6)[0]
    if rate <= 0 or granule <= 0:
        raise ValueError("%s: rate %d granule %d" % (path.name, rate, granule))
    return int(granule * 1000 / rate + 0.5)


def pack_dirs(addon):
    """Media folders of the race packs (a Packs/<dir>.lua each)."""
    return {p.stem for p in (addon / "Packs").glob("*.lua")}


def lengths(addon, packs=False):
    """packs=False: the files Lengths.lua covers; packs=True: the race pack files."""
    dirs, out, seen = pack_dirs(addon), {}, set()
    for f in sorted(addon.glob("Media/**/*.ogg")):
        if f.stem in seen:
            raise ValueError("two files named %s" % f.stem)
        seen.add(f.stem)
        if (f.parent.parent.name == "Media" and f.parent.name in dirs) == packs:
            out[f.stem] = ms_of(f)
    return out


def read_packs(addon):
    """key -> ms of every pack row (Packs/*.lua)."""
    out = {}
    for p in sorted((addon / "Packs").glob("*.lua")):
        s = p.read_bytes().decode("utf-8")
        for k, ms in re.findall(r'\{ key = "([^"]+)", num = \d+,[^\n]*? ms = (\d+) \}', s):
            if k in out:
                raise ValueError("two pack rows named %s" % k)
            out[k] = int(ms)
    return out


def text(lens):
    return HEAD + "".join('\t["%s"] = %d,\n' % (k, v) for k, v in sorted(lens.items())) + "}\n"


def read_lua(path):
    s = path.read_bytes().decode("utf-8").replace("\r\n", "\n")
    return {k: int(v) for k, v in re.findall(r'\["([^"]+)"\] = (\d+),', s)}


def check(addon):
    """0 when Lengths.lua has every shipped ogg with its real length, and nothing else."""
    lua = addon / "Lengths.lua"
    if not lua.is_file():
        print("FAIL len: no Lengths.lua")
        return 1
    want, have = lengths(addon), read_lua(lua)
    bad = sorted(k for k in set(want) | set(have) if want.get(k) != have.get(k))
    for k in bad:
        print("FAIL len %s: file %s, table %s" % (k, want.get(k), have.get(k)))
    pwant, phave = lengths(addon, True), read_packs(addon)
    pbad = sorted(k for k in set(pwant) | set(phave) if pwant.get(k) != phave.get(k))
    for k in pbad:
        print("FAIL len %s: file %s, pack row %s" % (k, pwant.get(k), phave.get(k)))
    if not bad and not pbad:
        print("len: %d files ok + %d pack files ok" % (len(want), len(pwant)))
    return 1 if bad or pbad else 0


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "check":
        sys.exit(check(pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else SRC))
    lens = lengths(SRC)
    (SRC / "Lengths.lua").write_bytes(text(lens).replace("\n", "\r\n").encode("utf-8"))
    print("wrote Lengths.lua: %d files" % len(lens))
    for k, v in sorted(lens.items()):
        print("  %s %d ms" % (k, v))
