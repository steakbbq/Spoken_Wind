"""Lua checks without luac (this PC has none).

Loads the LuaJIT lua51.dll that OBS installs, through ctypes.
  python -I tools/lua.py check   compile-only check of Spoken_Wind/*.lua (no code runs)
  python -I tools/lua.py match   tests/test_match.lua (fart lines, all forms, names, locales)
  python -I tools/lua.py pick    tests/test_pick.lua  (random, never twice in a row)
  python -I tools/lua.py core    tests/test_core.lua  (Core.lua with a fake client)
  python -I tools/lua.py all     check + all tests
LuaJIT is close to, but not the same as, the game's Lua 5.1.
"""
import ctypes
import os
import pathlib
import sys

# Folder that holds a lua51.dll (LuaJIT). Set LUA51_DLL_DIR to use another one.
DLL_DIR = os.environ.get("LUA51_DLL_DIR", r"C:\Program Files\obs-studio\bin\64bit")
ROOT = pathlib.Path(__file__).resolve().parent.parent
TESTS = {"match": "test_match.lua", "pick": "test_pick.lua", "core": "test_core.lua"}


def lua():
    os.add_dll_directory(DLL_DIR)
    L = ctypes.CDLL(os.path.join(DLL_DIR, "lua51.dll"))
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
    for f in sorted((folder or ROOT / "Spoken_Wind").glob("*.lua")):
        src = f.read_bytes()
        s = L.luaL_newstate()
        rc = L.luaL_loadbuffer(s, src, len(src), ("=" + f.name).encode())
        if rc != 0:
            bad += 1
            print("FAIL", L.lua_tolstring(s, -1, None).decode(errors="replace"))
        else:
            print("ok  ", f.name)
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
        n = check(Lh, addon) + sum(test(Lh, t, addon) for t in TESTS.values())
    else:
        print(__doc__)
        n = 1
    sys.exit(1 if n else 0)
