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
csv_fixture="$(mktemp /tmp/macmeter-performance-csv.XXXXXX)"
git_fixture="$(mktemp -d /tmp/macmeter-clean-worktree.XXXXXX)"
trap 'rm -f "$values" "$helper" "$helper_verify" "$fixture" "$fixture.tmp" "$csv_fixture" "$csv_fixture.tmp"; rmdir "$helper_directory" "$helper_verify_directory" 2>/dev/null || true; rm -rf "$git_fixture"' EXIT
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
    rawCSV:{formatVersion:1, fileName:"fixture.csv",
      sha256:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      byteCount:100},
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
make_fixture
jq '.rawCSV.sha256="not-a-digest"' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
reject_fixture
make_fixture
jq '.rawCSV.fileName="../fixture.csv"' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
reject_fixture

write_csv_fixture() {
  printf '%s\n' \
    'elapsed_seconds,rss_kib,cpu_interval_percent,interval_seconds,cpu_delta_ns,wall_delta_ns,phase' \
    '0,90,0.000,0.000,0,0,warmup' \
    '1800,100,0.100,1800.000,1800000000,1800000000000,boundary' \
    '1859,110,0.100,59.000,59000000,59000000000,measurement' \
    '1920,120,0.200,61.000,122000000,61000000000,measurement' \
    '1979,115,0.300,59.000,177000000,59000000000,measurement' >"$csv_fixture"
}
bind_csv_fixture() {
  local summary sha256 byte_count
  summary="$(bash "$project_root/Scripts/summarize-performance-csv.sh" "$csv_fixture")"
  sha256="$(shasum -a 256 "$csv_fixture" | awk '{print $1}')"
  byte_count="$(wc -c <"$csv_fixture" | tr -d '[:space:]')"
  jq \
    --arg name "$(basename "$csv_fixture")" \
    --arg sha256 "$sha256" \
    --argjson byteCount "$byte_count" \
    --argjson results "$summary" \
    '.rawCSV={formatVersion:1,fileName:$name,sha256:$sha256,byteCount:$byteCount}
      | .results=$results' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
}
reject_csv_binding() {
  if bash "$project_root/Scripts/verify-performance-csv.sh" "$fixture" "$csv_fixture" >/dev/null 2>&1; then
    echo "Invalid raw performance CSV binding unexpectedly passed" >&2
    exit 1
  fi
}

write_csv_fixture
summary="$(bash "$project_root/Scripts/summarize-performance-csv.sh" "$csv_fixture")"
jq -e '. == {samples:3, baselineRSSKiB:100, maximumRSSKiB:120,
  growthKiB:20, averageCPUPercent:0.2, p95CPUPercent:0.3,
  measurementDurationSeconds:179}' <<<"$summary" >/dev/null
make_fixture
bind_csv_fixture
bash "$project_root/Scripts/verify-performance-csv.sh" "$fixture" "$csv_fixture" >/dev/null

for mutation in \
  '.results.samples += 1' \
  '.results.measurementDurationSeconds += 1' \
  '.results.averageCPUPercent += 0.001' \
  '.results.p95CPUPercent += 0.001' \
  '.results.baselineRSSKiB += 1' \
  '.results.maximumRSSKiB += 1' \
  '.results.growthKiB += 1' \
  '.thresholds.rssLimitKiB = 119' \
  '.thresholds.growthLimitKiB = 19' \
  '.thresholds.averageCPUPercentLimit = 0.199' \
  '.thresholds.p95CPUPercentLimit = 0.299'; do
  make_fixture
  bind_csv_fixture
  jq "$mutation" "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
  reject_csv_binding
done

make_fixture
bind_csv_fixture
jq '.rawCSV.byteCount += 1' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
reject_csv_binding
make_fixture
bind_csv_fixture
jq '.rawCSV.fileName = "another.csv"' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
reject_csv_binding

# A byte-level change is rejected even when it does not alter any parsed value.
printf '\n' >>"$csv_fixture"
reject_csv_binding

# Updating the digest cannot conceal a raw-data change whose recomputed result differs.
write_csv_fixture
sed 's/0.300,59.000,177000000,59000000000,measurement/0.400,59.000,236000000,59000000000,measurement/' \
  "$csv_fixture" >"$csv_fixture.tmp" && mv "$csv_fixture.tmp" "$csv_fixture"
bind_csv_fixture
jq '.results.averageCPUPercent=0.2 | .results.p95CPUPercent=0.3' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
reject_csv_binding

# Derived display columns must agree with the independently retained raw deltas.
write_csv_fixture
sed 's/0.300,59.000,177000000/0.299,59.000,177000000/' \
  "$csv_fixture" >"$csv_fixture.tmp" && mv "$csv_fixture.tmp" "$csv_fixture"
if bash "$project_root/Scripts/summarize-performance-csv.sh" "$csv_fixture" >/dev/null 2>&1; then
  echo "Inconsistent derived CSV interval unexpectedly passed" >&2
  exit 1
fi

# elapsed_seconds must be the floor of cumulative monotonic wall-time deltas.
write_csv_fixture
sed 's/^1920,120/1919,120/' "$csv_fixture" >"$csv_fixture.tmp" && mv "$csv_fixture.tmp" "$csv_fixture"
if bash "$project_root/Scripts/summarize-performance-csv.sh" "$csv_fixture" >/dev/null 2>&1; then
  echo "CSV with elapsed time detached from raw wall deltas unexpectedly passed" >&2
  exit 1
fi

# A rebound CSV cannot claim the required warmup without raw elapsed time.
write_csv_fixture
sed 's/^1800,100,0.100,1800.000,1800000000,1800000000000,boundary$/0,100,0.000,0.000,0,0,boundary/;
  s/^1859,110/59,110/; s/^1920,120/120,120/; s/^1979,115/179,115/' \
  "$csv_fixture" >"$csv_fixture.tmp" && mv "$csv_fixture.tmp" "$csv_fixture"
make_fixture
bind_csv_fixture
reject_csv_binding

# Rebinding hashes and summaries cannot conceal a non-59/61 measurement interval.
write_csv_fixture
sed 's/^1920,120,0.200,61.000,122000000,61000000000/1860,120,0.200,1.000,2000000,1000000000/;
  s/^1979,115/1919,115/' "$csv_fixture" >"$csv_fixture.tmp" && mv "$csv_fixture.tmp" "$csv_fixture"
make_fixture
bind_csv_fixture
reject_csv_binding

# Overlapping tolerances must not let a phase-locked constant cadence pass as 59/61.
write_csv_fixture
sed 's/^1859,110,0.100,59.000,59000000,59000000000/1860,110,0.100,60.000,60000000,60000000000/;
  s/^1920,120,0.200,61.000,122000000,61000000000/1920,120,0.200,60.000,120000000,60000000000/;
  s/^1979,115,0.300,59.000,177000000,59000000000/1980,115,0.300,60.000,180000000,60000000000/' \
  "$csv_fixture" >"$csv_fixture.tmp" && mv "$csv_fixture.tmp" "$csv_fixture"
make_fixture
bind_csv_fixture
reject_csv_binding

# A swapped 61/59 sequence cannot satisfy the declared 59/61 order.
write_csv_fixture
sed 's/^1859,110,0.100,59.000,59000000,59000000000/1861,110,0.100,61.000,61000000,61000000000/;
  s/^1920,120,0.200,61.000,122000000,61000000000/1920,120,0.200,59.000,118000000,59000000000/;
  s/^1979,115,0.300,59.000,177000000,59000000000/1981,115,0.300,61.000,183000000,61000000000/' \
  "$csv_fixture" >"$csv_fixture.tmp" && mv "$csv_fixture.tmp" "$csv_fixture"
make_fixture
bind_csv_fixture
reject_csv_binding

# A short final row is invalid unless it is the interval that crosses soakSeconds.
write_csv_fixture
sed 's/^1979,115,0.300,59.000,177000000,59000000000/1921,115,0.300,1.000,3000000,1000000000/' \
  "$csv_fixture" >"$csv_fixture.tmp" && mv "$csv_fixture.tmp" "$csv_fixture"
make_fixture
bind_csv_fixture
reject_csv_binding

# The same short final row is valid when prior < target <= total proves truncation.
make_fixture
jq '.soakSeconds=121' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
bind_csv_fixture
bash "$project_root/Scripts/verify-performance-csv.sh" "$fixture" "$csv_fixture" >/dev/null

# Phase ordering and a unique boundary are part of the independently parsed record.
write_csv_fixture
sed '/boundary$/d' "$csv_fixture" >"$csv_fixture.tmp" && mv "$csv_fixture.tmp" "$csv_fixture"
if bash "$project_root/Scripts/summarize-performance-csv.sh" "$csv_fixture" >/dev/null 2>&1; then
  echo "CSV without a measurement boundary unexpectedly passed" >&2
  exit 1
fi
write_csv_fixture
sed -n '/boundary$/p' "$csv_fixture" >>"$csv_fixture"
if bash "$project_root/Scripts/summarize-performance-csv.sh" "$csv_fixture" >/dev/null 2>&1; then
  echo "CSV with a second measurement boundary unexpectedly passed" >&2
  exit 1
fi

echo "Performance harness checks passed"
