#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source ~/Developer/.secrets/.env; set +a
KEY=~/.appstoreconnect/private_keys/AuthKey_3PCCY7B92H.p8
KEY_ID=3PCCY7B92H
ISSUER="${ASC_ISSUER_ID:?ASC_ISSUER_ID missing}"
VER=1.0; BUILD=5
OUT=build/devid; rm -rf "$OUT"; mkdir -p "$OUT"

echo "== archive"
xcodebuild -project JustMD/JustMD.xcodeproj -scheme JustMD -configuration Release archive \
  -archivePath "$OUT/JustMD.xcarchive" -destination 'generic/platform=macOS' \
  CURRENT_PROJECT_VERSION=$BUILD -quiet
echo "== export (developer-id)"
xcodebuild -exportArchive -archivePath "$OUT/JustMD.xcarchive" \
  -exportOptionsPlist scripts/ExportOptionsDevID.plist -exportPath "$OUT/export" -quiet
APP="$OUT/export/JustMD.app"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E "Authority|Identifier|flags"
echo "== notarize app"
ditto -c -k --keepParent "$APP" "$OUT/JustMD.zip"
xcrun notarytool submit "$OUT/JustMD.zip" --key "$KEY" --key-id "$KEY_ID" --issuer "$ISSUER" --wait
xcrun stapler staple "$APP"
echo "== dmg"
STAGE="$OUT/stage"; mkdir -p "$STAGE"; cp -R "$APP" "$STAGE/"; ln -s /Applications "$STAGE/Applications"
DMG="$OUT/JustMD-$VER.dmg"
hdiutil create -volname "JustMD" -srcfolder "$STAGE" -ov -format UDZO "$DMG" -quiet
codesign --sign "Developer ID Application: Iurii Istomin (N2HCJ99WYH)" --timestamp "$DMG"
echo "== notarize dmg"
xcrun notarytool submit "$DMG" --key "$KEY" --key-id "$KEY_ID" --issuer "$ISSUER" --wait
xcrun stapler staple "$DMG"
spctl -a -t open --context context:primary-signature -v "$DMG"
shasum -a 256 "$DMG"
echo "== DONE"
