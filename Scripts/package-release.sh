#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"

identity="${MACMETER_SIGN_IDENTITY:-}"
notary_profile="${MACMETER_NOTARY_PROFILE:-}"
owner_approval="${MACMETER_OWNER_APPROVAL:-}"
if [[ -z "$identity" ]]; then
  echo "Set MACMETER_SIGN_IDENTITY to a Developer ID Application identity." >&2
  exit 1
fi
if [[ -z "$notary_profile" ]]; then
  echo "Set MACMETER_NOTARY_PROFILE; production DMGs must be notarized and stapled." >&2
  exit 1
fi

source "$project_root/Scripts/version-policy.sh"

rm_target="$project_root/dist"
if [[ -e "$rm_target" ]]; then
  echo "Refusing to overwrite existing dist directory: $rm_target" >&2
  exit 1
fi

xcodebuild \
  -project MacMeter.xcodeproj \
  -scheme MacMeter \
  -configuration Release \
  -derivedDataPath build/ReleaseDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build

app="build/ReleaseDerivedData/Build/Products/Release/MacMeter.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
expected_version="$(macmeter_build_setting "$project_root" MARKETING_VERSION)"
expected_build="$(macmeter_build_setting "$project_root" CURRENT_PROJECT_VERSION)"
if [[ "$version" != "$expected_version" || "$build" != "$expected_build" ]]; then
  echo "Built artifact version $version ($build) does not match Xcode authority $expected_version ($expected_build)." >&2
  exit 1
fi
macmeter_validate_release_version "$version" "$owner_approval"

codesign --force --deep --options runtime --timestamp --sign "$identity" "$app"
codesign --verify --deep --strict --verbose=2 "$app"

mkdir -p dist/staging
ditto "$app" dist/staging/MacMeter.app
hdiutil create -volname MacMeter -srcfolder dist/staging -ov -format UDZO "dist/MacMeter-$version.dmg"

xcrun notarytool submit "dist/MacMeter-$version.dmg" --keychain-profile "$notary_profile" --wait
xcrun stapler staple "dist/MacMeter-$version.dmg"
xcrun stapler validate "dist/MacMeter-$version.dmg"

echo "Release artifact: dist/MacMeter-$version.dmg"
