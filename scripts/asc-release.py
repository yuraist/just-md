#!/usr/bin/env python3
"""Attach Xcode Cloud builds to App Store versions and submit them for review.

Usage:
  asc-release.py attach [--commit SHA] [--version X.Y]
  asc-release.py submit --version X.Y [--commit SHA]

Environment: ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY_PATH (a .p8 file).
Optional: ASC_APP_ID (default JustMD), ASC_WORKFLOW_ID (Xcode Cloud "Release").

attach: wait for the Xcode Cloud run of --commit (if given) to finish, take the
newest processed build whose version string equals --version (default: the
MARKETING_VERSION in the pbxproj), make sure an editable App Store version
with that string exists (created when ASC allows it) and attach the build.
Exit 0 with a message when nothing can be done yet.

submit: attach as above, cancel a pending review submission of that version
if one exists, add the version plus every in-app purchase in READY_TO_SUBMIT
to a review submission (reusing an unsubmitted draft) and submit it.
Stdlib only; the JWT comes from asc-jwt.py next to this file.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com"
APP_ID = os.environ.get("ASC_APP_ID", "6779422717")
WORKFLOW_ID = os.environ.get("ASC_WORKFLOW_ID", "CB6FBC8C-5EAE-4F07-B3D6-5400A0194382")
PLATFORM = "MAC_OS"
EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
            "METADATA_REJECTED", "INVALID_BINARY", "WAITING_FOR_EXPORT_COMPLIANCE"}
PENDING = {"WAITING_FOR_REVIEW", "IN_REVIEW"}
HERE = os.path.dirname(os.path.abspath(__file__))


class ASC:
    def __init__(self) -> None:
        self._token = ""
        self._minted = 0.0

    def token(self) -> str:
        if time.time() - self._minted > 900:
            self._token = subprocess.check_output([
                sys.executable, os.path.join(HERE, "asc-jwt.py"),
                os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"],
                os.environ["ASC_PRIVATE_KEY_PATH"],
            ], text=True).strip()
            self._minted = time.time()
        return self._token

    def call(self, method: str, path: str, body: dict | None = None, ok404: bool = False) -> dict:
        url = path if path.startswith("http") else API + path
        req = urllib.request.Request(url, method=method)
        req.add_header("Authorization", f"Bearer {self.token()}")
        data = None
        if body is not None:
            req.add_header("Content-Type", "application/json")
            data = json.dumps(body).encode()
        try:
            with urllib.request.urlopen(req, data=data) as resp:
                raw = resp.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            if ok404 and e.code == 404:
                return {}
            raise SystemExit(f"{method} {url} -> {e.code}: {e.read().decode()[:600]}")

    def get(self, path: str, **params: str) -> dict:
        if params:
            path += ("&" if "?" in path else "?") + urllib.parse.urlencode(params)
        return self.call("GET", path)


def log(msg: str) -> None:
    print(msg, flush=True)


def marketing_version() -> str:
    pbx = os.path.join(HERE, "..", "JustMD", "JustMD.xcodeproj", "project.pbxproj")
    with open(pbx) as f:
        m = re.search(r"MARKETING_VERSION = ([0-9.]+);", f.read())
    if not m:
        raise SystemExit("MARKETING_VERSION not found in pbxproj")
    return m.group(1)


# ---------------------------------------------------------------- Xcode Cloud

def wait_for_run(asc: ASC, sha: str, timeout_s: int = 3600) -> None:
    """Block until the Xcode Cloud run for `sha` finishes successfully."""
    deadline = time.time() + timeout_s
    seen = False
    while time.time() < deadline:
        runs = asc.get(f"/v1/ciWorkflows/{WORKFLOW_ID}/buildRuns", limit="25")
        for run in runs.get("data", []):
            a = run["attributes"]
            if (a.get("sourceCommit") or {}).get("commitSha", "").startswith(sha):
                seen = True
                if a["executionProgress"] == "COMPLETE":
                    if a["completionStatus"] != "SUCCEEDED":
                        raise SystemExit(f"Xcode Cloud run #{a['number']} finished with {a['completionStatus']}")
                    log(f"Xcode Cloud run #{a['number']} succeeded")
                    return
                log(f"Xcode Cloud run #{a['number']} is {a['executionProgress']}; waiting")
                break
        else:
            log("no Xcode Cloud run for this commit yet; waiting" if not seen else "run vanished; waiting")
        time.sleep(60)
    raise SystemExit("timed out waiting for Xcode Cloud")


def newest_build(asc: ASC, version: str, timeout_s: int = 1800) -> dict | None:
    """Newest build with that version string; waits while it is still processing."""
    deadline = time.time() + timeout_s
    while True:
        builds = asc.get("/v1/builds", **{
            "filter[app]": APP_ID,
            "filter[preReleaseVersion.version]": version,
            "sort": "-uploadedDate", "limit": "1",
        }).get("data", [])
        if not builds:
            return None
        build = builds[0]
        state = build["attributes"]["processingState"]
        if state == "VALID":
            return build
        if state in ("FAILED", "INVALID"):
            raise SystemExit(f"build {build['attributes']['version']} is {state}")
        if time.time() > deadline:
            raise SystemExit("timed out waiting for build processing")
        log(f"build {build['attributes']['version']} is {state}; waiting")
        time.sleep(60)


# --------------------------------------------------------------- App Store

def find_version(asc: ASC, version: str) -> dict | None:
    data = asc.get(f"/v1/apps/{APP_ID}/appStoreVersions", **{
        "filter[versionString]": version, "filter[platform]": PLATFORM,
    }).get("data", [])
    return data[0] if data else None


def ensure_version(asc: ASC, version: str) -> dict | None:
    found = find_version(asc, version)
    if found:
        return found
    try:
        created = asc.call("POST", "/v1/appStoreVersions", {"data": {
            "type": "appStoreVersions",
            "attributes": {"platform": PLATFORM, "versionString": version},
            "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}},
        }})
    except SystemExit as e:
        if "cannot create a new version" in str(e):
            log(f"ASC does not allow creating {version} yet (previous version still in review)")
            return None
        raise
    log(f"created App Store version {version}")
    return created["data"]


def attached_build_id(asc: ASC, version_id: str) -> str | None:
    rel = asc.call("GET", f"/v1/appStoreVersions/{version_id}/relationships/build", ok404=True)
    data = rel.get("data")
    return data["id"] if data else None


def attach(asc: ASC, version: str, commit: str | None) -> tuple[dict | None, dict | None]:
    if commit:
        wait_for_run(asc, commit)
    build = newest_build(asc, version)
    if build is None:
        log(f"no processed build with version {version} yet")
        return None, None
    log(f"newest build for {version}: {build['attributes']['version']} ({build['id']})")
    asv = ensure_version(asc, version)
    if asv is None:
        return build, None
    state = asv["attributes"]["appVersionState"]
    if state not in EDITABLE:
        log(f"version {version} is {state}; not touching its build")
        return build, asv
    if attached_build_id(asc, asv["id"]) == build["id"]:
        log("build already attached")
        return build, asv
    asc.call("PATCH", f"/v1/appStoreVersions/{asv['id']}/relationships/build",
             {"data": {"type": "builds", "id": build["id"]}})
    log(f"attached build {build['attributes']['version']} to {version}")
    return build, asv


# ------------------------------------------------------------------ Review

def submissions(asc: ASC) -> list[dict]:
    return asc.get("/v1/reviewSubmissions", **{
        "filter[app]": APP_ID, "filter[platform]": PLATFORM, "limit": "50",
    }).get("data", [])


def cancel_pending(asc: ASC, version_id: str) -> None:
    for sub in submissions(asc):
        if sub["attributes"]["state"] not in PENDING:
            continue
        items = asc.get(f"/v1/reviewSubmissions/{sub['id']}/items", include="appStoreVersion")
        if any(i.get("relationships", {}).get("appStoreVersion", {}).get("data", {}).get("id") == version_id
               for i in items.get("data", [])):
            asc.call("PATCH", f"/v1/reviewSubmissions/{sub['id']}", {"data": {
                "type": "reviewSubmissions", "id": sub["id"], "attributes": {"canceled": True}}})
            log(f"cancelled pending review submission {sub['id']}")
            time.sleep(5)


def ready_iaps(asc: ASC) -> list[str]:
    data = asc.get(f"/v1/apps/{APP_ID}/inAppPurchasesV2", limit="200").get("data", [])
    return [i["id"] for i in data if i["attributes"]["state"] == "READY_TO_SUBMIT"]


def submit(asc: ASC, version: str, commit: str | None) -> None:
    build, asv = attach(asc, version, commit)
    if build is None:
        raise SystemExit("nothing to submit: no build")
    if asv is None:
        asv = find_version(asc, version)
    if asv is None:
        raise SystemExit(f"version {version} does not exist in ASC and cannot be created yet")
    if asv["attributes"]["appVersionState"] in PENDING:
        cancel_pending(asc, asv["id"])
        asv = find_version(asc, version)
        if attached_build_id(asc, asv["id"]) != build["id"]:
            asc.call("PATCH", f"/v1/appStoreVersions/{asv['id']}/relationships/build",
                     {"data": {"type": "builds", "id": build["id"]}})
            log(f"attached build {build['attributes']['version']} to {version}")
    elif attached_build_id(asc, asv["id"]) != build["id"]:
        raise SystemExit(f"version {version} is {asv['attributes']['appVersionState']} and the build is not attached")

    draft = next((s for s in submissions(asc) if s["attributes"]["state"] == "READY_FOR_REVIEW"), None)
    if draft is None:
        draft = asc.call("POST", "/v1/reviewSubmissions", {"data": {
            "type": "reviewSubmissions", "attributes": {"platform": PLATFORM},
            "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}}}})["data"]
        log(f"created review submission {draft['id']}")
    else:
        log(f"reusing draft review submission {draft['id']}")
    existing = asc.get(f"/v1/reviewSubmissions/{draft['id']}/items").get("data", [])
    have_version = any(i.get("relationships", {}).get("appStoreVersion", {}).get("data", {}).get("id") == asv["id"]
                       for i in existing)
    if not have_version:
        asc.call("POST", "/v1/reviewSubmissionItems", {"data": {
            "type": "reviewSubmissionItems",
            "relationships": {
                "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": draft["id"]}},
                "appStoreVersion": {"data": {"type": "appStoreVersions", "id": asv["id"]}}}}})
        log(f"added version {version} to the submission")
    have_iaps = {i.get("relationships", {}).get("inAppPurchaseV2", {}).get("data", {}).get("id") for i in existing}
    for iap in ready_iaps(asc):
        if iap in have_iaps:
            continue
        asc.call("POST", "/v1/reviewSubmissionItems", {"data": {
            "type": "reviewSubmissionItems",
            "relationships": {
                "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": draft["id"]}},
                "inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap}}}}})
        log(f"added in-app purchase {iap} to the submission")
    asc.call("PATCH", f"/v1/reviewSubmissions/{draft['id']}", {"data": {
        "type": "reviewSubmissions", "id": draft["id"], "attributes": {"submitted": True}}})
    log(f"submitted {version} (build {build['attributes']['version']}) for review")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("command", choices=["attach", "submit"])
    p.add_argument("--commit")
    p.add_argument("--version")
    args = p.parse_args()
    version = args.version or marketing_version()
    asc = ASC()
    if args.command == "attach":
        attach(asc, version, args.commit)
    else:
        submit(asc, version, args.commit)


if __name__ == "__main__":
    main()
