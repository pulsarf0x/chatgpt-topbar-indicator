#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift test
xcodebuild -project QuotaBar.xcodeproj -scheme QuotaBar-macOS \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/macOS CODE_SIGNING_ALLOWED=NO build
xcodebuild -project QuotaBar.xcodeproj -scheme QuotaBar-iOS \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/iOS CODE_SIGNING_ALLOWED=NO build
