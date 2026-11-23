"""Tests for tools/release.py: toc, changelog, zip, and the CurseForge calls against a fake local server.

    python -I -m unittest discover -s tests -p test_release.py -v
"""
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import threading
import unittest
import zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).resolve().parent
TOOLS = HERE.parent / "tools"
sys.path.insert(0, str(TOOLS))
import release  # noqa: E402

TOKEN = "tok-SECRET-1234567890"
LUA = b"-- fake addon\nprint('hi')\n"
CHANGELOG = """# Changelog

## 0.7.0 [release]
- Route name is the Race voices plus #N.
- Rarity ladder.

## 0.6.9 [beta]
- Shown guide name.

## 0.6.8 [alpha]
- First build.
"""


def make_repo(tmp, version="0.7.0", interface="16001", changelog=CHANGELOG, lua=LUA, extra=True):
    root = Path(tmp)
    (root / "Spoken_Wind").mkdir(parents=True, exist_ok=True)
    toc = ("## Interface: %s\n## Title: Spoken Wind\n## Version: %s\n## SavedVariables: SpokenWindDB\n\nCore.lua\n"
           % (interface, version))
    (root / "Spoken_Wind" / "Spoken_Wind.toc").write_bytes(toc.encode())
    (root / "Spoken_Wind" / "Core.lua").write_bytes(lua)
    if extra:
        (root / "Spoken_Wind" / "Media").mkdir(exist_ok=True)
        (root / "Spoken_Wind" / "Media" / "a.ogg").write_bytes(b"OggS\x00\x01\x02")
        # never in the public zip: the private dev addon folder (stage.py does not read it) and its stage
        (root / "dev" / "Spoken_Wind_Dev").mkdir(parents=True, exist_ok=True)
        (root / "dev" / "Spoken_Wind_Dev" / "Dev.lua").write_bytes(b"-- dev\n")
    if changelog is not None:
        (root / "CHANGELOG.md").write_text(changelog, encoding="utf-8")
    return root


class Fake(ThreadingHTTPServer):
    def __init__(self):
        super().__init__(("127.0.0.1", 0), Handler)
        self.token = TOKEN
        self.requests = []
        self.reset()

    def reset(self):
        self.versions = [
            {"id": 111, "gameVersionTypeID": 517, "name": "1.60.1"},          # retail type, same name: must NOT be used
            {"id": 777, "gameVersionTypeID": release.FOREVER_TYPE_ID, "name": "1.60.1"},
            {"id": 778, "gameVersionTypeID": release.FOREVER_TYPE_ID, "name": "1.60.2"},
        ]
        self.upload_status = 200
        self.upload_body = {"id": 4242}
        self.requests = []


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, obj):
        raw = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def _record(self, body=b""):
        self.server.requests.append({"method": self.command, "path": self.path, "headers": dict(self.headers), "body": body})

    def do_GET(self):
        self._record()
        if self.headers.get("X-Api-Token") != self.server.token:
            return self._send(401, {"errorCode": 401, "errorMessage": "You must provide an API token"})
        if self.path == "/api/game/wow/versions":
            return self._send(200, self.server.versions)
        self._send(404, {"errorCode": 404, "errorMessage": "nope"})

    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(n)
        self._record(body)
        if self.headers.get("X-Api-Token") != self.server.token:
            return self._send(401, {"errorCode": 401, "errorMessage": "bad token"})
        if not re.fullmatch(r"/api/projects/\d+/upload-file", self.path):
            return self._send(404, {"errorCode": 404})
        if self.server.upload_status != 200:
            # a hostile or careless server that echoes the token back
            return self._send(self.server.upload_status, {"errorMessage": "failed for token " + TOKEN})
        self._send(200, self.server.upload_body)


def run_cli(root, args, token=TOKEN, extra_env=None):
    env = dict(os.environ)
    env.pop("CF_API_KEY", None)
    env.pop("CF_PROJECT_ID", None)
    if token is not None:
        env["CF_API_KEY"] = token
    env.update(extra_env or {})
    p = subprocess.run([sys.executable, "-I", str(TOOLS / "release.py"), "--root", str(root)] + args,
                       capture_output=True, text=True, env=env, timeout=60)
    return p.returncode, p.stdout, p.stderr


class Pure(unittest.TestCase):
    def test_toc(self):
        with tempfile.TemporaryDirectory() as t:
            root = make_repo(t, interface="16001, 16002, 16003")
            self.assertEqual(release.toc_version(root), "0.7.0")
            self.assertEqual(release.wanted_game_versions(root), ["1.60.1"])
            root = make_repo(t, version="1.2")
            with self.assertRaises(release.ReleaseError):
                release.toc_version(root)

    def test_constants(self):
        self.assertEqual(release.PROJECT_ID, "1823255")
        self.assertEqual(release.ADDON, "Spoken_Wind")

    def test_top_changelog_section_must_match_the_toc(self):
        with tempfile.TemporaryDirectory() as t:
            root = make_repo(t, version="0.6.9")      # the section exists, but it is not the top one
            with self.assertRaises(release.ReleaseError) as cm:
                release.check(root)
            self.assertIn("top CHANGELOG.md section", str(cm.exception))

    def test_a_version_bump_needs_no_pipeline_edit(self):
        with tempfile.TemporaryDirectory() as t:
            root = make_repo(t, version="0.8.0", changelog="## 0.8.0 [beta]\n- next\n\n" + CHANGELOG.split("\n", 2)[2])
            info = release.check(root, "v0.8.0")
            self.assertEqual((info["version"], info["type"], info["changelog"]), ("0.8.0", "beta", "- next"))

    def test_changelog_sections(self):
        with tempfile.TemporaryDirectory() as t:
            root = make_repo(t)
            kind, body = release.changelog_section(root, "0.7.0")
            self.assertEqual(kind, "release")
            self.assertIn("Race voices", body)
            self.assertNotIn("Shown guide name", body)          # stops at the next section
            self.assertEqual(release.changelog_section(root, "0.6.9")[0], "beta")
            self.assertEqual(release.changelog_section(root, "0.6.8")[0], "alpha")

    def test_changelog_header_forms(self):
        with tempfile.TemporaryDirectory() as t:
            root = make_repo(t, changelog="## v0.7.0 [Beta]\n- x\n")
            self.assertEqual(release.changelog_section(root, "0.7.0"), ("beta", "- x"))

    def test_changelog_errors(self):
        with tempfile.TemporaryDirectory() as t:
            for text, why in [
                ("## 0.6.9 [release]\n- x\n", "other version on top"),
                ("## 0.7.0\n- x\n", "no release type"),
                ("## 0.7.0 [stable]\n- x\n", "unknown release type"),
                ("## 0.7.0 [release]\n\n## 0.6.9 [release]\n- x\n", "empty section"),
            ]:
                root = make_repo(t, changelog=text)
                with self.assertRaises(release.ReleaseError, msg=why):
                    release.changelog_section(root, "0.7.0")
            root = make_repo(t, changelog=None)
            (Path(t) / "CHANGELOG.md").unlink(missing_ok=True)
            with self.assertRaises(release.ReleaseError):
                release.changelog_section(root, "0.7.0")

    def test_check_tag(self):
        with tempfile.TemporaryDirectory() as t:
            root = make_repo(t)
            self.assertEqual(release.check(root, "v0.7.0")["type"], "release")
            self.assertEqual(release.check(root)["version"], "0.7.0")
            with self.assertRaises(release.ReleaseError):
                release.check(root, "v0.7.1")
            with self.assertRaises(release.ReleaseError):
                release.check(root, "0.7.0")

    def test_match_versions_uses_the_forever_type_only(self):
        vs = [{"id": 1, "gameVersionTypeID": 517, "name": "1.60.1"},
              {"id": 2, "gameVersionTypeID": release.FOREVER_TYPE_ID, "name": "1.60.2"}]
        ids, missing, elsewhere = release.match_versions(vs, ["1.60.1", "1.60.2"])
        self.assertEqual(ids, [2])
        self.assertEqual(missing, ["1.60.1"])
        self.assertEqual([v["id"] for v in elsewhere], [1])

    def test_scrub(self):
        self.assertEqual(release.scrub("a %s b" % TOKEN, TOKEN), "a *** b")
        self.assertEqual(release.scrub("a b", ""), "a b")


class Build(unittest.TestCase):
    def test_zip_layout_and_bytes(self):
        with tempfile.TemporaryDirectory() as t:
            root = make_repo(t)
            zip_path, manifest = release.build(root, Path(t) / "dist")
            self.assertEqual(zip_path.name, "Spoken_Wind-0.7.0.zip")
            with zipfile.ZipFile(zip_path) as z:
                self.assertEqual(sorted(z.namelist()),
                                 ["Spoken_Wind/Core.lua", "Spoken_Wind/Media/a.ogg", "Spoken_Wind/Spoken_Wind.toc"])
                self.assertEqual(z.read("Spoken_Wind/Core.lua"), LUA.replace(b"\n", b"\r\n"))   # stage.py: CRLF
                self.assertEqual(z.read("Spoken_Wind/Media/a.ogg"), b"OggS\x00\x01\x02")
                self.assertIsNone(z.testzip())
            self.assertEqual(len(manifest), 3)
            md5 = (root / "stage" / "MANIFEST.md5").read_text(encoding="utf-8")
            self.assertIn(hashlib.md5(b"OggS\x00\x01\x02").hexdigest() + " *Media/a.ogg", md5)

    def test_no_dev_files_in_the_zip(self):
        with tempfile.TemporaryDirectory() as t:
            root = make_repo(t)
            zip_path, _ = release.build(root, Path(t) / "dist")
            with zipfile.ZipFile(zip_path) as z:
                for n in z.namelist():
                    self.assertTrue(n.startswith("Spoken_Wind/"), n)
                    self.assertNotIn("Dev", n)
                    self.assertNotIn("dev/", n)

    def test_zip_is_the_same_every_time(self):
        with tempfile.TemporaryDirectory() as t:
            root = make_repo(t)
            a, _ = release.build(root, Path(t) / "d1")
            b, _ = release.build(root, Path(t) / "d2")
            self.assertEqual(a.read_bytes(), b.read_bytes())

    def test_verify_fails_on_a_changed_file(self):
        with tempfile.TemporaryDirectory() as t:
            root = make_repo(t)
            zip_path, manifest = release.build(root, Path(t) / "dist")
            bad = Path(t) / "bad.zip"
            with zipfile.ZipFile(zip_path) as zin, zipfile.ZipFile(bad, "w") as zout:
                for n in zin.namelist():
                    zout.writestr(n, zin.read(n) + (b"x" if n.endswith("Core.lua") else b""))
            with self.assertRaises(release.ReleaseError) as cm:
                release.verify_zip(bad, manifest, "0.7.0")
            self.assertIn("Spoken_Wind/Core.lua", str(cm.exception))

    def test_verify_fails_on_an_extra_or_dev_file(self):
        with tempfile.TemporaryDirectory() as t:
            root = make_repo(t)
            zip_path, manifest = release.build(root, Path(t) / "dist")
            for extra in ("Spoken_Wind_Dev/Dev.lua", "Spoken_Wind/DevTools.lua", "tools/release.py", "Spoken_Wind/dev/x.lua"):
                bad = Path(t) / "bad.zip"
                with zipfile.ZipFile(zip_path) as zin, zipfile.ZipFile(bad, "w") as zout:
                    for n in zin.namelist():
                        zout.writestr(n, zin.read(n))
                    zout.writestr(extra, b"x")
                with self.assertRaises(release.ReleaseError, msg=extra):
                    release.verify_zip(bad, manifest, "0.7.0")

    def test_verify_fails_on_a_missing_file(self):
        with tempfile.TemporaryDirectory() as t:
            root = make_repo(t)
            zip_path, manifest = release.build(root, Path(t) / "dist")
            bad = Path(t) / "bad.zip"
            with zipfile.ZipFile(zip_path) as zin, zipfile.ZipFile(bad, "w") as zout:
                for n in zin.namelist():
                    if not n.endswith(".ogg"):
                        zout.writestr(n, zin.read(n))
            with self.assertRaises(release.ReleaseError):
                release.verify_zip(bad, manifest, "0.7.0")

    def test_verify_fails_on_another_toc_version(self):
        with tempfile.TemporaryDirectory() as t:
            root = make_repo(t)
            zip_path, manifest = release.build(root, Path(t) / "dist")
            with self.assertRaises(release.ReleaseError):
                release.verify_zip(zip_path, manifest, "0.7.1")

    def test_build_stops_when_the_dev_flag_is_on(self):
        with tempfile.TemporaryDirectory() as t:
            root = make_repo(t, lua=b"SPOKEN_WIND_DEV = true\n")
            with self.assertRaises(Exception):
                release.build(root, Path(t) / "dist")
            self.assertFalse((Path(t) / "dist" / "Spoken_Wind-0.7.0.zip").exists())

    def test_cli_build(self):
        with tempfile.TemporaryDirectory() as t:
            root = make_repo(t)
            code, out, err = run_cli(root, ["build", "--out", str(Path(t) / "dist")], token=None)
            self.assertEqual(code, 0, err)
            self.assertIn("built", out)
            self.assertIn("same md5 as stage/MANIFEST.md5", out)

    def test_cli_check_with_tag(self):
        with tempfile.TemporaryDirectory() as t:
            root = make_repo(t)
            self.assertEqual(run_cli(root, ["check", "--tag", "v0.7.0"], token=None)[0], 0)
            self.assertEqual(run_cli(root, ["check", "--tag", "v0.7.1"], token=None)[0], 1)

    def test_the_real_toc_has_no_x_lines(self):
        toc = (HERE.parent / "Spoken_Wind" / "Spoken_Wind.toc").read_text(encoding="utf-8")
        self.assertIsNone(re.search(r"^##\s*X-", toc, re.M))


class CurseForge(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.srv = Fake()
        cls.site = "http://127.0.0.1:%d" % cls.srv.server_address[1]
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()
        cls.srv.server_close()

    def setUp(self):
        self.srv.reset()
        self.tmp = tempfile.TemporaryDirectory()
        self.root = make_repo(self.tmp.name)
        self.zip, _ = release.build(self.root, Path(self.tmp.name) / "dist")

    def tearDown(self):
        self.tmp.cleanup()

    def assert_no_token(self, *texts):
        for t in texts:
            self.assertNotIn(TOKEN, t)

    def test_versions_match(self):
        code, out, err = run_cli(self.root, ["versions", "--site", self.site])
        self.assertEqual(code, 0, err)
        self.assertIn("match 1.60.1 -> id 777", out)
        self.assertNotIn("id 111", out)
        self.assert_no_token(out, err)
        self.assertEqual(self.srv.requests[0]["headers"].get("X-Api-Token"), TOKEN)

    def test_versions_no_exact_match_fails_and_guesses_nothing(self):
        self.srv.versions = [{"id": 111, "gameVersionTypeID": 517, "name": "1.60.1"},
                             {"id": 900, "gameVersionTypeID": release.FOREVER_TYPE_ID, "name": "1.59.9"}]
        code, out, err = run_cli(self.root, ["versions", "--site", self.site])
        self.assertEqual(code, 1)
        self.assertIn("Nothing is guessed", err)
        self.assertIn("1.59.9=900", out)                         # lists what exists
        self.assertIn("other type (NOT used)", out)
        self.assert_no_token(out, err)

    def test_versions_without_token(self):
        code, out, err = run_cli(self.root, ["versions", "--site", self.site], token=None)
        self.assertEqual(code, 1)
        self.assertIn("CF_API_KEY is not set", err)
        code, out, err = run_cli(self.root, ["versions", "--site", self.site, "--skip-if-no-token"], token=None)
        self.assertEqual(code, 0)
        self.assertIn("skipped", out)
        self.assertEqual(self.srv.requests, [])

    def test_wrong_token(self):
        code, out, err = run_cli(self.root, ["versions", "--site", self.site], token="other-token")
        self.assertEqual(code, 1)
        self.assertIn("HTTP 401", err)

    def test_upload_dry_run_sends_nothing(self):
        code, out, err = run_cli(self.root, ["upload", "--dry-run", "--zip", str(self.zip), "--project-id", "123",
                                             "--tag", "v0.7.0", "--site", self.site], token=None)
        self.assertEqual(code, 0, err)
        self.assertIn("dry run", out)
        self.assertIn('"releaseType": "release"', out)
        self.assertIn("Race voices", out)
        self.assertEqual(self.srv.requests, [])

    def test_upload_dry_run_with_token_reads_only(self):
        code, out, err = run_cli(self.root, ["upload", "--dry-run", "--zip", str(self.zip), "--project-id", "123",
                                             "--site", self.site])
        self.assertEqual(code, 0, err)
        self.assertIn("777", out)
        self.assertEqual([r["method"] for r in self.srv.requests], ["GET"])
        self.assert_no_token(out, err)

    def test_upload(self):
        code, out, err = run_cli(self.root, ["upload", "--zip", str(self.zip), "--project-id", "123",
                                             "--tag", "v0.7.0", "--site", self.site])
        self.assertEqual(code, 0, err)
        self.assertIn("CurseForge file id 4242", out)
        self.assert_no_token(out, err)
        posts = [r for r in self.srv.requests if r["method"] == "POST"]
        self.assertEqual(len(posts), 1)
        post = posts[0]
        self.assertEqual(post["path"], "/api/projects/123/upload-file")
        self.assertEqual(post["headers"].get("X-Api-Token"), TOKEN)
        self.assertTrue(post["headers"]["Content-Type"].startswith("multipart/form-data; boundary="))
        body = post["body"]
        m = re.search(rb'name="metadata"\r\n\r\n(\{.*?\})\r\n--', body, re.S)
        self.assertIsNotNone(m)
        meta = json.loads(m.group(1))
        self.assertEqual(meta["gameVersions"], [777])
        self.assertEqual(meta["releaseType"], "release")
        self.assertEqual(meta["changelogType"], "markdown")
        self.assertEqual(meta["displayName"], "Spoken Wind 0.7.0")
        self.assertIn("Race voices", meta["changelog"])
        self.assertNotIn("Shown guide name", meta["changelog"])
        self.assertIn(b'name="file"; filename="Spoken_Wind-0.7.0.zip"', body)
        self.assertIn(self.zip.read_bytes(), body)
        self.assertNotIn(TOKEN.encode(), body)                   # the token is only in the header

    def test_upload_error_body_is_scrubbed(self):
        self.srv.upload_status = 500
        code, out, err = run_cli(self.root, ["upload", "--zip", str(self.zip), "--project-id", "123", "--site", self.site])
        self.assertEqual(code, 1)
        self.assertIn("HTTP 500", err)
        self.assertIn("***", err)
        self.assert_no_token(out, err)

    def test_upload_no_game_version_sends_nothing(self):
        self.srv.versions = [{"id": 111, "gameVersionTypeID": 517, "name": "1.60.1"}]
        code, out, err = run_cli(self.root, ["upload", "--zip", str(self.zip), "--project-id", "123", "--site", self.site])
        self.assertEqual(code, 1)
        self.assertEqual([r["method"] for r in self.srv.requests], ["GET"])

    def test_upload_refuses_bad_input(self):
        base = ["upload", "--zip", str(self.zip), "--site", self.site]
        code, out, err = run_cli(self.root, base + ["--project-id", ""])
        self.assertEqual(code, 1)
        self.assertIn("project id", err)
        code, out, err = run_cli(self.root, base + ["--project-id", "abc"])
        self.assertEqual(code, 1)
        code, out, err = run_cli(self.root, base + ["--project-id", "123", "--tag", "v9.9.9"])
        self.assertEqual(code, 1)
        self.assertIn("does not match", err)
        code, out, err = run_cli(self.root, ["upload", "--zip", str(Path(self.tmp.name) / "Spoken_Wind-9.9.9.zip"),
                                             "--project-id", "123", "--site", self.site])
        self.assertEqual(code, 1)
        code, out, err = run_cli(self.root, ["upload", "--zip", str(self.zip), "--project-id", "123"], token=None)
        self.assertEqual(code, 1)
        self.assertIn("CF_API_KEY is not set", err)
        self.assertEqual(self.srv.requests, [])

    def test_token_goes_only_to_curseforge(self):
        code, out, err = run_cli(self.root, ["versions", "--site", "https://example.com"])
        self.assertEqual(code, 1)
        self.assertIn("refusing to send the token", err)
        self.assert_no_token(out, err)


if __name__ == "__main__":
    unittest.main()
