# MacMeter 0.1.0 requirement traceability

Status meanings: **Verified** has current automated or physical evidence; **Partial** has implementation evidence but incomplete acceptance evidence; **Pending external** requires credentials, another machine, a physical transition, or elapsed soak time.

| ID | Requirement | Status | Authoritative evidence / remaining evidence |
|---|---|---|---|
| APP-01 | Native Swift 6, Apple Silicon, macOS 13+, menu-bar-only, no Dock icon | Verified | `Package.swift`, `MacMeter.xcodeproj`, `MacMeterApp.swift`, arm64 artifact checks and `LSUIElement=true` in `Scripts/qa.sh` |
| CPU-01 | Normalized total 0–100% | Verified | `MetricMath.cpuReading`; formula/boundary tests in `MetricMathTests` |
| CPU-02 | Summed total 0–coreCount×100% | Verified | Per-core sum assertion and live M4 test |
| CPU-03 | Per-core percentages with E/P labels; popover shows both totals | Verified | `CoreTopologyReader`, `MeterPopoverView`, exact live M4 result 16 cores / 12 P / 4 E |
| TEMP-01 | Hottest valid `SOC MTR Temp` only; invalid/missing shows `—`, never stale or substituted | Verified | `SensorBridge.m`; selector fixtures reject `PMU tdie`, invalid, unrelated and empty inputs; M4 correctly reports unavailable |
| TEMP-02 | Median ≤3°C and p95 ≤5°C versus trusted independent tool | Pending external | Requires a supported Mac exposing exact sensors plus an independent trusted reference |
| NET-01 | Simultaneous inbound/outbound physical Wi-Fi/Ethernet; exclude loopback and tunnels/VPN | Verified in code; physical transitions pending | `NetworkProvider` selects active `en*`; source/unit tests; Wi-Fi/Ethernet/VPN transition matrix remains physical |
| NET-02 | Decimal Kbps/KBps/Mbps/MBps with exact eight-bit conversion | Verified | All conversion branches in `MetricMathTests` |
| NET-03 | Rebaseline after interface/counter changes and sleep/wake | Verified in logic; physical sleep/wake pending | Counter/interface/reset tests, coordinator baseline tests, workspace notification handlers |
| NET-04 | Controlled-transfer median error ≤5%, p95 ≤10% | Pending external | Requires controlled physical-interface transfer capture |
| BAT-01 | Signed current × voltage battery-terminal power; precision ≤0.1 W | Verified | Positive, negative, zero and ±1/20/49/50 mA fixtures |
| BAT-02 | Green `C 30W`, red `D 8.4W`, neutral `— 0W`; no trailing `.0` | Verified | `MenuBarLabelView`, formatter tests, semantic accessibility tests |
| BAT-03 | Missing/inconsistent battery telemetry isolates to `—` | Verified in code; desktop physical check pending | `BatteryPowerProvider`, unavailable rendering and failure-isolation tests |
| DISP-01 | Independent enable/disable; disabled providers stop polling | Verified | Settings and coordinator provider-count tests |
| DISP-02 | Compact, Default zones, Cycle every 5 seconds | Verified automated | Mode × all 16 metric combinations render matrix; live five-cycle p95 gate |
| DISP-03 | Empty selection retains reachable gauge | Verified | All-disabled render coverage and explicit accessibility label |
| POP-01 | Click opens full readings, core rows, explanations, timestamp, Settings, version and Quit | Verified implementation/render | `MeterPopoverView` and render matrix; direct menu interaction remains manual |
| SET-01 | Metrics, CPU convention, network unit, appearance, 1/2/5/10 refresh, login, About/privacy | Verified | `MacMeterSettingsView`, defaults/persistence and rendering tests |
| SET-02 | Immediate `UserDefaults` persistence with specified defaults | Verified | `SettingsStoreTests` |
| LOGIN-01 | `SMAppService.mainApp`, approval/denied/not-found states | Verified in isolation; installed flow pending | Injected service tests; signed-installed logout/login requires release artifact |
| ARCH-01 | Injectable settings, clock, topology, login and hardware providers | Verified | Coordinator/provider initializers and fake-clock/provider/login tests |
| ARCH-02 | Single non-overlapping sampler; presentation changes do not poll; failures isolate | Verified | Coordinator task/subscription and isolation tests |
| ARCH-03 | Timestamped availability states | Verified | `MetricAvailability.observedAt` tests and clock-derived transitions |
| QA-01 | Metric/conversion branches fully exercised; overall line coverage ≥85% | Verified | Semantic branch fixtures; source-only coverage gate in `Scripts/qa.sh` (latest 92.10%) |
| QA-02 | CPU tolerance ≤0.1 percentage point; battery ≤0.1 W | Verified | Exact deterministic assertions |
| QA-03 | Refresh p95 ±200 ms; render p95 <250 ms; cycle 5 s ±200 ms | Verified on M4 | Live hardware timing suite; values recorded in `AUTOMATED_RESULTS.md` |
| QA-04 | Light/dark, increased text, constrained layout, all combinations/modes | Verified render automation; manual readability pending | Cartesian render matrix plus constrained Cycle frame |
| QA-05 | VoiceOver announces names, units and full battery direction | Partial | Applied labels and exact semantic string tests; real VoiceOver traversal remains manual |
| PERF-01 | Idle CPU ≤1% average, p95 ≤3%; RSS ≤80 MiB; ≤5 MiB growth/24 h | Pending elapsed run | Enforced by `Scripts/performance-soak.sh`; default 30-minute warm-up + 24-hour run not complete |
| PERF-02 | Seven-day soak before 1.0 consideration | Pending elapsed run | Not started; not required to change preview version |
| DIST-01 | Hardened, Developer ID-signed, notarized/stapled DMG; clean install | Pending external | Enforced packaging script exists; requires owner signing identity and notary profile |
| PRIV-01 | No telemetry or outbound requests | Verified | Source/framework gate and runtime preview socket check from independent QA |
| VER-01 | Start/remain 0.x; only owner command `pass` authorizes 1.0.0 | Verified | Xcode single version authority and script policy tests; current artifact `0.1.0 (1)` |
| HW-01 | M1/M2 laptop, M4 Max, no-battery desktop acceptance matrix | Partial | M4 Max automated/live evidence complete; other two machines unavailable in current workspace |
| PM-01 | Development → QA → PM rejection/fix loop | Verified for preview | Independent QA and PM approved the prior preview after a PM rejection and regression loop; rerun required after subsequent changes |

## Current completion boundary

All implementation requirements and the locally automatable M4 checks have evidence. Full production readiness remains unproven until the pending external and elapsed-time rows are completed. The app must remain `0.1.0` until the owner explicitly says **pass**.
