#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
app="${MACMETER_APP_PATH:-$project_root/build/DerivedData/Build/Products/Release/MacMeter.app}"
warmup_seconds="${MACMETER_WARMUP_SECONDS:-1800}"
soak_seconds="${MACMETER_SOAK_SECONDS:-86400}"
sample_seconds="${MACMETER_SAMPLE_SECONDS:-60}"
output="${MACMETER_PERFORMANCE_OUTPUT:-$project_root/QA/performance-soak.csv}"
evidence="${MACMETER_PERFORMANCE_EVIDENCE:-$project_root/QA/latest-performance.json}"
rss_limit_kib="${MACMETER_RSS_LIMIT_KIB:-81920}"
growth_limit_kib="${MACMETER_GROWTH_LIMIT_KIB:-5120}"
cpu_average_limit="${MACMETER_CPU_AVERAGE_LIMIT:-1.0}"
cpu_p95_limit="${MACMETER_CPU_P95_LIMIT:-3.0}"

source "$project_root/Scripts/performance-math.sh"

if ! [[ "$warmup_seconds" =~ ^[0-9]+$ && "$soak_seconds" =~ ^[1-9][0-9]*$ && "$sample_seconds" =~ ^[1-9][0-9]*$ && "$rss_limit_kib" =~ ^[1-9][0-9]*$ && "$growth_limit_kib" =~ ^[0-9]+$ && "$cpu_average_limit" =~ ^[0-9]+([.][0-9]+)?$ && "$cpu_p95_limit" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "Performance durations and thresholds must be nonnegative numbers in their documented units" >&2
  exit 64
fi
output_file_name="$(basename "$output")"
if [[ ! "$output_file_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  echo "Performance CSV filename must contain only letters, numbers, dots, underscores, or hyphens" >&2
  exit 64
fi

if [[ -z "${MACMETER_SAMPLE_SECONDS:-}" && "$sample_seconds" == 60 ]]; then
  sample_cadence=(59 61)
else
  sample_cadence=("$sample_seconds")
fi
cadence_json="$(printf '%s\n' "${sample_cadence[@]}" | jq -s 'map(tonumber)')"

executable="$app/Contents/MacOS/MacMeter"
if [[ ! -x "$executable" ]]; then
  echo "Release executable not found: $executable" >&2
  exit 1
fi

metrics_directory="$(mktemp -d /tmp/macmeter-process-metrics.XXXXXX)"
metrics_binary="$metrics_directory/process-metrics"
xcrun clang -O2 -Wall -Wextra -Werror \
  "$project_root/Scripts/process-metrics.c" -o "$metrics_binary"
metrics_source_sha256="$(shasum -a 256 "$project_root/Scripts/process-metrics.c" | awk '{print $1}')"
metrics_binary_sha256="$(shasum -a 256 "$metrics_binary" | awk '{print $1}')"
metrics_compiler="$(xcrun clang --version | head -1)"
cpu_values_file="$(mktemp /tmp/macmeter-cpu-values.XXXXXX)"
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
commit="$(git -C "$project_root" rev-parse HEAD)"
hardware="$(sysctl -n machdep.cpu.brand_string)"
dirty=false
if [[ -n "$(git -C "$project_root" status --porcelain)" ]]; then dirty=true; fi
binary_sha256="$(shasum -a 256 "$executable" | awk '{print $1}')"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
pid=""
caffeinate_pid=""
finalized=false
failure_reason="unexpected error"
baseline_rss=""
maximum_rss=0
sample_count=0
average_cpu=""
cpu_p95=""
growth=""
measurement_duration_seconds=""
measurement_cpu_start=""
measurement_wall_start=""
latest_cpu_ns=""
latest_wall_ns=""
latest_rss=""

write_base_evidence() {
  local status="$1"
  jq -n \
    --arg status "$status" \
    --arg commit "$commit" \
    --arg startedAt "$started_at" \
    --arg hardware "$hardware" \
    --arg binarySHA256 "$binary_sha256" \
    --arg metricsSourceSHA256 "$metrics_source_sha256" \
    --arg metricsBinarySHA256 "$metrics_binary_sha256" \
    --arg metricsCompiler "$metrics_compiler" \
    --arg sleepPreventionMethod "caffeinate -dimsu -w harness PID with per-sample liveness checks" \
    --arg version "$version" \
    --arg build "$build" \
    --arg cpuMeasurementMethod "proc_pid_rusage cumulative user+system CPU nanoseconds divided by CLOCK_MONOTONIC wall-time deltas" \
    --argjson dirtyWorktree "$dirty" \
    --argjson pid "$pid" \
    --argjson warmupSeconds "$warmup_seconds" \
    --argjson soakSeconds "$soak_seconds" \
    --argjson sampleSeconds "$sample_seconds" \
    --argjson sampleCadenceSeconds "$cadence_json" \
    --argjson rssLimitKiB "$rss_limit_kib" \
    --argjson growthLimitKiB "$growth_limit_kib" \
    --argjson averageCPUPercentLimit "$cpu_average_limit" \
    --argjson p95CPUPercentLimit "$cpu_p95_limit" \
    '{status:$status, commit:$commit, startedAt:$startedAt, hardware:$hardware,
      binarySHA256:$binarySHA256, metricsSourceSHA256:$metricsSourceSHA256,
      metricsBinarySHA256:$metricsBinarySHA256, metricsCompiler:$metricsCompiler,
      sleepPreventionMethod:$sleepPreventionMethod,
      version:$version, build:$build, dirtyWorktree:$dirtyWorktree, pid:$pid,
      warmupSeconds:$warmupSeconds, soakSeconds:$soakSeconds,
      sampleSeconds:$sampleSeconds, sampleCadenceSeconds:$sampleCadenceSeconds,
      cpuMeasurementMethod:$cpuMeasurementMethod,
      thresholds:{rssLimitKiB:$rssLimitKiB, growthLimitKiB:$growthLimitKiB,
        averageCPUPercentLimit:$averageCPUPercentLimit,
        p95CPUPercentLimit:$p95CPUPercentLimit}}' >"$evidence"
}

add_results() {
  local field="$1"
  jq \
    --arg field "$field" \
    --argjson samples "$sample_count" \
    --argjson baselineRSSKiB "$baseline_rss" \
    --argjson maximumRSSKiB "$maximum_rss" \
    --argjson growthKiB "$growth" \
    --argjson averageCPUPercent "$average_cpu" \
    --argjson p95CPUPercent "$cpu_p95" \
    --argjson measurementDurationSeconds "$measurement_duration_seconds" \
    '. + {($field):{samples:$samples, baselineRSSKiB:$baselineRSSKiB,
      maximumRSSKiB:$maximumRSSKiB, growthKiB:$growthKiB,
      averageCPUPercent:$averageCPUPercent, p95CPUPercent:$p95CPUPercent,
      measurementDurationSeconds:$measurementDurationSeconds}}' \
    "$evidence" >"$evidence.tmp"
  mv "$evidence.tmp" "$evidence"
}

write_completed_evidence() {
  local finished_at csv_sha256 csv_byte_count csv_file_name
  finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  csv_sha256="$(shasum -a 256 "$output" | awk '{print $1}')"
  csv_byte_count="$(wc -c <"$output" | tr -d '[:space:]')"
  csv_file_name="$output_file_name"
  jq \
    --arg status "passed" \
    --arg finishedAt "$finished_at" \
    --arg csvFileName "$csv_file_name" \
    --arg csvSHA256 "$csv_sha256" \
    --argjson csvByteCount "$csv_byte_count" \
    --argjson samples "$sample_count" \
    --argjson baselineRSSKiB "$baseline_rss" \
    --argjson maximumRSSKiB "$maximum_rss" \
    --argjson growthKiB "$growth" \
    --argjson averageCPUPercent "$average_cpu" \
    --argjson p95CPUPercent "$cpu_p95" \
    --argjson measurementDurationSeconds "$measurement_duration_seconds" \
    '. + {status:$status, finishedAt:$finishedAt,
      rawCSV:{formatVersion:1, fileName:$csvFileName,
        sha256:$csvSHA256, byteCount:$csvByteCount},
      results:{samples:$samples, baselineRSSKiB:$baselineRSSKiB,
        maximumRSSKiB:$maximumRSSKiB, growthKiB:$growthKiB,
        averageCPUPercent:$averageCPUPercent, p95CPUPercent:$p95CPUPercent,
        measurementDurationSeconds:$measurementDurationSeconds}}' \
    "$evidence" >"$evidence.tmp"
  mv "$evidence.tmp" "$evidence"
}

compute_results() {
  if (( sample_count == 0 )) || [[ -z "$measurement_cpu_start" || -z "$measurement_wall_start" ]]; then
    return 1
  fi
  local cpu_delta_ns wall_delta_ns
  cpu_delta_ns=$((latest_cpu_ns - measurement_cpu_start))
  wall_delta_ns=$((latest_wall_ns - measurement_wall_start))
  average_cpu="$(cpu_percent_from_deltas "$cpu_delta_ns" "$wall_delta_ns")"
  cpu_p95="$(nearest_rank_percentile "$cpu_values_file" "$sample_count" 95)"
  growth=$((maximum_rss - baseline_rss))
  measurement_duration_seconds="$(awk -v wall="$wall_delta_ns" 'BEGIN { printf "%.3f", wall / 1000000000 }')"
}

write_failed_evidence() {
  local exit_code="$1"
  local finished_at
  finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  write_base_evidence "failed"
  jq \
    --arg finishedAt "$finished_at" \
    --arg failureReason "$failure_reason" \
    --argjson exitCode "$exit_code" \
    '. + {finishedAt:$finishedAt, failureReason:$failureReason, exitCode:$exitCode}' \
    "$evidence" >"$evidence.tmp"
  mv "$evidence.tmp" "$evidence"
  if compute_results; then add_results "partialResults"; fi
}

fail() {
  failure_reason="$1"
  echo "$failure_reason" >&2
  exit 1
}

cleanup() {
  local exit_code=$?
  if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  if [[ -n "${pid:-}" && "$finalized" != true ]]; then write_failed_evidence "$exit_code" || true; fi
  if [[ -n "${caffeinate_pid:-}" ]]; then
    kill "$caffeinate_pid" 2>/dev/null || true
    wait "$caffeinate_pid" 2>/dev/null || true
  fi
  rm -f "$cpu_values_file" "$metrics_binary"
  rmdir "$metrics_directory" 2>/dev/null || true
  return "$exit_code"
}
trap cleanup EXIT
trap 'failure_reason="interrupted"; exit 130' INT TERM

caffeinate -dimsu -w "$$" >/dev/null 2>&1 &
caffeinate_pid=$!
"$executable" >/dev/null 2>&1 &
pid=$!

take_sample() {
  local metrics
  if ! kill -0 "$caffeinate_pid" 2>/dev/null; then
    fail "Sleep-prevention process exited during the performance soak"
  fi
  if ! metrics="$("$metrics_binary" "$pid" 2>/dev/null)"; then
    fail "MacMeter exited or process metrics became unavailable during the performance soak"
  fi
  IFS=, read -r latest_cpu_ns latest_wall_ns <<<"$metrics"
  latest_rss="$(ps -o rss= -p "$pid" | awk '{print $1}')"
  if [[ -z "$latest_rss" ]]; then fail "MacMeter RSS became unavailable during the performance soak"; fi
}

mkdir -p "$(dirname "$output")" "$(dirname "$evidence")"
printf 'elapsed_seconds,rss_kib,cpu_interval_percent,interval_seconds,cpu_delta_ns,wall_delta_ns,phase\n' >"$output"
write_base_evidence "running"

take_sample
start_wall_ns="$latest_wall_ns"
previous_cpu_ns="$latest_cpu_ns"
previous_wall_ns="$latest_wall_ns"
measurement_target_ns=$((start_wall_ns + warmup_seconds * 1000000000))
finish_target_ns=$((measurement_target_ns + soak_seconds * 1000000000))
cadence_index=0
measurement_started=false
if (( warmup_seconds == 0 )); then
  measurement_started=true
  measurement_cpu_start="$latest_cpu_ns"
  measurement_wall_start="$latest_wall_ns"
  baseline_rss="$latest_rss"
  maximum_rss="$latest_rss"
  printf '0,%s,0.000,0.000,0,0,boundary\n' "$latest_rss" >>"$output"
else
  printf '0,%s,0.000,0.000,0,0,warmup\n' "$latest_rss" >>"$output"
fi

while (( latest_wall_ns < finish_target_ns )); do
  delay="${sample_cadence[$cadence_index]}"
  cadence_index=$(((cadence_index + 1) % ${#sample_cadence[@]}))
  target_ns="$finish_target_ns"
  if [[ "$measurement_started" != true ]]; then target_ns="$measurement_target_ns"; fi
  remaining_ns=$((target_ns - latest_wall_ns))
  delay_ns=$((delay * 1000000000))
  if (( delay_ns > remaining_ns )); then
    delay=$(((remaining_ns + 999999999) / 1000000000))
    if (( delay < 1 )); then delay=1; fi
  fi

  sleep "$delay"
  take_sample
  cpu_delta_ns=$((latest_cpu_ns - previous_cpu_ns))
  wall_delta_ns=$((latest_wall_ns - previous_wall_ns))
  interval_cpu="$(cpu_percent_from_deltas "$cpu_delta_ns" "$wall_delta_ns")"
  interval_seconds="$(awk -v wall="$wall_delta_ns" 'BEGIN { printf "%.3f", wall / 1000000000 }')"
  elapsed_seconds=$(((latest_wall_ns - start_wall_ns) / 1000000000))

  if [[ "$measurement_started" != true && "$latest_wall_ns" -ge "$measurement_target_ns" ]]; then
    measurement_started=true
    measurement_cpu_start="$latest_cpu_ns"
    measurement_wall_start="$latest_wall_ns"
    baseline_rss="$latest_rss"
    maximum_rss="$latest_rss"
    cadence_index=0
    printf '%s,%s,%s,%s,%s,%s,boundary\n' "$elapsed_seconds" "$latest_rss" "$interval_cpu" "$interval_seconds" "$cpu_delta_ns" "$wall_delta_ns" >>"$output"
  elif [[ "$measurement_started" == true ]]; then
    if (( latest_rss > maximum_rss )); then maximum_rss="$latest_rss"; fi
    printf '%s\n' "$interval_cpu" >>"$cpu_values_file"
    sample_count=$((sample_count + 1))
    printf '%s,%s,%s,%s,%s,%s,measurement\n' "$elapsed_seconds" "$latest_rss" "$interval_cpu" "$interval_seconds" "$cpu_delta_ns" "$wall_delta_ns" >>"$output"
  else
    printf '%s,%s,%s,%s,%s,%s,warmup\n' "$elapsed_seconds" "$latest_rss" "$interval_cpu" "$interval_seconds" "$cpu_delta_ns" "$wall_delta_ns" >>"$output"
  fi

  previous_cpu_ns="$latest_cpu_ns"
  previous_wall_ns="$latest_wall_ns"
done

if (( sample_count == 0 )); then fail "No post-warm-up samples were collected"; fi

compute_results
echo "Performance soak: baseline=${baseline_rss}KiB max=${maximum_rss}KiB growth=${growth}KiB averageCPU=${average_cpu}% p95CPU=${cpu_p95}% duration=${measurement_duration_seconds}s"

if (( maximum_rss > rss_limit_kib )); then
  fail "RSS limit failed: ${maximum_rss}KiB > ${rss_limit_kib}KiB after warm-up"
fi
if (( growth > growth_limit_kib )); then fail "RSS growth failed: ${growth}KiB > ${growth_limit_kib}KiB"; fi
if ! awk -v cpu="$average_cpu" -v limit="$cpu_average_limit" 'BEGIN { exit !(cpu <= limit) }'; then
  fail "Idle CPU limit failed: ${average_cpu}% > ${cpu_average_limit}%"
fi
if ! awk -v cpu="$cpu_p95" -v limit="$cpu_p95_limit" 'BEGIN { exit !(cpu <= limit) }'; then
  fail "Idle CPU p95 failed: ${cpu_p95}% > ${cpu_p95_limit}%"
fi

write_completed_evidence
if ! bash "$project_root/Scripts/verify-performance-csv.sh" "$evidence" "$output" >/dev/null; then
  fail "Completed performance evidence did not match the raw CSV"
fi
finalized=true
