#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
evidence="${1:?usage: verify-performance-csv.sh EVIDENCE_JSON RAW_CSV}"
csv="${2:?usage: verify-performance-csv.sh EVIDENCE_JSON RAW_CSV}"

test -f "$evidence"
test -f "$csv"

expected_name="$(jq -er '.rawCSV.fileName' "$evidence")"
expected_sha256="$(jq -er '.rawCSV.sha256' "$evidence")"
expected_bytes="$(jq -er '.rawCSV.byteCount' "$evidence")"
format_version="$(jq -er '.rawCSV.formatVersion | select(. == 1)' "$evidence")"
status="$(jq -er '.status | select(. == "passed" or . == "failed")' "$evidence")"
failure_kind=""
if [[ "$status" == "failed" ]]; then
  failure_kind="$(jq -er '.failure.kind | select(type == "string" and length > 0)' "$evidence")"
fi
actual_name="$(basename "$csv")"
actual_sha256="$(shasum -a 256 "$csv" | awk '{print $1}')"
actual_bytes="$(wc -c <"$csv" | tr -d '[:space:]')"
warmup_seconds="$(jq -er '.warmupSeconds | select(type == "number" and . >= 0 and . == floor)' "$evidence")"
cadence_csv="$(jq -er '
  .sampleCadenceSeconds
  | select(type == "array" and length > 0)
  | select(all(.[]; type == "number" and . > 0 and . == floor))
  | map(tostring) | join(",")
' "$evidence")"
soak_seconds="$(jq -er '.soakSeconds | select(type == "number" and . > 0 and . == floor)' "$evidence")"
rss_limit_kib="$(jq -er '.thresholds.rssLimitKiB | select(type == "number" and . > 0 and . == floor)' "$evidence")"
growth_limit_kib="$(jq -er '.thresholds.growthLimitKiB | select(type == "number" and . >= 0 and . == floor)' "$evidence")"
cpu_average_limit="$(jq -er '.thresholds.averageCPUPercentLimit | select(type == "number" and . >= 0)' "$evidence")"
cpu_p95_limit="$(jq -er '.thresholds.p95CPUPercentLimit | select(type == "number" and . >= 0)' "$evidence")"

if [[ "$actual_name" != "$expected_name" ]]; then
  echo "Raw performance CSV filename does not match evidence" >&2
  exit 1
fi
if [[ "$actual_sha256" != "$expected_sha256" ]]; then
  echo "Raw performance CSV SHA-256 does not match evidence" >&2
  exit 1
fi
if [[ "$actual_bytes" != "$expected_bytes" ]]; then
  echo "Raw performance CSV byte count does not match evidence" >&2
  exit 1
fi

LC_ALL=C awk -F, -v warmup_seconds="$warmup_seconds" -v soak_seconds="$soak_seconds" \
  -v cadence_csv="$cadence_csv" -v evidence_status="$status" -v failure_kind="$failure_kind" '
  function invalid(message) {
    print "Raw performance schedule does not match evidence: " message > "/dev/stderr"
    exit 1
  }
  BEGIN {
    cadence_count = split(cadence_csv, cadence, ",")
    if (cadence_count == 0) invalid("empty sample cadence")
  }
  NR == 1 { next }
  {
    cumulative_wall_ns += $6 + 0
    if ($7 == "boundary") {
      boundary_count++
      if (cumulative_wall_ns < warmup_seconds * 1000000000) {
        invalid("measurement boundary precedes declared warmup")
      }
    } else if ($7 == "measurement") {
      measurement_count++
      measurement_wall_ns[measurement_count] = $6 + 0
      measurement_total_ns += $6 + 0
    }
  }
  END {
    if (boundary_count != 1) exit 1
    if (measurement_count == 0) {
      if (evidence_status != "failed" || failure_kind != "rss_limit") exit 1
      exit 0
    }
    for (sample_index = 1; sample_index <= measurement_count; sample_index++) {
      expected = cadence[((sample_index - 1) % cadence_count) + 1]
      actual = measurement_wall_ns[sample_index] / 1000000000
      early_tolerance = expected * 0.005
      if (early_tolerance < 0.05) early_tolerance = 0.05
      if (early_tolerance > 0.25) early_tolerance = 0.25
      late_tolerance = expected * 0.01
      if (late_tolerance < 0.1) late_tolerance = 0.1
      if (late_tolerance > 0.75) late_tolerance = 0.75
      if (sample_index < measurement_count &&
          (actual < expected - early_tolerance || actual > expected + late_tolerance)) {
        invalid("measurement interval " sample_index " is outside cadence tolerance")
      }
      if (sample_index == measurement_count && actual > expected + late_tolerance) {
        invalid("final measurement interval exceeds cadence tolerance")
      }
      if (sample_index == measurement_count && actual < expected - early_tolerance) {
        prior_measurement_ns = measurement_total_ns - measurement_wall_ns[sample_index]
        target_ns = soak_seconds * 1000000000
        if (prior_measurement_ns >= target_ns || measurement_total_ns < target_ns) {
          invalid("short final interval is not justified by crossing the soak target")
        }
      }
    }
  }
' "$csv"

measurement_count="$(awk -F, 'NR > 1 && $7 == "measurement" { count++ } END { print count + 0 }' "$csv")"
if (( measurement_count == 0 )); then
  zero_summary="$(bash "$project_root/Scripts/summarize-performance-csv.sh" "$csv" --allow-zero)"
  jq -e --argjson zeroSummary "$zero_summary" '
    .status == "failed"
    and .rawCSV.formatVersion == 1
    and (.failure.kind == "rss_limit")
    and (.failure.reason | type == "string" and length > 0)
    and (.failure.exitCode | type == "number" and . == floor and . != 0)
    and .failureReason == .failure.reason
    and .exitCode == .failure.exitCode
    and (.partialResults | not)
    and .failure.measurements == {
      samples:0, latestRSSKiB:$zeroSummary.baselineRSSKiB,
      baselineRSSKiB:$zeroSummary.baselineRSSKiB,
      maximumRSSKiB:$zeroSummary.maximumRSSKiB,
      growthKiB:0
    }
    and $zeroSummary.baselineRSSKiB > .thresholds.rssLimitKiB
  ' "$evidence" >/dev/null
  echo "Raw performance CSV binding and zero-sample boundary failure validate"
  exit 0
fi

recomputed="$(bash "$project_root/Scripts/summarize-performance-csv.sh" "$csv")"
rss_failure_stats="$(awk -F, \
  -v rss_limit="$rss_limit_kib" \
  -v growth_limit="$growth_limit_kib" '
  $7 == "boundary" {
    baseline = $2 + 0
    maximum = baseline
    boundary_over_limit = (baseline > rss_limit ? 1 : 0)
  }
  $7 == "measurement" {
    count++
    rss = $2 + 0
    if (rss > maximum) maximum = rss
    if (first_kind == "") {
      if (maximum > rss_limit) {
        first_kind = "rss_limit"
        first_row = count
      } else if (maximum - baseline > growth_limit) {
        first_kind = "rss_growth"
        first_row = count
      }
    }
    last_rss = rss
  }
  END { printf "%s,%d,%d,%d,%d,%d,%d", first_kind, first_row, count, last_rss, maximum, maximum - baseline, boundary_over_limit }
' "$csv")"
IFS=, read -r first_rss_failure_kind first_rss_failure_row raw_measurement_count last_rss raw_maximum_rss raw_growth_rss boundary_over_limit <<<"$rss_failure_stats"
first_rss_failure_kind_json="null"
if [[ -n "$first_rss_failure_kind" ]]; then first_rss_failure_kind_json="\"$first_rss_failure_kind\""; fi

jq -e --argjson recomputed "$recomputed" \
  --argjson firstRSSFailureKind "$first_rss_failure_kind_json" \
  --argjson firstRSSFailureRow "$first_rss_failure_row" \
  --argjson rawMeasurementCount "$raw_measurement_count" \
  --argjson lastRSSKiB "$last_rss" \
  --argjson rawMaximumRSSKiB "$raw_maximum_rss" \
  --argjson rawGrowthKiB "$raw_growth_rss" \
  --argjson boundaryOverLimit "$boundary_over_limit" '
  if .status == "passed" then
    .results == $recomputed
    and $recomputed.maximumRSSKiB <= .thresholds.rssLimitKiB
    and $recomputed.growthKiB <= .thresholds.growthLimitKiB
    and $recomputed.averageCPUPercent <= .thresholds.averageCPUPercentLimit
    and $recomputed.p95CPUPercent <= .thresholds.p95CPUPercentLimit
  elif .status == "failed" then
    .partialResults == $recomputed
    and .rawCSV.formatVersion == 1
    and (.failure.kind | type == "string" and length > 0)
    and (.failure.reason | type == "string" and length > 0)
    and (.failure.exitCode | type == "number" and . == floor and . != 0)
    and .failureReason == .failure.reason
    and .exitCode == .failure.exitCode
    and .failure.measurements.samples == $recomputed.samples
    and .failure.measurements.latestRSSKiB == $lastRSSKiB
    and .failure.measurements.baselineRSSKiB == $recomputed.baselineRSSKiB
    and .failure.measurements.maximumRSSKiB == $rawMaximumRSSKiB
    and .failure.measurements.growthKiB == $rawGrowthKiB
    and $boundaryOverLimit == 0
    and (.finishedAt | type == "string" and length > 0)
    and (
      if .failure.kind == "rss_limit" then
        $firstRSSFailureKind == "rss_limit"
        and $firstRSSFailureRow == $rawMeasurementCount
        and $lastRSSKiB == $rawMaximumRSSKiB
      elif .failure.kind == "rss_growth" then
        $firstRSSFailureKind == "rss_growth"
        and $firstRSSFailureRow == $rawMeasurementCount
        and $lastRSSKiB == $rawMaximumRSSKiB
      elif .failure.kind == "cpu_average" then
        $recomputed.averageCPUPercent > .thresholds.averageCPUPercentLimit
      elif .failure.kind == "cpu_p95" then
        $recomputed.p95CPUPercent > .thresholds.p95CPUPercentLimit
      else
        .failure.kind as $kind
        | ["interrupted","sleep_prevention","metrics_unavailable",
          "rss_unavailable","no_samples","evidence_mismatch","unexpected_error"]
        | index($kind) != null
      end
    )
    and (
      .failure.kind as $kind
      | if (["cpu_average","cpu_p95","evidence_mismatch"] | index($kind)) != null then
        $recomputed.measurementDurationSeconds >= .soakSeconds
      else true end
    )
  else
    false
  end
' "$evidence" >/dev/null

echo "Raw performance CSV binding and recomputed results validate for $(jq -r '.status' "$evidence") evidence"
