#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
filter="$project_root/Scripts/timing-evidence.jq"

validate() {
  jq -e \
    --arg commit "fixture-sha" \
    --arg startedAt "2026-07-19T00:00:00Z" \
    --arg hardware "Apple M4 Max" \
    --argjson dirtyWorktree false \
    -f "$filter" >/dev/null
}

valid='{"commit":"fixture-sha","startedAt":"2026-07-19T00:00:00Z","hardware":"Apple M4 Max","dirtyWorktree":false,"refresh":{"refreshErrorP95Seconds":0.1,"hostPaintP95Seconds":0.2,"renderFailures":0},"cycle":{"errorP95Seconds":0.1}}'
printf '%s' "$valid" | validate

invalid_documents=(
  '{"commit":"fixture-sha","startedAt":"2026-07-19T00:00:00Z","hardware":"Apple M4 Max","dirtyWorktree":false,"refresh":{"renderFailures":0}}'
  '{"commit":"fixture-sha","startedAt":"2026-07-19T00:00:00Z","hardware":"Apple M4 Max","dirtyWorktree":false,"refresh":{"refreshErrorP95Seconds":"0.1","hostPaintP95Seconds":0.2,"renderFailures":0},"cycle":{"errorP95Seconds":0.1}}'
  '{"commit":"wrong-sha","startedAt":"2026-07-19T00:00:00Z","hardware":"Apple M4 Max","dirtyWorktree":false,"refresh":{"refreshErrorP95Seconds":0.1,"hostPaintP95Seconds":0.2,"renderFailures":0},"cycle":{"errorP95Seconds":0.1}}'
  '{"commit":"fixture-sha","startedAt":"2026-07-19T00:00:00Z","hardware":"Apple M4 Max","dirtyWorktree":false,"refresh":{"refreshErrorP95Seconds":0.201,"hostPaintP95Seconds":0.2,"renderFailures":0},"cycle":{"errorP95Seconds":0.1}}'
)

for document in "${invalid_documents[@]}"; do
  if printf '%s' "$document" | validate; then
    echo "Invalid timing evidence unexpectedly passed: $document" >&2
    exit 1
  fi
done

echo "Timing evidence validator checks passed"
