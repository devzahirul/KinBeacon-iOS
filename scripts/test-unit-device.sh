#!/bin/bash
# Runs the KinKit unit tests on the connected iPhone (via the KinKitTestHost app).
set -o pipefail
cd "$(dirname "$0")/.."
DEVICE_ID=${DEVICE_ID:-$(xcrun xctrace list devices 2>/dev/null | grep -v Simulator | grep -E '\([0-9]+\.[0-9.]+\) \(' | head -1 | sed -E 's/.*\(([0-9A-Fa-f-]+)\)$/\1/')}
xcodebuild -project KinBeacon.xcodeproj -scheme KinBeacon -destination "id=$DEVICE_ID" -derivedDataPath DerivedData \
  -allowProvisioningUpdates test -only-testing:KinKitTests "$@"
