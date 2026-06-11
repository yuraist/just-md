# Distribution

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
