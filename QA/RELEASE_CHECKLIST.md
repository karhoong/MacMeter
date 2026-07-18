# MacMeter release checklist

## Automated evidence

- [x] Swift unit and coordinator suites pass with coverage enabled.
- [x] Swift 6 Debug and Release Xcode builds pass.
- [x] Built app is arm64, version `0.1.0`, and `LSUIElement=true`.
- [x] No outbound-network implementation is present.

## Physical validation

- [ ] M1/M2 laptop: CPU topology, SoC temperature, charge, drain, sleep/wake.
- [x] M4 Max: 16 cores reported as 12 Performance and 4 Efficiency.
- [ ] Apple Silicon desktop: battery reports unavailable without affecting other metrics.
- [ ] Wi-Fi/Ethernet transitions do not create spikes.
- [ ] VPN traffic is counted once through the physical interface.
- [ ] Launch at Login survives logout/login and handles denied approval.
- [ ] Compact, Default, and five-second Cycle modes remain readable.
- [ ] VoiceOver announces metric names, units, and full battery direction.
- [ ] Light, dark, increased-text, auto-hidden, and constrained menu bars pass.

## Performance and stability

- [ ] Idle average CPU ≤1%; p95 ≤3% over 30 minutes.
- [ ] `Scripts/performance-soak.sh` passes after a 30-minute warm-up: RSS ≤80 MiB at every post-warm-up sample, ≤5 MiB growth over 24 hours, idle CPU ≤1% average and ≤3% p95 (60-second cadence).
- [x] Refresh p95 within ±200ms; sample-to-render p95 <250ms.
- [x] Cycle interval is 5s ±200ms.
- [ ] Seven-day physical soak completed before owner considers `1.0.0`.

## Authority

- [ ] QA readiness recorded.
- [ ] Product-manager readiness recorded.
- [ ] Version remains `0.x` until the owner explicitly says **pass**.
