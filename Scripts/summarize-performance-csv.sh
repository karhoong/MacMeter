#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
csv="${1:?usage: summarize-performance-csv.sh RAW_CSV}"
allow_zero=false
if [[ "${2:-}" == "--allow-zero" ]]; then
  allow_zero=true
elif [[ -n "${2:-}" ]]; then
  echo "usage: summarize-performance-csv.sh RAW_CSV [--allow-zero]" >&2
  exit 64
fi
source "$project_root/Scripts/performance-math.sh"

test -f "$csv"
values_file="$(mktemp /tmp/macmeter-csv-cpu-values.XXXXXX)"
stats_file="$(mktemp /tmp/macmeter-csv-stats.XXXXXX)"
trap 'rm -f "$values_file" "$stats_file"' EXIT

LC_ALL=C awk -F, -v values_file="$values_file" -v stats_file="$stats_file" -v allow_zero="$allow_zero" '
  function invalid(message) {
    print "Invalid performance CSV at line " NR ": " message > "/dev/stderr"
    failed = 1
    exit 1
  }
  function is_uint(value) { return value ~ /^[0-9]+$/ }
  function is_number(value) { return value ~ /^[0-9]+([.][0-9]+)?$/ }

  NR == 1 {
    expected = "elapsed_seconds,rss_kib,physical_footprint_kib,cpu_interval_percent,interval_seconds,cpu_delta_ns,wall_delta_ns,phase"
    if ($0 != expected) invalid("unexpected header")
    next
  }

  {
    if (NF != 8) invalid("expected eight columns")
    if (!is_uint($1)) invalid("elapsed_seconds is not an unsigned integer")
    if (!is_uint($2)) invalid("rss_kib is not an unsigned integer")
    if (!is_uint($3)) invalid("physical_footprint_kib is not an unsigned integer")
    if (!is_number($4)) invalid("cpu_interval_percent is not a nonnegative number")
    if (!is_number($5)) invalid("interval_seconds is not a nonnegative number")
    if (!is_uint($6)) invalid("cpu_delta_ns is not an unsigned integer")
    if (!is_uint($7)) invalid("wall_delta_ns is not an unsigned integer")
    if ($8 != "warmup" && $8 != "boundary" && $8 != "measurement") invalid("unknown phase")

    if (rows > 0 && ($1 + 0) < previous_elapsed) invalid("elapsed time moved backwards")
    if ($8 == "measurement" && rows > 0 && ($1 + 0) <= previous_elapsed) invalid("measurement elapsed time did not advance")
    previous_elapsed = $1 + 0
    rows++

    if (($7 + 0) == 0) {
      if (($6 + 0) != 0 || $4 != "0.000" || $5 != "0.000") invalid("zero wall delta has inconsistent derived values")
    } else {
      expected_cpu = sprintf("%.3f", 100 * ($6 + 0) / ($7 + 0))
      expected_seconds = sprintf("%.3f", ($7 + 0) / 1000000000)
      if ($4 != expected_cpu) invalid("cpu_interval_percent does not match raw deltas")
      if ($5 != expected_seconds) invalid("interval_seconds does not match raw wall delta")
    }

    cumulative_wall_ns += $7 + 0
    expected_elapsed = int(cumulative_wall_ns / 1000000000)
    if (($1 + 0) != expected_elapsed) invalid("elapsed_seconds does not match cumulative raw wall deltas")

    if ($8 == "warmup") {
      if (seen_boundary) invalid("warmup row follows measurement boundary")
      next
    }

    if ($8 == "boundary") {
      if (seen_boundary) invalid("multiple measurement boundaries")
      seen_boundary = 1
      baseline = $2 + 0
      maximum = baseline
      baseline_physical = $3 + 0
      maximum_physical = baseline_physical
      next
    }

    if (!seen_boundary) invalid("measurement row precedes boundary")
    if (($7 + 0) <= 0) invalid("measurement wall delta must be positive")
    count++
    sum_cpu_ns += $6 + 0
    sum_wall_ns += $7 + 0
    if (($2 + 0) > maximum) maximum = $2 + 0
    if (($3 + 0) > maximum_physical) maximum_physical = $3 + 0
    printf "%.3f\n", 100 * ($6 + 0) / ($7 + 0) >> values_file
  }

  END {
    if (failed) exit 1
    if (NR < 2) invalid("contains no data rows")
    if (!seen_boundary) invalid("missing measurement boundary")
    if (count == 0 && allow_zero != "true") invalid("contains no measurement rows")
    printf "%.0f,%.0f,%.0f,%.0f,%.0f,%.0f,%.0f\n", count, baseline, maximum, baseline_physical, maximum_physical, sum_cpu_ns, sum_wall_ns > stats_file
  }
' "$csv"

IFS=, read -r sample_count baseline_rss maximum_rss baseline_physical maximum_physical total_cpu_ns total_wall_ns <"$stats_file"
if (( sample_count == 0 )); then
  jq -n \
    --argjson baselineRSSKiB "$baseline_rss" \
    --argjson baselinePhysicalFootprintKiB "$baseline_physical" \
    '{samples:0, baselineRSSKiB:$baselineRSSKiB,
      maximumRSSKiB:$baselineRSSKiB, growthKiB:0,
      baselinePhysicalFootprintKiB:$baselinePhysicalFootprintKiB,
      maximumPhysicalFootprintKiB:$baselinePhysicalFootprintKiB,
      physicalFootprintGrowthKiB:0,
      averageCPUPercent:null, p95CPUPercent:null,
      measurementDurationSeconds:0}'
  exit 0
fi
average_cpu="$(cpu_percent_from_deltas "$total_cpu_ns" "$total_wall_ns")"
cpu_p95="$(nearest_rank_percentile "$values_file" "$sample_count" 95)"
growth=$((maximum_rss - baseline_rss))
physical_growth=$((maximum_physical - baseline_physical))
measurement_duration_seconds="$(awk -v wall="$total_wall_ns" 'BEGIN { printf "%.3f", wall / 1000000000 }')"

jq -n \
  --argjson samples "$sample_count" \
  --argjson baselineRSSKiB "$baseline_rss" \
  --argjson maximumRSSKiB "$maximum_rss" \
  --argjson growthKiB "$growth" \
  --argjson baselinePhysicalFootprintKiB "$baseline_physical" \
  --argjson maximumPhysicalFootprintKiB "$maximum_physical" \
  --argjson physicalFootprintGrowthKiB "$physical_growth" \
  --argjson averageCPUPercent "$average_cpu" \
  --argjson p95CPUPercent "$cpu_p95" \
  --argjson measurementDurationSeconds "$measurement_duration_seconds" \
  '{samples:$samples, baselineRSSKiB:$baselineRSSKiB,
    maximumRSSKiB:$maximumRSSKiB, growthKiB:$growthKiB,
    baselinePhysicalFootprintKiB:$baselinePhysicalFootprintKiB,
    maximumPhysicalFootprintKiB:$maximumPhysicalFootprintKiB,
    physicalFootprintGrowthKiB:$physicalFootprintGrowthKiB,
    averageCPUPercent:$averageCPUPercent, p95CPUPercent:$p95CPUPercent,
    measurementDurationSeconds:$measurementDurationSeconds}'
