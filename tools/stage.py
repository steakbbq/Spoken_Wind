"""Builds stage/Spoken_Wind (what gets copied to AddOns) + stage/MANIFEST.md5.
Text files: CRLF, UTF-8 without BOM. Media: copied byte for byte.
  python -I tools/stage.py
"""
import hashlib
import pathlib
import shutil

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "Spoken_Wind"
OUT = ROOT / "stage" / "Spoken_Wind"


def main():
    if OUT.parent.exists():
        shutil.rmtree(OUT.parent)
    (OUT / "Media").mkdir(parents=True)
    for f in sorted(SRC.rglob("*")):
        if f.is_dir():
            continue
        rel = f.relative_to(SRC)
        dst = OUT / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        if f.suffix in (".lua", ".toc"):
            b = f.read_bytes()
            assert not b.startswith(b"\xef\xbb\xbf"), f"BOM in {rel}"
            b.decode("utf-8")
            dst.write_bytes(b.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n"))
        else:
            shutil.copyfile(f, dst)
    lines = []
    for f in sorted(OUT.rglob("*")):
        if f.is_file():
            lines.append(f"{hashlib.md5(f.read_bytes()).hexdigest()} *{f.relative_to(OUT).as_posix()}")
    (OUT.parent / "MANIFEST.md5").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines))
    print(f"{len(lines)} files, {sum(f.stat().st_size for f in OUT.rglob('*') if f.is_file())} bytes")


if __name__ == "__main__":
    main()
