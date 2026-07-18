#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
evidence="${1:-$project_root/QA/latest-runtime-privacy.json}"
app="${MACMETER_APP_PATH:-$project_root/build/DerivedData/Build/Products/Release/MacMeter.app}"
executable="$app/Contents/MacOS/MacMeter"
observer_tool="/usr/sbin/lsof"

test -f "$evidence"
test -x "$executable"
test -x "$observer_tool"
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

jq -e \
  --arg commit "$commit" \
  --argjson dirtyWorktree "$dirty_worktree" \
  --arg hardware "$hardware" \
  --arg appBinarySHA256 "$binary_sha256" \
  --arg version "$version" \
  --arg build "$build" \
  --arg observerScriptSHA256 "$observer_script_sha256" \
  --arg observerToolPath "$observer_tool" \
  --arg observerToolVersion "$observer_tool_version" \
  -f "$project_root/Scripts/runtime-privacy-evidence.jq" \
  "$evidence" >/dev/null

echo "Runtime privacy evidence validates for $commit and $binary_sha256"
