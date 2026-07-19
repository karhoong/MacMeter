# MacMeter release checklist

## Automated evidence

- [x] Swift unit and coordinator suites pass with coverage enabled.
- [x] All declared metric calculation/conversion decision paths pass the executable 100% semantic branch contract; production line coverage is ≥85%.
- [x] Swift 6 Debug and Release Xcode builds pass.
- [x] Built app is arm64, version `0.1.3`, and `LSUIElement=true`.
- [x] No outbound-network implementation is present; the current Release candidate has commit/artifact-bound runtime evidence of zero outbound or listening sockets.

## Physical validation

- [ ] M1/M2 laptop: CPU topology, SoC temperature, charge, drain, sleep/wake.
- [x] M4 Max: 16 cores reported as 12 Performance and 4 Efficiency.
- [ ] Apple Silicon desktop: battery reports unavailable without affecting other metrics.
- [ ] Wi-Fi/Ethernet transitions do not create spikes.
- [ ] VPN traffic is counted once through the physical interface.
- [ ] Launch at Login survives logout/login and handles denied approval.
- [ ] Compact single-line all-metric and five-second Cycle modes remain readable.
- [ ] VoiceOver announces metric names, units, and full battery direction.
- [ ] Light, dark, increased-text, auto-hidden, and constrained menu bars pass.

## Performance and stability

- [ ] Idle average CPU ≤1%; p95 ≤3% over 30 minutes.
- [ ] Resolve the owner decision on literal RSS versus physical footprint after the first run's RSS failure; until then literal `/bin/ps` RSS remains the active gate.
- [ ] `Scripts/performance-soak.sh` passes after a 30-minute warm-up under the approved memory policy: idle CPU ≤1% cumulative average and ≤3% interval p95 (alternating 59/61-second monotonic cadence); v2 raw CSV hash/size binding and independent RSS, physical-footprint, CPU, and duration recomputation also pass.
- [x] Refresh p95 within ±200ms; sample-to-render p95 <250ms.
- [x] Cycle interval is 5s ±200ms.
- [ ] Seven-day physical soak completed before owner considers `1.0.0`.

## Authority

- [ ] QA readiness recorded.
- [ ] Product-manager readiness recorded.
- [ ] Version remains `0.x` until the owner explicitly says **pass**.
