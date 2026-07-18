#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
app="${MACMETER_APP_PATH:-$project_root/build/DerivedData/Build/Products/Release/MacMeter.app}"
evidence="${MACMETER_PRIVACY_EVIDENCE:-$project_root/QA/latest-runtime-privacy.json}"
requested_duration="${MACMETER_PRIVACY_DURATION_SECONDS:-10}"
sample_interval=1
executable="$app/Contents/MacOS/MacMeter"
observer_tool="/usr/sbin/lsof"
observer_method="lsof all Internet sockets for the exact child PID at one-second intervals"
launch_method="direct execution of the built app executable; observe its exact child PID"

case "$requested_duration" in
  ''|*[!0-9]*)
    echo "MACMETER_PRIVACY_DURATION_SECONDS must be an integer of at least 10" >&2
    exit 1
    ;;
esac
if ((requested_duration < 10)); then
  echo "MACMETER_PRIVACY_DURATION_SECONDS must be at least 10" >&2
  exit 1
fi
test -x "$executable"
test -x "$observer_tool"
mkdir -p "$(dirname "$evidence")"

temporary_directory="$(mktemp -d /tmp/macmeter-runtime-privacy.XXXXXX)"
network_output="$temporary_directory/network-sockets"
network_errors="$temporary_directory/network-errors"
process_output="$temporary_directory/process-files"
process_errors="$temporary_directory/process-errors"
socket_records="$temporary_directory/socket-records"
: >"$socket_records"
app_pid=""
cleanup() {
  if [[ -n "$app_pid" ]] && kill -0 "$app_pid" 2>/dev/null; then
    kill "$app_pid" 2>/dev/null || true
    wait "$app_pid" 2>/dev/null || true
  fi
  rm -f "$network_output" "$network_errors" "$process_output" "$process_errors" "$socket_records"
  rmdir "$temporary_directory" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

commit="$(git -C "$project_root" rev-parse HEAD)"
dirty_worktree=false
if [[ -n "$(git -C "$project_root" status --porcelain)" ]]; then dirty_worktree=true; fi
hardware="$(sysctl -n machdep.cpu.brand_string)"
binary_sha256="$(shasum -a 256 "$executable" | awk '{print $1}')"
observer_script_sha256="$(shasum -a 256 "$project_root/Scripts/runtime-privacy-evidence.sh" | awk '{print $1}')"
observer_tool_version="$($observer_tool -v 2>&1 | awk -F: '/revision:/ {sub(/^[[:space:]]+/, "", $2); print $2; exit}')"
test -n "$observer_tool_version"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
started_epoch="$(date -u +%s)"

"$executable" \
  -metrics.cpu.enabled YES \
  -metrics.temperature.enabled YES \
  -metrics.network.enabled YES \
  -metrics.battery.enabled YES \
  -general.updateInterval 2 \
  >/dev/null 2>&1 &
app_pid=$!

samples=0
network_socket_observations=0
listening_socket_observations=0
observer_errors=0
liveness_failures=0
failure_reason=""

while :; do
  if ! kill -0 "$app_pid" 2>/dev/null; then
    liveness_failures=$((liveness_failures + 1))
    failure_reason="MacMeter exited during observation"
    break
  fi

  : >"$process_output"
  : >"$process_errors"
  if ! "$observer_tool" -w -nP -a -p "$app_pid" -Fpcf >"$process_output" 2>"$process_errors"; then
    observer_errors=$((observer_errors + 1))
    failure_reason="lsof could not inspect the MacMeter process"
    break
  fi
  if ! grep -qx "p$app_pid" "$process_output" || [[ -s "$process_errors" ]]; then
    observer_errors=$((observer_errors + 1))
    failure_reason="lsof did not confirm the exact MacMeter child PID"
    break
  fi

  : >"$network_output"
  : >"$network_errors"
  network_status=0
  "$observer_tool" -w -nP -a -p "$app_pid" -i -FpcfPnT >"$network_output" 2>"$network_errors" || network_status=$?
  if [[ -s "$network_errors" ]] || ((network_status > 1)); then
    observer_errors=$((observer_errors + 1))
    failure_reason="lsof failed while enumerating Internet sockets"
    break
  fi

  sample_socket_count="$(awk '/^f/ {count++} END {print count+0}' "$network_output")"
  sample_listening_count="$(awk '/^TST=LISTEN$/ {count++} END {print count+0}' "$network_output")"
  if { ((network_status == 0)) && ((sample_socket_count == 0)); } \
    || { ((network_status == 1)) && [[ -s "$network_output" ]]; }; then
    observer_errors=$((observer_errors + 1))
    failure_reason="lsof returned an inconsistent Internet-socket result"
    break
  fi
  network_socket_observations=$((network_socket_observations + sample_socket_count))
  listening_socket_observations=$((listening_socket_observations + sample_listening_count))
  samples=$((samples + 1))
  if ((sample_socket_count > 0)); then
    {
      printf 'sample=%s\n' "$samples"
      sed '/^$/d' "$network_output"
    } >>"$socket_records"
    failure_reason="MacMeter opened an Internet socket during observation"
    break
  fi

  current_epoch="$(date -u +%s)"
  elapsed=$((current_epoch - started_epoch))
  if ((elapsed >= requested_duration)); then break; fi
  sleep "$sample_interval"
done

finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
finished_epoch="$(date -u +%s)"
actual_duration=$((finished_epoch - started_epoch))
status="passed"
if [[ -n "$failure_reason" ]] || ((actual_duration < requested_duration)) || ((samples < requested_duration)); then
  status="failed"
  if [[ -z "$failure_reason" ]]; then failure_reason="Observation did not meet its duration or sample-count contract"; fi
fi

socket_records_json="$(jq -R -s 'split("\n") | map(select(length > 0))' "$socket_records")"
temporary_evidence="$evidence.tmp.$$"
jq -n \
  --arg status "$status" \
  --arg commit "$commit" \
  --argjson dirtyWorktree "$dirty_worktree" \
  --arg hardware "$hardware" \
  --arg appBinarySHA256 "$binary_sha256" \
  --arg version "$version" \
  --arg build "$build" \
  --arg observerScriptSHA256 "$observer_script_sha256" \
  --arg observerToolPath "$observer_tool" \
  --arg observerToolVersion "$observer_tool_version" \
  --arg launchMethod "$launch_method" \
  --arg startedAt "$started_at" \
  --arg finishedAt "$finished_at" \
  --arg method "$observer_method" \
  --arg failureReason "$failure_reason" \
  --argjson requestedDurationSeconds "$requested_duration" \
  --argjson actualDurationSeconds "$actual_duration" \
  --argjson sampleIntervalSeconds "$sample_interval" \
  --argjson samples "$samples" \
  --argjson networkSocketObservations "$network_socket_observations" \
  --argjson listeningSocketObservations "$listening_socket_observations" \
  --argjson observerErrors "$observer_errors" \
  --argjson processLivenessFailures "$liveness_failures" \
  --argjson observedSocketRecords "$socket_records_json" \
  '{
    schemaVersion: 1,
    status: $status,
    commit: $commit,
    dirtyWorktree: $dirtyWorktree,
    hardware: $hardware,
    appBinarySHA256: $appBinarySHA256,
    version: $version,
    build: $build,
    observerScriptSHA256: $observerScriptSHA256,
    observerToolPath: $observerToolPath,
    observerToolVersion: $observerToolVersion,
    launchMethod: $launchMethod,
    observationConfiguration: {
      enabledMetrics: ["cpu", "temperature", "network", "battery"],
      updateIntervalSeconds: 2
    },
    startedAt: $startedAt,
    finishedAt: $finishedAt,
    observation: {
      method: $method,
      requestedDurationSeconds: $requestedDurationSeconds,
      actualDurationSeconds: $actualDurationSeconds,
      sampleIntervalSeconds: $sampleIntervalSeconds,
      samples: $samples,
      networkSocketObservations: $networkSocketObservations,
      listeningSocketObservations: $listeningSocketObservations,
      observerErrors: $observerErrors,
      processLivenessFailures: $processLivenessFailures
    },
    observedSocketRecords: $observedSocketRecords,
    failureReason: (if $failureReason == "" then null else $failureReason end)
  }' >"$temporary_evidence"
mv "$temporary_evidence" "$evidence"

if [[ "$status" != "passed" ]]; then
  echo "Runtime privacy observation failed: $failure_reason" >&2
  exit 1
fi
echo "Runtime privacy evidence recorded: $evidence"
