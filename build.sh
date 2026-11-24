#!/bin/bash
# Builds "Receipt Ingester.app" and dist/Receipt-Ingester.zip. Must run on macOS
# (GitHub Actions does this automatically; see .github/workflows/build.yml).
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-1.0.0}"
APP="dist/Receipt Ingester.app"
PLIST="$APP/Contents/Info.plist"

rm -rf dist
mkdir -p dist

# -s makes a stay-open app, so it keeps watching until it's quit.
osacompile -s -o "$APP" src/ReceiptIngester.applescript
cp src/ingest.sh "$APP/Contents/Resources/ingest.sh"
chmod 755 "$APP/Contents/Resources/ingest.sh"

plutil -replace CFBundleIdentifier -string "com.receipt-ingester.app" "$PLIST"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$PLIST"
plutil -replace CFBundleVersion -string "$VERSION" "$PLIST"
plutil -replace NSAppleEventsUsageDescription -string "Receipt Ingester adds each receipt as a new row in your Numbers spreadsheet." "$PLIST"
plutil -replace NSDownloadsFolderUsageDescription -string "Receipt Ingester looks in Downloads for receipt photos you AirDrop to this Mac." "$PLIST"

# Ad-hoc signature (free). macOS still asks once to "Open Anyway" because it isn't notarized.
codesign --force --deep --sign - "$APP"

ditto -c -k --keepParent "$APP" dist/Receipt-Ingester.zip
echo "Built dist/Receipt-Ingester.zip (version $VERSION)"
