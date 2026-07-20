# MacMeter automated QA evidence

Date: 2026-07-20
Candidate: 1.0.3 (build 1)
Hardware: Apple M4 Max, 16 cores (12 Performance, 4 Efficiency)  
Status: QA GREEN and product-manager APPROVED on the exact `1.0.3` artifact

Release source commit: `db43e2bdd20d891d72caba4c0ae1e07a28df680b`

Release binary SHA-256: `a724c6f555f8003c7b39012e92b0646610ea55150d5d2840bb1a9103182bc603`

## Passing

- `1.0.3` replaces icon-highlight metric selection with native checkboxes, locks every Settings tab to one fixed-width canvas, wraps long copy, and adds system-default plus 17 selectable interface languages.
- The shortened exact-commit `1.0.3` suite passed 95 tests with zero failures, including all six hardware/timing cases through `Scripts/qa.sh`. Production coverage is 2511/2661 lines (94.363%). It does not run the retired long-duration soak.
- Battery VoiceOver copy is localized end-to-end in both the popover and status item. A table-driven regression covers the metric name, charge direction, and watt unit in every one of the 17 explicit languages.
- All 33 declared metric calculation/conversion decision paths are exercised by an executable set-equality contract, including CPU counter reset/zero/kind paths, every network rejection, unit, and compact-decimal mode, all battery directions, Celsius/Fahrenheit conversion, temperature bounds, and formatting paths. Battery precision fixtures include nonzero currents from ±1 mA through ±50 mA.
- Live providers: CPU/topology, physical-interface network rates, battery power, and SoC temperature. The M4 Max live test now requires a valid temperature through the read-only AppleSMC fallback and a cached refresh below 250 ms.
- SoC classifier fixtures: hottest valid exact `SOC MTR Temp`; hottest valid AppleSMC CPU/GPU die key (`Tp`/`Te`/`Tg`/`TCMz`); duplicate names; rejected `PMU tdie`, battery, SSD, and chassis substitution; invalid values; unrelated sensors; and empty input.
- Deterministic raw-provider fixtures cover active `en*` selection while excluding down, non-running, loopback, bridge, and tunnel devices; network source failure; missing battery/property telemetry; every inconsistent battery direction/state; and charge/drain/idle values.
- Coordinator: disabled-provider polling, fresh rate baselines, immediate enable-sample timestamps, unavailable enable isolation, provider failure isolation, injected clock, exact interval restart, and cancellation.
- Login item service: injected enable, disable, approval-required, not-found, and error paths.
- Swift 6 Debug, Swift Package, and clean arm64 Release builds pass. The verified artifact is `1.0.3 (1)`, `LSUIElement=true`, with the compiled app icon.
- Static outbound-network source and linked-framework gates. Every QA Release candidate also undergoes a 10-second, one-second-cadence `lsof` observation of its exact child PID with all four providers forced on at the default two-second refresh; commit/dirty state, binary SHA-256, version/build, hardware, timestamps, configuration, method, observer provenance, liveness, and zero outbound/listening sockets are recorded in ignored `QA/latest-runtime-privacy.json` and revalidated fail-closed.
- Live M4 timing gates pass: refresh p95 error 88.97 ms (≤200 ms), AppKit-host paint p95 48.34 ms (<250 ms) with zero render failures, and five-second cycle p95 error 17.42 ms (≤200 ms). Exact values, UTC start time, commit SHA, and worktree state are generated at `QA/latest-timing.json` by every QA run.
- Native UI matrix: Compact/Cycle × all 16 metric combinations, constrained-width assertions, and light/dark bitmap rendering for the complete popover and every Settings tab. Every multi-metric Compact mask uses exactly two rows, Network owns the top row when present, and the no-Network special cases are locked. CPU/temperature interpolation, icon-bearing tabs/cards, stable Settings title, vertical centering, upload/download spacing, and battery colors have executable regressions.
- The native status title is applied directly to `NSStatusBarButton.attributedTitle` with zero custom status-button subviews. Both the details popover and Settings are stable native AppKit trees; the Release target contains no `import SwiftUI` or `NSHostingController` and does not link SwiftUI. A 25-cycle Settings regression and 30-update/25-open popover regressions lock root, section, and core-row identity. Closed popovers stop repainting and refresh immediately before appearing.
- The status-button interaction regression performs a real `NSStatusBarButton.performClick`, proves one lazy native popover tree is prepared, presented, and reused across 25 cycles, then exercises the shared Settings action and verifies popover dismissal plus a visible `MacMeter.Settings` window. Production sampling bursts are coalesced into one status-title refresh.
- Native Settings interaction coverage exercises all metric toggles, CPU convention, Celsius/Fahrenheit, all network units, Compact/Cycle, all refresh rates, and Launch at Login, then reconstructs the store to prove immediate persistence.

## QA scope

- Long-duration performance and seven-day soak tests are retired from the active release flow by owner direction. Historical scripts remain available for optional diagnostics and are not represented as release gates.

## Outstanding external release evidence

- Developer ID signing identity and notarytool profile; notarized/stapled DMG, Gatekeeper assessment, and clean install.
- Installed-app Launch at Login across approval, denial, logout, and login.
- M1/M2 laptop and Apple Silicon no-battery desktop.
- Charger transitions, sleep/wake, controlled network accuracy, Wi-Fi/Ethernet/VPN transitions.
- Manual VoiceOver/increased-text/constrained-menu review remains outstanding evidence.

The owner explicitly issued the required `pass` command and authorized `1.0.0` on 2026-07-19; the protected policy now permits owner-approved `1.0.x` patch releases and still rejects unapproved or unsupported versions.

Dedicated QA returned GREEN and the product-manager returned APPROVE on the exact commit and artifact above. The remaining items are explicitly external distribution, additional-hardware, transition, or manual accessibility evidence; none blocks this interface release under the current owner-approved QA scope.
