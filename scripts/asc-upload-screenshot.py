#!/usr/bin/env python3
"""Upload a screenshot to an App Store version localization.

Usage: asc-upload-screenshot.py <jwt> <localization_id> <display_type> <png_path>...

Creates (or reuses) the screenshot set for the display type, then for each
file: reserves the asset, executes the upload operations, and commits with
an MD5 checksum. Stdlib only.
"""
import hashlib
import json
import sys
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"


def call(jwt: str, method: str, url: str, body: dict | None = None) -> dict:
    req = urllib.request.Request(url, method=method)
    req.add_header("Authorization", f"Bearer {jwt}")
    data = None
    if body is not None:
        req.add_header("Content-Type", "application/json")
        data = json.dumps(body).encode()
    try:
        with urllib.request.urlopen(req, data=data) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raise SystemExit(f"{method} {url} -> {e.code}: {e.read().decode()[:400]}")


def main() -> None:
    jwt, loc_id, display_type, *paths = sys.argv[1:]

    sets = call(jwt, "GET",
                f"{API}/appStoreVersionLocalizations/{loc_id}/appScreenshotSets")
    set_id = next((s["id"] for s in sets["data"]
                   if s["attributes"]["screenshotDisplayType"] == display_type), None)
    if set_id is None:
        created = call(jwt, "POST", f"{API}/appScreenshotSets", {
            "data": {
                "type": "appScreenshotSets",
                "attributes": {"screenshotDisplayType": display_type},
                "relationships": {"appStoreVersionLocalization": {
                    "data": {"type": "appStoreVersionLocalizations", "id": loc_id}}},
            }
        })
        set_id = created["data"]["id"]
    print(f"screenshot set: {set_id}")

    for path in paths:
        with open(path, "rb") as f:
            blob = f.read()
        name = path.rsplit("/", 1)[-1]
        shot = call(jwt, "POST", f"{API}/appScreenshots", {
            "data": {
                "type": "appScreenshots",
                "attributes": {"fileName": name, "fileSize": len(blob)},
                "relationships": {"appScreenshotSet": {
                    "data": {"type": "appScreenshotSets", "id": set_id}}},
            }
        })
        shot_id = shot["data"]["id"]
        for op in shot["data"]["attributes"]["uploadOperations"]:
            req = urllib.request.Request(op["url"], method=op["method"])
            for h in op["requestHeaders"]:
                req.add_header(h["name"], h["value"])
            chunk = blob[op["offset"]: op["offset"] + op["length"]]
            with urllib.request.urlopen(req, data=chunk) as resp:
                resp.read()
        call(jwt, "PATCH", f"{API}/appScreenshots/{shot_id}", {
            "data": {
                "type": "appScreenshots",
                "id": shot_id,
                "attributes": {
                    "uploaded": True,
                    "sourceFileChecksum": hashlib.md5(blob).hexdigest(),
                },
            }
        })
        print(f"uploaded {name} ({len(blob)} bytes) -> {shot_id}")


if __name__ == "__main__":
    main()
