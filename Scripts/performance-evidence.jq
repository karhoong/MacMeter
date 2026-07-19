def nonnegative_number: type == "number" and . >= 0;
def nonnegative_integer: type == "number" and . >= 0 and floor == .;
def positive_integer: type == "number" and . > 0 and floor == .;

.schemaVersion == 2
and .status == "passed"
and .commit == $commit
and .hardware == $hardware
and .binarySHA256 == $binarySHA256
and .metricsSourceSHA256 == $metricsSourceSHA256
and .metricsBinarySHA256 == $metricsBinarySHA256
and .metricsCompiler == $metricsCompiler
and .sleepPreventionMethod == "caffeinate -dimsu -w harness PID with per-sample liveness checks"
and .dirtyWorktree == false
and .version == $version
and .build == $build
and (.startedAt | type == "string" and length > 0)
and (.finishedAt | type == "string" and length > 0)
and .warmupSeconds == 1800
and .soakSeconds == 86400
and .sampleSeconds == 60
and .sampleCadenceSeconds == [59, 61]
and .cpuMeasurementMethod == "proc_pid_rusage cumulative user+system CPU nanoseconds divided by CLOCK_MONOTONIC wall-time deltas"
and .rssMeasurementMethod == "/bin/ps resident set size in KiB; active release gate"
and .physicalFootprintMeasurementMethod == "proc_pid_rusage RUSAGE_INFO_V4 ri_phys_footprint bytes floored after division by 1024; observational until policy approval"
and .thresholds == {
  rssLimitKiB: 81920,
  growthLimitKiB: 5120,
  averageCPUPercentLimit: 1,
  p95CPUPercentLimit: 3
}
and .rawCSV.formatVersion == 2
and (.rawCSV.fileName | type == "string"
  and test("^[A-Za-z0-9][A-Za-z0-9._-]*$"))
and (.rawCSV.sha256 | type == "string" and test("^[0-9a-f]{64}$"))
and (.rawCSV.byteCount | positive_integer)
and (.results | type == "object")
and (.results.samples | positive_integer)
and .results.samples >= 1400
and (.results.baselineRSSKiB | nonnegative_integer)
and (.results.maximumRSSKiB | nonnegative_integer)
and (.results.growthKiB | nonnegative_integer)
and (.results.baselinePhysicalFootprintKiB | nonnegative_integer)
and (.results.maximumPhysicalFootprintKiB | nonnegative_integer)
and (.results.physicalFootprintGrowthKiB | nonnegative_integer)
and (.results.averageCPUPercent | nonnegative_number)
and (.results.p95CPUPercent | nonnegative_number)
and (.results.measurementDurationSeconds | nonnegative_number)
and .results.measurementDurationSeconds >= 86400
and .results.maximumRSSKiB >= .results.baselineRSSKiB
and .results.growthKiB == (.results.maximumRSSKiB - .results.baselineRSSKiB)
and .results.maximumPhysicalFootprintKiB >= .results.baselinePhysicalFootprintKiB
and .results.physicalFootprintGrowthKiB == (.results.maximumPhysicalFootprintKiB - .results.baselinePhysicalFootprintKiB)
and .results.maximumRSSKiB <= .thresholds.rssLimitKiB
and .results.growthKiB <= .thresholds.growthLimitKiB
and .results.averageCPUPercent <= .thresholds.averageCPUPercentLimit
and .results.p95CPUPercent <= .thresholds.p95CPUPercentLimit
