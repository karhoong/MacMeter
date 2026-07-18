#!/bin/bash

cpu_percent_from_deltas() {
  local cpu_nanoseconds="$1"
  local wall_nanoseconds="$2"
  awk -v cpu="$cpu_nanoseconds" -v wall="$wall_nanoseconds" '
    BEGIN {
      if (wall <= 0 || cpu < 0) exit 1
      printf "%.3f", 100 * cpu / wall
    }
  '
}

nearest_rank_percentile() {
  local values_file="$1"
  local count="$2"
  local percentile="$3"
  local index
  index=$(((percentile * count + 99) / 100))
  sort -n "$values_file" | sed -n "${index}p"
}
