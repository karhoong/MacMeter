#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
source "$project_root/Scripts/performance-math.sh"

test "$(cpu_percent_from_deltas 500000000 10000000000)" = "5.000"
test "$(cpu_percent_from_deltas 0 61000000000)" = "0.000"
if cpu_percent_from_deltas 1 0 >/dev/null 2>&1; then
  echo "Zero wall-time delta unexpectedly passed" >&2
  exit 1
fi

values="$(mktemp /tmp/macmeter-performance-values.XXXXXX)"
helper_directory="$(mktemp -d /tmp/macmeter-process-metrics-test.XXXXXX)"
helper_verify_directory="$(mktemp -d /tmp/macmeter-process-metrics-verify.XXXXXX)"
helper="$helper_directory/process-metrics"
helper_verify="$helper_verify_directory/process-metrics"
trap 'rm -f "$values" "$helper" "$helper_verify"; rmdir "$helper_directory" "$helper_verify_directory" 2>/dev/null || true' EXIT
printf '0.100\n3.000\n0.500\n4.000\n1.000\n' >"$values"
test "$(nearest_rank_percentile "$values" 5 95)" = "4.000"

xcrun clang -O2 -Wall -Wextra -Werror \
  "$project_root/Scripts/process-metrics.c" -o "$helper"
xcrun clang -O2 -Wall -Wextra -Werror \
  "$project_root/Scripts/process-metrics.c" -o "$helper_verify"
test "$(shasum -a 256 "$helper" | awk '{print $1}')" = "$(shasum -a 256 "$helper_verify" | awk '{print $1}')"
IFS=, read -r cpu_before wall_before < <("$helper" "$$")
work=0
for ((index = 0; index < 50000; index++)); do work=$((work + index)); done
IFS=, read -r cpu_after wall_after < <("$helper" "$$")
test "$cpu_after" -ge "$cpu_before"
test "$wall_after" -gt "$wall_before"
test "$work" -gt 0

if rg -n 'ps[[:space:]].*-o[[:space:]]+%cpu|cpu_sum' "$project_root/Scripts/performance-soak.sh"; then
  echo "Performance harness still uses decaying ps %cpu snapshots" >&2
  exit 1
fi

fixture="$(mktemp /tmp/macmeter-performance-evidence.XXXXXX)"
git_fixture="$(mktemp -d /tmp/macmeter-clean-worktree.XXXXXX)"
trap 'rm -f "$values" "$helper" "$helper_verify" "$fixture" "$fixture.tmp"; rmdir "$helper_directory" "$helper_verify_directory" 2>/dev/null || true; rm -rf "$git_fixture"' EXIT
git -C "$git_fixture" init -q
require_clean_worktree "$git_fixture"
touch "$git_fixture/untracked"
if require_clean_worktree "$git_fixture"; then
  echo "Dirty worktree unexpectedly passed" >&2
  exit 1
fi
make_fixture() {
  jq -n '{
    status:"passed", commit:"fixture-commit", hardware:"Fixture Mac",
    binarySHA256:"fixture-binary", metricsSourceSHA256:"fixture-metrics",
    metricsBinarySHA256:"fixture-metrics-binary", metricsCompiler:"Fixture Clang",
    sleepPreventionMethod:"caffeinate -dimsu -w harness PID with per-sample liveness checks",
    dirtyWorktree:false, version:"0.1.0", build:"1",
    startedAt:"2026-01-01T00:00:00Z", finishedAt:"2026-01-02T00:30:00Z",
    warmupSeconds:1800, soakSeconds:86400, sampleSeconds:60,
    sampleCadenceSeconds:[59,61],
    cpuMeasurementMethod:"proc_pid_rusage cumulative user+system CPU nanoseconds divided by CLOCK_MONOTONIC wall-time deltas",
    thresholds:{rssLimitKiB:81920, growthLimitKiB:5120,
      averageCPUPercentLimit:1, p95CPUPercentLimit:3},
    results:{samples:1440, baselineRSSKiB:73472, maximumRSSKiB:74000,
      growthKiB:528, averageCPUPercent:0.7, p95CPUPercent:2.2,
      measurementDurationSeconds:86401}
  }' >"$fixture"
}
validate_fixture() {
  jq -e --arg commit fixture-commit --arg hardware "Fixture Mac" \
    --arg binarySHA256 fixture-binary --arg metricsSourceSHA256 fixture-metrics \
    --arg metricsBinarySHA256 fixture-metrics-binary --arg metricsCompiler "Fixture Clang" \
    --arg version 0.1.0 --arg build 1 \
    -f "$project_root/Scripts/performance-evidence.jq" "$fixture" >/dev/null
}
reject_fixture() {
  if validate_fixture; then
    echo "Invalid performance evidence unexpectedly passed" >&2
    exit 1
  fi
}

make_fixture
validate_fixture
make_fixture
jq '.sampleCadenceSeconds=[60]' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
reject_fixture
make_fixture
jq '.dirtyWorktree=true' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
reject_fixture
make_fixture
jq '.results.averageCPUPercent=1.001' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
reject_fixture
make_fixture
jq '.results.measurementDurationSeconds=86399' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
reject_fixture
make_fixture
jq 'del(.cpuMeasurementMethod)' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
reject_fixture
make_fixture
jq '.results.growthKiB=527' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
reject_fixture

echo "Performance harness checks passed"
