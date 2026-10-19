#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project QuotaBar.xcodeproj -scheme QuotaBar-macOS \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build/macOS CODE_SIGNING_ALLOWED=NO build

app_path="$PWD/build/macOS/Build/Products/Release/QuotaBar-macOS.app"
local_entitlements="$PWD/build/macOS/LocalApp.entitlements"

# Local signing seals both bundles and applies the widget sandbox entitlement.
# iCloud needs a provisioned Apple team and is deliberately omitted in this mode.
python3 - Configuration/App-macOS.entitlements "$local_entitlements" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as source:
    entitlements = plistlib.load(source)
entitlements.pop('com.apple.developer.ubiquity-kvstore-identifier', None)
with open(sys.argv[2], 'wb') as output:
    plistlib.dump(entitlements, output)
PY
/usr/libexec/PlistBuddy -c 'Delete :QuotaBarLocalBuild' "$app_path/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Add :QuotaBarLocalBuild bool true' "$app_path/Contents/Info.plist"
/usr/bin/codesign --force --sign - --identifier net.plumia.QuotaBar.widgets \
  --entitlements Configuration/Widget-macOS.entitlements \
  "$app_path/Contents/PlugIns/QuotaWidgets-macOS.appex"
/usr/bin/codesign --force --sign - --identifier net.plumia.QuotaBar \
  --entitlements "$local_entitlements" "$app_path"
/usr/bin/codesign --verify --deep --strict "$app_path"
printf '\nLocally signed app: %s\n' "$app_path"
printf 'Run ./Scripts/install-macos.sh to install and register its desktop widget.\n'
printf 'iCloud requires an Apple-team-signed build from Xcode.\n'
