"""Spoken Wind fart synth. Every sound is made here from scratch (numpy + scipy DSP).
No sound files are read or downloaded.

  python -I tools/synth.py        -> Spoken_Wind/Media/fart/NN_name.ogg (+ build/wav/*.wav)

Model: a flapping valve. A pulse train (one flap per cycle) with a wobbling,
per-cycle-jittered period and per-cycle loudness, through a few body
resonances and a moving low-pass (cheeks + cloth). Extra layers: air hiss,
wet bubbles, slosh noise, stop/start gates, a fast flutter. Then a small room.
Every sound has its own fixed seed, so a rebuild gives the same files.
"""
import json
import pathlib

import numpy as np
import soundfile as sf
from scipy import signal
from scipy.interpolate import PchipInterpolator

SR = 44100
ROOT = pathlib.Path(__file__).resolve().parent.parent
MEDIA = ROOT / "Spoken_Wind" / "Media" / "fart"
WAVS = ROOT / "build" / "wav"
TAU = 2 * np.pi


# ---------------------------------------------------------------- helpers
def tax(n):
    return np.arange(n) / SR


def curve(pts, n):
    """Smooth curve through (seconds, value) points; a number = flat."""
    if not isinstance(pts, (list, tuple)):
        return np.full(n, float(pts))
    ts = np.array([p[0] for p in pts], float)
    vs = np.array([p[1] for p in pts], float)
    if len(ts) == 1:
        return np.full(n, vs[0])
    return PchipInterpolator(ts, vs)(np.clip(tax(n), ts[0], ts[-1]))


def wander(n, rate, rng):
    """Smooth random wobble, unit std, about `rate` new values a second."""
    k = max(5, int(n / SR * rate) + 5)
    y = PchipInterpolator(np.linspace(0, n / SR, k), rng.standard_normal(k))(tax(n))
    s = y.std()
    return y / s if s > 0 else y


def band(x, lo, hi, order=2):
    sos = signal.butter(order, [lo, min(hi, SR * 0.45)], "bandpass", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def lowpass(x, fc, order=2):
    return signal.sosfilt(signal.butter(order, fc, "lowpass", fs=SR, output="sos"), x)


def highpass(x, fc, order=2):
    return signal.sosfilt(signal.butter(order, fc, "highpass", fs=SR, output="sos"), x)


def svf_lp(x, fc, q=0.7):
    """Low-pass with a cutoff that moves every sample (TPT state variable filter)."""
    g = np.tan(np.pi * np.clip(fc, 30, SR * 0.45) / SR)
    k = 1.0 / q
    a1 = 1.0 / (1.0 + g * (g + k))
    a2 = g * a1
    a3 = g * a2
    xs, A1, A2, A3 = x.tolist(), a1.tolist(), a2.tolist(), a3.tolist()
    out = [0.0] * len(xs)
    ic1 = ic2 = 0.0
    for i, v0 in enumerate(xs):
        v3 = v0 - ic2
        v1 = A1[i] * ic1 + A2[i] * v3
        v2 = ic2 + A2[i] * ic1 + A3[i] * v3
        ic1 = 2 * v1 - ic1
        ic2 = 2 * v2 - ic2
        out[i] = v2
    return np.array(out)


def norm(x):
    m = np.abs(x).max()
    return x / m if m > 0 else x


# ---------------------------------------------------------------- layers
def flaps(f0, rng, oq, oq_jit, skew, cyc_jit, shimmer):
    """One flap per cycle. Period and open time and loudness change every cycle."""
    n = len(f0)
    c0 = np.floor(np.cumsum(f0) / SR).astype(int)
    f = f0 * np.exp(cyc_jit * rng.standard_normal(c0[-1] + 2))[c0]
    ph = np.cumsum(f) / SR
    cyc = np.floor(ph).astype(int)
    x = ph - cyc
    nc = cyc[-1] + 2
    o = np.clip(oq + oq_jit * rng.standard_normal(nc), 0.12, 0.95)[cyc]
    tp, tn = o * skew, o * (1 - skew)
    w = np.zeros(n)
    a = x < tp
    w[a] = 0.5 * (1 - np.cos(np.pi * x[a] / tp[a]))
    b = (~a) & (x < tp + tn)
    w[b] = np.cos(0.5 * np.pi * (x[b] - tp[b]) / tn[b])
    amp = np.clip(1 + shimmer * rng.standard_normal(nc), 0.15, 2.2)[cyc]
    return w * amp


def voice(dur, f0, amp, rng, *, wob=0.06, wob_rate=20, vib=(0, 0), cyc_jit=0.05, shimmer=0.15,
          oq=0.55, oq_jit=0.08, skew=0.75, diff=0.7, formants=((250, 3, 1.0),), dry=0.15,
          lp=3000, lp_q=0.7, flutter=None, breath=0.08, gate=None, push=0.0):
    """The flapping valve. f0 / amp / lp: (seconds, value) points or one number.
    push: louder = a bit higher, like more pressure."""
    n = int(dur * SR)
    t = tax(n)
    env = np.clip(curve(amp, n), 0, None)
    f = curve(f0, n) * np.exp(wob * wander(n, wob_rate, rng))
    if vib[0]:
        f = f * (1 + vib[1] * np.sin(TAU * vib[0] * t + rng.uniform(0, TAU)))
    if push:
        f = f * (1 + push * (env - 0.5))
    f = np.clip(f, 18, 3000)
    w = flaps(f, rng, oq, oq_jit, skew, cyc_jit, shimmer)
    src = diff * norm(np.diff(w, prepend=w[0])) + (1 - diff) * norm(w - w.mean())
    if breath:
        air = band(rng.standard_normal(n), 600, 4500) * (0.25 + w)
        src = src + breath * norm(air)
    y = dry * src
    for fc, q, g in formants:
        bb, aa = signal.iirpeak(fc, q, fs=SR)
        y = y + g * signal.lfilter(bb, aa, src)
    y = svf_lp(y, curve(lp, n), lp_q)
    if flutter:
        rate, depth = flutter
        fr = rate * np.exp(0.15 * wander(n, 4, rng))
        dep = curve(depth, n)
        env = env * (1 - dep * (0.5 + 0.5 * np.sin(TAU * np.cumsum(fr) / SR)) ** 2)
    if gate is not None:
        env = env * gate[:n]
    return norm(y * env)


def hiss(dur, amp, rng, lo=500, hi=3500, flutter=None):
    """Air: band-passed noise (the pfffft)."""
    n = int(dur * SR)
    env = np.clip(curve(amp, n), 0, None)
    y = band(rng.standard_normal(n), lo, hi)
    y = y * (1 + 0.35 * wander(n, 30, rng))
    if flutter:
        rate, depth = flutter
        fr = rate * np.exp(0.2 * wander(n, 5, rng))
        env = env * (1 - depth * (0.5 + 0.5 * np.sin(TAU * np.cumsum(fr) / SR)) ** 2)
    return norm(y * env)


def bubbles(dur, rate, rng, fmin=250, fmax=1800, tau=(0.003, 0.014), chirp=0.35):
    """Wet pops: short rising sine blips at random times (rate = pops a second)."""
    n = int(dur * SR)
    out = np.zeros(n)
    p = np.clip(curve(rate, n), 0, None) / SR
    for e in np.nonzero(rng.random(n) < p)[0]:
        f = np.exp(rng.uniform(np.log(fmin), np.log(fmax)))
        tc = rng.uniform(*tau)
        L = min(int(tc * 6 * SR), n - e)
        tt = np.arange(L) / SR
        ph = TAU * np.cumsum(f * (1 + chirp * tt / (tc * 6))) / SR
        out[e:e + L] += rng.uniform(0.3, 1.0) * np.sin(ph) * np.exp(-tt / tc)
    return norm(out)


def slosh(dur, amp, rng, lo=120, hi=700):
    n = int(dur * SR)
    y = band(rng.standard_normal(n), lo, hi) * np.clip(1 + 0.8 * wander(n, 12, rng), 0, None)
    return norm(y * np.clip(curve(amp, n), 0, None))


def gate(dur, rng, on, off, ramp=0.004, start_on=True):
    """Stop/start: random on and off pieces, soft edges."""
    n = int(dur * SR)
    g = np.zeros(n)
    i, state = 0, start_on
    while i < n:
        L = max(1, int(rng.uniform(*(on if state else off)) * SR))
        if state:
            g[i:i + L] = 1
        i += L
        state = not state
    k = int(ramp * SR)
    win = np.hanning(2 * k + 1)
    return np.convolve(g, win / win.sum(), "same")


def holes(dur, cuts, ramp=0.006):
    """Gate that is on, with a few short holes: cuts = [(start, length)]."""
    n = int(dur * SR)
    g = np.ones(n)
    for s, L in cuts:
        g[int(s * SR):int((s + L) * SR)] = 0
    k = int(ramp * SR)
    win = np.hanning(2 * k + 1)
    return np.convolve(g, win / win.sum(), "same")


def mix(total, layers):
    """layers: (start seconds, signal, gain)."""
    out = np.zeros(int(total * SR))
    for st, x, g in layers:
        i = int(st * SR)
        L = min(len(x), len(out) - i)
        out[i:i + L] += g * x[:L]
    return out


def room(x, rng, rt=0.32, wet=0.1):
    """Small room: early bounces + a short noise tail. Adds tail time."""
    L = int(rt * SR)
    t = np.arange(L) / SR
    ir = lowpass(rng.standard_normal(L) * np.exp(-6.9 * t / rt), 3500)
    ir[:int(0.004 * SR)] = 0
    for d, g in ((0.006, 0.5), (0.011, -0.35), (0.017, 0.25), (0.023, -0.18)):
        ir[int(d * SR)] += g * np.abs(ir).max() * 3
    ir = ir / np.sqrt(np.sum(ir ** 2))
    pad = np.concatenate([x, np.zeros(L)])
    rev = signal.fftconvolve(pad, ir)[:len(pad)]
    return pad + wet * rev * (np.abs(pad).max() / (np.abs(rev).max() + 1e-9))


# ---------------------------------------------------------------- loudness
def _biquad_shelf(fs, f0=1681.97, g_db=3.9998, q=0.7072):
    A = 10 ** (g_db / 40)
    w = TAU * f0 / fs
    al = np.sin(w) / (2 * q)
    c = np.cos(w)
    b = [A * ((A + 1) + (A - 1) * c + 2 * np.sqrt(A) * al), -2 * A * ((A - 1) + (A + 1) * c),
         A * ((A + 1) + (A - 1) * c - 2 * np.sqrt(A) * al)]
    a = [(A + 1) - (A - 1) * c + 2 * np.sqrt(A) * al, 2 * ((A - 1) - (A + 1) * c),
         (A + 1) - (A - 1) * c - 2 * np.sqrt(A) * al]
    return np.array(b) / a[0], np.array(a) / a[0]


def loudness(x):
    """Rough LUFS-like number (K-weighting, 100 ms blocks, -10 LU gate)."""
    b, a = _biquad_shelf(SR)
    y = signal.lfilter(b, a, x)
    y = highpass(y, 38)
    B = int(0.1 * SR)
    blocks = [np.mean(y[i:i + B] ** 2) for i in range(0, max(1, len(y) - B + 1), B // 4)] or [np.mean(y ** 2)]
    blocks = np.array(blocks) + 1e-12
    lk = -0.691 + 10 * np.log10(blocks)
    keep = blocks[lk > -70]
    rel = -0.691 + 10 * np.log10(keep.mean()) - 10
    keep = blocks[(lk > rel) & (lk > -70)]
    return float(-0.691 + 10 * np.log10(keep.mean()))


CEIL = 10 ** (-1.5 / 20)   # -1.5 dBFS sample peak (room for the ogg encoder)
TARGET = -16.0             # loudness for every fart


def master(x, rng):
    x = highpass(x, 32)
    x = room(x, rng)
    x = x - x.mean()
    n = len(x)
    fade = np.ones(n)
    k = int(0.003 * SR)
    fade[:k] = np.linspace(0, 1, k)
    k = int(0.04 * SR)
    fade[-k:] = np.linspace(1, 0, k)
    x = norm(x * fade) * CEIL
    gain = 1.0
    for _ in range(6):   # louder until TARGET, soft-limited at the ceiling
        y = CEIL * np.tanh(x * gain / CEIL)
        lk = loudness(y)
        if abs(lk - TARGET) < 0.3 or (gain >= 2.4 and lk < TARGET):
            break
        gain = min(2.4, gain * 10 ** ((TARGET - lk) / 20))
    return y, lk, gain


# ---------------------------------------------------------------- the farts
def f_squeak(r):
    v = voice(0.42, [(0, 330), (0.07, 480), (0.25, 540), (0.36, 500), (0.42, 360)],
              [(0, 0), (0.015, 1), (0.3, 0.85), (0.42, 0)], r, wob=0.04, wob_rate=25, cyc_jit=0.025,
              shimmer=0.1, oq=0.45, skew=0.7, diff=0.8, formants=((650, 4, 1.0), (1700, 6, 0.5)),
              dry=0.1, lp=4500, breath=0.12, push=0.15)
    h = hiss(0.14, [(0, 0), (0.02, 1), (0.14, 0)], r, 1000, 4000)
    return mix(0.52, [(0, v, 1), (0.36, h, 0.15)])


def f_rumble(r):
    v = voice(2.3, [(0, 64), (0.25, 58), (0.7, 50), (1.1, 55), (1.5, 47), (1.9, 42), (2.3, 34)],
              [(0, 0), (0.05, 0.85), (0.4, 1), (0.8, 0.75), (1.2, 0.95), (1.7, 0.6), (2.1, 0.35), (2.3, 0)],
              r, wob=0.12, wob_rate=10, cyc_jit=0.14, shimmer=0.3, oq=0.65, oq_jit=0.12, diff=0.6,
              formants=((150, 2.2, 1), (380, 3, 0.6), (900, 4, 0.2)), dry=0.3,
              lp=[(0, 800), (0.5, 1300), (1.2, 900), (1.8, 1200), (2.3, 500)], flutter=(7, 0.35),
              breath=0.06, push=0.2)
    h = hiss(0.3, [(0, 0), (0.05, 1), (0.3, 0)], r, 300, 1500)
    return mix(2.45, [(0, v, 1), (2.12, h, 0.1)])


def f_wet(r):
    g = gate(1.3, r, on=(0.04, 0.12), off=(0.005, 0.03))
    v = voice(1.3, [(0, 95), (0.3, 82), (0.7, 100), (1.0, 78), (1.3, 60)],
              [(0, 0), (0.02, 1), (0.6, 0.9), (1.0, 0.8), (1.3, 0)], r, wob=0.2, wob_rate=35,
              cyc_jit=0.2, shimmer=0.4, oq=0.7, oq_jit=0.15, diff=0.55,
              formants=((210, 2, 1), (650, 3, 0.6), (1400, 4, 0.25)), dry=0.25,
              lp=[(0, 1800), (0.5, 1200), (1.3, 900)], flutter=(13, 0.4), breath=0.1, gate=g)
    b = bubbles(1.35, [(0, 60), (0.5, 140), (1.1, 200), (1.35, 40)], r)
    s = slosh(1.35, [(0, 0), (0.1, 1), (1.0, 0.8), (1.35, 0)], r)
    splat = bubbles(0.18, 600, r, 300, 2500, (0.002, 0.008))
    return mix(1.45, [(0, v, 1), (0, b, 0.45), (0, s, 0.22), (1.15, splat, 0.5)])


def f_trumpet(r):
    v = voice(1.0, [(0, 120), (0.04, 158), (0.4, 166), (0.75, 172), (0.9, 205), (1.0, 150)],
              [(0, 0), (0.008, 1), (0.12, 0.85), (0.7, 0.9), (0.88, 1), (1.0, 0)], r, wob=0.03,
              wob_rate=14, vib=(5.5, 0.022), cyc_jit=0.015, shimmer=0.06, oq=0.32, oq_jit=0.03,
              skew=0.82, diff=0.92, formants=((480, 3, 0.6), (1150, 5, 1.0), (2500, 6, 0.35)),
              dry=0.12, lp=6000, breath=0.04)
    end = voice(0.14, [(0, 95), (0.14, 80)], [(0, 0), (0.005, 1), (0.14, 0)], r, cyc_jit=0.08,
                oq=0.5, formants=((300, 3, 1), (900, 4, 0.4)), lp=2500)
    return mix(1.2, [(0, v, 1), (1.0, end, 0.5)])


def f_slowsqueak(r):
    g = holes(2.6, [(0.9, 0.03), (1.72, 0.04)])
    v = voice(2.6, [(0, 185), (0.5, 235), (1.0, 225), (1.5, 300), (2.0, 345), (2.35, 430), (2.6, 380)],
              [(0, 0), (0.25, 0.55), (0.8, 0.7), (1.4, 0.65), (2.0, 0.85), (2.45, 0.9), (2.6, 0)], r,
              wob=0.07, wob_rate=11, vib=(7, 0.03), cyc_jit=0.035, shimmer=0.12, oq=0.45, diff=0.7,
              formants=((600, 3, 1), (1800, 6, 0.4)), dry=0.3, lp=3500, breath=0.18,
              flutter=(4, 0.25), gate=g, push=0.1)
    h = hiss(0.2, [(0, 0), (0.03, 1), (0.2, 0)], r, 800, 3500)
    return mix(2.75, [(0, v, 1), (2.5, h, 0.12)])


def f_triple(r):
    def pap(L, f0):
        return voice(L, f0, [(0, 0), (0.006, 1), (L * 0.7, 0.8), (L, 0)], r, wob=0.05, cyc_jit=0.06,
                     shimmer=0.2, oq=0.55, diff=0.75, formants=((300, 3, 1), (950, 4, 0.5)),
                     dry=0.2, lp=2600, breath=0.05)
    return mix(1.0, [(0, pap(0.11, [(0, 118), (0.11, 105)]), 0.85),
                     (0.19, pap(0.11, [(0, 135), (0.11, 120)]), 0.9),
                     (0.40, pap(0.52, [(0, 108), (0.3, 92), (0.52, 70)]), 1)])


def f_brrt(r):
    layers, t = [], 0.0
    for k in range(9):
        ioi = 0.075 * 1.09 ** k
        L = 0.6 * ioi
        f0 = r.uniform(95, 145)
        layers.append((t, voice(L, [(0, f0), (L, f0 * 0.9)], [(0, 0), (0.004, 1), (L * 0.6, 0.85), (L, 0)],
                                r, wob=0.04, cyc_jit=0.06, shimmer=0.2, oq=0.5, diff=0.8,
                                formants=((280, 3, 1), (850, 4, 0.5)), dry=0.2, lp=2400, breath=0.04),
                       r.uniform(0.75, 1.0)))
        t += ioi
    last = voice(0.26, [(0, 110), (0.26, 68)], [(0, 0), (0.005, 1), (0.18, 0.8), (0.26, 0)], r,
                 wob=0.05, cyc_jit=0.08, shimmer=0.25, oq=0.55, diff=0.75,
                 formants=((260, 3, 1), (800, 4, 0.5)), dry=0.2, lp=2000)
    layers.append((t + 0.02, last, 1.0))
    return mix(t + 0.32, layers)


def f_quack(r):
    v = voice(0.5, [(0, 230), (0.08, 285), (0.22, 260), (0.5, 175)],
              [(0, 0), (0.01, 1), (0.17, 0.6), (0.22, 0.95), (0.5, 0)], r, wob=0.03, cyc_jit=0.02,
              shimmer=0.08, oq=0.28, skew=0.8, diff=0.9,
              formants=((1400, 7, 1), (750, 4, 0.5), (2900, 8, 0.3)), dry=0.1, lp=5500, breath=0.05)
    return mix(0.55, [(0, v, 1)])


def f_balloon(r):
    v = voice(2.0, [(0, 640), (0.35, 560), (0.9, 430), (1.35, 300), (1.7, 180), (2.0, 105)],
              [(0, 0), (0.02, 0.9), (1.0, 0.85), (1.7, 0.95), (2.0, 0)], r, wob=0.05, wob_rate=18,
              vib=(9, 0.02), cyc_jit=0.04, shimmer=0.12, oq=0.4, diff=0.85,
              formants=((780, 4, 1), (1900, 6, 0.5)), dry=0.12, lp=[(0, 5000), (2.0, 2200)],
              flutter=(16, [(0, 0), (1.2, 0.1), (2.0, 0.6)]), breath=0.15)
    return mix(2.08, [(0, v, 1)])


def f_sputter(r):
    g = gate(1.6, r, on=(0.05, 0.16), off=(0.03, 0.12))
    v = voice(1.6, [(0, 88), (0.5, 75), (0.9, 95), (1.3, 70), (1.6, 62)],
              [(0, 0), (0.01, 1), (0.8, 0.9), (1.6, 0.6)], r, wob=0.15, cyc_jit=0.12, shimmer=0.3,
              oq=0.6, diff=0.65, formants=((240, 2.5, 1), (780, 3.5, 0.5)), dry=0.2, lp=1600,
              flutter=(18, 0.35), breath=0.05, gate=g)
    b = bubbles(1.6, 30, r, 200, 1200)
    h = hiss(0.22, [(0, 0), (0.02, 1), (0.22, 0)], r, 500, 2500)
    return mix(1.75, [(0, v, 1), (0, b, 0.25), (1.5, h, 0.3)])


def f_tuba(r):
    v = voice(0.9, [(0, 52), (0.05, 72), (0.5, 70), (0.78, 64), (0.9, 48)],
              [(0, 0), (0.01, 1), (0.2, 0.85), (0.7, 0.9), (0.9, 0)], r, wob=0.045, wob_rate=18, vib=(4.5, 0.025),
              cyc_jit=0.025, shimmer=0.08, oq=0.38, skew=0.8, diff=0.9,
              formants=((170, 3, 1), (520, 4, 0.8), (1050, 5, 0.35)), dry=0.15, lp=2800, breath=0.03)
    return mix(0.95, [(0, v, 1)])


def f_pfft(r):
    h = hiss(0.9, [(0, 0), (0.04, 1), (0.5, 0.7), (0.9, 0)], r, 500, 3200, flutter=(24, 0.5))
    under = voice(0.85, [(0, 290), (0.85, 320)], [(0, 0), (0.1, 1), (0.85, 0)], r, wob=0.08,
                  cyc_jit=0.05, oq=0.6, diff=0.6, formants=((700, 3, 1),), lp=2000, breath=0.3)
    tip = voice(0.16, [(0, 420), (0.16, 520)], [(0, 0), (0.01, 1), (0.16, 0)], r, wob=0.03,
                cyc_jit=0.02, oq=0.4, diff=0.85, formants=((900, 5, 1), (2000, 7, 0.4)), lp=4500)
    return mix(1.1, [(0, h, 1), (0, under, 0.25), (0.88, tip, 0.6)])


def f_legend(r):
    a = voice(1.35, [(0, 58), (0.6, 52), (1.35, 68)], [(0, 0), (0.05, 0.9), (0.7, 1), (1.35, 0.85)], r,
              wob=0.12, wob_rate=10, cyc_jit=0.14, shimmer=0.3, oq=0.65, diff=0.6,
              formants=((150, 2.2, 1), (380, 3, 0.6), (900, 4, 0.2)), dry=0.3, lp=1000,
              flutter=(7, 0.3), breath=0.06)
    b = voice(1.1, [(0, 70), (0.4, 110), (0.9, 170), (1.1, 178)], [(0, 0.6), (0.6, 0.95), (1.1, 0.9)], r,
              wob=0.02, vib=(5.5, 0.015), cyc_jit=0.02, shimmer=0.08, oq=0.34, skew=0.82, diff=0.92,
              formants=((480, 3, 0.6), (1150, 5, 1.0), (2500, 6, 0.35)), dry=0.12, lp=5000, breath=0.04)
    c = voice(0.55, [(0, 160), (0.55, 105)], [(0, 0.9), (0.55, 0.5)], r, wob=0.08, cyc_jit=0.08,
              oq=0.5, diff=0.75, formants=((300, 3, 1), (950, 4, 0.5)), lp=2600,
              gate=gate(0.55, r, on=(0.04, 0.09), off=(0.02, 0.05)))
    d = voice(0.25, [(0, 380), (0.25, 470)], [(0, 0), (0.01, 1), (0.25, 0)], r, wob=0.04,
              cyc_jit=0.025, oq=0.45, diff=0.8, formants=((650, 4, 1), (1700, 6, 0.5)), lp=4500)
    e = bubbles(0.22, 500, r, 250, 2000, (0.002, 0.009))
    fade_a = np.ones(len(a))
    fade_a[-int(0.1 * SR):] = np.linspace(1, 0, int(0.1 * SR))
    return mix(3.5, [(0, a * fade_a, 1), (1.25, b, 0.9), (2.33, c, 0.8), (2.98, d, 0.6), (3.22, e, 0.45)])


def f_question(r):
    v = voice(0.75, [(0, 112), (0.35, 100), (0.5, 120), (0.62, 190), (0.75, 280)],
              [(0, 0), (0.01, 1), (0.45, 0.8), (0.6, 0.9), (0.75, 0)], r, wob=0.05, cyc_jit=0.05,
              shimmer=0.15, oq=0.5, diff=0.8, formants=((330, 3, 1), (1000, 4, 0.5), (2000, 6, 0.25)),
              dry=0.15, lp=3500, flutter=(10, 0.2), breath=0.06)
    return mix(0.8, [(0, v, 1)])


# (file stem, name in game, maker, seed). Order = the numbers in /wind test N.
# Must match the FART row in Spoken_Wind/Emotes.lua (tests check it).
FARTS = [
    ("01_squeak", "Squeak", f_squeak, 101),
    ("02_rumble", "Rumble", f_rumble, 202),
    ("03_wet", "Wet", f_wet, 303),
    ("04_trumpet", "Trumpet", f_trumpet, 404),
    ("05_slowsqueak", "Slow squeak", f_slowsqueak, 505),
    ("06_triple", "Triple", f_triple, 606),
    ("07_brrt", "Brrt", f_brrt, 707),
    ("08_quack", "Quack", f_quack, 808),
    ("09_balloon", "Balloon", f_balloon, 909),
    ("10_sputter", "Sputter", f_sputter, 1010),
    ("11_tuba", "Tuba", f_tuba, 1111),
    ("12_pfft", "Pfft", f_pfft, 1212),
    ("13_legend", "Legend", f_legend, 1313),
    ("14_question", "Question", f_question, 1414),
]


def main():
    MEDIA.mkdir(parents=True, exist_ok=True)
    WAVS.mkdir(parents=True, exist_ok=True)
    for old in MEDIA.glob("*.ogg"):
        old.unlink()
    info = []
    for stem, name, fn, seed in FARTS:
        rng = np.random.default_rng(seed)
        y, lk, gain = master(fn(rng), rng)
        sf.write(WAVS / (stem + ".wav"), y, SR, subtype="PCM_16")
        sf.write(MEDIA / (stem + ".ogg"), y, SR, format="OGG", subtype="VORBIS", compression_level=0.15)
        info.append({"file": stem, "name": name, "seconds": round(len(y) / SR, 3), "lk": round(lk, 2),
                     "limit_gain": round(gain, 2)})
        print(f"{stem:14s} {len(y) / SR:5.2f}s  lk {lk:6.1f}  gain {gain:4.2f}")
    (ROOT / "build" / "synth.json").write_text(json.dumps(info, indent=1))


if __name__ == "__main__":
    main()
