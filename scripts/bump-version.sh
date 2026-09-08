#!/bin/zsh
# Usage: bump-version.sh X.Y — sets MARKETING_VERSION for every configuration.
set -euo pipefail
cd "$(dirname "$0")/.."
sed -i '' "s/MARKETING_VERSION = [0-9.]*;/MARKETING_VERSION = $1;/" JustMD/JustMD.xcodeproj/project.pbxproj
grep -c "MARKETING_VERSION = $1;" JustMD/JustMD.xcodeproj/project.pbxproj
