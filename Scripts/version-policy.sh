#!/bin/bash

macmeter_build_setting() {
  local project_root="$1"
  local setting="$2"
  xcodebuild \
    -project "$project_root/MacMeter.xcodeproj" \
    -scheme MacMeter \
    -configuration Release \
    -derivedDataPath "$project_root/build/VersionSettings" \
    -showBuildSettings 2>/dev/null \
    | awk -v key="$setting" '$1 == key && $2 == "=" { print $3; exit }'
}

macmeter_validate_release_version() {
  local version="$1"
  local owner_approval="${2:-}"

  if [[ "$version" =~ ^0\.[0-9]+\.[0-9]+$ ]]; then
    return 0
  fi
  if [[ "$version" =~ ^1\.0\.[0-9]+$ ]]; then
    if [[ "$owner_approval" == "pass" ]]; then
      return 0
    fi
    echo "$version requires the owner approval value: pass" >&2
    return 1
  fi
  echo "Unsupported release version under the owner-controlled policy: $version" >&2
  return 1
}
