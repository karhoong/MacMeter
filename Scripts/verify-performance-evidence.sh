#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
evidence="${1:-$project_root/build/qa/latest-performance.json}"
csv_override="${2:-${MACMETER_PERFORMANCE_OUTPUT:-}}"
app="${MACMETER_APP_PATH:-$project_root/build/DerivedData/Build/Products/Release/MacMeter.app}"
executable="$app/Contents/MacOS/MacMeter"
source "$project_root/Scripts/performance-math.sh"

test -f "$evidence"
test -x "$executable"
if ! require_clean_worktree "$project_root"; then
  echo "Current worktree is not clean" >&2
  exit 1
fi
commit="$(git -C "$project_root" rev-parse HEAD)"
hardware="$(sysctl -n machdep.cpu.brand_string)"
binary_sha256="$(shasum -a 256 "$executable" | awk '{print $1}')"
metrics_source_sha256="$(shasum -a 256 "$project_root/Scripts/process-metrics.c" | awk '{print $1}')"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
metrics_directory="$(mktemp -d /tmp/macmeter-verify-metrics.XXXXXX)"
metrics_binary="$metrics_directory/process-metrics"
trap 'rm -f "$metrics_binary"; rmdir "$metrics_directory" 2>/dev/null || true' EXIT
xcrun clang -O2 -Wall -Wextra -Werror \
  "$project_root/Scripts/process-metrics.c" -o "$metrics_binary"
metrics_binary_sha256="$(shasum -a 256 "$metrics_binary" | awk '{print $1}')"
metrics_compiler="$(xcrun clang --version | head -1)"

jq -e \
  --arg commit "$commit" \
  --arg hardware "$hardware" \
  --arg binarySHA256 "$binary_sha256" \
  --arg metricsSourceSHA256 "$metrics_source_sha256" \
  --arg metricsBinarySHA256 "$metrics_binary_sha256" \
  --arg metricsCompiler "$metrics_compiler" \
  --arg version "$version" \
  --arg build "$build" \
  -f "$project_root/Scripts/performance-evidence.jq" \
  "$evidence" >/dev/null

if [[ -n "$csv_override" ]]; then
  raw_csv="$csv_override"
else
  evidence_directory="$(cd "$(dirname "$evidence")" && pwd)"
  raw_csv="$evidence_directory/$(jq -er '.rawCSV.fileName' "$evidence")"
fi
bash "$project_root/Scripts/verify-performance-csv.sh" "$evidence" "$raw_csv" >/dev/null

echo "Performance evidence validates for $commit"
