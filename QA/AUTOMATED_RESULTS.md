# MacMeter automated QA evidence

Date: 2026-07-19  
Candidate: 0.1.0 (build 1)  
Hardware: Apple M4 Max, 16 cores (12 Performance, 4 Efficiency)  
Status: automated/local preview checks pass; production release evidence remains incomplete

## Passing

- `bash Scripts/qa.sh`: 41 tests, 0 failures.
- Production Swift line coverage: 1,121/1,232 (90.99%).
- Metric calculation and conversion branches have deterministic boundary tests, including nonzero battery currents from ±1 mA through ±50 mA.
- Live providers: CPU/topology, physical-interface network rates, and battery power. The M4 Max exposes no valid `SOC MTR Temp`, so temperature correctly reports unavailable rather than substituting another sensor.
- SoC classifier fixtures: hottest valid `SOC MTR Temp`, duplicate names, rejected `PMU tdie` substitution, invalid values, unrelated sensors, and empty input.
- Coordinator: disabled-provider polling, fresh rate baselines, provider failure isolation, injected clock, exact interval restart, and cancellation.
- Login item service: injected enable, disable, approval-required, not-found, and error paths.
- Swift 6 Release Xcode build; arm64; bundle `com.karhoong.MacMeter`; `LSUIElement=true`; `0.1.0 (1)`.
- Static outbound-network source and linked-framework gates.

## Performance diagnostic

- Short diagnostic only (not release-valid): 30-second warm-up and 120-second measurement.
- RSS baseline 85,648 KiB; maximum 86,320 KiB; growth 672 KiB; average CPU 0.342%.
- This correctly failed the RSS gate because it omitted the required 30-minute warm-up and remained above 80 MiB.
- A separately launched process later fell below the limit, but isolated snapshots do not satisfy the release gate.

## Outstanding external/long-running release evidence

- Default `Scripts/performance-soak.sh`: 30-minute warm-up plus 24-hour measurement.
- Developer ID signing identity and notarytool profile; notarized/stapled DMG, Gatekeeper assessment, and clean install.
- Installed-app Launch at Login across approval, denial, logout, and login.
- M1/M2 laptop and Apple Silicon no-battery desktop.
- Charger transitions, sleep/wake, controlled network accuracy, Wi-Fi/Ethernet/VPN transitions.
- Manual visual/accessibility matrix and seven-day soak before any owner consideration of `1.0.0`.

The application version remains `0.1.0`. Only the owner command `pass` can authorize `1.0.0`.
