#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || { echo 'Install XcodeGen: brew install xcodegen' >&2; exit 1; }
command -v xcodebuild >/dev/null || { echo 'This step requires macOS and full Xcode.' >&2; exit 1; }
mkdir -p artifacts
xcodegen generate --spec project.yml
xcodebuild -version | tee artifacts/xcode-version.txt
xcodegen --version | tee artifacts/xcodegen-version.txt
xcodebuild -project Stride.xcodeproj -scheme StridePhone \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/phone CODE_SIGNING_ALLOWED=NO build \
  2>&1 | tee artifacts/iphone-build.log
xcodebuild -project Stride.xcodeproj -scheme StrideTV \
  -sdk appletvsimulator -destination 'generic/platform=tvOS Simulator' \
  -derivedDataPath build/tv CODE_SIGNING_ALLOWED=NO build \
  2>&1 | tee artifacts/tvos-build.log
ditto -c -k --sequesterRsrc --keepParent \
  build/phone/Build/Products/Debug-iphonesimulator/StridePhone.app artifacts/StridePhone-simulator.zip
ditto -c -k --sequesterRsrc --keepParent \
  build/tv/Build/Products/Debug-appletvsimulator/StrideTV.app artifacts/StrideTV-simulator.zip
