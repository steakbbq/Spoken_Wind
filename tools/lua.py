"""Lua checks without luac (this PC has none).

Loads the LuaJIT lua51.dll that OBS installs, through ctypes.
  python -I tools/lua.py check   compile-only check of Spoken_Wind/*.lua (no code runs)
  python -I tools/lua.py match   tests/test_match.lua (fart lines, all forms, names, locales)
  python -I tools/lua.py pick    tests/test_pick.lua  (random, never twice in a row)
  python -I tools/lua.py core    tests/test_core.lua  (Core.lua with a fake client)
  python -I tools/lua.py board   tests/test_board.lua (Board.lua: merge, S, Seen, sums; 0.6.4)
  python -I tools/lua.py sim     tests/test_sim.lua   (gossip simulator, small; full run: python tools/sim/run.py)
  python -I tools/lua.py all     check (+ dev/Spoken_Wind_Dev if there) + all tests + the length table
                                 (tools/oglen.py check: Lengths.lua = the ogg files)
LuaJIT is close to, but not the same as, the game's Lua 5.1.
"""
import ctypes
import importlib.util
import os
import pathlib
import sys

# Folder that holds a lua51.dll (LuaJIT). Set LUA51_DLL_DIR to use another one.
DLL_DIR = os.environ.get("LUA51_DLL_DIR", r"C:\Program Files\obs-studio\bin\64bit")
# Linux (CI): LuaJIT shared library, e.g. apt install libluajit-5.1-2. LUA51_LIB sets another file.
SO_NAME = os.environ.get("LUA51_LIB", "libluajit-5.1.so.2")
ROOT = pathlib.Path(__file__).resolve().parent.parent
TESTS = {"match": "test_match.lua", "pick": "test_pick.lua", "core": "test_core.lua", "board": "test_board.lua", "sim": "test_sim.lua"}


def lens(addon=None):
    """tools/oglen.py check on the addon folder (Lengths.lua = the shipped ogg files)."""
    spec = importlib.util.spec_from_file_location("oglen", ROOT / "tools" / "oglen.py")
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m.check(addon or ROOT / "Spoken_Wind")


def lua():
    if sys.platform == "win32":
        os.add_dll_directory(DLL_DIR)
        L = ctypes.CDLL(os.path.join(DLL_DIR, "lua51.dll"))
    else:
        L = ctypes.CDLL(SO_NAME)
    L.luaL_newstate.restype = ctypes.c_void_p
    L.luaL_openlibs.argtypes = [ctypes.c_void_p]
    L.luaL_loadbuffer.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p]
    L.lua_pcall.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int]
    L.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
    L.lua_tolstring.restype = ctypes.c_char_p
    L.lua_close.argtypes = [ctypes.c_void_p]
    return L


def check(L, folder=None):
    bad = 0
    base = folder or ROOT / "Spoken_Wind"
    for f in sorted(base.glob("*.lua")) + sorted(base.glob("UI/*.lua")):   # UI/: the generated screens + Look.lua
        src = f.read_bytes()
        s = L.luaL_newstate()
        rc = L.luaL_loadbuffer(s, src, len(src), ("=" + f.relative_to(base).as_posix()).encode())
        if rc != 0:
            bad += 1
            print("FAIL", L.lua_tolstring(s, -1, None).decode(errors="replace"))
        else:
            print("ok  ", f.relative_to(base).as_posix())
        L.lua_close(s)
    return bad


def test(L, name, addon_dir=None):
    f = ROOT / "tests" / name
    src = (("ROOT=[[" + ROOT.as_posix() + "]] ADDON_DIR=[[" + (addon_dir or (ROOT / "Spoken_Wind")).as_posix()
            + "]] ").encode() + f.read_bytes())
    s = L.luaL_newstate()
    L.luaL_openlibs(s)
    rc = L.luaL_loadbuffer(s, src, len(src), ("=" + name).encode())
    if rc == 0:
        rc = L.lua_pcall(s, 0, 0, 0)
    if rc != 0:
        print("FAIL", L.lua_tolstring(s, -1, None).decode(errors="replace"))
    L.lua_close(s)
    return 1 if rc != 0 else 0


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "check"
    addon = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else None   # e.g. stage\Spoken_Wind
    Lh = lua()
    if mode == "check":
        n = check(Lh, addon)
    elif mode in TESTS:
        n = test(Lh, TESTS[mode], addon)
    elif mode == "all":
        dev = ROOT / "dev" / "Spoken_Wind_Dev"   # private repo only
        n = (check(Lh, addon) + (check(Lh, dev) if dev.is_dir() else 0)
             + sum(test(Lh, t, addon) for t in TESTS.values()) + lens(addon))
    else:
        print(__doc__)
        n = 1
    sys.exit(1 if n else 0)
