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

LC_ALL=C awk -F, -v warmup_seconds="$warmup_seconds" -v soak_seconds="$soak_seconds" -v cadence_csv="$cadence_csv" '
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
    if (boundary_count != 1 || measurement_count == 0) exit 1
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

recomputed="$(bash "$project_root/Scripts/summarize-performance-csv.sh" "$csv")"
jq -e --argjson recomputed "$recomputed" '
  .status == "passed"
  and .results == $recomputed
  and $recomputed.maximumRSSKiB <= .thresholds.rssLimitKiB
  and $recomputed.growthKiB <= .thresholds.growthLimitKiB
  and $recomputed.averageCPUPercent <= .thresholds.averageCPUPercentLimit
  and $recomputed.p95CPUPercent <= .thresholds.p95CPUPercentLimit
' "$evidence" >/dev/null

echo "Raw performance CSV binding and recomputed results validate"
