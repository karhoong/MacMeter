# MacMeter automated QA evidence

Date: 2026-07-19  
Candidate: 0.1.4 (build 1)
Hardware: Apple M4 Max, 16 cores (12 Performance, 4 Efficiency)  
Status: automated/local preview checks pass; production release evidence remains incomplete

## Passing

- `bash Scripts/qa.sh`: 73 XCTest cases, 0 failures, plus version, timing-evidence, raw-performance-evidence, and runtime-privacy mutation suites.
- Production Swift line coverage: 2,076/2,236 (92.84%).
- All 33 declared metric calculation/conversion decision paths are exercised by an executable set-equality contract, including CPU counter reset/zero/kind paths, every network rejection, unit, and compact-decimal mode, all battery directions, Celsius/Fahrenheit conversion, temperature bounds, and formatting paths. Battery precision fixtures include nonzero currents from ±1 mA through ±50 mA.
- Live providers: CPU/topology, physical-interface network rates, battery power, and SoC temperature. The M4 Max live test now requires a valid temperature through the read-only AppleSMC fallback and a cached refresh below 250 ms.
- SoC classifier fixtures: hottest valid exact `SOC MTR Temp`; hottest valid AppleSMC CPU/GPU die key (`Tp`/`Te`/`Tg`/`TCMz`); duplicate names; rejected `PMU tdie`, battery, SSD, and chassis substitution; invalid values; unrelated sensors; and empty input.
- Deterministic raw-provider fixtures cover active `en*` selection while excluding down, non-running, loopback, bridge, and tunnel devices; network source failure; missing battery/property telemetry; every inconsistent battery direction/state; and charge/drain/idle values.
- Coordinator: disabled-provider polling, fresh rate baselines, immediate enable-sample timestamps, unavailable enable isolation, provider failure isolation, injected clock, exact interval restart, and cancellation.
- Login item service: injected enable, disable, approval-required, not-found, and error paths.
- Swift 6 Release Xcode build; arm64; bundle `com.karhoong.MacMeter`; `LSUIElement=true`; `0.1.4 (1)`.
- Static outbound-network source and linked-framework gates. Every QA Release candidate also undergoes a 10-second, one-second-cadence `lsof` observation of its exact child PID with all four providers forced on at the default two-second refresh; commit/dirty state, binary SHA-256, version/build, hardware, timestamps, configuration, method, observer provenance, liveness, and zero outbound/listening sockets are recorded in ignored `QA/latest-runtime-privacy.json` and revalidated fail-closed.
- Live M4 timing gates enforce refresh p95 error ≤200 ms, AppKit-host paint p95 <250 ms with a non-nil cached bitmap, and five-second cycle p95 error ≤200 ms. Exact values, UTC start time, commit SHA, and worktree state are generated at `QA/latest-timing.json` by every QA run.
- Render matrix: Compact/Cycle × all 16 metric combinations × light/dark × small/large/accessibility text. Every Cycle page fits a 136-point intrinsic-width budget. The production label is a native `NSStatusItem` attributed string rather than `MenuBarExtra`, with executable assertions that every segment uses a 6.5-point monospaced font and battery drain/charge/idle use native system red/green/blue. Dedicated semantic regressions prove all 15 non-empty Compact selections contain every enabled metric exactly once and lock the all-four title to `↑0.0↓0.5MB/s\n50% | 80°C | D 12W`, including the Fahrenheit variant.
- The native status title is applied directly to `NSStatusBarButton.attributedTitle` with zero custom status-button subviews. The popover host is created only when first opened and released after close. Settings no longer uses a SwiftUI hosting controller: one small native AppKit tree is retained and reused across red-close/programmatic-close cycles, preventing repeated presentation-tree allocation. A 25-cycle lifecycle regression locks that identity, while another regression proves repeated popover hosts deallocate.
- The status-button interaction regression performs a real `NSStatusBarButton.performClick`, proves lazy popover content is prepared and presentation is requested, then exercises the shared Settings action and verifies popover dismissal plus a visible `MacMeter.Settings` window.
- Native Settings interaction coverage exercises all metric toggles, CPU convention, Celsius/Fahrenheit, all network units, Compact/Cycle, all refresh rates, and Launch at Login, then reconstructs the store to prove immediate persistence. The live candidate's pre-interaction baseline was 47,840 KiB RSS and 18 MiB physical footprint.

## Performance evidence

- The first definitive run completed its 30-minute warm-up, then crossed literal RSS from 74,320 KiB to 90,736 KiB after about 3.5 measurement hours; the exact first failing row and bound failure evidence are archived under ignored `QA/performance-failures/20260719-0345-rss`.
- Read-only `vmmap`/heap diagnostics on that process reported a 32.4 MiB physical footprint and 27 MiB heap despite 90.7 MiB `ps` RSS. A fresh process similarly reported 85,936 KiB RSS with only a 22.5 MiB physical footprint. These observations do not prove the 24-hour growth requirement, but they demonstrate that literal RSS includes substantial volatile shared SwiftUI/AppKit residency.
- Evidence format v2 now records literal `/bin/ps` RSS and `proc_pid_rusage RUSAGE_INFO_V4` physical footprint in every row. The strict verifier independently recomputes baseline, maximum, and growth for both measures. RSS remains the active pass/fail gate until the owner approves another policy.
- A clean `0.1.3` rerun exposed a product lifecycle failure during normal UI journeys: RSS rose from about 50 MiB to 80.3 MiB after the popover host was retained, then to 104 MiB after the Settings host was retained. Physical footprint rose from about 20 MiB to 53 MiB. Bound evidence and diagnostics are archived under ignored `QA/performance-failures/20260719-1852-ui-retention`. `0.1.4` releases each popover host and replaces the heavyweight Settings host with one stable native AppKit tree; a new definitive soak remains required.

## Outstanding external/long-running release evidence

- A new default `Scripts/performance-soak.sh` run after the memory-policy decision: 30-minute warm-up plus 24-hour measurement. CPU uses cumulative `proc_pid_rusage` user+system nanoseconds over actual monotonic 59/61-second intervals, avoiding decaying-average and phase-alias bias. The v2 raw CSV retains RSS, physical footprint, and CPU/wall nanosecond deltas and is bound by filename, byte count, and SHA-256; the verifier ties elapsed time back to cumulative raw deltas, enforces the declared warmup and alternating cadence (except a target-truncated final interval), and independently recomputes all aggregates and approved thresholds. Live commit/hardware/binary/helper/toolchain/status/results provenance is generated at ignored `QA/latest-performance.json`.
- Developer ID signing identity and notarytool profile; notarized/stapled DMG, Gatekeeper assessment, and clean install.
- Installed-app Launch at Login across approval, denial, logout, and login.
- M1/M2 laptop and Apple Silicon no-battery desktop.
- Charger transitions, sleep/wake, controlled network accuracy, Wi-Fi/Ethernet/VPN transitions.
- Manual visual/accessibility matrix and seven-day soak before any owner consideration of `1.0.0`.

The application version remains in the `0.x` series. Only the owner command `pass` can authorize `1.0.0`.
