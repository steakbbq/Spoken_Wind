"""Number checks for the farts (no ears needed). Reads the .ogg files back
(the decoded audio = what the game plays) and writes:
  build/report.json, build/report.txt     per sound numbers + pass / fail
  preview/spec/NN_name.png                spectrogram + pitch line per sound
  build/sheet.png                         all spectrograms on one sheet

  python -I tools/analyze.py

Checks (all must pass):
  length 0.3..4.5 s, 44.1 kHz mono, sample peak <= -1.0 dBFS, 0 clipped samples,
  4x oversampled peak <= -0.3 dBFS, loudness within 1.5 LU of -16,
  voiced sounds: pitch wobble > 0.5 % frame to frame (not a robot beep),
  not one pure tone (spectral flatness, harmonics > 3),
  every pair of sounds different (feature distance >= 1.0),
  ffmpeg decodes every file with no error.
"""
import json
import pathlib
import struct
import subprocess
import sys
import zlib

import numpy as np
import soundfile as sf
from scipy import signal

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import synth  # noqa: E402

ROOT = synth.ROOT
MEDIA = synth.MEDIA
SPEC = ROOT / "preview" / "spec"
BUILD = ROOT / "build"


def _vertex(seg, k):
    """Sub-sample offset of a dip (parabola through 3 points)."""
    if 0 < k < len(seg) - 1:
        a, b, c = seg[k - 1], seg[k], seg[k + 1]
        den = a - 2 * b + c
        if den > 0:
            return 0.5 * (a - c) / den
    return 0.0


def f0_track(x, sr):
    """YIN-like pitch per 60 ms frame, 10 ms hop, 30-900 Hz. 0 = unvoiced."""
    ds = 2
    y = signal.resample_poly(x, 1, ds)
    fs = sr / ds
    # pitch lives low: look under 1.2 kHz so flap-to-flap jitter up high does not hide it
    y = signal.sosfiltfilt(signal.butter(4, 1200, fs=fs, output="sos"), y)
    N = int(0.06 * fs)
    hop = int(0.01 * fs)
    tmin, tmax = int(fs / 900), int(fs / 30)
    out, rms = [], []
    for i in range(0, len(y) - N - tmax, hop):
        fr = y[i:i + N + tmax]
        a = fr[:N]
        rms.append(np.sqrt(np.sum(a ** 2) / N))
        d = np.array([np.sum((a - fr[t:t + N]) ** 2) for t in range(tmax + 1)])
        cm = d.copy()
        cm[1:] = d[1:] * np.arange(1, tmax + 1) / (np.cumsum(d[1:]) + 1e-12)
        cm[0] = 1
        seg = cm[tmin:]
        below = np.nonzero(seg < 0.3)[0]
        if len(below):
            k = below[0]
            while k + 1 < len(seg) and seg[k + 1] < seg[k]:
                k += 1
            out.append(fs / (k + tmin + _vertex(seg, k)))
        elif seg.min() < 0.45:          # rough but still pitched (flappy)
            k = int(np.argmin(seg))
            out.append(fs / (k + tmin + _vertex(seg, k)))
        else:
            out.append(0.0)
    rms = np.array(rms)
    f = np.array(out)
    if len(f):
        f[rms < rms.max() * 0.05] = 0
    return f


def features(x, sr):
    n = len(x)
    f, Pxx = signal.welch(x, sr, nperseg=4096)
    P = Pxx + 1e-20
    centroid = float(np.sum(f * P) / np.sum(P))
    band_ = (f > 50) & (f < 8000)
    flat = float(np.exp(np.mean(np.log(P[band_]))) / np.mean(P[band_]))
    f0 = f0_track(x, sr)
    v = f0[f0 > 0]
    voiced = float(len(v) / max(1, len(f0)))
    if len(v) > 3:
        med = float(np.median(v))
        lo, hi = float(np.percentile(v, 5)), float(np.percentile(v, 95))
        steps = np.abs(np.diff(np.log(v)))
        steps = steps[steps < 0.2]          # skip octave jumps
        wob = float(np.median(steps) * 100) if len(steps) else 0.0
    else:
        med = lo = hi = wob = 0.0
    env = np.abs(signal.hilbert(x))
    env = signal.sosfilt(signal.butter(2, 25, fs=sr, output="sos"), env)
    e = env[::441]
    peaks, _ = signal.find_peaks(e, prominence=e.max() * 0.25, distance=4)
    B = int(0.1 * sr)
    i = int(np.argmax([np.sum(x[j:j + B] ** 2) for j in range(0, max(1, n - B), B // 4)]) * (B // 4))
    S = np.abs(np.fft.rfft(x[i:i + B] * np.hanning(len(x[i:i + B]))))
    Sd = 20 * np.log10(S / S.max() + 1e-9)
    hp_, _ = signal.find_peaks(Sd, height=-30, distance=8)
    return {
        "centroid": round(centroid), "flatness": round(flat, 4),
        "voiced": round(voiced, 2), "f0_med": round(med, 1), "f0_lo": round(lo, 1), "f0_hi": round(hi, 1),
        "wobble_pct": round(wob, 2), "bursts": int(len(peaks)), "spec_peaks": int(len(hp_)),
    }, f0


def mel_profile(x, sr, nb=24):
    f, P = signal.welch(x, sr, nperseg=2048)
    mel = 2595 * np.log10(1 + f / 700)
    edges = np.linspace(mel[1], 2595 * np.log10(1 + 8000 / 700), nb + 1)
    prof = np.array([P[(mel >= edges[k]) & (mel < edges[k + 1])].sum() for k in range(nb)])
    prof = 10 * np.log10(prof + 1e-20)
    return prof - prof.max()


def png_write(path, rgb):
    """Tiny PNG writer (no Pillow on this PC). rgb: H x W x 3 uint8."""
    h, w, _ = rgb.shape
    raw = b"".join(b"\x00" + rgb[r].tobytes() for r in range(h))

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    data = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    pathlib.Path(path).write_bytes(data)


# dark purple -> red -> orange -> pale yellow (magma-like)
_STOPS = np.array([[0, 0, 4], [40, 11, 84], [101, 21, 110], [159, 42, 99], [212, 72, 66],
                   [245, 125, 21], [250, 193, 39], [252, 253, 191]], float)


def colormap(v):
    v = np.clip(v, 0, 1) * (len(_STOPS) - 1)
    i = np.minimum(v.astype(int), len(_STOPS) - 2)
    t = (v - i)[..., None]
    return (_STOPS[i] * (1 - t) + _STOPS[i + 1] * t).astype(np.uint8)


def spectro_img(x, sr, f0, fmax=4000, H=160, px_per_s=160):
    """Spectrogram 0..fmax Hz (80 dB range), pitch line in cyan. Returns RGB array."""
    f, t, S = signal.spectrogram(x, sr, nperseg=2048, noverlap=2048 - 256, window="hann")
    S = 10 * np.log10(S + 1e-14)
    S = (S - (S.max() - 80)) / 80
    keep = f <= fmax
    S, f = S[keep], f[keep]
    W = max(60, int(len(x) / sr * px_per_s))
    yi = np.linspace(0, len(f) - 1, H)
    xi = np.linspace(0, S.shape[1] - 1, W)
    img = S[np.round(yi).astype(int)][:, np.round(xi).astype(int)][::-1]
    rgb = colormap(img)
    for k, v in enumerate(f0):
        if 0 < v < fmax:
            cx = int((k * 0.01 + 0.03) * px_per_s)
            cy = H - 1 - int(v / fmax * (H - 1))
            if 0 <= cx < W - 1:
                rgb[max(0, cy - 1):cy + 1, cx:cx + 2] = (127, 224, 255)
    return rgb


def ffmpeg_ok(p):
    try:
        r = subprocess.run(["ffmpeg", "-v", "error", "-i", str(p), "-f", "null", "-"],
                           capture_output=True, text=True, timeout=60)
        return r.returncode == 0 and not r.stderr.strip(), r.stderr.strip()[:200]
    except FileNotFoundError:
        return None, "no ffmpeg"


def main():
    SPEC.mkdir(parents=True, exist_ok=True)
    rows, profs, fails, imgs = [], [], [], []
    for stem, name, _, _ in synth.FARTS:
        p = MEDIA / (stem + ".ogg")
        x, sr = sf.read(p, dtype="float64")
        info = sf.info(p)
        peak = float(np.abs(x).max())
        tp = float(np.abs(signal.resample_poly(x, 4, 1)).max())
        clip = int(np.sum(np.abs(x) >= 0.999))
        ft, f0 = features(x, sr)
        lk = synth.loudness(x)
        ok_ff, _ = ffmpeg_ok(p)
        r = {"file": stem + ".ogg", "name": name, "seconds": round(len(x) / sr, 3), "sr": sr,
             "channels": info.channels, "codec": info.subtype, "bytes": p.stat().st_size,
             "peak_dbfs": round(20 * np.log10(peak), 2), "true_peak_dbfs": round(20 * np.log10(tp), 2),
             "clipped": clip, "loudness": round(lk, 2), "ffmpeg_decode": ok_ff, **ft}
        bad = []
        if not 0.3 <= r["seconds"] <= 4.5: bad.append("length")
        if sr != 44100 or info.channels != 1: bad.append("format")
        if r["peak_dbfs"] > -1.0: bad.append("peak")
        if clip: bad.append("clip")
        if r["true_peak_dbfs"] > -0.3: bad.append("truepeak")
        if abs(lk + 16) > 1.5: bad.append("loudness")
        if r["voiced"] > 0.3 and r["wobble_pct"] < 0.5: bad.append("robotic")
        if r["spec_peaks"] <= 3 and r["flatness"] < 0.01: bad.append("puretone")
        if ok_ff is False: bad.append("ffmpeg")
        r["fail"] = bad
        fails += [f"{stem}:{b}" for b in bad]
        rows.append(r)
        profs.append(mel_profile(x, sr))
        img = spectro_img(x, sr, f0)
        png_write(SPEC / (stem + ".png"), img)
        imgs.append(img)

    keys = ["seconds", "centroid", "flatness", "voiced", "f0_med", "f0_hi", "bursts", "wobble_pct"]
    M = np.array([[np.log1p(r[k]) for k in keys] for r in rows])
    Z = (M - M.mean(0)) / (M.std(0) + 1e-9)
    P = np.array(profs)
    Pz = (P - P.mean(0)) / (P.std() + 1e-9)
    n = len(rows)
    D = np.zeros((n, n))
    for i in range(n):
        for j in range(n):
            D[i, j] = np.sqrt(np.sum((Z[i] - Z[j]) ** 2) + 0.25 * np.mean((Pz[i] - Pz[j]) ** 2) * len(keys))
    iu = np.triu_indices(n, 1)
    k = int(np.argmin(D[iu]))
    a, b = iu[0][k], iu[1][k]
    closest = {"pair": [rows[a]["file"], rows[b]["file"]], "distance": round(float(D[a, b]), 2)}
    if D[a, b] < 1.0:
        fails.append("variety")

    rep = {"sounds": rows, "closest_pair": closest, "fails": fails}
    BUILD.mkdir(exist_ok=True)
    (BUILD / "report.json").write_text(json.dumps(rep, indent=1), encoding="utf-8")
    lines = [f"{'file':16s} {'sec':>5s} {'pk':>6s} {'tp':>6s} {'clip':>4s} {'LK':>6s} {'f0med':>5s} "
             f"{'f0 range':>11s} {'wob%':>5s} {'vcd':>4s} {'cent':>5s} {'flat':>6s} {'bst':>3s} {'kB':>4s} fail"]
    for r in rows:
        lines.append(f"{r['file']:16s} {r['seconds']:5.2f} {r['peak_dbfs']:6.1f} {r['true_peak_dbfs']:6.1f} "
                     f"{r['clipped']:4d} {r['loudness']:6.1f} {r['f0_med']:5.0f} "
                     f"{r['f0_lo']:5.0f}-{r['f0_hi']:<5.0f} {r['wobble_pct']:5.2f} {r['voiced']:4.2f} "
                     f"{r['centroid']:5d} {r['flatness']:6.3f} {r['bursts']:3d} {r['bytes'] // 1024:4d} "
                     f"{','.join(r['fail']) or '-'}")
    lines.append(f"closest pair: {closest['pair'][0]} ~ {closest['pair'][1]}  distance {closest['distance']}")
    lines.append("ALL PASS" if not fails else "FAILS: " + " ".join(fails))
    (BUILD / "report.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines))

    W = max(i.shape[1] for i in imgs)
    sheet = np.concatenate([np.pad(i, ((0, 6), (0, W - i.shape[1]), (0, 0)), constant_values=40) for i in imgs])
    png_write(BUILD / "sheet.png", sheet)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
