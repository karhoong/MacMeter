# MacMeter 0.1.3 requirement traceability

Status meanings: **Verified** has current automated or physical evidence; **Partial** has implementation evidence but incomplete acceptance evidence; **Pending external** requires credentials, another machine, a physical transition, or elapsed soak time.

| ID | Requirement | Status | Authoritative evidence / remaining evidence |
|---|---|---|---|
| APP-01 | Native Swift 6, Apple Silicon, macOS 13+, menu-bar-only, no Dock icon | Verified | `Package.swift`, `MacMeter.xcodeproj`, `MacMeterApp.swift`, arm64 artifact checks and `LSUIElement=true` in `Scripts/qa.sh` |
| CPU-01 | Normalized total 0–100% | Verified | `MetricMath.cpuReading`; formula/boundary tests in `MetricMathTests` |
| CPU-02 | Summed total 0–coreCount×100% | Verified | Per-core sum assertion and live M4 test |
| CPU-03 | Per-core percentages with E/P labels; popover shows both totals | Verified | `CoreTopologyReader`, `MeterPopoverView`, exact live M4 result 16 cores / 12 P / 4 E |
| TEMP-01 | Hottest valid SoC die temperature; invalid/missing shows `—`, never stale or substituted from battery/SSD/chassis | Verified | `SensorBridge.m`; exact `SOC MTR Temp` is preferred, with read-only AppleSMC `Tp`/`Te`/`Tg`/`TCMz` fallback; classifier fixtures reject `PMU tdie`, invalid, unrelated and empty inputs; live M4 hardware test requires a valid reading and cached refresh below 250 ms |
| TEMP-02 | Median ≤3°C and p95 ≤5°C versus trusted independent tool | Pending external | Requires a supported Mac exposing exact sensors plus an independent trusted reference |
| NET-01 | Simultaneous inbound/outbound physical Wi-Fi/Ethernet; exclude loopback and tunnels/VPN | Verified in code; physical transitions pending | `NetworkProvider` selects active `en*`; deterministic fixtures exclude down/non-running `en*`, loopback, bridge and tunnel devices; Wi-Fi/Ethernet/VPN transition matrix remains physical |
| NET-02 | Decimal Kbps/KBps/Mbps/MBps with exact eight-bit conversion | Verified | All conversion branches in `MetricMathTests` |
| NET-03 | Rebaseline after interface/counter changes and sleep/wake | Verified in logic; physical sleep/wake pending | Counter/interface/reset tests, coordinator baseline tests, workspace notification handlers |
| NET-04 | Controlled-transfer median error ≤5%, p95 ≤10% | Pending external | Requires controlled physical-interface transfer capture |
| BAT-01 | Signed current × voltage battery-terminal power; precision ≤0.1 W | Verified | Positive, negative, zero and ±1/20/49/50 mA fixtures |
| BAT-02 | Green `C 30W`, red `D 8.4W`, blue `— 0W`; no trailing `.0` | Verified | `BatteryColorRole` exact mapping, `MenuBarLabelView`, formatter tests, semantic accessibility tests |
| BAT-03 | Missing/inconsistent battery telemetry isolates to `—` | Verified in code; desktop physical check pending | Injected raw battery fixtures cover no battery, missing voltage/current, every inconsistent direction/state, and valid charge/drain/idle; unavailable rendering and desktop physical check remain separate |
| DISP-01 | Independent enable/disable; disabled providers stop polling | Verified | Settings and coordinator provider-count tests |
| DISP-02 | Compact shows every selection; all four use one status-bar-safe row; Cycle rotates every 5 seconds | Verified automated | Production uses a native variable-width `NSStatusItem`; semantic tests prove every selection appears exactly once, lock the all-four order/string, and assert an 8-point monospaced font on every attributed segment; Compact/Cycle render matrix and live five-cycle p95 gate |
| DISP-03 | Empty selection retains reachable gauge | Verified | All-disabled render coverage and explicit accessibility label |
| POP-01 | Click opens full readings, core rows, explanations, timestamp, Settings, version and Quit | Verified automated; live accessibility traversal pending | `MeterPopoverView` renders the shared version/build label. A real `NSStatusBarButton.performClick` regression exercises the production target/action, proves lazy popover preparation/presentation, then invokes the shared Settings action and verifies dismissal plus a visible retained `MacMeter.Settings` window. |
| SET-01 | Metrics, CPU convention, Celsius/Fahrenheit, network unit, Compact/Cycle appearance, 1/2/5/10 refresh, login, About/privacy | Verified | `MacMeterSettingsView`, defaults/migration/persistence and rendering tests |
| SET-02 | Immediate `UserDefaults` persistence with specified defaults | Verified | `SettingsStoreTests` |
| LOGIN-01 | `SMAppService.mainApp`, approval/denied/not-found states | Verified in isolation; installed flow pending | Injected service tests; signed-installed logout/login requires release artifact |
| ARCH-01 | Injectable settings, clock, topology, login and hardware providers | Verified | Coordinator/provider initializers and fake-clock/provider/login tests |
| ARCH-02 | Single non-overlapping sampler; presentation changes do not poll; failures isolate | Verified | Coordinator task/subscription and isolation tests |
| ARCH-03 | Timestamped availability states | Verified | `MetricAvailability.observedAt`, clock-derived transitions, immediate fresh enable timestamps, and unavailable-enable non-advancement tests |
| QA-01 | 100% metric calculation/conversion decision-path coverage; overall line coverage ≥85% | Verified | `MetricDecisionPath` executable set-equality test covers all 33 declared semantic paths; source-only line gate in `Scripts/qa.sh` is 1,734/1,886 (91.94%). Swift's exported LLVM data provides no branch counters, so the explicit production-path recorder is the authoritative branch gate rather than a line-coverage proxy. |
| QA-02 | CPU tolerance ≤0.1 percentage point; battery ≤0.1 W | Verified | Exact deterministic assertions |
| QA-03 | Refresh p95 ±200 ms; render p95 <250 ms; cycle 5 s ±200 ms | Verified on M4 | Live hardware timing suite; generated commit/timestamp-bound results in ignored `QA/latest-timing.json` |
| QA-04 | Light/dark, increased text, constrained layout, all combinations/modes | Verified render automation; manual readability pending | Compact/Cycle Cartesian render matrix across all 16 selections; every Cycle page ≤136 pt and every non-empty Compact selection resists compression while staying ≤180 pt wide and ≤24 pt tall; physical constrained-menu readability remains manual |
| QA-05 | VoiceOver announces names, units and full battery direction | Partial | Applied labels and exact semantic string tests; real VoiceOver traversal remains manual |
| PERF-01 | Idle CPU ≤1% average, p95 ≤3%; RSS ≤80 MiB; ≤5 MiB growth/24 h | Short-run pass; 24-hour run pending | The original SwiftUI status-label build crossed literal RSS after about 3.5 hours. `0.1.3` now applies an attributed title directly to the native status button, has no custom status-button subviews, lazily creates the popover, and uses a pure AppKit lifecycle. A live preview sampled at 0.0% CPU and 47,920 KiB RSS. This clears the immediate bounds but does not establish 24-hour growth; the definitive 30-minute warm-up + 24-hour run must be repeated on the new implementation. |
| PERF-02 | Seven-day soak before 1.0 consideration | Pending elapsed run | Not started; not required to change preview version |
| DIST-01 | Hardened, Developer ID-signed, notarized/stapled DMG; clean install | Pending external | Enforced packaging script exists; requires owner signing identity and notary profile |
| PRIV-01 | No telemetry, outbound requests, or listening sockets | Verified | Source/framework gate plus `Scripts/runtime-privacy-evidence.sh`; every QA Release build generates ignored `QA/latest-runtime-privacy.json`, bound to commit/dirty state, artifact SHA-256, version/build, hardware, timestamp, observer implementation/tool, and a fail-closed 10-second exact-PID socket observation with all providers enabled at the default two-second refresh |
| VER-01 | Start/remain 0.x; only owner command `pass` authorizes 1.0.0 | Verified | Xcode single version authority and script policy tests; current artifact `0.1.3 (1)` |
| HW-01 | M1/M2 laptop, M4 Max, no-battery desktop acceptance matrix | Partial | M4 Max automated/live evidence complete; other two machines unavailable in current workspace |
| PM-01 | Development → QA → PM rejection/fix loop | Verified for preview | Independent QA and PM approved the prior preview after a PM rejection and regression loop; rerun required after subsequent changes |

## Current completion boundary

All implementation requirements and the locally automatable M4 checks have evidence. Full production readiness remains unproven until the pending external and elapsed-time rows are completed. The app must remain in the `0.x` series until the owner explicitly says **pass**.
