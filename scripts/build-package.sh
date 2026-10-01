#!/bin/bash
# Builds every KinKit module for the iOS Simulator and prints only diagnostics.
set -o pipefail
cd "$(dirname "$0")/../Packages/KinKit"
xcodebuild -scheme KinKit-Package -destination 'generic/platform=iOS Simulator' -derivedDataPath ../../DerivedData build 2>&1 \
  | grep -E "error:|warning:|BUILD" | sort -u | head -${1:-40}
