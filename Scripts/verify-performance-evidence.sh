#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
evidence="${1:-$project_root/QA/latest-performance.json}"
app="${MACMETER_APP_PATH:-$project_root/build/DerivedData/Build/Products/Release/MacMeter.app}"
executable="$app/Contents/MacOS/MacMeter"

test -f "$evidence"
test -x "$executable"
commit="$(git -C "$project_root" rev-parse HEAD)"
hardware="$(sysctl -n machdep.cpu.brand_string)"
binary_sha256="$(shasum -a 256 "$executable" | awk '{print $1}')"
metrics_source_sha256="$(shasum -a 256 "$project_root/Scripts/process-metrics.c" | awk '{print $1}')"

jq -e \
  --arg commit "$commit" \
  --arg hardware "$hardware" \
  --arg binarySHA256 "$binary_sha256" \
  --arg metricsSourceSHA256 "$metrics_source_sha256" \
  -f "$project_root/Scripts/performance-evidence.jq" \
  "$evidence" >/dev/null

echo "Performance evidence validates for $commit"
