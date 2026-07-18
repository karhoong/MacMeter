#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
filter="$project_root/Scripts/runtime-privacy-evidence.jq"
fixture="$(mktemp /tmp/macmeter-runtime-privacy-evidence.XXXXXX)"
trap 'rm -f "$fixture" "$fixture.tmp"' EXIT

make_fixture() {
  jq -n '{
    schemaVersion:1, status:"passed", commit:"fixture-commit", dirtyWorktree:false,
    hardware:"Fixture Apple Silicon", appBinarySHA256:"fixture-binary",
    version:"0.1.0", build:"1", observerScriptSHA256:"fixture-observer",
    observerToolPath:"/usr/sbin/lsof", observerToolVersion:"4.91",
    launchMethod:"direct execution of the built app executable; observe its exact child PID",
    observationConfiguration:{
      enabledMetrics:["cpu","temperature","network","battery"],
      updateIntervalSeconds:2
    },
    startedAt:"2026-07-19T00:00:00Z", finishedAt:"2026-07-19T00:00:10Z",
    observation:{
      method:"lsof all Internet sockets for the exact child PID at one-second intervals",
      requestedDurationSeconds:10, actualDurationSeconds:10, sampleIntervalSeconds:1,
      samples:11, networkSocketObservations:0, listeningSocketObservations:0,
      observerErrors:0, processLivenessFailures:0
    },
    observedSocketRecords:[], failureReason:null
  }' >"$fixture"
}

validate_fixture() {
  jq -e \
    --arg commit fixture-commit \
    --argjson dirtyWorktree false \
    --arg hardware "Fixture Apple Silicon" \
    --arg appBinarySHA256 fixture-binary \
    --arg version 0.1.0 \
    --arg build 1 \
    --arg observerScriptSHA256 fixture-observer \
    --arg observerToolPath /usr/sbin/lsof \
    --arg observerToolVersion 4.91 \
    -f "$filter" "$fixture" >/dev/null
}

reject_fixture() {
  if validate_fixture; then
    echo "Invalid runtime privacy evidence unexpectedly passed" >&2
    exit 1
  fi
}

make_fixture
validate_fixture

mutations=(
  '.schemaVersion=2'
  '.commit="other-commit"'
  '.dirtyWorktree=true'
  '.appBinarySHA256="other-binary"'
  '.version="1.0.0"'
  '.observerScriptSHA256="other-observer"'
  '.observerToolVersion="other-version"'
  '.status="failed"'
  '.observationConfiguration.enabledMetrics=["cpu"]'
  '.observationConfiguration.updateIntervalSeconds=10'
  '.finishedAt="2026-07-19T00:00:09Z"'
  '.observation.requestedDurationSeconds=9'
  '.observation.requestedDurationSeconds=10.5 | .observation.actualDurationSeconds=10.5 | .finishedAt="2026-07-19T00:00:10Z"'
  '.observation.actualDurationSeconds=9'
  '.observation.sampleIntervalSeconds=2'
  '.observation.samples=9'
  '.observation.networkSocketObservations=1'
  '.observation.listeningSocketObservations=1'
  '.observation.observerErrors=1'
  '.observation.processLivenessFailures=1'
  '.observedSocketRecords=["f12","n198.51.100.1:443"]'
  '.failureReason="observer failed"'
  'del(.observation.method)'
)
for mutation in "${mutations[@]}"; do
  make_fixture
  jq "$mutation" "$fixture" >"$fixture.tmp"
  mv "$fixture.tmp" "$fixture"
  reject_fixture
done

make_fixture
jq '.dirtyWorktree=true' "$fixture" >"$fixture.tmp"
mv "$fixture.tmp" "$fixture"
jq -e \
  --arg commit fixture-commit \
  --argjson dirtyWorktree true \
  --arg hardware "Fixture Apple Silicon" \
  --arg appBinarySHA256 fixture-binary \
  --arg version 0.1.0 \
  --arg build 1 \
  --arg observerScriptSHA256 fixture-observer \
  --arg observerToolPath /usr/sbin/lsof \
  --arg observerToolVersion 4.91 \
  -f "$filter" "$fixture" >/dev/null

rg -q '"\$observer_tool" -w -nP -a -p "\$app_pid" -i -FpcfPnT' "$project_root/Scripts/runtime-privacy-evidence.sh"
rg -q 'kill -0 "\$app_pid"' "$project_root/Scripts/runtime-privacy-evidence.sh"
rg -q -- '-metrics.network.enabled YES' "$project_root/Scripts/runtime-privacy-evidence.sh"

echo "Runtime privacy evidence checks passed"
