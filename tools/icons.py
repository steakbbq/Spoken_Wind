"""Cuts the achievement icon sheets into square 128x128 TGA icons for the addon.
  python tools/icons.py [sheet-dir]       (default: release/ in this repo)
Needs Pillow + numpy + scipy. They are in the user site here, so no -I.

Three sheets (see SHEETS): the old 15 icons, 15 new, 2 new. Tiles are NOT on an exact grid.
Each tile is found from its bright, colored frame pixels: small gaps closed, the inside of
the ring filled, then connected patches = tiles, sorted by row, then column (no fixed
grid). The cut is a square around the patch (whole frame + a small dark margin), scaled
to 128x128. A patch that is not 15-45% of the sheet height or not nearly full stops the
script (the art alone, or an open ring).

Also writes ring.tga: white outline of the frame shape, tinted by the addon in the item
quality color (see Ring).

Output: Spoken_Wind/Media/ach/<id>.tga = 128x128, 32-bit, uncompressed (type 2),
bottom-left origin (descriptor 0x08). The same TGA kind as 499 files in installed
addons that load on this client (checked 2026-11-22).
"""
import pathlib
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = pathlib.Path(__file__).resolve().parent.parent
RELEASE = ROOT / "release"
OUT = ROOT / "Spoken_Wind" / "Media" / "ach"
# (file, ids in reading order, tiles per row). Ids = Achievements.lua order.
SHEETS = [
    ("acheev-classic-clean.png",
     ["super", "legend", "orchestra", "thousand", "gas",
      "penpals", "cropduster", "double", "callback", "machinegun",
      "sbd", "night", "tuba", "selfstarter", "first"], 5),
    ("acheev-social1.png",
     ["heard", "packed", "ovation", "around", "town",
      "fame", "fanclub", "cult", "household", "insync",
      "born", "witness", "everywind", "labpartner", "source"], 5),
    ("acheev-social2.png", ["authornote", "windbag"], 2),
]
SIZE = 128
MARGIN = 0.03   # dark margin around the frame, part of the side
EDGE = 4        # px of sheet kept outside the frame; past that = plain background
CHAMFER = 14    # corner cut of the ring in px at 128 (measured from the cut tiles)
THICK = 4.0     # ring thickness in px at 128


def frame_boxes(rgb, count, cols):
    """(left, top, right, bottom) of each tile's frame in reading order, + tile masks."""
    a = rgb.astype(np.int16)
    v = a.max(axis=2)
    sat = v - a.min(axis=2)
    mask = (v > 80) & (sat > 40)                # bright + colored: frame metal, gems, glow
    mask = ndimage.binary_closing(mask, iterations=3)   # join the thin dark gaps in the ring
    mask = ndimage.binary_fill_holes(mask)      # ring + all inside = one solid tile
    labels, n = ndimage.label(mask)
    objs = ndimage.find_objects(labels)
    sizes = ndimage.sum(mask, labels, range(1, n + 1))
    H, W = mask.shape
    found = []
    for i, sl in enumerate(objs):
        if sizes[i] < (0.1 * H) ** 2:           # specks and glow bits
            continue
        w, h = sl[1].stop - sl[1].start, sl[0].stop - sl[0].start
        # a whole tile: 15-45% of the sheet height, nearly full (an open ring = art only = wrong)
        assert 0.15 * H <= w <= 0.45 * H and 0.15 * H <= h <= 0.45 * H and sizes[i] / (w * h) > 0.8, \
            f"patch {w}x{h} at {sl[1].start},{sl[0].start} fill {sizes[i] / (w * h):.2f}, not a whole frame"
        found.append((i + 1, sl))
    assert len(found) == count, f"found {len(found)} tiles, expected {count}"
    # reading order: sort by center y, cut into rows of `cols`, sort each row by center x
    found.sort(key=lambda f: f[1][0].start + f[1][0].stop)
    ordered = []
    for r in range(0, count, cols):
        ordered += sorted(found[r:r + cols], key=lambda f: f[1][1].start + f[1][1].stop)
    boxes, picked = [], []
    for lab, sl in ordered:
        boxes.append((sl[1].start, sl[0].start, sl[1].stop, sl[0].stop))
        picked.append(labels == lab)
    return boxes, picked, mask


def square(box):
    l, t, r, b = box
    side = max(r - l, b - t)
    side = int(round(side / (1 - 2 * MARGIN)))
    cx, cy = (l + r) / 2, (t + b) / 2
    x0, y0 = int(round(cx - side / 2)), int(round(cy - side / 2))
    return x0, y0, x0 + side, y0 + side


def check_tga(path):
    h = path.read_bytes()[:18]
    assert h[2] == 2 and h[12] | h[13] << 8 == SIZE and h[14] | h[15] << 8 == SIZE \
        and h[16] == 32 and h[17] == 0x08, f"TGA header {h.hex()} {path}"


def cut_sheet(path, ids, cols):
    """{id: (RGBA tile, frame box, cut square)} for one sheet."""
    rgb = np.asarray(Image.open(path).convert("RGB"))
    boxes, picked, anyTile = frame_boxes(rgb, len(ids), cols)
    bg = np.median(rgb[~ndimage.binary_dilation(anyTile, iterations=6)], axis=0).astype(np.uint8)
    dist = [ndimage.distance_transform_edt(~m) for m in picked]   # px to each tile
    tiles = {}
    for k, (id_, box) in enumerate(zip(ids, boxes)):
        sq = square(box)
        # The square can reach a neighbor tile or its glow: a pixel nearer to another tile,
        # or over EDGE px out from this frame, = plain background. Frame, gems, own glow stay.
        far = dist[k] > EDGE
        if len(dist) > 1:
            far |= dist[k] > np.min([d for j, d in enumerate(dist) if j != k], axis=0)
        clean = rgb.copy()
        clean[far] = bg
        # outside the sheet: dark fill (Image.crop pads with black)
        tile = Image.fromarray(clean).crop(sq).resize((SIZE, SIZE), Image.LANCZOS).convert("RGBA")
        tiles[id_] = (tile, box, sq)
    return tiles


def Ring(chamfer=CHAMFER, thick=THICK, scale=8):
    """White outline (alpha only) of a square with cut corners, SIZE x SIZE. Outer edge on the
    tile edge, `thick` px wide, so it sits in the dark margin around the gold frame.
    Drawn at `scale`x and shrunk = anti-aliased."""
    S = SIZE * scale

    def poly(inset):
        lo, hi = inset * scale, S - inset * scale
        c = max(0.0, chamfer * scale - inset * scale * 0.4142)   # inner cut stays parallel
        return [(lo + c, lo), (hi - c, lo), (hi, lo + c), (hi, hi - c),
                (hi - c, hi), (lo + c, hi), (lo, hi - c), (lo, lo + c)]
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    d.polygon(poly(0), fill=255)
    d.polygon(poly(thick), fill=0)
    out = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0))
    out.putalpha(m.resize((SIZE, SIZE), Image.LANCZOS))
    return out


def main():
    args = sys.argv[1:]
    folder = pathlib.Path(args[0]) if args else RELEASE
    OUT.mkdir(parents=True, exist_ok=True)
    n = 0
    for name, ids, cols in SHEETS:
        for id_, (tile, box, sq) in cut_sheet(folder / name, ids, cols).items():
            path = OUT / f"{id_}.tga"
            tile.save(path)                      # Pillow: type 2, bottom-left, 8 alpha bits
            check_tga(path)
            n += 1
            print(f"{id_:12s} frame {box[2] - box[0]}x{box[3] - box[1]} at {box[0]},{box[1]}  cut {sq[2] - sq[0]}px  tga ok")
    path = OUT / "ring.tga"
    Ring().save(path)
    check_tga(path)
    print(f"ring         chamfer {CHAMFER} px, thickness {THICK:g} px, outer edge at 0 px  tga ok")
    print(f"{n} icons + ring -> {OUT}")


if __name__ == "__main__":
    main()
