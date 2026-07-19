# MacMeter release checklist

## Automated evidence

- [x] Swift unit and coordinator suites pass with coverage enabled.
- [x] All declared metric calculation/conversion decision paths pass the executable 100% semantic branch contract; production line coverage is ≥85%.
- [x] Swift 6 Debug and Release Xcode builds pass.
- [x] Rebuild and verify the arm64 `1.0.2` release with `LSUIElement=true` and compiled `AppIcon.icns`.
- [x] No outbound-network implementation is present; the current Release candidate has commit/artifact-bound runtime evidence of zero outbound or listening sockets.

## Physical validation

- [ ] M1/M2 laptop: CPU topology, SoC temperature, charge, drain, sleep/wake.
- [x] M4 Max: 16 cores reported as 12 Performance and 4 Efficiency.
- [ ] Apple Silicon desktop: battery reports unavailable without affecting other metrics.
- [ ] Wi-Fi/Ethernet transitions do not create spikes.
- [ ] VPN traffic is counted once through the physical interface.
- [ ] Launch at Login survives logout/login and handles denied approval.
- [ ] Compact two-line all-metric and five-second Cycle modes remain readable.
- [ ] VoiceOver announces metric names, units, and full battery direction.
- [ ] Light, dark, increased-text, auto-hidden, and constrained menu bars pass.

## Performance and stability

- [x] Refresh p95 within ±200ms; sample-to-render p95 <250ms.
- [x] Cycle interval is 5s ±200ms.
- [x] Long-duration performance and seven-day soak tests are retired from the active QA flow by owner direction.

## Authority

- [x] QA readiness recorded for `1.0.2`.
- [x] Product-manager readiness recorded for `1.0.2`.
- [x] Owner explicitly said **pass** and authorized promotion to `1.0.0`.
