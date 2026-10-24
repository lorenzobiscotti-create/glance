#!/bin/bash
# Builds build/Glance.app (Apple Silicon + Intel) and zips it to build/Glance.zip.
# Runs on a Mac with Xcode or the Command Line Tools installed.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Glance.app
SDK="$(xcrun --sdk macosx --show-sdk-path)"

rm -rf build
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
# The updater compares this number with the newest GitHub release (build-N).
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${GITHUB_RUN_NUMBER:-0}" "$APP/Contents/Info.plist"

for arch in arm64 x86_64; do
    xcrun swiftc -O -parse-as-library -swift-version 5 \
        -target "$arch-apple-macos14.0" -sdk "$SDK" \
        Glance/*.swift -o "build/Glance-$arch"
done
lipo -create build/Glance-arm64 build/Glance-x86_64 -output "$APP/Contents/MacOS/Glance"

# Ad-hoc signature: no Apple Developer account needed.
codesign --force --sign - "$APP"

(cd build && ditto -c -k --keepParent Glance.app Glance.zip)
echo "Built build/Glance.zip"
