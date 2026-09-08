# Distribution

## Release state (2026-09-08)

**1.0 submitted for App Store review on 2026-09-08** with build 5 (Xcode
Cloud run 5, commit `8d6b548`: printing entitlement, Read-mode image fixes,
final screenshots and preview). Review submission
`f60c4544-d687-44e6-8a08-28bbc2a80374`, version state WAITING_FOR_REVIEW.
Watch it with the ASC MCP (`get_review_status`). Earlier notes below.

**Direct download shipped 2026-09-08:** the same 1.0 (build 5) source,
exported with Developer ID, notarized and stapled, is on GitHub Releases as
[`JustMD-1.0.dmg`](https://github.com/yuraist/justmd/releases/tag/v1.0)
(universal, SHA-256 `74895e4c…b02943`). The landing page's direct-download
link points at `releases/latest/download/JustMD-1.0.dmg`. Reproduce with
`scripts/release-devid.sh` (archive → export → notarytool with the ASC API
key from `~/Developer/.secrets/.env` → staple → DMG → notarize + staple the
DMG); it writes to `build/devid/`. The Developer ID Application certificate
now exists in the login keychain, so PRI-48 is unblocked.

Open steps are tracked in Linear: project
[JustMD 1.0 Release](https://linear.app/nuta-life/project/justmd-10-release-cc787e86c15d)
(Prism App team). Issue numbers below refer to it.

Done by automation:

- ✅ Bundle ID `com.nuta.JustMD` registered on the developer portal (via ASC
  API + `scripts/asc-jwt.py`; bundle-ID resource id `23N89WX93Z`)
- ✅ App Store build exported: `build/export-appstore/JustMD.pkg` — universal,
  cloud-signed (Apple Distribution), sandbox + hardened runtime; the
  Info.plist-in-Resources validation risk fixed in the pbxproj
- ✅ Screenshots: `marketing/screenshots/appstore-{1,2}-*.png` (2880×1800,
  regenerable via the `AppStoreScreenshots` test suite)
- ✅ Listing texts ready: `docs/appstore-metadata.md`
- ✅ Landing + privacy policy: `https://justmd.nuta.life/` (Cloudflare Worker,
  source in the public `yuraist/justmd` repo)
- ✅ 1.0 QA pass complete ([PRI-42](https://linear.app/nuta-life/issue/PRI-42))
- ✅ **Xcode Cloud** (set up 2026-09-07, same shape as Prism/Nuta): product
  `JustMD`, workflow **Release** — every push to `master` runs `JustMDTests`
  on a Mac, then archives a Mac App Store eligible build with Xcode "Latest
  Release". Xcode Cloud assigns the build number, so no local `.pkg` export
  or `altool` upload is needed for App Store builds; pick the build in ASC.
  Manual builds: Xcode → Integrate → Xcode Cloud → Manage Workflows, or
  `POST /v1/ciBuildRuns` with the workflow id (`scripts/asc-jwt.py` for the JWT).
  Build 5 (run #5, 2026-09-08) is attached to version 1.0 (builds 2–4 came
  from earlier pushes the same day; every push to master costs a build
  number, so batch docs changes). Run #1 failed only
  because its number collided with the June build 1.

Blocked on owner-only steps:

1. ~~**Create the app record**~~ — done; the record is `6779422717`. ([PRI-43](https://linear.app/nuta-life/issue/PRI-43) now tracks build 2 via Xcode Cloud.) Original notes: appstoreconnect.apple.com → My Apps → New App
   (macOS, bundle `com.nuta.JustMD`; names in `docs/appstore-metadata.md`).
   The API cannot create app records. Then upload is one command:
   `xcrun altool --upload-app -f build/export-appstore/JustMD.pkg -t macos
   --apiKey 3PCCY7B92H --apiIssuer <issuer>` (verified working up to the
   missing-record error).
2. ~~**Developer ID certificate**~~ ([PRI-48](https://linear.app/nuta-life/issue/PRI-48)) — done 2026-09-08, see above. Original notes: cloud signing returned a permission error
   (only the Account Holder may create Developer ID certs). Xcode →
   Settings → Accounts → Manage Certificates → ＋ → Developer ID Application;
   then `xcodebuild -exportArchive … -exportOptionsPlist
   scripts/ExportOptionsDevID.plist` + notarytool + DMG.
3. ~~**GitHub Pages domain**~~ — resolved ([PRI-45](https://linear.app/nuta-life/issue/PRI-45)): the site left GitHub Pages
   and runs as the Cloudflare Worker `justmd-site` (repo `yuraist/justmd`,
   `public/` + `wrangler.jsonc`, `npx wrangler@4 deploy`) on the same account
   as nuta.life, custom domain `https://justmd.nuta.life/`; privacy policy at
   `/privacy`.

How to get JustMD 1.0 into users' hands. Two channels, not mutually exclusive —
many indie Mac apps ship both. Current project state already satisfies the hard
requirements for either: sandbox ON, hardened runtime ON, signed icon set,
automatic signing under team `N2HCJ99WYH`, bundle `com.nuta.JustMD`.

## Option A — Mac App Store

**Best for:** trust, discoverability, zero update/payment infrastructure.
**Costs:** Apple Developer Program ($99/yr, already a member), 15–30% commission
if the app is paid, review turnaround (~24–48 h per release).

Steps:

1. **App Store Connect record** — appstoreconnect.apple.com → My Apps → New App
   (macOS, bundle `com.nuta.JustMD`). Fill: name, subtitle, description, keywords,
   category (Productivity — already in the build), support URL, privacy-policy URL,
   privacy labels ("Data Not Collected" — the app touches nothing).
   The ASC MCP server in `~/Developer/appstoreconnect-mcp/` can automate metadata.
2. **Screenshots** — at least one per required size: 2880×1800 or 2560×1600
   (Retina 16:10). Editor with hidden markers + Read mode with a table are the
   obvious shots.
3. **Archive & upload** — Xcode: Product → Archive → Distribute App →
   App Store Connect. CLI equivalent:

   ```bash
   xcodebuild -project JustMD/JustMD.xcodeproj -scheme JustMD archive \
     -archivePath build/JustMD.xcarchive
   xcodebuild -exportArchive -archivePath build/JustMD.xcarchive \
     -exportOptionsPlist ExportOptions.plist -exportPath build/export
   # ExportOptions.plist: method = app-store-connect, teamID = N2HCJ99WYH
   xcrun altool --upload-package … # or drag the .pkg into Transporter.app
   ```

4. **Submit for review** — pick the build in ASC, answer export compliance
   (already `ITSAppUsesNonExemptEncryption = false`), submit. First reviews of a
   new app sometimes take longer; releases after that are usually a day.

Review gotchas for an app like this: must do something on first launch with no
file open (the Welcome window covers this), privacy-policy URL must resolve,
screenshots must show the real app.

## Option B — Direct download from your own site (Developer ID)

**Best for:** instant releases, no review, optional non-Apple payments
(Paddle / Lemon Squeezy / Gumroad keep ~5% instead of 30%).
**You own:** hosting, updates, license enforcement if paid.

Steps:

1. **Export with Developer ID** — Product → Archive → Distribute App →
   Direct Distribution (Developer ID). CLI: same archive, then
   `-exportOptionsPlist` with `method = developer-id`.
2. **Notarize** — Apple scans the binary; required or Gatekeeper blocks it:

   ```bash
   ditto -c -k --keepParent build/export/JustMD.app build/JustMD.zip
   xcrun notarytool submit build/JustMD.zip \
     --keychain-profile "notary" --wait        # profile: store-credentials once
   xcrun stapler staple build/export/JustMD.app
   ```

   (Xcode's Organizer does archive + notarize + staple in one flow — easiest path.)
3. **Package** — a `.dmg` with an Applications-folder shortcut
   (`create-dmg` from Homebrew) or just the stapled `.zip`.
4. **Host** — any static hosting; a landing page with the download link.
5. **Updates** — add [Sparkle 2](https://sparkle-project.org) (sandbox-compatible):
   the app checks an appcast XML on your site and self-updates. Without it,
   users redownload manually.
6. **Bonus reach** — submit a Homebrew cask (`brew install --cask justmd`) once
   the download URL is stable.

Note: the sandbox can stay ON for the direct build too — keep one build config.

## Option C — Both (recommended end-state)

Same codebase, two export methods. Ship 1.0 on the App Store first (it forces
the metadata/QA discipline and gives a trustworthy storefront), then add the
Developer ID + Sparkle build when a landing page exists. Keep versions in sync;
only the export method and (eventually) the update mechanism differ.

## Suggested path for 1.0

1. App Store only.
2. Write metadata + take screenshots (the landing-page skill can draft copy).
3. Manual QA pass (see roadmap), bump build number, archive, upload, submit.
4. Post-1.0: landing page + Developer ID/Sparkle build as v1.0.1 or v1.1.
