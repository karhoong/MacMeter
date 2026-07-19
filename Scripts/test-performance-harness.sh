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
helper_before="$("$helper" "$$")"
if ! [[ "$helper_before" =~ ^[0-9]+,[0-9]+,[0-9]+$ ]]; then
  echo "Process metrics helper did not emit exactly three unsigned fields" >&2
  exit 1
fi
IFS=, read -r cpu_before wall_before footprint_before <<<"$helper_before"
work=0
for ((index = 0; index < 50000; index++)); do work=$((work + index)); done
IFS=, read -r cpu_after wall_after footprint_after < <("$helper" "$$")
test "$cpu_after" -ge "$cpu_before"
test "$wall_after" -gt "$wall_before"
test "$footprint_before" -gt 0
test "$footprint_after" -gt 0
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
    schemaVersion:2, status:"passed", commit:"fixture-commit", hardware:"Fixture Mac",
    binarySHA256:"fixture-binary", metricsSourceSHA256:"fixture-metrics",
    metricsBinarySHA256:"fixture-metrics-binary", metricsCompiler:"Fixture Clang",
    sleepPreventionMethod:"caffeinate -dimsu -w harness PID with per-sample liveness checks",
    dirtyWorktree:false, version:"0.1.0", build:"1",
    startedAt:"2026-01-01T00:00:00Z", finishedAt:"2026-01-02T00:30:00Z",
    warmupSeconds:1800, soakSeconds:86400, sampleSeconds:60,
    sampleCadenceSeconds:[59,61],
    cpuMeasurementMethod:"proc_pid_rusage cumulative user+system CPU nanoseconds divided by CLOCK_MONOTONIC wall-time deltas",
    rssMeasurementMethod:"/bin/ps resident set size in KiB; active release gate",
    physicalFootprintMeasurementMethod:"proc_pid_rusage RUSAGE_INFO_V4 ri_phys_footprint bytes floored after division by 1024; observational until policy approval",
    thresholds:{rssLimitKiB:81920, growthLimitKiB:5120,
      averageCPUPercentLimit:1, p95CPUPercentLimit:3},
    rawCSV:{formatVersion:2, fileName:"fixture.csv",
      sha256:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      byteCount:100},
    results:{samples:1440, baselineRSSKiB:73472, maximumRSSKiB:74000,
      growthKiB:528, averageCPUPercent:0.7, p95CPUPercent:2.2,
      baselinePhysicalFootprintKiB:22000, maximumPhysicalFootprintKiB:22400,
      physicalFootprintGrowthKiB:400,
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
make_fixture
jq '.schemaVersion=1' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
reject_fixture
make_fixture
jq 'del(.rssMeasurementMethod)' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
reject_fixture
make_fixture
jq 'del(.physicalFootprintMeasurementMethod)' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
reject_fixture
make_fixture
jq '.results.maximumPhysicalFootprintKiB=.results.baselinePhysicalFootprintKiB-1' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
reject_fixture
make_fixture
jq '.results.physicalFootprintGrowthKiB=399.5' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
reject_fixture

write_csv_fixture() {
  printf '%s\n' \
    'elapsed_seconds,rss_kib,physical_footprint_kib,cpu_interval_percent,interval_seconds,cpu_delta_ns,wall_delta_ns,phase' \
    '0,90,40,0.000,0.000,0,0,warmup' \
    '1800,100,50,0.100,1800.000,1800000000,1800000000000,boundary' \
    '1859,110,60,0.100,59.000,59000000,59000000000,measurement' \
    '1920,120,70,0.200,61.000,122000000,61000000000,measurement' \
    '1979,115,65,0.300,59.000,177000000,59000000000,measurement' >"$csv_fixture"
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
    '.rawCSV={formatVersion:2,fileName:$name,sha256:$sha256,byteCount:$byteCount}
      | .results=$results' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
}
write_failed_csv_fixture() {
  printf '%s\n' \
    'elapsed_seconds,rss_kib,physical_footprint_kib,cpu_interval_percent,interval_seconds,cpu_delta_ns,wall_delta_ns,phase' \
    '0,90,40,0.000,0.000,0,0,warmup' \
    '1800,100,50,0.100,1800.000,1800000000,1800000000000,boundary' \
    '1859,110,60,0.100,59.000,59000000,59000000000,measurement' \
    '1920,118,68,0.200,61.000,122000000,61000000000,measurement' \
    '1979,120,70,0.300,59.000,177000000,59000000000,measurement' >"$csv_fixture"
}
rebind_failed_csv_fixture() {
  local summary sha256 byte_count latest_rss latest_physical
  summary="$(bash "$project_root/Scripts/summarize-performance-csv.sh" "$csv_fixture")"
  sha256="$(shasum -a 256 "$csv_fixture" | awk '{print $1}')"
  byte_count="$(wc -c <"$csv_fixture" | tr -d '[:space:]')"
  latest_rss="$(awk -F, '$8 == "measurement" { latest = $2 } END { print latest }' "$csv_fixture")"
  latest_physical="$(awk -F, '$8 == "measurement" { latest = $3 } END { print latest }' "$csv_fixture")"
  jq --arg name "$(basename "$csv_fixture")" --arg sha256 "$sha256" \
    --argjson byteCount "$byte_count" --argjson summary "$summary" --argjson latestRSSKiB "$latest_rss" \
    --argjson latestPhysicalFootprintKiB "$latest_physical" '
    .rawCSV={formatVersion:2,fileName:$name,sha256:$sha256,byteCount:$byteCount}
    | .partialResults=$summary
    | .failure.measurements={samples:$summary.samples,latestRSSKiB:$latestRSSKiB,
        baselineRSSKiB:$summary.baselineRSSKiB,maximumRSSKiB:$summary.maximumRSSKiB,
        growthKiB:$summary.growthKiB,
        latestPhysicalFootprintKiB:$latestPhysicalFootprintKiB,
        baselinePhysicalFootprintKiB:$summary.baselinePhysicalFootprintKiB,
        maximumPhysicalFootprintKiB:$summary.maximumPhysicalFootprintKiB,
        physicalFootprintGrowthKiB:$summary.physicalFootprintGrowthKiB}' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
}
make_failed_fixture() {
  make_fixture
  write_failed_csv_fixture
  bind_csv_fixture
  jq '.status="failed"
    | .thresholds.rssLimitKiB=119
    | .failureReason="RSS limit failed: 120KiB > 119KiB after warm-up"
    | .exitCode=1
    | .failure={kind:"rss_limit",reason:.failureReason,exitCode:1,
        measurements:{samples:.results.samples,latestRSSKiB:120,
          baselineRSSKiB:.results.baselineRSSKiB,
          maximumRSSKiB:.results.maximumRSSKiB,growthKiB:.results.growthKiB,
          latestPhysicalFootprintKiB:70,
          baselinePhysicalFootprintKiB:.results.baselinePhysicalFootprintKiB,
          maximumPhysicalFootprintKiB:.results.maximumPhysicalFootprintKiB,
          physicalFootprintGrowthKiB:.results.physicalFootprintGrowthKiB}}
    | .partialResults=.results
    | del(.results)' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
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
  growthKiB:20, baselinePhysicalFootprintKiB:50,
  maximumPhysicalFootprintKiB:70, physicalFootprintGrowthKiB:20,
  averageCPUPercent:0.2, p95CPUPercent:0.3,
  measurementDurationSeconds:179}' <<<"$summary" >/dev/null
make_fixture
bind_csv_fixture
bash "$project_root/Scripts/verify-performance-csv.sh" "$fixture" "$csv_fixture" >/dev/null

# Failed evidence is also raw-bound and independently recomputed, but never
# accepted by the release-only performance-evidence.jq contract.
make_failed_fixture
bash "$project_root/Scripts/verify-performance-csv.sh" "$fixture" "$csv_fixture" >/dev/null
if validate_fixture; then
  echo "Failed evidence unexpectedly passed the release contract" >&2
  exit 1
fi
jq '.partialResults.maximumRSSKiB += 1' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
reject_csv_binding
for mutation in \
  '.failure.measurements.latestPhysicalFootprintKiB += 1' \
  '.failure.measurements.baselinePhysicalFootprintKiB += 1' \
  '.failure.measurements.maximumPhysicalFootprintKiB += 1' \
  '.failure.measurements.physicalFootprintGrowthKiB += 1'; do
  make_failed_fixture
  jq "$mutation" "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
  reject_csv_binding
done
make_failed_fixture
jq 'del(.rawCSV)' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
reject_csv_binding
make_failed_fixture
jq 'del(.cpuMeasurementMethod)' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
reject_csv_binding
make_failed_fixture
jq '.failureReason=""' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
reject_csv_binding
make_failed_fixture
jq '.failure.kind="rss_growth"' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
reject_csv_binding
make_failed_fixture
jq '.thresholds.rssLimitKiB=120' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
reject_csv_binding
jq '.thresholds.rssLimitKiB=119' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
make_failed_fixture
jq '.failure.exitCode=0 | .exitCode=0' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
reject_csv_binding
make_failed_fixture
jq '.failure.exitCode=1.5 | .exitCode=1.5' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
reject_csv_binding
make_failed_fixture
jq '.rawCSV.formatVersion=1' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
reject_csv_binding
make_failed_fixture
jq '.thresholds.rssLimitKiB="119"' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
reject_csv_binding
make_failed_fixture
jq '.thresholds.growthLimitKiB=-1' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
reject_csv_binding
make_failed_fixture
jq '.thresholds.averageCPUPercentLimit="1"' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
reject_csv_binding
make_failed_fixture
jq '.thresholds.p95CPUPercentLimit=-0.1' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
reject_csv_binding

# An RSS failure must end on the first crossing; a rebound after an earlier
# breach is impossible under the producer's fail-fast state machine.
make_failed_fixture
sed 's/^1920,118/1920,120/; s/^1979,120/1979,115/' "$csv_fixture" >"$csv_fixture.tmp" && mv "$csv_fixture.tmp" "$csv_fixture"
rebind_failed_csv_fixture
reject_csv_binding

# A producer with immediate boundary gating cannot emit later measurements
# when the boundary itself already exceeds the absolute RSS limit.
make_failed_fixture
sed -n '1,4p' "$csv_fixture" >"$csv_fixture.tmp" && mv "$csv_fixture.tmp" "$csv_fixture"
rebind_failed_csv_fixture
jq '.thresholds.rssLimitKiB=99' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
reject_csv_binding

# A boundary that already exceeds the absolute RSS limit is a valid, bound,
# zero-measurement failure and must not wait for another cadence interval.
printf '%s\n' \
  'elapsed_seconds,rss_kib,physical_footprint_kib,cpu_interval_percent,interval_seconds,cpu_delta_ns,wall_delta_ns,phase' \
  '0,120,50,0.000,0.000,0,0,boundary' >"$csv_fixture"
make_fixture
sha256="$(shasum -a 256 "$csv_fixture" | awk '{print $1}')"
byte_count="$(wc -c <"$csv_fixture" | tr -d '[:space:]')"
jq --arg name "$(basename "$csv_fixture")" --arg sha256 "$sha256" --argjson byteCount "$byte_count" '
  .status="failed" | .warmupSeconds=0 | .soakSeconds=10 | .sampleSeconds=1
  | .sampleCadenceSeconds=[1] | .thresholds.rssLimitKiB=119
  | .rawCSV={formatVersion:2,fileName:$name,sha256:$sha256,byteCount:$byteCount}
  | .failureReason="RSS limit failed: 120KiB > 119KiB at the measurement boundary"
  | .exitCode=1
  | .failure={kind:"rss_limit",reason:.failureReason,exitCode:1,
      measurements:{samples:0,latestRSSKiB:120,baselineRSSKiB:120,
        maximumRSSKiB:120,growthKiB:0,
        latestPhysicalFootprintKiB:50,baselinePhysicalFootprintKiB:50,
        maximumPhysicalFootprintKiB:50,physicalFootprintGrowthKiB:0}}
  | del(.results)' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
bash "$project_root/Scripts/verify-performance-csv.sh" "$fixture" "$csv_fixture" >/dev/null
jq '.failure.measurements.latestPhysicalFootprintKiB += 1' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
reject_csv_binding
jq '.failure.measurements.latestPhysicalFootprintKiB -= 1' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
jq '.thresholds.rssLimitKiB=120' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
reject_csv_binding

# Zero-sample failures still traverse the strict eight-column parser.
for mutation in \
  'wrong_header' \
  'bad_elapsed' \
  'bad_derived' \
  'unknown_phase'; do
  printf '%s\n' \
    'elapsed_seconds,rss_kib,physical_footprint_kib,cpu_interval_percent,interval_seconds,cpu_delta_ns,wall_delta_ns,phase' \
    '0,120,50,0.000,0.000,0,0,boundary' >"$csv_fixture"
  case "$mutation" in
    wrong_header) sed '1s/elapsed_seconds/elapsed/' "$csv_fixture" >"$csv_fixture.tmp" ;;
    bad_elapsed) sed '2s/^0,/1,/' "$csv_fixture" >"$csv_fixture.tmp" ;;
    bad_derived) sed '2s/0.000,0.000,0,0/0.001,0.000,0,0/' "$csv_fixture" >"$csv_fixture.tmp" ;;
    unknown_phase) sed '2s/boundary/mystery/' "$csv_fixture" >"$csv_fixture.tmp" ;;
  esac
  mv "$csv_fixture.tmp" "$csv_fixture"
  sha256="$(shasum -a 256 "$csv_fixture" | awk '{print $1}')"
  byte_count="$(wc -c <"$csv_fixture" | tr -d '[:space:]')"
  jq --arg sha256 "$sha256" --argjson byteCount "$byte_count" \
    '.rawCSV.sha256=$sha256 | .rawCSV.byteCount=$byteCount' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
  reject_csv_binding
done

# The strict v2 parser rejects malformed or missing physical-footprint values.
for mutation in negative fractional nonnumeric missing extra v1_header; do
  write_csv_fixture
  case "$mutation" in
    negative) sed 's/^1920,120,70,/1920,120,-1,/' "$csv_fixture" >"$csv_fixture.tmp" ;;
    fractional) sed 's/^1920,120,70,/1920,120,70.5,/' "$csv_fixture" >"$csv_fixture.tmp" ;;
    nonnumeric) sed 's/^1920,120,70,/1920,120,unknown,/' "$csv_fixture" >"$csv_fixture.tmp" ;;
    missing) sed 's/^1920,120,70,/1920,120,/' "$csv_fixture" >"$csv_fixture.tmp" ;;
    extra) sed 's/^1920,120,70,/1920,120,70,extra,/' "$csv_fixture" >"$csv_fixture.tmp" ;;
    v1_header) sed '1s/,physical_footprint_kib//' "$csv_fixture" >"$csv_fixture.tmp" ;;
  esac
  mv "$csv_fixture.tmp" "$csv_fixture"
  if bash "$project_root/Scripts/summarize-performance-csv.sh" "$csv_fixture" >/dev/null 2>&1; then
    echo "Malformed v2 physical-footprint CSV unexpectedly passed: $mutation" >&2
    exit 1
  fi
done

write_csv_fixture

# End-only CPU failures cannot be claimed from an early, cadence-valid partial
# run even when the partial aggregate currently exceeds the threshold.
make_fixture
bind_csv_fixture
jq '.status="failed"
  | .thresholds.averageCPUPercentLimit=0.1
  | .failureReason="Idle CPU limit failed"
  | .exitCode=1
  | .failure={kind:"cpu_average",reason:.failureReason,exitCode:1,
      measurements:{samples:.results.samples,latestRSSKiB:115,
        baselineRSSKiB:.results.baselineRSSKiB,
        maximumRSSKiB:.results.maximumRSSKiB,growthKiB:.results.growthKiB,
        latestPhysicalFootprintKiB:65,
        baselinePhysicalFootprintKiB:.results.baselinePhysicalFootprintKiB,
        maximumPhysicalFootprintKiB:.results.maximumPhysicalFootprintKiB,
        physicalFootprintGrowthKiB:.results.physicalFootprintGrowthKiB}}
  | .partialResults=.results
  | del(.results)' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
reject_csv_binding

write_csv_fixture

if ! rg -n 'maximum_rss > rss_limit_kib' "$project_root/Scripts/performance-soak.sh" >/dev/null ||
   ! rg -n 'maximum_rss - baseline_rss > growth_limit_kib' "$project_root/Scripts/performance-soak.sh" >/dev/null; then
  echo "Performance harness is missing per-sample fail-fast RSS checks" >&2
  exit 1
fi

for mutation in \
  '.results.samples += 1' \
  '.results.measurementDurationSeconds += 1' \
  '.results.averageCPUPercent += 0.001' \
  '.results.p95CPUPercent += 0.001' \
  '.results.baselineRSSKiB += 1' \
  '.results.maximumRSSKiB += 1' \
  '.results.growthKiB += 1' \
  '.results.baselinePhysicalFootprintKiB += 1' \
  '.results.maximumPhysicalFootprintKiB += 1' \
  '.results.physicalFootprintGrowthKiB += 1' \
  '.thresholds.rssLimitKiB = 119' \
  '.thresholds.growthLimitKiB = 19' \
  '.thresholds.averageCPUPercentLimit = 0.199' \
  '.thresholds.p95CPUPercentLimit = 0.299'; do
  make_fixture
  bind_csv_fixture
  jq "$mutation" "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
  reject_csv_binding
done

# Physical footprint is observational in v2: it is strictly recorded but is
# not silently substituted for the still-active RSS release gate.
write_csv_fixture
sed 's/,50,0.100,1800.000/,999999,0.100,1800.000/;
  s/,60,0.100,59.000/,1000000,0.100,59.000/;
  s/,70,0.200,61.000/,2000000,0.200,61.000/;
  s/,65,0.300,59.000/,1500000,0.300,59.000/' \
  "$csv_fixture" >"$csv_fixture.tmp" && mv "$csv_fixture.tmp" "$csv_fixture"
make_fixture
bind_csv_fixture
bash "$project_root/Scripts/verify-performance-csv.sh" "$fixture" "$csv_fixture" >/dev/null

# Rebinding the file digest cannot conceal a physical-footprint aggregate edit.
write_csv_fixture
make_fixture
bind_csv_fixture
sed 's/^1920,120,70,/1920,120,71,/' "$csv_fixture" >"$csv_fixture.tmp" && mv "$csv_fixture.tmp" "$csv_fixture"
sha256="$(shasum -a 256 "$csv_fixture" | awk '{print $1}')"
byte_count="$(wc -c <"$csv_fixture" | tr -d '[:space:]')"
jq --arg sha256 "$sha256" --argjson byteCount "$byte_count" \
  '.rawCSV.sha256=$sha256 | .rawCSV.byteCount=$byteCount' "$fixture" >"$fixture.tmp" && mv "$fixture.tmp" "$fixture"
reject_csv_binding

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
sed 's/^1800,100,50,0.100,1800.000,1800000000,1800000000000,boundary$/0,100,50,0.000,0.000,0,0,boundary/;
  s/^1859,110/59,110/; s/^1920,120/120,120/; s/^1979,115/179,115/' \
  "$csv_fixture" >"$csv_fixture.tmp" && mv "$csv_fixture.tmp" "$csv_fixture"
make_fixture
bind_csv_fixture
reject_csv_binding

# Rebinding hashes and summaries cannot conceal a non-59/61 measurement interval.
write_csv_fixture
sed 's/^1920,120,70,0.200,61.000,122000000,61000000000/1860,120,70,0.200,1.000,2000000,1000000000/;
  s/^1979,115/1919,115/' "$csv_fixture" >"$csv_fixture.tmp" && mv "$csv_fixture.tmp" "$csv_fixture"
make_fixture
bind_csv_fixture
reject_csv_binding

# Overlapping tolerances must not let a phase-locked constant cadence pass as 59/61.
write_csv_fixture
sed 's/^1859,110,60,0.100,59.000,59000000,59000000000/1860,110,60,0.100,60.000,60000000,60000000000/;
  s/^1920,120,70,0.200,61.000,122000000,61000000000/1920,120,70,0.200,60.000,120000000,60000000000/;
  s/^1979,115,65,0.300,59.000,177000000,59000000000/1980,115,65,0.300,60.000,180000000,60000000000/' \
  "$csv_fixture" >"$csv_fixture.tmp" && mv "$csv_fixture.tmp" "$csv_fixture"
make_fixture
bind_csv_fixture
reject_csv_binding

# A swapped 61/59 sequence cannot satisfy the declared 59/61 order.
write_csv_fixture
sed 's/^1859,110,60,0.100,59.000,59000000,59000000000/1861,110,60,0.100,61.000,61000000,61000000000/;
  s/^1920,120,70,0.200,61.000,122000000,61000000000/1920,120,70,0.200,59.000,118000000,59000000000/;
  s/^1979,115,65,0.300,59.000,177000000,59000000000/1981,115,65,0.300,61.000,183000000,61000000000/' \
  "$csv_fixture" >"$csv_fixture.tmp" && mv "$csv_fixture.tmp" "$csv_fixture"
make_fixture
bind_csv_fixture
reject_csv_binding

# A short final row is invalid unless it is the interval that crosses soakSeconds.
write_csv_fixture
sed 's/^1979,115,65,0.300,59.000,177000000,59000000000/1921,115,65,0.300,1.000,3000000,1000000000/' \
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
