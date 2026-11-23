#!/usr/bin/env python3
"""Spoken Wind release helper. Python 3 standard library only.

    python tools/release.py check    [--tag vX.Y.Z]
    python tools/release.py build    [--out dist]
    python tools/release.py versions [--skip-if-no-token] [--site URL]
    python tools/release.py upload   --zip FILE [--tag vX.Y.Z] [--dry-run] [--site URL]

check     tag, `## Version:` in Spoken_Wind/Spoken_Wind.toc and the TOP CHANGELOG.md section must all agree.
build     runs tools/stage.py, then dist/Spoken_Wind-<version>.zip from stage/Spoken_Wind (top folder Spoken_Wind/,
          fixed time stamps), then checks the zip against stage/MANIFEST.md5 (file count, every md5, no "Dev"
          in any name, toc version). Any mismatch fails.
versions  look up the CurseForge game version "1.60.1" (WoW Forever type) by name; exit 1 when there is no exact match.
upload    send the zip to CurseForge (game version id found by name at run time, never guessed).

The API token is read only from the environment variable CF_API_KEY. It is never printed.
Any text from the server is scrubbed of the token before it is printed.
"""
import argparse
import contextlib
import hashlib
import importlib.util
import io
import json
import os
import re
import sys
import urllib.error
import urllib.request
import uuid
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOOLS = ROOT / "tools"
ADDON = "Spoken_Wind"
# CurseForge project id (public: it is in the project page URL)
PROJECT_ID = "1823255"
# WoW Forever game version, looked up by NAME inside the Forever type (never by a guessed id)
GAME_VERSIONS = ["1.60.1"]
SITE = "https://wow.curseforge.com"
# CurseForge gameVersionTypeID of the WoW Forever flavor (the id BigWigsMods/packager uses for "forever")
FOREVER_TYPE_ID = 88568
RELEASE_TYPES = ("release", "beta", "alpha")
TIMEOUT = 60


HEADER = r"^##\s+v?(\d+\.\d+\.\d+)\s*(?:\[\s*([A-Za-z]+)\s*\])?\s*$"


class ReleaseError(Exception):
    pass


# --------------------------------------------------------------------------- toc, changelog


def toc_fields(root):
    path = Path(root) / ADDON / (ADDON + ".toc")
    if not path.is_file():
        raise ReleaseError("missing %s" % path)
    fields = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^##\s*([A-Za-z0-9_-]+)\s*:\s*(.*?)\s*$", line)
        if m:
            fields[m.group(1)] = m.group(2)
    return fields


def toc_version(root):
    v = toc_fields(root).get("Version", "")
    if not re.fullmatch(r"\d+\.\d+\.\d+", v):
        raise ReleaseError("toc Version %r is not X.Y.Z" % v)
    return v


def wanted_game_versions(root):
    return list(GAME_VERSIONS)


def changelog_top_version(root):
    path = Path(root) / "CHANGELOG.md"
    if not path.is_file():
        raise ReleaseError("missing CHANGELOG.md")
    for line in path.read_text(encoding="utf-8").splitlines():
        if re.match(r"^##\s", line):
            m = re.match(HEADER, line)
            return m.group(1) if m else "unreadable (%s)" % line.strip()
    return "missing"


def changelog_section(root, version):
    """(release type, markdown body) of the CHANGELOG.md section `## X.Y.Z [release|beta|alpha]`."""
    path = Path(root) / "CHANGELOG.md"
    if not path.is_file():
        raise ReleaseError("missing CHANGELOG.md")
    lines = path.read_text(encoding="utf-8").splitlines()
    start = None
    kind = None
    for i, line in enumerate(lines):
        m = re.match(HEADER, line)
        if m and m.group(1) == version:
            start, kind = i, (m.group(2) or "").lower()
            break
    if start is None:
        raise ReleaseError("CHANGELOG.md has no section '## %s [release|beta|alpha]'" % version)
    if kind not in RELEASE_TYPES:
        raise ReleaseError("CHANGELOG.md section %s needs a release type: [release], [beta] or [alpha]" % version)
    body = []
    for line in lines[start + 1:]:
        if re.match(r"^##\s", line):
            break
        body.append(line)
    text = "\n".join(body).strip()
    if not text:
        raise ReleaseError("CHANGELOG.md section %s is empty" % version)
    return kind, text


def check(root, tag=None):
    version = toc_version(root)
    if tag is not None and tag != "v" + version:
        raise ReleaseError("tag %s does not match toc Version %s (expected v%s)" % (tag, version, version))
    top = changelog_top_version(root)
    if top != version:
        raise ReleaseError("the top CHANGELOG.md section is %s, the toc Version is %s" % (top, version))
    kind, body = changelog_section(root, version)
    return {"version": version, "type": kind, "changelog": body, "game_versions": wanted_game_versions(root)}


# --------------------------------------------------------------------------- build


def md5_bytes(data):
    return hashlib.md5(data).hexdigest()


def load_stage_tool():
    spec = importlib.util.spec_from_file_location("sw_stage", TOOLS / "stage.py")
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def run_stage(root):
    """tools/stage.py build() on root/Spoken_Wind -> root/stage/Spoken_Wind + stage/MANIFEST.md5 (public part only)."""
    root = Path(root)
    stage = load_stage_tool()
    with contextlib.redirect_stdout(io.StringIO()):
        stage.build(root / ADDON, root / "stage" / ADDON)
    for f in (root / "stage" / ADDON).rglob("*"):
        if f.suffix in (".lua", ".toc") and re.search(rb"SPOKEN_WIND_DEV\s*=[^=]", f.read_bytes()):
            raise ReleaseError("dev flag set in %s" % f.name)


def stage_manifest(root):
    path = Path(root) / "stage" / "MANIFEST.md5"
    if not path.is_file():
        raise ReleaseError("missing stage/MANIFEST.md5")
    out = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^([0-9a-f]{32}) \*(.+)$", line.strip())
        if m:
            out["%s/%s" % (ADDON, m.group(2))] = m.group(1)
    if not out:
        raise ReleaseError("stage/MANIFEST.md5 is empty")
    return out


def verify_zip(zip_path, manifest, version):
    """Fail hard unless the zip holds exactly the manifest files, with the same md5, and nothing from Dev."""
    tocname = "%s/%s.toc" % (ADDON, ADDON)
    with zipfile.ZipFile(zip_path) as z:
        if z.testzip() is not None:
            raise ReleaseError("zip is corrupt")
        names = z.namelist()
        got = {n: md5_bytes(z.read(n)) for n in names if not n.endswith("/")}
        toc = z.read(tocname).decode("utf-8") if tocname in got else ""
    if len(names) != len(set(names)):
        raise ReleaseError("zip has duplicate names")
    bad = [n for n in names if not n.startswith(ADDON + "/") or "Dev" in n
           or re.search(r"(^|/)(dev|tests|tools)(/|$)", n)]
    if bad:
        raise ReleaseError("files that must not be in the zip: %s" % ", ".join(bad[:5]))
    if len(got) != len(manifest):
        raise ReleaseError("zip has %d files, MANIFEST.md5 has %d" % (len(got), len(manifest)))
    diff = ["  %s: manifest %s, zip %s" % (k, manifest.get(k), got.get(k))
            for k in sorted(set(manifest) | set(got)) if manifest.get(k) != got.get(k)]
    if diff:
        raise ReleaseError("zip does not match stage/MANIFEST.md5:\n%s" % "\n".join(diff[:20]))
    m = re.search(r"^##\s*Version\s*:\s*(\S+)\s*$", toc, re.M)
    if not m or m.group(1) != version:
        raise ReleaseError("toc inside the zip has Version %s, expected %s" % (m.group(1) if m else "none", version))


def build(root, out_dir, stage=True):
    root = Path(root)
    version = toc_version(root)
    if stage:
        run_stage(root)
    manifest = stage_manifest(root)
    base = root / "stage" / ADDON
    files = sorted(p for p in base.rglob("*") if p.is_file())
    if not files:
        raise ReleaseError("stage/%s has no files" % ADDON)
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    zip_path = out_dir / ("%s-%s.zip" % (ADDON, version))
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
        for p in files:
            info = zipfile.ZipInfo("%s/%s" % (ADDON, p.relative_to(base).as_posix()), date_time=(2020, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            z.writestr(info, p.read_bytes())
    try:
        verify_zip(zip_path, manifest, version)
    except ReleaseError:
        zip_path.unlink()
        raise
    return zip_path, manifest


# --------------------------------------------------------------------------- CurseForge


def scrub(text, token):
    text = str(text)
    if token:
        text = text.replace(token, "***")
    return text


def http(method, url, token, data=None, headers=None):
    # the token goes only to CurseForge (or a local test server), never to another host
    if not (url.startswith(SITE + "/") or url.startswith("http://127.0.0.1:") or url.startswith("http://localhost:")):
        raise ReleaseError("refusing to send the token to %s" % url.split("/api/")[0])
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("X-Api-Token", token)
    req.add_header("Accept", "application/json")
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")
        raise ReleaseError("HTTP %d from %s: %s" % (e.code, method + " " + scrub(url, token), scrub(body, token)[:400]))
    except urllib.error.URLError as e:
        raise ReleaseError("cannot reach %s: %s" % (scrub(url, token), scrub(e.reason, token)))


def fetch_versions(site, token):
    status, body = http("GET", site + "/api/game/wow/versions", token)
    try:
        data = json.loads(body)
    except ValueError:
        raise ReleaseError("game versions answer is not JSON")
    if not isinstance(data, list):
        raise ReleaseError("game versions answer is not a list")
    return data


def match_versions(all_versions, wanted, type_id=FOREVER_TYPE_ID):
    """(ids, missing, same_name_other_type): exact name inside the WoW Forever type only."""
    ids, missing, elsewhere = [], [], []
    for name in wanted:
        hit = [v for v in all_versions if v.get("gameVersionTypeID") == type_id and v.get("name") == name]
        if hit:
            ids.append(hit[0]["id"])
        else:
            missing.append(name)
            elsewhere += [v for v in all_versions if v.get("name") == name]
    return ids, missing, elsewhere


def need_token(skip_ok=False):
    token = os.environ.get("CF_API_KEY", "").strip()
    if not token and not skip_ok:
        raise ReleaseError("CF_API_KEY is not set")
    return token


def cmd_versions(args):
    root = Path(args.root)
    wanted = wanted_game_versions(root)
    token = need_token(skip_ok=args.skip_if_no_token)
    if not token:
        print("no CF_API_KEY: game version list skipped (wanted: %s, WoW Forever type %d)"
              % (", ".join(wanted), FOREVER_TYPE_ID))
        return 0
    versions = fetch_versions(args.site, token)
    forever = sorted((v for v in versions if v.get("gameVersionTypeID") == FOREVER_TYPE_ID), key=lambda v: v.get("id", 0))
    print("CurseForge WoW Forever game versions (type %d): %s"
          % (FOREVER_TYPE_ID, ", ".join("%s=%s" % (v.get("name"), v.get("id")) for v in forever) or "none"))
    ids, missing, elsewhere = match_versions(versions, wanted)
    for name, i in zip([w for w in wanted if w not in missing], ids):
        print("match %s -> id %s" % (name, i))
    if missing:
        for v in elsewhere:
            print("same name, other type (NOT used): %s id=%s type=%s" % (v.get("name"), v.get("id"), v.get("gameVersionTypeID")))
        raise ReleaseError("no exact CurseForge game version for: %s (WoW Forever type %d). Nothing is guessed."
                           % (", ".join(missing), FOREVER_TYPE_ID))
    return 0


def multipart(fields, file_field, filename, file_bytes):
    boundary = "----spokenwind" + uuid.uuid4().hex
    out = []
    for name, value in fields.items():
        out.append(("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n" % (boundary, name)).encode("utf-8"))
        out.append(value.encode("utf-8") + b"\r\n")
    out.append(("--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\n"
                "Content-Type: application/zip\r\n\r\n" % (boundary, file_field, filename)).encode("utf-8"))
    out.append(file_bytes + b"\r\n")
    out.append(("--%s--\r\n" % boundary).encode("utf-8"))
    return b"".join(out), "multipart/form-data; boundary=" + boundary


def cmd_upload(args):
    root = Path(args.root)
    info = check(root, args.tag)
    version = info["version"]
    zip_path = Path(args.zip)
    if zip_path.name != "%s-%s.zip" % (ADDON, version):
        raise ReleaseError("zip name %s does not match toc Version %s" % (zip_path.name, version))
    if not zip_path.is_file():
        raise ReleaseError("missing %s" % zip_path)
    project = str(args.project_id or "").strip()
    if not re.fullmatch(r"\d+", project):
        raise ReleaseError("project id is empty or not a number")
    token = need_token(skip_ok=args.dry_run)
    if token:
        versions = fetch_versions(args.site, token)
        ids, missing, elsewhere = match_versions(versions, info["game_versions"])
        if missing:
            raise ReleaseError("no exact CurseForge game version for: %s (WoW Forever type %d). Nothing is guessed."
                               % (", ".join(missing), FOREVER_TYPE_ID))
    else:
        ids = []
    metadata = {
        "displayName": "Spoken Wind %s" % version,
        "gameVersions": ids,
        "releaseType": info["type"],
        "changelog": info["changelog"],
        "changelogType": "markdown",
    }
    data = zip_path.read_bytes()
    if args.dry_run:
        print("dry run: nothing is sent to CurseForge")
        print("file: %s (%d bytes, sha256 %s)" % (zip_path.name, len(data), hashlib.sha256(data).hexdigest()))
        print("project id: %s" % project)
        print("metadata: %s" % json.dumps(metadata, indent=2))
        if not token:
            print("no CF_API_KEY: game version ids not looked up")
        return 0
    body, ctype = multipart({"metadata": json.dumps(metadata)}, "file", zip_path.name, data)
    status, answer = http("POST", "%s/api/projects/%s/upload-file" % (args.site, project), token, body,
                          {"Content-Type": ctype})
    try:
        file_id = json.loads(answer).get("id")
    except ValueError:
        file_id = None
    print("uploaded %s as %s %s, CurseForge file id %s" % (zip_path.name, info["type"], version, file_id))
    return 0


# --------------------------------------------------------------------------- main


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--root", default=str(ROOT), help="repo folder (tests use a temp copy)")
    sub = p.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("check")
    a.add_argument("--tag")
    b = sub.add_parser("build")
    b.add_argument("--out", default="dist")
    c = sub.add_parser("versions")
    c.add_argument("--skip-if-no-token", action="store_true")
    c.add_argument("--site", default=SITE)
    d = sub.add_parser("upload")
    d.add_argument("--zip", required=True)
    d.add_argument("--project-id", default=PROJECT_ID)
    d.add_argument("--tag")
    d.add_argument("--dry-run", action="store_true")
    d.add_argument("--site", default=SITE)
    args = p.parse_args(argv)
    try:
        if args.cmd == "check":
            info = check(args.root, args.tag)
            print("version %s, release type %s, game versions %s" % (info["version"], info["type"], ", ".join(info["game_versions"])))
            print("changelog:\n%s" % info["changelog"])
            return 0
        if args.cmd == "build":
            zip_path, contents = build(args.root, args.out)
            for k in sorted(contents):
                print("%s *%s" % (contents[k], k))
            print("built %s (%d bytes), %d files, same md5 as stage/MANIFEST.md5, no Dev files" % (zip_path, zip_path.stat().st_size, len(contents)))
            return 0
        if args.cmd == "versions":
            return cmd_versions(args)
        if args.cmd == "upload":
            return cmd_upload(args)
    except ReleaseError as e:
        print("ERROR: %s" % scrub(e, os.environ.get("CF_API_KEY", "").strip()), file=sys.stderr)
        return 1
    return 2


if __name__ == "__main__":
    sys.exit(main())
