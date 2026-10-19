#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project QuotaBar.xcodeproj -scheme QuotaBar-macOS \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build/macOS CODE_SIGNING_ALLOWED=NO build
printf '\nApp locale : %s/build/macOS/Build/Products/Release/QuotaBar-macOS.app\n' "$PWD"
printf 'Widget et iCloud nécessitent une compilation avec signature Apple configurée.\n'
