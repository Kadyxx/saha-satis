#!/bin/bash
# FreeDevice yapılandırmasının kimliklerini ve yetkilerini, derlenen paketin Info.plist'lerini doğrular.
# Normal yapılandırmanın değişmediğini de kontrol eder.
# Kullanım: check-freedevice.sh <FreeDevice ile derlenmiş SahaSatis.app>
set -euo pipefail

APP="$1"
fail() { echo "HATA: $1" >&2; exit 1; }

plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1"; }

setting() { # hedef, yapılandırma, ayar
  xcodebuild -project SahaSatis.xcodeproj -target "$1" -configuration "$2" -showBuildSettings 2>/dev/null \
    | awk -F ' = ' -v key="$3" '{ name = $1; gsub(/^ +/, "", name) } name == key { print $2; exit }'
}

expect() { # açıklama, beklenen, bulunan
  [ "$2" = "$3" ] || fail "$1: beklenen '$2', bulunan '$3'"
  echo "tamam: $1 = $3"
}

expect "FreeDevice uygulama kimliği" com.kadyxx.sahasatis "$(plist "$APP/Info.plist" CFBundleIdentifier)"
expect "FreeDevice widget kimliği" com.kadyxx.sahasatis.widget \
  "$(plist "$APP/PlugIns/SahaSatisWidget.appex/Info.plist" CFBundleIdentifier)"
expect "FreeDevice App Group" group.com.kadyxx.sahasatis "$(plist "$APP/Info.plist" AppGroupID)"
expect "FreeDevice widget App Group" group.com.kadyxx.sahasatis \
  "$(plist "$APP/PlugIns/SahaSatisWidget.appex/Info.plist" AppGroupID)"

ENTITLEMENTS=$(setting SahaSatis FreeDevice CODE_SIGN_ENTITLEMENTS)
expect "FreeDevice yetki dosyası" Config/SahaSatis-FreeDevice.entitlements "$ENTITLEMENTS"
if grep -qE 'icloud|applesignin' "$ENTITLEMENTS"; then fail "FreeDevice yetkilerinde iCloud / Sign in with Apple var"; fi
grep -q 'com.apple.security.application-groups' "$ENTITLEMENTS" || fail "FreeDevice yetkilerinde App Group yok"
WIDGET_ENTITLEMENTS=$(setting SahaSatisWidget FreeDevice CODE_SIGN_ENTITLEMENTS)
if grep -qE 'icloud|applesignin' "$WIDGET_ENTITLEMENTS"; then fail "Widget yetkilerinde iCloud / Sign in with Apple var"; fi
grep -q 'com.apple.security.application-groups' "$WIDGET_ENTITLEMENTS" || fail "Widget yetkilerinde App Group yok"

for config in Debug Release; do
  expect "$config uygulama kimliği" com.example.sahasatis "$(setting SahaSatis $config PRODUCT_BUNDLE_IDENTIFIER)"
  expect "$config yetki dosyası" Config/SahaSatis.entitlements "$(setting SahaSatis $config CODE_SIGN_ENTITLEMENTS)"
done
