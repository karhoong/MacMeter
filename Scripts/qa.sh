#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"

cache_root="/tmp/macmeter-qa-cache"
bash Scripts/test-version-policy.sh
env XDG_CACHE_HOME="$cache_root/xdg" \
  CLANG_MODULE_CACHE_PATH="$cache_root/clang" \
  SWIFTPM_MODULECACHE_OVERRIDE="$cache_root/clang" \
  MACMETER_RUN_HARDWARE_TESTS=1 \
  swift test --enable-code-coverage --cache-path "$cache_root/swiftpm"

coverage_json=".build/arm64-apple-macosx/debug/codecov/MacMeter.json"
test -f "$coverage_json"
jq -e '
  [.data[0].files[] | select(.filename | contains("/Sources/MacMeter/")) | .summary.lines]
  | ((map(.covered) | add) * 100 / (map(.count) | add)) >= 85
' "$coverage_json" >/dev/null

if rg -n 'URLSession|NW[A-Z][A-Za-z]+|https?://|CFNetwork|WKWebView|WebView|socket[[:space:]]*\(' Sources/MacMeter Sources/MacMeterSensors; then
  echo "Unexpected outbound-network implementation found" >&2
  exit 1
fi

xcodebuild \
  -project MacMeter.xcodeproj \
  -scheme MacMeter \
  -configuration Debug \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild \
  -project MacMeter.xcodeproj \
  -scheme MacMeter \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build

app="build/DerivedData/Build/Products/Release/MacMeter.app"
test -d "$app"
source Scripts/version-policy.sh
expected_version="$(macmeter_build_setting "$project_root" MARKETING_VERSION)"
expected_build="$(macmeter_build_setting "$project_root" CURRENT_PROJECT_VERSION)"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" = "$expected_version"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")" = "$expected_build"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" = "com.karhoong.MacMeter"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$app/Contents/Info.plist")" = "true"
file "$app/Contents/MacOS/MacMeter" | grep -q "arm64"
if otool -L "$app/Contents/MacOS/MacMeter" | rg 'CFNetwork|Network\.framework|WebKit'; then
  echo "Unexpected outbound-capable framework linked" >&2
  exit 1
fi

echo "MacMeter QA checks passed: $app"
