#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./Scripts/build-macos.sh

app_path="$PWD/build/macOS/Build/Products/Release/QuotaBar-macOS.app"
destination="$HOME/Applications/QuotaBar.app"
mkdir -p "$HOME/Applications"
if [[ -e "$destination" ]]; then
  existing_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination/Contents/Info.plist")
  if [[ "$existing_id" != net.plumia.QuotaBar ]]; then
    printf 'Refusing to replace another application at %s\n' "$destination" >&2
    exit 1
  fi
fi

# QuotaBar has no unsaved documents; quit its prior copies before updating it.
/usr/bin/pkill -x QuotaBar-macOS || true
/usr/bin/pkill -x QuotaWidgets-macOS || true
for attempt in {1..20}; do
  if ! /usr/bin/pgrep -x QuotaBar-macOS >/dev/null; then break; fi
  sleep 0.1
done
if /usr/bin/pgrep -x QuotaBar-macOS >/dev/null; then
  printf 'Quit QuotaBar before installing this update.\n' >&2
  exit 1
fi
/usr/bin/ditto "$app_path" "$destination"
/usr/bin/codesign --verify --deep --strict "$destination"
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f "$destination"
/usr/bin/pluginkit -a "$destination/Contents/PlugIns/QuotaWidgets-macOS.appex"
registration=$(/usr/bin/pluginkit -m -A -D -i net.plumia.QuotaBar.widgets)
if [[ "$registration" != *net.plumia.QuotaBar.widgets* ]]; then
  printf 'Widget registration could not be confirmed.\n' >&2
  exit 1
fi
/usr/bin/open -n "$destination"
printf '\nInstalled and launched: %s\n%s\n' "$destination" "$registration"
printf 'Close and reopen Edit Widgets, then search for QuotaBar.\n'
