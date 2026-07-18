#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
app="${MACMETER_APP_PATH:-$project_root/build/DerivedData/Build/Products/Release/MacMeter.app}"
warmup_seconds="${MACMETER_WARMUP_SECONDS:-1800}"
soak_seconds="${MACMETER_SOAK_SECONDS:-86400}"
sample_seconds="${MACMETER_SAMPLE_SECONDS:-60}"
output="${MACMETER_PERFORMANCE_OUTPUT:-$project_root/QA/performance-soak.csv}"
rss_limit_kib=81920
growth_limit_kib=5120
cpu_p95_limit=3.0

executable="$app/Contents/MacOS/MacMeter"
if [[ ! -x "$executable" ]]; then
  echo "Release executable not found: $executable" >&2
  exit 1
fi

"$executable" >/dev/null 2>&1 &
pid=$!
cpu_values_file="$(mktemp /tmp/macmeter-cpu-values.XXXXXX)"
cleanup() {
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  rm -f "$cpu_values_file"
}
trap cleanup EXIT INT TERM

mkdir -p "$(dirname "$output")"
printf 'elapsed_seconds,rss_kib,cpu_percent\n' >"$output"

started="$(date +%s)"
measurement_start=$((started + warmup_seconds))
finish=$((measurement_start + soak_seconds))
baseline_rss=""
maximum_rss=0
cpu_sum=0
sample_count=0

while true; do
  now="$(date +%s)"
  if (( now >= finish )); then break; fi
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "MacMeter exited during the performance soak" >&2
    exit 1
  fi

  rss="$(ps -o rss= -p "$pid" | awk '{print $1}')"
  cpu="$(ps -o %cpu= -p "$pid" | awk '{print $1}')"
  elapsed=$((now - started))
  printf '%s,%s,%s\n' "$elapsed" "$rss" "$cpu" >>"$output"

  if (( now >= measurement_start )); then
    if [[ -z "$baseline_rss" ]]; then baseline_rss="$rss"; fi
    if (( rss > maximum_rss )); then maximum_rss="$rss"; fi
    cpu_sum="$(awk -v sum="$cpu_sum" -v value="$cpu" 'BEGIN { printf "%.6f", sum + value }')"
    printf '%s\n' "$cpu" >>"$cpu_values_file"
    sample_count=$((sample_count + 1))
  fi
  sleep "$sample_seconds"
done

if (( sample_count == 0 )); then
  echo "No post-warm-up samples were collected" >&2
  exit 1
fi

average_cpu="$(awk -v sum="$cpu_sum" -v count="$sample_count" 'BEGIN { printf "%.3f", sum / count }')"
p95_index=$(((95 * sample_count + 99) / 100))
cpu_p95="$(sort -n "$cpu_values_file" | sed -n "${p95_index}p")"
growth=$((maximum_rss - baseline_rss))
echo "Performance soak: baseline=${baseline_rss}KiB max=${maximum_rss}KiB growth=${growth}KiB averageCPU=${average_cpu}% p95CPU=${cpu_p95}%"

if (( maximum_rss > rss_limit_kib )); then
  echo "RSS limit failed: ${maximum_rss}KiB > ${rss_limit_kib}KiB after warm-up" >&2
  exit 1
fi
if (( growth > growth_limit_kib )); then
  echo "RSS growth failed: ${growth}KiB > ${growth_limit_kib}KiB" >&2
  exit 1
fi
if ! awk -v cpu="$average_cpu" 'BEGIN { exit !(cpu <= 1.0) }'; then
  echo "Idle CPU limit failed: ${average_cpu}% > 1.0%" >&2
  exit 1
fi
if ! awk -v cpu="$cpu_p95" -v limit="$cpu_p95_limit" 'BEGIN { exit !(cpu <= limit) }'; then
  echo "Idle CPU p95 failed: ${cpu_p95}% > ${cpu_p95_limit}%" >&2
  exit 1
fi
