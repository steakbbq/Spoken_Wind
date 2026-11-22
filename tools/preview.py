"""Writes preview/index.html: a local page to hear every fart before install.
Plays the real Spoken_Wind/Media/fart/*.ogg files (the ones the game gets).

  python -I tools/preview.py      (run tools/analyze.py first for the numbers)
"""
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import synth  # noqa: E402

ROOT = synth.ROOT
rep = json.loads((ROOT / "build" / "report.json").read_text(encoding="utf-8"))
by = {r["file"][:-4]: r for r in rep["sounds"]}
items = [{"n": i + 1, "stem": stem, "name": name, "sec": by[stem]["seconds"],
          "f0": by[stem]["f0_med"]} for i, (stem, name, _, _) in enumerate(synth.FARTS)]

PAGE = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Spoken Wind check</title>
<style>
:root { --bg:#f6f3ee; --fg:#1d1b18; --mut:#6d665c; --card:#fffdf9; --line:#e4ddd2; --acc:#8a5a00; --bad:#b3261e; }
@media (prefers-color-scheme: dark) { :root { --bg:#16140f; --fg:#efe9df; --mut:#a39a8c; --card:#201d17; --line:#353026; --acc:#f2b84b; --bad:#ff8a80; } }
* { box-sizing:border-box; }
body { margin:0; background:var(--bg); color:var(--fg); font:15px/1.35 system-ui, sans-serif; }
main { max-width:860px; margin:0 auto; padding:20px 16px 40px; }
h1 { font-size:22px; margin:0 0 4px; }
.sub { color:var(--mut); margin:0 0 14px; font-size:13px; }
.bar { display:flex; gap:8px; flex-wrap:wrap; margin-bottom:14px; align-items:center; }
button { font:inherit; border:1px solid var(--line); background:var(--card); color:var(--fg); border-radius:8px; padding:7px 12px; cursor:pointer; }
button:hover { border-color:var(--acc); }
button.on { background:var(--acc); color:var(--bg); border-color:var(--acc); }
.row { display:grid; grid-template-columns:34px 44px 1fr auto; gap:10px; align-items:center; background:var(--card);
       border:1px solid var(--line); border-radius:10px; padding:8px 10px; margin-bottom:6px; }
.row.playing { border-color:var(--acc); }
.row.drop { opacity:.45; }
.num { color:var(--mut); font-variant-numeric:tabular-nums; text-align:right; }
.name b { display:block; }
.name span { color:var(--mut); font-size:12px; }
.spec { height:46px; max-width:100%; border-radius:4px; display:block; margin-top:4px; }
.vote { color:var(--mut); }
.vote.drop { color:var(--bad); border-color:var(--bad); }
#out { color:var(--mut); font-size:13px; min-height:18px; }
code { background:var(--card); border:1px solid var(--line); border-radius:4px; padding:1px 5px; }
</style>
</head>
<body>
<main>
<h1>Spoken Wind · fart check</h1>
<p class="sub">__COUNT__ farts · the real game files · <code>/wind test N</code> plays #N in game</p>
<div class="bar">
  <button id="all">▶ All</button>
  <button id="rnd">🎲 Random</button>
  <button id="stop">■ Stop</button>
  <button id="copy">Copy drops</button>
  <span id="out"></span>
</div>
<div id="list"></div>
</main>
<script>
const ITEMS = __ITEMS__;
const list = document.getElementById("list"), out = document.getElementById("out");
let drops = new Set();
try { drops = new Set(JSON.parse(localStorage.getItem("spokenwind-drops") || "[]")); } catch (e) {}
const save = () => { try { localStorage.setItem("spokenwind-drops", JSON.stringify([...drops])); } catch (e) {} };
let cur = null, queue = [], last = 0;
function stop() {
  queue = [];
  if (cur) { cur.pause(); cur.currentTime = 0; }
  document.querySelectorAll(".row.playing").forEach(r => r.classList.remove("playing"));
}
function play(it, then) {
  if (cur) { cur.pause(); }
  document.querySelectorAll(".row.playing").forEach(r => r.classList.remove("playing"));
  const a = new Audio("../Spoken_Wind/Media/fart/" + it.stem + ".ogg");
  cur = a; last = it.n;
  const row = document.getElementById("r" + it.n);
  row.classList.add("playing");
  out.textContent = "#" + it.n + " " + it.name;
  a.onended = () => { row.classList.remove("playing"); if (then) setTimeout(then, 450); };
  a.play().catch(err => { out.textContent = "can't play: " + err.message; });
}
function next() { const it = queue.shift(); if (it) play(it, next); }
for (const it of ITEMS) {
  const r = document.createElement("div");
  r.className = "row" + (drops.has(it.n) ? " drop" : "");
  r.id = "r" + it.n;
  r.innerHTML = `<div class="num">${it.n}</div><button aria-label="Play ${it.name}">▶</button>
    <div class="name"><b>${it.name}</b><span>${it.sec.toFixed(1)} s${it.f0 ? " · ~" + Math.round(it.f0) + " Hz" : " · noisy"}</span>
    <img class="spec" src="spec/${it.stem}.png" alt=""></div>
    <button class="vote${drops.has(it.n) ? " drop" : ""}" title="Mark to drop">👎</button>`;
  r.children[1].onclick = () => { queue = []; play(it); };
  r.querySelector(".vote").onclick = (e) => {
    drops.has(it.n) ? drops.delete(it.n) : drops.add(it.n);
    e.target.classList.toggle("drop", drops.has(it.n)); r.classList.toggle("drop", drops.has(it.n)); save();
  };
  list.appendChild(r);
}
document.getElementById("all").onclick = () => { stop(); queue = ITEMS.slice(); next(); };
document.getElementById("stop").onclick = () => { stop(); out.textContent = ""; };
document.getElementById("rnd").onclick = () => {   // like the game: never the same one twice in a row
  stop();
  const pool = ITEMS.filter(i => i.n !== last && !drops.has(i.n));
  if (pool.length) play(pool[Math.floor(Math.random() * pool.length)]);
};
document.getElementById("copy").onclick = async () => {
  const t = drops.size ? "Spoken Wind drop: " + [...drops].sort((a, b) => a - b).map(n => "#" + n + " " + ITEMS[n - 1].name).join(", ") : "Spoken Wind: keep all";
  try { await navigator.clipboard.writeText(t); out.textContent = "copied: " + t; } catch (e) { out.textContent = t; }
};
</script>
</body>
</html>
"""

html = PAGE.replace("__ITEMS__", json.dumps(items)).replace("__COUNT__", str(len(items)))
(ROOT / "preview" / "index.html").write_text(html, encoding="utf-8")
print("wrote", ROOT / "preview" / "index.html")
