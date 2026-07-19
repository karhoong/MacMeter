# MacMeter automated QA evidence

Date: 2026-07-19  
Candidate: 0.1.0 (build 1)  
Hardware: Apple M4 Max, 16 cores (12 Performance, 4 Efficiency)  
Status: automated/local preview checks pass; production release evidence remains incomplete

## Passing

- `bash Scripts/qa.sh`: 60 XCTest cases, 0 failures, plus version, timing-evidence, raw-performance-evidence, and runtime-privacy mutation suites.
- Production Swift line coverage: 1,391/1,476 (94.24%).
- All 29 declared metric calculation/conversion decision paths are exercised by an executable set-equality contract, including CPU counter reset/zero/kind paths, every network rejection and unit, all battery directions, temperature bounds, and formatting paths. Battery precision fixtures include nonzero currents from ±1 mA through ±50 mA.
- Live providers: CPU/topology, physical-interface network rates, and battery power. The M4 Max exposes no valid `SOC MTR Temp`, so temperature correctly reports unavailable rather than substituting another sensor.
- SoC classifier fixtures: hottest valid `SOC MTR Temp`, duplicate names, rejected `PMU tdie` substitution, invalid values, unrelated sensors, and empty input.
- Deterministic raw-provider fixtures cover active `en*` selection while excluding down, non-running, loopback, bridge, and tunnel devices; network source failure; missing battery/property telemetry; every inconsistent battery direction/state; and charge/drain/idle values.
- Coordinator: disabled-provider polling, fresh rate baselines, immediate enable-sample timestamps, unavailable enable isolation, provider failure isolation, injected clock, exact interval restart, and cancellation.
- Login item service: injected enable, disable, approval-required, not-found, and error paths.
- Swift 6 Release Xcode build; arm64; bundle `com.karhoong.MacMeter`; `LSUIElement=true`; `0.1.0 (1)`.
- Static outbound-network source and linked-framework gates. Every QA Release candidate also undergoes a 10-second, one-second-cadence `lsof` observation of its exact child PID with all four providers forced on at the default two-second refresh; commit/dirty state, binary SHA-256, version/build, hardware, timestamps, configuration, method, observer provenance, liveness, and zero outbound/listening sockets are recorded in ignored `QA/latest-runtime-privacy.json` and revalidated fail-closed.
- Live M4 timing gates enforce refresh p95 error ≤200 ms, AppKit-host paint p95 <250 ms with a non-nil cached bitmap, and five-second cycle p95 error ≤200 ms. Exact values, UTC start time, commit SHA, and worktree state are generated at `QA/latest-timing.json` by every QA run.
- Render matrix: Compact/Default/Cycle × all 16 metric combinations × light/dark × small/large/accessibility text. Every Cycle page fits a 136-point intrinsic-width budget; all-metric Compact and Default labels fit 300- and 480-point budgets respectively at small, large, and accessibility text sizes, without forced clipping in the test.

## Performance evidence

- The first definitive run completed its 30-minute warm-up, then crossed literal RSS from 74,320 KiB to 90,736 KiB after about 3.5 measurement hours; the exact first failing row and bound failure evidence are archived under ignored `QA/performance-failures/20260719-0345-rss`.
- Read-only `vmmap`/heap diagnostics on that process reported a 32.4 MiB physical footprint and 27 MiB heap despite 90.7 MiB `ps` RSS. A fresh process similarly reported 85,936 KiB RSS with only a 22.5 MiB physical footprint. These observations do not prove the 24-hour growth requirement, but they demonstrate that literal RSS includes substantial volatile shared SwiftUI/AppKit residency.
- Evidence format v2 now records literal `/bin/ps` RSS and `proc_pid_rusage RUSAGE_INFO_V4` physical footprint in every row. The strict verifier independently recomputes baseline, maximum, and growth for both measures. RSS remains the active pass/fail gate until the owner approves another policy.

## Outstanding external/long-running release evidence

- A new default `Scripts/performance-soak.sh` run after the memory-policy decision: 30-minute warm-up plus 24-hour measurement. CPU uses cumulative `proc_pid_rusage` user+system nanoseconds over actual monotonic 59/61-second intervals, avoiding decaying-average and phase-alias bias. The v2 raw CSV retains RSS, physical footprint, and CPU/wall nanosecond deltas and is bound by filename, byte count, and SHA-256; the verifier ties elapsed time back to cumulative raw deltas, enforces the declared warmup and alternating cadence (except a target-truncated final interval), and independently recomputes all aggregates and approved thresholds. Live commit/hardware/binary/helper/toolchain/status/results provenance is generated at ignored `QA/latest-performance.json`.
- Developer ID signing identity and notarytool profile; notarized/stapled DMG, Gatekeeper assessment, and clean install.
- Installed-app Launch at Login across approval, denial, logout, and login.
- M1/M2 laptop and Apple Silicon no-battery desktop.
- Charger transitions, sleep/wake, controlled network accuracy, Wi-Fi/Ethernet/VPN transitions.
- Manual visual/accessibility matrix and seven-day soak before any owner consideration of `1.0.0`.

The application version remains `0.1.0`. Only the owner command `pass` can authorize `1.0.0`.
