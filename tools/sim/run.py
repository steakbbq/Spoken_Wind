"""Spoken Wind board: FULL gossip simulation (500 characters, 60 days) + report + PNG.

  python tools/sim/run.py [--out DIR] [--days 60] [--tune-days 30] [--quick] [--timer]
  --timer = the timer S study (timer vs press only on the same seed, more seeds, guild + group mixes).

Runs tools/sim/sim.lua (the real Spoken_Wind/Board.lua) through LuaJIT the way tools/lua.py does.
Writes DIR/report.md, DIR/coverage.png, DIR/raw/*.json. Use plain `python` (matplotlib), not -I.
Small mode (inside the gate): python -I tools/lua.py sim
"""
import argparse
import importlib.util
import json
import pathlib
import time

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent
_spec = importlib.util.spec_from_file_location("sw_lua", ROOT / "tools" / "lua.py")
LP = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(LP)
LUA = LP.lua()


def lit(o):
    """Python value -> Lua table literal."""
    if isinstance(o, bool):
        return "true" if o else "false"
    if isinstance(o, (int, float)):
        return repr(o)
    if isinstance(o, str):
        return json.dumps(o)
    if isinstance(o, (list, tuple)):
        return "{" + ",".join(lit(x) for x in o) + "}"
    return "{" + ",".join(f"[{json.dumps(k)}]={lit(v)}" for k, v in o.items()) + "}"


def run_one(cfg, out_json):
    drv = (f'ROOT=[[{ROOT.as_posix()}]] ADDON_DIR=[[{(ROOT / "Spoken_Wind").as_posix()}]]\n'
           'local Run, ToJSON = assert(loadfile(ROOT .. "/tools/sim/sim.lua"))()\n'
           f'local r = Run({lit(cfg)})\n'
           f'local f = assert(io.open([[{pathlib.Path(out_json).as_posix()}]], "wb"))\n'
           'f:write(ToJSON(r)) f:close()\n')
    src = drv.encode()
    s = LUA.luaL_newstate()
    LUA.luaL_openlibs(s)
    rc = LUA.luaL_loadbuffer(s, src, len(src), b"=sim")
    if rc == 0:
        rc = LUA.lua_pcall(s, 0, 0, 0)
    if rc != 0:
        msg = LUA.lua_tolstring(s, -1, None).decode(errors="replace")
        LUA.lua_close(s)
        raise RuntimeError("sim failed: " + msg)
    LUA.lua_close(s)
    r = json.loads(pathlib.Path(out_json).read_text())
    for k in ("cp", "days", "details", "viol", "stats", "fake"):
        if isinstance(r.get(k), list):   # a dense Lua table (days 1..N) comes out as an array
            r[k] = {str(i + 1): v for i, v in enumerate(r[k])}
    for c in r["cp"].values():
        if isinstance(c.get("grid"), list):
            c["grid"] = {}
    return r


def pct(x, d=0):
    return "-" if x is None else f"{100 * x:.{d}f}%"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(HERE / "out"))
    ap.add_argument("--days", type=int, default=60)
    ap.add_argument("--tune-days", type=int, default=30)
    ap.add_argument("--chars", type=int, default=500)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--quick", action="store_true", help="smoke run (150 chars, 14 days, fewer configs)")
    ap.add_argument("--timer", action="store_true", help="the timer S study")
    ap.add_argument("--bud-measure", action="store_true", help="raise budget step 1: the honest need, no budget")
    ap.add_argument("--bud", action="store_true", help="raise budget step 2: on vs off, honest + fakers")
    ap.add_argument("--bud-new", type=int, default=0, help="raise budget option: also try a cap on the first sight")
    a = ap.parse_args()
    if a.quick:
        a.chars, a.days, a.tune_days = 150, 14, 14
    if a.timer:
        return main_timer(a)
    if a.bud_measure:
        return main_bud_measure(a)
    if a.bud:
        return main_bud(a)
    out = pathlib.Path(a.out)
    (out / "raw").mkdir(parents=True, exist_ok=True)
    t0 = time.time()
    cps = [d for d in (1, 7, 14, 30, 60) if d <= a.days]
    users_list = [u for u in (10, 25, 50, 100, 500) if u <= a.chars]
    if a.quick:
        users_list = sorted({10, 50, a.chars})
    main_runs = {}
    for u in users_list:
        t = time.time()
        main_runs[u] = run_one({"chars": a.chars, "days": a.days, "users": u, "seed": a.seed, "checkpoints": cps},
                               out / "raw" / f"main_{u}.json")
        print(f"main users={u}: {time.time() - t:.0f}s", flush=True)
    extra = {}   # more seeds for the pass/fail flags
    for sd in ([] if a.quick else [a.seed + 1, a.seed + 2]):
        for u in (50, a.chars):
            extra[(u, sd)] = run_one({"chars": a.chars, "days": a.days, "users": u, "seed": sd, "checkpoints": cps},
                                     out / "raw" / f"seed{sd}_{u}.json")
            print(f"seed {sd} users={u} done", flush=True)
    tune = {}
    tunes = [a.chars] if a.quick else [a.chars, 100]
    for u in tunes:
        for k in (3, 4, 5):
            for top in (0, 1, 2):
                tune[(u, k, top)] = run_one({"chars": a.chars, "days": a.tune_days, "users": u, "seed": a.seed, "k": k,
                                             "top": top, "checks": False, "est": False,
                                             "checkpoints": [d for d in (7, 30) if d <= a.tune_days]},
                                            out / "raw" / f"tune_{u}_{k}_{top}.json")
                print(f"tune users={u} k={k} top={top} done", flush=True)
    fake = run_one({"chars": a.chars, "days": a.days, "users": a.chars, "seed": a.seed, "fakers": True, "checks": False,
                    "est": False, "checkpoints": [a.days]}, out / "raw" / "fakers.json")
    print("fakers done", flush=True)
    total = time.time() - t0
    report(a, out, main_runs, extra, tune, fake, cps, total)
    plot(out, main_runs)
    print(f"done in {total / 60:.1f} min -> {out}")


def day(r, d):
    return r["days"].get(str(d)) or {}


def passes(r):
    return {c[0]: c[1] for c in r["checks"]}


def report(a, out, main_runs, extra, tune, fake, cps, total):
    L = []
    P = L.append
    users = sorted(main_runs)
    P("# Spoken Wind 0.6.4 board: gossip simulation\n")
    P(f"{a.chars} chars, {a.days} days, seed {a.seed}, k=4 top=2, 2% loss/copy. Real Board.lua. Runtime {total / 60:.1f} min.\n")
    names = [c[0] for c in main_runs[users[-1]]["checks"]]
    P("## PASS / FAIL (no fakers)\n")
    P("| check | " + " | ".join(f"{u} users" for u in users) + " | other seeds |")
    P("|---|" + "---|" * (len(users) + 1))
    for n in names:
        row = []
        for u in users:
            c = next((x for x in main_runs[u]["checks"] if x[0] == n), None)
            if c is None:
                row.append("-")
            else:
                row.append(("PASS" if c[1] else "FAIL") + ("" if c[1] or c[2] in (None, "") else f" ({c[2]})"))
        oth = [passes(r).get(n) for r in extra.values()]
        tail = f"{'PASS' if all(oth) else 'FAIL'} ({len(oth)} runs)" if oth else "-"
        P(f"| {n} | " + " | ".join(row) + f" | {tail} |")
    for u in users:
        det = main_runs[u].get("details") or {}
        for kind, lst in (det.items() if isinstance(det, dict) else []):
            P(f"\n- {u} users, `{kind}`: " + " | ".join(lst))
    # --- seen
    P("\n## Seen estimator (default 0.05 / 50, real code)\n")
    P("Share of clients with an estimate whose |Seen - 100*true coverage| <= 10 points; `?` = share still under 20 entries; median abs error (points).\n")
    P("| users | day | clients | within 10 pts | Seen ? | median error | bias (+ = Seen too high) |")
    P("|---|---|---|---|---|---|---|")
    seen_pass = {}
    for u in users:
        for d in cps:
            if d < 7:
                continue
            g = (main_runs[u]["cp"].get(str(d)) or {}).get("grid", {}).get("r0.05_w50")
            if not g:
                continue
            med = "-" if g.get("med") is None else f"{g.get('med'):.1f}"
            bias = "-" if g.get("bias") is None else f"{g.get('bias'):+.1f}"
            P(f"| {u} | {d} | {day(main_runs[u], d).get('n')} | {pct(g.get('share'))} ({g.get('n')}) | {pct(g.get('qshare'))} | {med} | {bias} |")
            if u in (50, 100, 500) and d == 7:
                seen_pass[u] = g.get("share") is not None and g.get("share") >= 0.9
    P("\nSeen PASS (day 7, 50/100/500 users, >= 90% within 10 pts): "
      + ", ".join(f"{u}: {'PASS' if v else 'FAIL'}" for u, v in sorted(seen_pass.items())))
    P("\n### Estimator grid: share within 10 pts (users 50, 100, 500)\n")
    keys = list(main_runs[users[-1]]["cp"][str(cps[0])]["grid"].keys())
    ul = [u for u in (50, 100, 500) if u in main_runs]
    dl = [d for d in (7, 30) if d in cps]
    P("| raise_window | " + " | ".join(f"{u}u d{d}" for d in dl for u in ul) + " | min d7 |")
    P("|---|" + "---|" * (len(dl) * len(ul) + 1))
    best = None
    for k in keys:
        cells, m7 = [], []
        for d in dl:
            for u in ul:
                g = (main_runs[u]["cp"].get(str(d)) or {}).get("grid", {}).get(k) or {}
                cells.append(pct(g.get("share")))
                if d == 7:
                    m7.append(g.get("share") or 0)
        mn = min(m7) if m7 else 0
        P(f"| {k} | " + " | ".join(cells) + f" | {pct(mn)} |")
        if best is None or mn > best[1]:
            best = (k, mn)
    P(f"\nBest estimator setting (worst of 50/100/500 at day 7): {best[0]} -> {pct(best[1])}. "
      + ("Passes." if best[1] >= 0.9 else "NO setting reaches 90%."))
    # --- coverage
    P("\n## Coverage (B.All l / true l over visible 0.6.4 chars): median [p10 - p90]\n")
    P("| users | clients | " + " | ".join(f"day {d}" for d in cps) + " | rows d7 | rows d30 | rows d60 |")
    P("|---|---|" + "---|" * (len(cps) + 3))
    for u in users:
        r = main_runs[u]
        cells = []
        for d in cps:
            c = day(r, d).get("cov") or [None, None, None]
            cells.append(f"{pct(c[0], 1)} [{pct(c[1], 1)} - {pct(c[2], 1)}]")
        rows = [str(day(r, d).get("rows", "-")) for d in (7, 30, 60)]
        P(f"| {u} | {r['world']['clients']} | " + " | ".join(cells) + " | " + " | ".join(rows) + " |")
    P("\nOnly 0.6.4 characters can be on a board (0.6.2/0.6.3 send no per-character counters). Rows = board entries + own chars.")
    P("World: " + "; ".join(
        f"{u}u: {main_runs[u]['world']['v2']}/{main_runs[u]['world']['v3']}/{main_runs[u]['world']['v4']} chars on 0.6.2/0.6.3/0.6.4, "
        f"{main_runs[u]['world']['hiddenChars']} hidden" for u in users[-2:]))
    # --- same vs cross
    P("\n## Same-realm vs cross-realm coverage (median over clients)\n")
    dd = [d for d in cps if d >= 7]
    P("| users | " + " | ".join(f"d{d} same / cross" for d in dd) + " |")
    P("|---|" + "---|" * len(dd))
    for u in users:
        cells = []
        for d in dd:
            c = main_runs[u]["cp"].get(str(d)) or {}
            cells.append(f"{pct(c.get('same'), 1)} / {pct(c.get('cross'), 1)}")
        P(f"| {u} | " + " | ".join(cells) + " |")
    # --- top10
    P("\n## Days until 90% of a realm's 0.6.4 clients hold each of its top-10 chars (by true h)\n")
    P("| users | median day | p90 day | reached / total |")
    P("|---|---|---|---|")
    for u in users:
        t = main_runs[u]["top10"]
        P(f"| {u} | {t.get('median', '-')} | {t.get('p90', '-')} | {t['reached']} / {t['total']} |")
    # --- bytes
    P("\n## Bytes per online hour per 0.6.4 client\n")
    P("| users | sent mean | sent median | sent p90 | F | S | H | received mean | received median |")
    P("|---|---|---|---|---|---|---|---|---|")
    for u in users:
        b = main_runs[u]["bytes"]
        P(f"| {u} | {b['sentMean']:.0f} | {b['sentMed']:.0f} | {b['sentP90']:.0f} | {b['F']:.0f} | {b['S']:.0f} | {b['H']:.0f} | {b['recvMean']:.0f} | {b['recvMed']:.0f} |")
    r = main_runs[users[-1]]
    o = r["stats"]["old"]
    P(f"\n## Old clients ({users[-1]} users)\n")
    P(f"S texts read: {o['S']}, misparsed: {r['stats']['mis']}. F taken {o['F']}, F refused (0.6.2 tail) {o['dropF']}; "
      f"H taken {o['H']}, H refused (0.6.2) {o['dropH']}; parse errors {r['stats']['parseErr']}; Lua errors {r['stats']['luaErr']}. "
      f"0.6.4 S sent {r['stats']['s']}, max S size {r['stats']['sMax']} B.")
    P("0.6.2 drops every F/H that carries numbers (F falls back to the seed, H is not counted as heard); 0.6.3 accepts them.")
    P("Custom chat channels: modelled as unused (the addon never sends there). Parties 80% same-realm, guilds same-realm.")
    # --- tuning
    P("\n## Tuning k (entries per S) x top picks\n")
    P(f"Coverage median at day 7 / {a.tune_days}, bytes per online hour, coverage per 100 sent bytes/hour.\n")
    for u in sorted({k[0] for k in tune}):
        P(f"\n**{u} users**\n")
        P(f"| k | top | cov d7 | cov d{a.tune_days} | sent B/h | recv B/h | cov d{a.tune_days} % per 100 B/h |")
        P("|---|---|---|---|---|---|---|")
        bestk, bestcov = None, None
        for k in (3, 4, 5):
            for top in (0, 1, 2):
                r = tune[(u, k, top)]
                d7 = (day(r, 7).get("cov") or [None])[0]
                dn = (day(r, a.tune_days).get("cov") or [None])[0]
                sb = r["bytes"]["sentMean"]
                eff = (dn or 0) * 100 / (sb / 100) if sb else 0
                P(f"| {k} | {top} | {pct(d7, 1)} | {pct(dn, 1)} | {sb:.0f} | {r['bytes']['recvMean']:.0f} | {eff:.2f} |")
                if bestk is None or eff > bestk[0]:
                    bestk = (eff, k, top, dn, sb)
                if bestcov is None or (dn or 0) > bestcov[0]:
                    bestcov = (dn or 0, k, top, sb)
        P(f"\nBest coverage per byte at {u} users: k={bestk[1]}, top={bestk[2]} ({pct(bestk[3], 1)}, {bestk[4]:.0f} B/h). "
          f"Highest coverage: k={bestcov[1]}, top={bestcov[2]} ({pct(bestcov[0], 1)}, {bestcov[3]:.0f} B/h).")
    # --- fakers
    f = fake["fake"]
    P(f"\n## Fakers (report only, {a.chars} users, {a.days} days)\n")
    P(f"{f['fakers']} fakers (1% of 0.6.4 chars); worst case: every F tail and S own entry = the receiver's stored numbers +{f['jump']} "
      f"(the faker knows each receiver), plus 3 real top players in each S at truth +{f['jump']}.\n")
    P(f"- clients holding a faked entry: {f['holders']} of {f['clients']} ({pct(f['holderShare'], 1)}); faked entries total {f['fakedEntries']}")
    P(f"- max over-truth: x{f['maxOverRatio']:.0f} (max absolute +{f['maxOverAbs']}); entries at the cap ({f['cap']}): {f['atCap']}")
    P(f"- share of all `All` sums that is fake: farts {pct(f['fakeShareF'], 1)}, heard {pct(f['fakeShareL'], 1)}")
    P(f"- limits: one message raises a stored number by at most {f['jump']}; nothing goes above {f['cap']}; "
      f"a fake needs {f['cap'] // f['jump']} messages from one sender to reach the cap.")
    (out / "report.md").write_text("\n".join(L) + "\n", encoding="utf8")


def plot(out, main_runs):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, ax = plt.subplots(figsize=(8, 4.5))
    cols = {10: "#7a7a7a", 50: "#1f77b4", 500: "#d62728"}
    for u in sorted(main_runs):
        if u not in cols:
            continue
        xs, med, lo, hi = [], [], [], []
        for d in sorted(int(x) for x in main_runs[u]["days"]):
            c = main_runs[u]["days"][str(d)].get("cov")
            if c and c[0] is not None:
                xs.append(d)
                med.append(100 * c[0])
                lo.append(100 * c[1])
                hi.append(100 * c[2])
        ax.plot(xs, med, color=cols[u], label=f"{u} users (median)")
        ax.fill_between(xs, lo, hi, color=cols[u], alpha=0.18, linewidth=0)
    ax.set_xlabel("day")
    ax.set_ylabel("coverage of heard farts (%)")
    ax.set_title("Board coverage vs days (band = p10-p90 of clients)")
    ax.grid(alpha=0.3)
    ax.legend()
    fig.tight_layout()
    fig.savefig(out / "coverage.png", dpi=130)


MIXES = [("guild 30% / group 40%", 0.3, 0.4), ("guild 90% / group 20%", 0.9, 0.2),
         ("guild 70% / group 10%", 0.7, 0.1), ("guild 10% / group 60%", 0.1, 0.6)]


def bud_cfgs(a):
    """The honest runs of the budget study (timer on = the build): users, press only, seeds, mixes."""
    cps = [d for d in (1, 7, 14, 30, 60) if d <= a.days]
    out = []
    for u in (10, 25, 50, 100, 500):
        out.append((f"u{u}", {"chars": a.chars, "days": a.days, "users": u, "seed": a.seed, "checkpoints": cps, "timer": True}))
    out.append(("u500_press", {"chars": a.chars, "days": a.days, "users": 500, "seed": a.seed, "checkpoints": cps}))
    for sd in (a.seed + 1, a.seed + 2):
        for u in (50, 500):
            out.append((f"u{u}_s{sd}", {"chars": a.chars, "days": a.days, "users": u, "seed": sd, "checkpoints": cps,
                                         "timer": True, "est": False}))
    for name, gs, ps in MIXES:
        out.append((f"mix_g{int(gs * 100)}_p{int(ps * 100)}", {"chars": a.chars, "days": a.days, "users": 500, "seed": a.seed,
                    "checkpoints": [7, 30, 60], "guildShare": gs, "partyShare": ps, "est": False, "timer": True}))
    return out


def main_bud_measure(a):
    """Step 1: the honest need with no budget. need = rise per day since the first sight (+1 day)."""
    out = pathlib.Path(a.out)
    (out / "raw").mkdir(parents=True, exist_ok=True)
    t0 = time.time()
    rows = []
    for key, cfg in bud_cfgs(a):
        r = run_one(dict(cfg, budMeasure=True), out / "raw" / f"measure_{key}.json")
        b = r["bud"]
        rows.append((key, b))
        print(f"{key}: A max {b['needA']['max']:.0f} p999 {b['needA']['p999']:.0f} | B max {b['needB']['max']:.0f} "
              f"p999 {b['needB']['p999']:.0f} | first max {b['first0']['max']:.0f} p999 {b['first0']['p999']:.0f} "
              f"n={b['needB']['n']} caps={b['honestCaps']} {r['seconds']:.0f}s", flush=True)
    summ = {k: {"max": max(b[k]["max"] for _, b in rows), "p999": max(b[k]["p999"] for _, b in rows),
                "p9999": max(b[k]["p9999"] for _, b in rows), "p99": max(b[k]["p99"] for _, b in rows)}
            for k in ("needA", "needB", "first0")}
    (out / "measure.json").write_text(json.dumps({"runs": dict(rows), "all": summ}, indent=1))
    print(json.dumps(summ), flush=True)
    print(f"done in {(time.time() - t0) / 60:.1f} min -> {out}")


def main_bud(a):
    """Step 2: budget on (the build) vs off on the same seeds: honest caps 0 + the same boards; then fakers."""
    out = pathlib.Path(a.out)
    (out / "raw").mkdir(parents=True, exist_ok=True)
    t0 = time.time()
    honest = []
    for key, cfg in bud_cfgs(a):
        off = run_one(dict(cfg, budOff=True), out / "raw" / f"off_{key}.json")
        on = run_one(cfg, out / "raw" / f"on_{key}.json")
        same = off["boardHash"] == on["boardHash"] and json.dumps(off["days"], sort_keys=True) == json.dumps(on["days"], sort_keys=True)
        honest.append((key, off, on, same))
        print(f"{key}: caps {on['bud']['honestCaps']} same={same} pass {on['nPass']}/{on['nPass'] + on['nFail']} "
              f"{off['seconds'] + on['seconds']:.0f}s", flush=True)
    fk = {}
    for mode in ("naive", "hl"):
        cfg = {"chars": a.chars, "days": a.days, "users": a.chars, "seed": a.seed, "fakers": True, "checks": False,
               "est": False, "checkpoints": [7, 14, 30, 60], "timer": True, "fakeMode": mode}
        fk[(mode, "off")] = run_one(dict(cfg, budOff=True), out / "raw" / f"fakers_{mode}_off.json")
        fk[(mode, "on")] = run_one(cfg, out / "raw" / f"fakers_{mode}_on.json")
        print(f"fakers {mode} done", flush=True)
    opt = None
    if a.bud_new:   # the option: a cap on the first sight too (budNew), cost for honest + effect on fakers
        cfg = {"chars": a.chars, "days": a.days, "users": a.chars, "seed": a.seed, "fakers": True, "checks": False,
               "est": False, "checkpoints": [7, 14, 30, 60], "timer": True, "budNew": a.bud_new}
        fo = {m: run_one(dict(cfg, fakeMode=m), out / "raw" / f"fakers_{m}_new.json") for m in ("naive", "hl")}
        hk, hc = next(x for x in bud_cfgs(a) if x[0] == "u500")
        ho = run_one(dict(hc, budNew=a.bud_new), out / "raw" / "opt_new_u500.json")
        off = next(x[1] for x in honest if x[0] == "u500")
        opt = (fo, ho, off)
        print("option first-sight cap done", flush=True)
    total = time.time() - t0
    report_bud(a, out, honest, fk, total, opt)
    print(f"done in {total / 60:.1f} min -> {out}")


def report_bud(a, out, honest, fk, total, opt=None):
    L = ["# Spoken Wind 0.6.4: raise budget study", ""]
    on0 = honest[0][2]["bud"]
    L.append(f"Budget: {on0['cfg']} per day since the first sight, plus one day "
             f"(first sight: {'free, CAP + JUMP only' if on0['new'] == -1 else 'capped at ' + str(on0['new'])}). "
             f"{a.chars} chars, {a.days} days. Run time {total / 60:.1f} min.")
    L += ["", "## Honest runs: budget on vs off (same seed)", "",
          "| run | cuts (honest) | boards same | coverage d7 / d30 / d60 (on) | pass |", "|---|---|---|---|---|"]
    for key, off, on, same in honest:
        d = on["days"]
        cov = " / ".join(pct(d[str(k)]["cov"][0]) if str(k) in d else "-" for k in (7, 30, 60))
        L.append(f"| {key} | {on['bud']['honestCaps']} | {'yes' if same else 'NO'} | {cov} | {on['nPass']}/{on['nPass'] + on['nFail']} |")
    allsame = all(x[3] for x in honest) and all(x[2]["bud"]["honestCaps"] == 0 for x in honest)
    L += ["", f"Honest result: {'0 cuts, boards identical in every run (diff = 0)' if allsame else 'NOT CLEAN: see table'}.", ""]
    L += ["## Fakers (1% of 500 users, timer on; naive = f, h, l + JUMP on every message and + JUMP on the top 3 "
          "honest; hl = only its own h + l + JUMP, the 2 shown lists)", "",
          "| run | fake share F | fake share L | entries at 1,000,000 | max over truth | cuts on fakers | cuts on honest rows | faker in top 10 (d1 / d7 / d30 / d60) | faker #1 (d1 / d7 / d60) |",
          "|---|---|---|---|---|---|---|---|---|"]
    for tag in ("naive", "hl"):
        for st in ("off", "on"):
            r = fk[(tag, st)]
            f = r["fake"]
            fd = {x["day"]: x for x in (r.get("fakeDays") or [])}
            def sh(d, k):
                return pct(fd[d][k]) if d in fd else "-"
            L.append(f"| {tag} budget {st} | {pct(f['fakeShareF'])} | {pct(f['fakeShareL'])} | {f['atCap']} | {f['maxOverAbs']:.0f} | "
                     f"{r['bud']['fakeCaps']} | {r['bud']['honestCaps']} | {sh(1, 'top10')} / {sh(7, 'top10')} / {sh(30, 'top10')} / {sh(60, 'top10')} | "
                     f"{sh(1, 'top1')} / {sh(7, 'top1')} / {sh(60, 'top1')} |")
    L += ["", "Cuts on honest rows in faker runs = the fakers' +JUMP claims on the top 3 honest players, cut by the budget.", ""]
    if opt:
        fo, ho, off = opt
        L += [f"## Option: also cap the first sight at {a.bud_new:,} (not in the build)", "",
              "| run | fake share F | fake share L | entries at 1,000,000 | max over truth | faker in top 10 (d1 / d7 / d30 / d60) | faker #1 (d1 / d7 / d60) |",
              "|---|---|---|---|---|---|---|"]
        for m in ("naive", "hl"):
            r = fo[m]
            f = r["fake"]
            fd = {x["day"]: x for x in (r.get("fakeDays") or [])}
            def sh2(d, k):
                return pct(fd[d][k]) if d in fd else "-"
            L.append(f"| {m} first-sight cap | {pct(f['fakeShareF'])} | {pct(f['fakeShareL'])} | {f['atCap']} | {f['maxOverAbs']:.0f} | "
                     f"{sh2(1, 'top10')} / {sh2(7, 'top10')} / {sh2(30, 'top10')} / {sh2(60, 'top10')} | "
                     f"{sh2(1, 'top1')} / {sh2(7, 'top1')} / {sh2(60, 'top1')} |")
        same = off["boardHash"] == ho["boardHash"]
        L += ["", f"Honest cost (u500, timer, same seed): {ho['bud']['honestCaps']} cuts on honest players, "
              f"boards {'the same' if same else 'DIFFERENT'} vs no budget.", ""]
    (out / "report.md").write_text("\n".join(L) + "\n", encoding="utf-8")


def main_timer(a):
    """The timer S study: every run twice (timer / press only, same seed), more seeds, guild + group mixes."""
    out = pathlib.Path(a.out)
    (out / "raw").mkdir(parents=True, exist_ok=True)
    t0 = time.time()
    cps = [d for d in (1, 7, 14, 30, 60) if d <= a.days]
    users_list = [u for u in (10, 25, 50, 100, 500) if u <= a.chars]
    if a.quick:
        users_list = sorted({10, 50, a.chars})
    base, tim = {}, {}
    for u in users_list:
        cfg = {"chars": a.chars, "days": a.days, "users": u, "seed": a.seed, "checkpoints": cps}
        t = time.time()
        base[u] = run_one(cfg, out / "raw" / f"base_{u}.json")
        tim[u] = run_one(dict(cfg, timer=True), out / "raw" / f"timer_{u}.json")
        print(f"users={u}: {time.time() - t:.0f}s", flush=True)
    extra = {}
    for sd in ([] if a.quick else [a.seed + 1, a.seed + 2]):
        for u in (50, a.chars):
            extra[(u, sd)] = run_one({"chars": a.chars, "days": a.days, "users": u, "seed": sd, "checkpoints": cps,
                                      "timer": True, "est": False}, out / "raw" / f"timer_seed{sd}_{u}.json")
            print(f"seed {sd} users={u} done", flush=True)
    mixes = {}
    mcps = [d for d in (7, 30, 60) if d <= a.days]
    for name, gs, ps in MIXES:
        for u in sorted({50, a.chars}):
            cfg = {"chars": a.chars, "days": a.days, "users": u, "seed": a.seed, "checkpoints": mcps,
                   "guildShare": gs, "partyShare": ps, "est": False}
            key = f"g{int(gs * 100)}_p{int(ps * 100)}_{u}"
            mixes[(name, u)] = (run_one(dict(cfg, checks=False), out / "raw" / f"mix_base_{key}.json"),
                                run_one(dict(cfg, timer=True), out / "raw" / f"mix_timer_{key}.json"))
            print(f"mix {name} users={u} done", flush=True)
    fake = run_one({"chars": a.chars, "days": a.days, "users": a.chars, "seed": a.seed, "fakers": True, "checks": False,
                    "est": False, "checkpoints": [a.days], "timer": True}, out / "raw" / "fakers_timer.json")
    print("fakers done", flush=True)
    total = time.time() - t0
    report_timer(a, out, base, tim, extra, mixes, fake, cps, total)
    plot_timer(out, base, tim)
    print(f"done in {total / 60:.1f} min -> {out}")


def med(r, d):
    return (day(r, d).get("cov") or [None])[0]


def report_timer(a, out, base, tim, extra, mixes, fake, cps, total):
    L = []
    P = L.append
    users = sorted(tim)
    P("# Spoken Wind 0.6.4 board: timer S simulation\n")
    P(f"{a.chars} chars, {a.days} days, seed {a.seed}, k=4 top=2, 2% loss/copy. Real Board.lua. Runtime {total / 60:.1f} min.\n")
    P("Timer model: due = the last S (press or timer) + 300 s + 0-60 s. First one >= 60 s after login (+0-60 s). "
      "A 15 s tick: in combat at a tick (30%) = next tick. Board off = no timer S. GUILD and/or the group "
      "(PARTY/RAID/INSTANCE), one channel per send, alternate when both. No guild + no group = none. "
      "Same BoardS/EncodeS (k=4 top=2), same receive path, no send on receive. "
      "Sessions = whole online hours (60% of accounts play a day, 1-2 sessions of 1-4 h); guild = 70% of chars "
      "(10-40 members, same realm); group = 40% of the online chars each hour (2-5, 80% same realm). "
      "'press' = the same seed without the timer (= sim064).\n")
    # pass / fail
    names = [c[0] for c in tim[users[-1]]["checks"]]
    P("## PASS / FAIL (timer on)\n")
    P("| check | " + " | ".join(f"{u} users" for u in users) + " | other seeds | mixes | press-only runs |")
    P("|---|" + "---|" * (len(users) + 3))
    mixT = [m[1] for m in mixes.values()]
    for n in names:
        row = []
        for u in users:
            c = next((x for x in tim[u]["checks"] if x[0] == n), None)
            row.append("-" if c is None else ("PASS" if c[1] else "FAIL") + ("" if c[2] in (None, "") else f" ({c[2]})"))
        def col(runs):
            v = [passes(r).get(n) for r in runs if n in passes(r)]
            return f"{'PASS' if all(v) else 'FAIL'} ({len(v)} runs)" if v else "-"
        P(f"| {n} | " + " | ".join(row) + f" | {col(extra.values())} | {col(mixT)} | {col(base.values())} |")
    for u in users:
        det = tim[u].get("details") or {}
        for kind, lst in (det.items() if isinstance(det, dict) else []):
            P(f"\n- {u} users, `{kind}`: " + " | ".join(lst))
    # coverage
    P("\n## Coverage: timer median [p10 - p90] (press only median)\n")
    P("Coverage = B.All heard sum / true heard sum over the visible 0.6.4 chars, per client.\n")
    cd = [d for d in (1, 7, 30, 60) if d in cps]
    P("| users | clients | " + " | ".join(f"day {d}" for d in cd) + " |")
    P("|---|---|" + "---|" * len(cd))
    for u in users:
        cells = []
        for d in cd:
            c = day(tim[u], d).get("cov") or [None, None, None]
            cells.append(f"**{pct(c[0], 1)}** [{pct(c[1], 0)} - {pct(c[2], 0)}] ({pct(med(base[u], d), 1)})")
        P(f"| {u} | {tim[u]['world']['clients']} | " + " | ".join(cells) + " |")
    P("\n## Same realm vs cross realm: timer same / cross (press same / cross), median\n")
    dd = [d for d in (7, 30, 60) if d in cps]
    P("| users | " + " | ".join(f"day {d}" for d in dd) + " |")
    P("|---|" + "---|" * len(dd))
    for u in users:
        cells = []
        for d in dd:
            ct, cb = tim[u]["cp"].get(str(d)) or {}, base[u]["cp"].get(str(d)) or {}
            cells.append(f"**{pct(ct.get('same'), 0)}** / {pct(ct.get('cross'), 0)} ({pct(cb.get('same'), 0)} / {pct(cb.get('cross'), 0)})")
        P(f"| {u} | " + " | ".join(cells) + " |")
    # top 10
    P("\n## Realm top 10 known by 90% of the realm's 0.6.4 clients\n")
    P("Per char: the day >= 90% of its realm's clients hold one top-10 char (top 10 by true heard, end of run). "
      "Whole top 10: the day all 10 are held by >= 90% ('-' = not by day " + str(a.days) + ").\n")
    P("| users | per char median day | p90 | reached | whole top 10 per realm (timer) | (press only) |")
    P("|---|---|---|---|---|---|")
    def realms(r):
        return ", ".join(f"R{x['realm']}: {x.get('day', '-')}" for x in (r["top10"].get("realms") or []))
    for u in users:
        t, b = tim[u]["top10"], base[u]["top10"]
        P(f"| {u} | **{t.get('median', '-')}** ({b.get('median', '-')}) | {t.get('p90', '-')} ({b.get('p90', '-')}) | "
          f"{t['reached']}/{t['total']} ({b['reached']}/{b['total']}) | {realms(tim[u])} | {realms(base[u])} |")
    # seen
    P("\n## Seen estimator (default 0.05 / 50), timer on\n")
    P("| users | day | clients | within 10 pts | Seen ? | median error | bias (+ = too high) | press: within 10 / bias |")
    P("|---|---|---|---|---|---|---|---|")
    seen_pass = {}
    for u in users:
        for d in cps:
            if d < 7:
                continue
            g = (tim[u]["cp"].get(str(d)) or {}).get("grid", {}).get("r0.05_w50")
            gb = (base[u]["cp"].get(str(d)) or {}).get("grid", {}).get("r0.05_w50") or {}
            if not g:
                continue
            m = "-" if g.get("med") is None else f"{g.get('med'):.1f}"
            bi = "-" if g.get("bias") is None else f"{g.get('bias'):+.1f}"
            bb = "-" if gb.get("bias") is None else f"{gb.get('bias'):+.1f}"
            P(f"| {u} | {d} | {day(tim[u], d).get('n')} | {pct(g.get('share'))} ({g.get('n')}) | {pct(g.get('qshare'))} | {m} | {bi} | "
              f"{pct(gb.get('share'))} / {bb} |")
            if u in (50, 100, 500) and d == 7:
                seen_pass[u] = g.get("share") is not None and g.get("share") >= 0.9
    keys = list(tim[users[-1]]["cp"][str(cps[0])]["grid"].keys())
    best = None
    for k in keys:
        m7 = [((tim[u]["cp"].get("7") or {}).get("grid", {}).get(k) or {}).get("share") or 0 for u in (50, 100, 500) if u in tim]
        mn = min(m7) if m7 else 0
        if best is None or mn > best[1]:
            best = (k, mn)
    P("\nSeen PASS (day 7, 50/100/500 users, >= 90% within 10 pts): "
      + ", ".join(f"{u}: {'PASS' if v else 'FAIL'}" for u, v in sorted(seen_pass.items()))
      + f". Best grid setting (worst of 50/100/500 at day 7): {best[0]} -> {pct(best[1])}. "
      + ("Passes." if best[1] >= 0.9 else "NO setting reaches 90%: keep \"Seen ?\"."))
    # bytes
    P("\n## Bytes per online hour per 0.6.4 client: timer (press only)\n")
    P("| users | sent mean | F | S press | S timer | H | timer S / h | received mean | received median | received p90 |")
    P("|---|---|---|---|---|---|---|---|---|---|")
    for u in users:
        b, bb = tim[u]["bytes"], base[u]["bytes"]
        P(f"| {u} | **{b['sentMean']:.0f}** ({bb['sentMean']:.0f}) | {b['F']:.0f} | {b['S']:.0f} | {b.get('T', 0):.0f} | {b['H']:.0f} | "
          f"{b.get('tPerHour', 0):.1f} | **{b['recvMean']:.0f}** ({bb['recvMean']:.0f}) | {b['recvMed']:.0f} ({bb['recvMed']:.0f}) | "
          f"{b['recvP90']:.0f} ({bb['recvP90']:.0f}) |")
    # mixes
    P("\n## Guild + group mixes: timer (press only)\n")
    P("| mix | users | cov d7 | cov d30 | cov d60 | sent B/h | recv B/h | timer S / h | checks |")
    P("|---|---|---|---|---|---|---|---|---|")
    for u in sorted({50, a.chars}):
        if u in tim:
            r, rb = tim[u], base[u]
            P(f"| guild 70% / group 40% (default) | {u} | " + " | ".join(
                f"**{pct(med(r, d), 1)}** ({pct(med(rb, d), 1)})" for d in (7, 30, 60)) +
              f" | {r['bytes']['sentMean']:.0f} ({rb['bytes']['sentMean']:.0f}) | {r['bytes']['recvMean']:.0f} "
              f"({rb['bytes']['recvMean']:.0f}) | {r['bytes'].get('tPerHour', 0):.1f} | {r['nPass']} pass, {r['nFail']} fail |")
    for (name, u), (rb, r) in mixes.items():
        P(f"| {name} | {u} | " + " | ".join(f"**{pct(med(r, d), 1)}** ({pct(med(rb, d), 1)})" for d in (7, 30, 60)) +
          f" | {r['bytes']['sentMean']:.0f} ({rb['bytes']['sentMean']:.0f}) | {r['bytes']['recvMean']:.0f} "
          f"({rb['bytes']['recvMean']:.0f}) | {r['bytes'].get('tPerHour', 0):.1f} | {r['nPass']} pass, {r['nFail']} fail |")
    # old clients
    r = tim[users[-1]]
    o = r["stats"]["old"]
    P(f"\n## Old clients, timer on ({users[-1]} users)\n")
    P(f"0.6.2/0.6.3 read {o['S']} S texts (press + timer): misparsed {r['stats']['mis']}, parse errors "
      f"{r['stats']['parseErr']}, Lua errors {r['stats']['luaErr']}. They ignore S. "
      f"0.6.4 S sent {r['stats']['s']} ({r['stats'].get('t', 0)} from the timer), max S size {r['stats']['sMax']} B.")
    # fakers
    f = fake["fake"]
    P(f"\n## Fakers, timer on (report only, {a.chars} users, {a.days} days)\n")
    P(f"{f['fakers']} fakers (1%), worst case as in sim064 (+{f['jump']} per message, cap {f['cap']}).\n")
    P(f"- clients holding a faked entry: {f['holders']} of {f['clients']} ({pct(f['holderShare'], 1)}); faked entries {f['fakedEntries']}")
    P(f"- max over-truth x{f['maxOverRatio']:.0f} (max +{f['maxOverAbs']}); at the cap: {f['atCap']}")
    P(f"- fake share of all `All` sums: farts {pct(f['fakeShareF'], 1)}, heard {pct(f['fakeShareL'], 1)}")
    (out / "report.md").write_text("\n".join(L) + "\n", encoding="utf8")


def plot_timer(out, base, tim):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, ax = plt.subplots(figsize=(8, 4.5))
    cols = {10: "#7a7a7a", 50: "#1f77b4", 500: "#d62728"}
    for u in sorted(tim):
        if u not in cols:
            continue
        for runs, ls, tag in ((tim, "-", "timer"), (base, "--", "press only")):
            xs, md, lo, hi = [], [], [], []
            for d in sorted(int(x) for x in runs[u]["days"]):
                c = runs[u]["days"][str(d)].get("cov")
                if c and c[0] is not None:
                    xs.append(d)
                    md.append(100 * c[0])
                    lo.append(100 * c[1])
                    hi.append(100 * c[2])
            ax.plot(xs, md, color=cols[u], linestyle=ls, label=f"{u} users, {tag}")
            if runs is tim:
                ax.fill_between(xs, lo, hi, color=cols[u], alpha=0.15, linewidth=0)
    ax.set_xlabel("day")
    ax.set_ylabel("coverage of heard farts (%)")
    ax.set_title("Board coverage: timer S (solid, band p10-p90) vs press only (dashed)")
    ax.grid(alpha=0.3)
    ax.legend(fontsize=8)
    fig.tight_layout()
    fig.savefig(out / "coverage.png", dpi=130)


if __name__ == "__main__":
    main()
