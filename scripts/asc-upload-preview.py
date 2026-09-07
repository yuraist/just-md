#!/usr/bin/env python3
"""Upload an app preview video to an App Store version localization.

Usage: asc-upload-preview.py <jwt> <localization_id> <preview_type> <video_path> [poster_timecode]

preview_type is DESKTOP for Mac. poster_timecode picks the poster frame,
"HH:MM:SS:FF" (default 00:00:05:00). Creates or reuses the preview set,
reserves the asset, uploads the chunks, commits with an MD5 checksum.
Stdlib only; same shape as asc-upload-screenshot.py.
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
        raise SystemExit(f"{method} {url} -> {e.code}: {e.read().decode()[:600]}")


def main() -> None:
    jwt, loc_id, preview_type, path = sys.argv[1:5]
    timecode = sys.argv[5] if len(sys.argv) > 5 else "00:00:05:00"

    sets = call(jwt, "GET",
                f"{API}/appStoreVersionLocalizations/{loc_id}/appPreviewSets")
    set_id = next((s["id"] for s in sets["data"]
                   if s["attributes"]["previewType"] == preview_type), None)
    if set_id is None:
        created = call(jwt, "POST", f"{API}/appPreviewSets", {
            "data": {
                "type": "appPreviewSets",
                "attributes": {"previewType": preview_type},
                "relationships": {"appStoreVersionLocalization": {
                    "data": {"type": "appStoreVersionLocalizations", "id": loc_id}}},
            }
        })
        set_id = created["data"]["id"]
    print(f"preview set: {set_id}")

    with open(path, "rb") as f:
        blob = f.read()
    name = path.rsplit("/", 1)[-1]
    mime = "video/mp4" if name.lower().endswith(".mp4") else "video/quicktime"
    preview = call(jwt, "POST", f"{API}/appPreviews", {
        "data": {
            "type": "appPreviews",
            "attributes": {"fileName": name, "fileSize": len(blob), "mimeType": mime,
                           "previewFrameTimeCode": timecode},
            "relationships": {"appPreviewSet": {
                "data": {"type": "appPreviewSets", "id": set_id}}},
        }
    })
    preview_id = preview["data"]["id"]
    for op in preview["data"]["attributes"]["uploadOperations"]:
        req = urllib.request.Request(op["url"], method=op["method"])
        for h in op["requestHeaders"]:
            req.add_header(h["name"], h["value"])
        chunk = blob[op["offset"]: op["offset"] + op["length"]]
        with urllib.request.urlopen(req, data=chunk) as resp:
            resp.read()
    call(jwt, "PATCH", f"{API}/appPreviews/{preview_id}", {
        "data": {
            "type": "appPreviews",
            "id": preview_id,
            "attributes": {
                "uploaded": True,
                "sourceFileChecksum": hashlib.md5(blob).hexdigest(),
                "previewFrameTimeCode": timecode,
            },
        }
    })
    print(f"uploaded {name} ({len(blob)} bytes) -> {preview_id}")


if __name__ == "__main__":
    main()
