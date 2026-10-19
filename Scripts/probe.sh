#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -swift-version 6 -parse-as-library \
  Sources/QuotaCore/UsageSnapshot.swift Sources/QuotaBar/CodexClient.swift \
  Scripts/Probe.swift -o build/quota-probe
exec build/quota-probe
