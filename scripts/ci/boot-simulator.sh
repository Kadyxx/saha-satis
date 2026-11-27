#!/bin/bash
# İlk uygun iPhone simülatörünü açar; UDID'yi adım çıktısı olarak yazar.
set -euo pipefail

xcodebuild -version
UDID=$(xcrun simctl list devices available | grep -E '^\s+iPhone' | head -1 | grep -oE '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}' || true)
if [ -z "$UDID" ]; then
  echo "Uygun iPhone simülatörü bulunamadı" >&2
  xcrun simctl list devices available
  exit 1
fi
echo "udid=$UDID" >> "$GITHUB_OUTPUT"
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
