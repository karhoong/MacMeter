# MacMeter

MacMeter is a private, native Apple Silicon menu-bar monitor for CPU utilization, SoC temperature, network throughput, and battery charge/discharge power.

## Requirements

- Apple Silicon Mac
- macOS 13 or later
- Xcode 26 or a compatible Swift 6 toolchain

## Build

```sh
xcodebuild -project MacMeter.xcodeproj -scheme MacMeter -configuration Release \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

The unsigned local app is produced at `build/DerivedData/Build/Products/Release/MacMeter.app`.

For a production DMG, set `MACMETER_SIGN_IDENTITY` and a `notarytool` keychain profile in `MACMETER_NOTARY_PROFILE`, then run `bash Scripts/package-release.sh`. Notarization and stapling are mandatory. A future owner-approved `1.0.0` also requires `MACMETER_OWNER_APPROVAL=pass`; the current source remains `0.1.0` until the owner explicitly gives that command.

## Test

```sh
bash Scripts/qa.sh
```

The release performance gate is automated by `bash Scripts/performance-soak.sh`: it warms the Release app for 30 minutes, then samples RSS and CPU every minute for 24 hours. Short diagnostic runs can override `MACMETER_WARMUP_SECONDS`, `MACMETER_SOAK_SECONDS`, and `MACMETER_SAMPLE_SECONDS`; only the default full run satisfies the release checklist.

## Privacy and distribution

MacMeter reads local operating-system counters only. It has no analytics, telemetry, update checker, or other outbound network request. Exact SoC temperature uses runtime-discovered `SOC MTR Temp` sensors, with Apple Silicon `PMU tdie` sensors as the fallback used by newer chips such as M4. This is a read-only, undocumented IOHID interface, so MacMeter is intended for direct Developer ID distribution rather than the Mac App Store.

## Version policy

The application starts at `0.1.0` and remains in the `0.x` series until the owner explicitly says **pass**. QA and product review can report readiness but cannot promote the version to `1.0.0`.
