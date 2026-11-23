"""Builds stage/Spoken_Wind (what gets copied to AddOns) + stage/MANIFEST.md5.
If dev/Spoken_Wind_Dev exists (private repo only): also stage-dev/Spoken_Wind_Dev +
stage-dev/MANIFEST.md5, apart, so it never lands in the public zip.
Text files: CRLF, UTF-8 without BOM. Media: copied byte for byte.
Manifests: LF lines, so `md5sum -c MANIFEST.md5` reads them.
  python -I tools/stage.py
"""
import hashlib
import pathlib
import re
import shutil

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "Spoken_Wind"
OUT = ROOT / "stage" / "Spoken_Wind"
DEV_SRC = ROOT / "dev" / "Spoken_Wind_Dev"
DEV_OUT = ROOT / "stage-dev" / "Spoken_Wind_Dev"


def build(src, out):
    if out.parent.exists():
        shutil.rmtree(out.parent)
    out.mkdir(parents=True)
    for f in sorted(src.rglob("*")):
        if f.is_dir():
            continue
        rel = f.relative_to(src)
        dst = out / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        if f.suffix in (".lua", ".toc"):
            b = f.read_bytes()
            assert not b.startswith(b"\xef\xbb\xbf"), f"BOM in {rel}"
            b.decode("utf-8")
            dst.write_bytes(b.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n"))
        else:
            shutil.copyfile(f, dst)
    lines = []
    for f in sorted(out.rglob("*")):
        if f.is_file():
            lines.append(f"{hashlib.md5(f.read_bytes()).hexdigest()} *{f.relative_to(out).as_posix()}")
    (out.parent / "MANIFEST.md5").write_bytes(("\n".join(lines) + "\n").encode("utf-8"))   # LF, not CRLF
    print("\n".join(lines))
    print(f"{out}: {len(lines)} files, {sum(f.stat().st_size for f in out.rglob('*') if f.is_file())} bytes")


def main():
    build(SRC, OUT)
    # the public stage never turns the dev switch on by itself
    for f in OUT.rglob("*"):
        assert "Dev" not in f.name, f"dev file in public stage: {f}"
        if f.suffix in (".lua", ".toc"):
            assert not re.search(rb"SPOKEN_WIND_DEV\s*=[^=]", f.read_bytes()), f"dev flag set in {f.name}"
    if DEV_SRC.is_dir():
        build(DEV_SRC, DEV_OUT)


if __name__ == "__main__":
    main()
