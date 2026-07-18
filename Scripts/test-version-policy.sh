#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
source "$project_root/Scripts/version-policy.sh"

macmeter_validate_release_version "0.1.0" ""
macmeter_validate_release_version "0.9.9" ""
if macmeter_validate_release_version "1.0.0" "" 2>/dev/null; then
  echo "Unapproved 1.0.0 unexpectedly passed" >&2
  exit 1
fi
macmeter_validate_release_version "1.0.0" "pass"
if macmeter_validate_release_version "1.0.1" "pass" 2>/dev/null; then
  echo "Unapproved post-1.0 version unexpectedly passed" >&2
  exit 1
fi

grep -q '<string>$(MARKETING_VERSION)</string>' "$project_root/Resources/Info.plist"
grep -q '<string>$(CURRENT_PROJECT_VERSION)</string>' "$project_root/Resources/Info.plist"

version="$(macmeter_build_setting "$project_root" MARKETING_VERSION)"
build="$(macmeter_build_setting "$project_root" CURRENT_PROJECT_VERSION)"
test -n "$version"
test -n "$build"
macmeter_validate_release_version "$version" ""

echo "Version policy checks passed for $version ($build)"
