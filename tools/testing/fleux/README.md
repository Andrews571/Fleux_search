# Fleux testing-branch diagnostics (`tools/testing/fleux/`)

Read-only, on-device probes for CPU/battery/EAS/GPU A/B experiments on
`testing/cpu-battery-eas`. None of these scripts write kernel state; output
files are written only to the path you supply/output.

## Usage

    # push to the device (root shell), then:
    sh fleux-state-capture.sh /data/local/tmp/fleux_ab_baseline
    sh fleux-eas-probe.sh
    sh fleux-gpu-dump.sh
    sh fleux-fairness-check.sh 15

Compare snapshots between experiment legs (e.g. baseline vs EAS-on vs
EEVDF candidates).

## Scripts

| Script | What it captures | Use for |
|---|---|---|
| `fleux-state-capture.sh` | CPU topology/capacity, cpufreq policy+gov+`time_in_state`, cpuidle usage/residency, sched sysctls, thermal zones, PPM, wakeup sources, meminfo | reproducible A/B baselines |
| `fleux-eas-probe.sh` | `sched_energy_aware`, perf-domain info, EM state, asymmetric capacity, schedutil | verifying EAS is compiled in **and active** |
| `fleux-gpu-dump.sh` | `/proc/gpufreq*` OPP/var/power dumps, GPU thermal context | GPU DVFS/limit inspection |
| `fleux-fairness-check.sh` | CPU-time ratio of a nice-0 vs nice-10 CPU hog pair | preliminary fairness indicator (NOT proof) |
| `ab_wl.sh` | 4 hogs + 4 timer-wakers for N s; per-CPU busy ticks + per-policy cpufreq avg/max/time-at-max/transitions | A/B legs for EAS / PELT / scheduler changes |

## Known device caveats (audit unit)

- The ROM mounts **`/proc/sys` read-only**, so `sched_*` sysctl tuning cannot be
  applied at runtime by default. A temporary `mount -o remount,rw /proc/sys`
  is needed (revert with `remount,ro` afterward). See the report Appendix A.
- Under memory exhaustion some `sched_*` reads return `ENOMEM`; disable the
  OpenCode/agent harness and other load before measuring.
- PPM `THERMAL`/`PWR_THRO`/`FORCE_LIMIT` clamp the big cluster under sustained
  load, which dominates short A/B legs — measure on a **quiescent, cool** unit.

## Interpreting results

- **EAS**: `sched_energy_aware=1` plus perf-domain lines in
  `/proc/sched_debug` indicate activation. A runtime A/B (write `1`) is the
  intended experiment — do not silently change the kernel default.
- **PELT**: the stock boot cmdline intends `sched_pelt_multiplier=4`; the
  kernel default is `1`. Compare `up_rate_limit_us`/`time_in_state` spreads
  when testing `echo 4 > /proc/sys/kernel/sched_pelt_multiplier`.
- **Caution**: under heavy memory pressure (RAM exhausted, ZRAM swap full)
  some `/proc/sys/kernel/sched_*` reads can return `ENOMEM`. Re-test on a
  quiescent device before trusting a comparison.
- Scheduler decisions come from the report
  `docs/testing/CPU_BATTERY_EEVDF_EAS_REPORT.md`, not from these probes alone.