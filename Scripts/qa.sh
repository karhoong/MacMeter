#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"

cache_root="/tmp/macmeter-qa-cache"
timing_evidence="$project_root/build/qa/latest-timing.json"
privacy_evidence="$project_root/build/qa/latest-runtime-privacy.json"
qa_commit="$(git rev-parse HEAD)"
qa_started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
qa_hardware="$(sysctl -n machdep.cpu.brand_string)"
qa_dirty=false
if [[ -n "$(git status --porcelain)" ]]; then qa_dirty=true; fi
mkdir -p "$(dirname "$timing_evidence")"
rm -f "$timing_evidence"
rm -f "$privacy_evidence"
bash Scripts/test-version-policy.sh
bash Scripts/test-timing-evidence.sh
bash Scripts/test-runtime-privacy-evidence.sh
env XDG_CACHE_HOME="$cache_root/xdg" \
  CLANG_MODULE_CACHE_PATH="$cache_root/clang" \
  SWIFTPM_MODULECACHE_OVERRIDE="$cache_root/clang" \
  MACMETER_RUN_HARDWARE_TESTS=1 \
  MACMETER_TIMING_EVIDENCE_PATH="$timing_evidence" \
  MACMETER_QA_COMMIT="$qa_commit" \
  MACMETER_QA_STARTED_AT="$qa_started_at" \
  MACMETER_QA_DIRTY="$qa_dirty" \
  MACMETER_QA_HARDWARE="$qa_hardware" \
  swift test --enable-code-coverage --cache-path "$cache_root/swiftpm"

test -f "$timing_evidence"
jq -e \
  --arg commit "$qa_commit" \
  --arg startedAt "$qa_started_at" \
  --arg hardware "$qa_hardware" \
  --argjson dirtyWorktree "$qa_dirty" \
  -f Scripts/timing-evidence.jq \
  "$timing_evidence" >/dev/null

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
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$app/Contents/Info.plist")" = "AppIcon"
test -f "$app/Contents/Resources/AppIcon.icns"
file "$app/Contents/MacOS/MacMeter" | grep -q "arm64"
if otool -L "$app/Contents/MacOS/MacMeter" | rg 'CFNetwork|Network\.framework|WebKit'; then
  echo "Unexpected outbound-capable framework linked" >&2
  exit 1
fi

MACMETER_APP_PATH="$app" \
  MACMETER_PRIVACY_EVIDENCE="$privacy_evidence" \
  bash Scripts/runtime-privacy-evidence.sh
MACMETER_APP_PATH="$app" bash Scripts/verify-runtime-privacy-evidence.sh "$privacy_evidence"

echo "MacMeter QA checks passed: $app"
