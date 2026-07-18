.commit == $commit
and .startedAt == $startedAt
and .hardware == $hardware
and .dirtyWorktree == $dirtyWorktree
and (.refresh | type == "object")
and (.cycle | type == "object")
and (.refresh.refreshErrorP95Seconds | type == "number")
and (.refresh.hostPaintP95Seconds | type == "number")
and (.refresh.renderFailures | type == "number")
and (.cycle.errorP95Seconds | type == "number")
and (.refresh.refreshErrorP95Seconds <= 0.2)
and (.refresh.hostPaintP95Seconds < 0.25)
and (.refresh.renderFailures == 0)
and (.cycle.errorP95Seconds <= 0.2)
