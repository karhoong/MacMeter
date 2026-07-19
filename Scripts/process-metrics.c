#include <errno.h>
#include <libproc.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s <pid>\n", argv[0]);
        return 64;
    }

    char *end = NULL;
    errno = 0;
    long raw_pid = strtol(argv[1], &end, 10);
    if (errno != 0 || end == argv[1] || *end != '\0' || raw_pid <= 0) {
        fprintf(stderr, "invalid pid: %s\n", argv[1]);
        return 64;
    }

    struct rusage_info_v4 usage = {0};
    if (proc_pid_rusage((int)raw_pid, RUSAGE_INFO_V4, (rusage_info_t *)&usage) != 0) {
        perror("proc_pid_rusage");
        return 1;
    }

    struct timespec monotonic = {0};
    if (clock_gettime(CLOCK_MONOTONIC, &monotonic) != 0) {
        perror("clock_gettime");
        return 1;
    }

    uint64_t cpu_nanoseconds = usage.ri_user_time + usage.ri_system_time;
    uint64_t wall_nanoseconds =
        ((uint64_t)monotonic.tv_sec * UINT64_C(1000000000)) + (uint64_t)monotonic.tv_nsec;
    uint64_t physical_footprint_kib = usage.ri_phys_footprint / UINT64_C(1024);
    printf("%llu,%llu,%llu\n", (unsigned long long)cpu_nanoseconds,
           (unsigned long long)wall_nanoseconds,
           (unsigned long long)physical_footprint_kib);
    return 0;
}
