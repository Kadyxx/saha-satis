#!/bin/bash
# Uygulama ekran görüntüleri: senaryoların bu parçaya düşenlerini açık ve koyu modda çeker.
# Kullanım: screenshots.sh <udid> <SahaSatis.app> <parça: 1..N> <parça sayısı N>
set -euo pipefail

UDID="$1"
APP="$2"
SHARD="$3"
SHARDS="$4"
OUT=artifacts/screenshots
mkdir -p "$OUT"

# Yeni senaryo listeye eklenir; parçalara sırayla dağıtılır.
SCENES=(
  installedBase installedBaseForm weekDay importMapping importPreview customers detail form
  settings settingsReminders settingsCities visitForm visitRecording visitHistory today todayForm
  export exportPreview opportunities opportunityDetail opportunityForm opportunityLost
  quotes quoteDetail quoteForm region regionCity regionDistrict cardResult cardResultNew
  claudeButtons claudePreview claudeBroken settingsClaude draftPrompt settingsBackup
)

BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")
xcrun simctl install "$UDID" "$APP"

launch() {
  xcrun simctl launch "$UDID" "$BUNDLE_ID" -AppleLanguages "(tr)" -AppleLocale tr_TR "$@"
}

# İlk açılış yavaştır: bu parçanın ilk görüntüsü erken alınmasın diye bir kez ısıtılır.
launch -DebugSampleData
sleep 15
xcrun simctl terminate "$UDID" "$BUNDLE_ID" || true

if [ "$SHARD" = "1" ]; then
  xcrun simctl ui "$UDID" appearance light
  launch -DebugNoNotifications
  sleep 5
  xcrun simctl io "$UDID" screenshot "$OUT/app.png"
  xcrun simctl ui "$UDID" appearance dark
  sleep 2
  xcrun simctl io "$UDID" screenshot "$OUT/app-dark.png"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" || true
fi

# Yalnızca DEBUG derlemesinde, bellek içi hayali örnek veriyle.
for index in "${!SCENES[@]}"; do
  if (( index % SHARDS != SHARD - 1 )); then continue; fi
  scene="${SCENES[$index]}"
  for mode in light dark; do
    xcrun simctl ui "$UDID" appearance "$mode"
    launch -DebugSampleData -DebugScene "$scene"
    # Üst üste iki sheet açan senaryolar yavaş runner'da 5 sn'ye yetişmeyebiliyor.
    case "$scene" in claude*) sleep 12 ;; *) sleep 6 ;; esac
    xcrun simctl io "$UDID" screenshot "$OUT/screen-$scene-$mode.png"
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" || true
  done
done
xcrun simctl ui "$UDID" appearance light
