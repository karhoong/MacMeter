.schemaVersion == 1
and .status == "passed"
and .commit == $commit
and .dirtyWorktree == $dirtyWorktree
and .hardware == $hardware
and .appBinarySHA256 == $appBinarySHA256
and .version == $version
and .build == $build
and .observerScriptSHA256 == $observerScriptSHA256
and .observerToolPath == $observerToolPath
and .observerToolVersion == $observerToolVersion
and .launchMethod == "direct execution of the built app executable; observe its exact child PID"
and .observationConfiguration == {
  enabledMetrics: ["cpu", "temperature", "network", "battery"],
  updateIntervalSeconds: 2
}
and .observation.method == "lsof all Internet sockets for the exact child PID at one-second intervals"
and (.startedAt | type == "string")
and (.finishedAt | type == "string")
and ((.startedAt | fromdateiso8601) as $started
  | (.finishedAt | fromdateiso8601) as $finished
  | $finished >= $started
    and .observation.actualDurationSeconds == ($finished - $started))
and (.observation.requestedDurationSeconds | type == "number")
and (.observation.actualDurationSeconds | type == "number")
and (.observation.sampleIntervalSeconds | type == "number")
and (.observation.samples | type == "number")
and (.observation.networkSocketObservations | type == "number")
and (.observation.listeningSocketObservations | type == "number")
and (.observation.observerErrors | type == "number")
and (.observation.processLivenessFailures | type == "number")
and (.observation.requestedDurationSeconds >= 10)
and (.observation.requestedDurationSeconds == (.observation.requestedDurationSeconds | floor))
and (.observation.sampleIntervalSeconds == 1)
and (.observation.actualDurationSeconds == (.observation.actualDurationSeconds | floor))
and (.observation.samples == (.observation.samples | floor))
and (.observation.actualDurationSeconds >= .observation.requestedDurationSeconds)
and (.observation.samples >= (.observation.requestedDurationSeconds / .observation.sampleIntervalSeconds | floor))
and (.observation.networkSocketObservations == 0)
and (.observation.listeningSocketObservations == 0)
and (.observation.observerErrors == 0)
and (.observation.processLivenessFailures == 0)
and (.observedSocketRecords | type == "array")
and (.observedSocketRecords | length == 0)
and .failureReason == null
