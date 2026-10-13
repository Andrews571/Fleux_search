#!/system/bin/sh
# Fleux read-only state capture for CPU/battery/EAS A/B experiments.
# Usage: sh fleux-state-capture.sh [output_dir]
# Writes one dated snapshot text file. Never modifies kernel state.
OUT="${1:-/data/local/tmp/fleux_snapshots}"
mkdir -p "$OUT" || exit 1
S="$OUT/snapshot_$(date +%Y%m%d_%H%M%S).txt"
{
echo "== Fleux state snapshot $(date) =="
echo "kernel: $(uname -r 2>/dev/null)"
cat /proc/loadavg 2>/dev/null; echo

echo "== CPU topology / capacity =="
for c in /sys/devices/system/cpu/cpu[0-9]*; do
  [ -d "$c" ] || continue
  cpuid="${c##*/}"
  echo -n "$cpuid: online=$(cat $c/online 2>/dev/null) cap="
  cat "$c/cpu_capacity" 2>/dev/null || echo -n "n/a"
  echo -n " freq_cur="; cat "$c/cpufreq/scaling_cur_freq" 2>/dev/null || echo -n "n/a"
  echo
done

echo "== cpufreq policies =="
for p in /sys/devices/system/cpu/cpufreq/policy*; do
  [ -d "$p" ] || continue
  echo "-- ${p##*/} --"
  echo -n "governor="; cat "$p/scaling_governor" 2>/dev/null
  echo -n "driver="; cat "$p/scaling_driver" 2>/dev/null
  echo -n "min/max="; echo -n "$(cat "$p/scaling_min_freq" 2>/dev/null)/$(cat "$p/scaling_max_freq" 2>/dev/null)"
  echo -n " cur="; cat "$p/scaling_cur_freq" 2>/dev/null
  echo -n " schedutil rates: up="; cat "$p/schedutil/up_rate_limit_us" 2>/dev/null
  echo -n " down="; cat "$p/schedutil/down_rate_limit_us" 2>/dev/null
  echo
  [ -f "$p/stats/time_in_state" ] && grep -v "^$" "$p/stats/time_in_state" 2>/dev/null | head -20
done

echo "== cpuidle =="
for s in /sys/devices/system/cpu/cpuidle/*/; do
  name=$(cat "$s/name" 2>/dev/null); lat=$(cat "$s/latency" 2>/dev/null)
  res=$(cat "$s/residency" 2>/dev/null); usage=$(cat "$s/usage" 2>/dev/null)
  time_ns=$(cat "$s/time" 2>/dev/null)
  echo "${s##*/}: name=$name latency=${lat}us residency=${res}us usage=$usage time_ns=$time_ns"
done

echo "== scheduler sysctls =="
for s in sched_energy_aware sched_sync_hint_enable sched_cstate_aware \
         sched_pelt_multiplier sched_migration_cost_ns sched_util_clamp_min \
         sched_util_clamp_max sched_child_runs_first sched_schedstats; do
  echo -n "$s="; cat "/proc/sys/kernel/$s" 2>/dev/null || echo -n "unreadable(EAGAIN?)$?"
  echo
done

echo "== thermal =="
for t in /sys/class/thermal/thermal_zone*/; do
  [ -d "$t" ] || continue
  echo -n "${t##*/}: type=$(cat "$t/type" 2>/dev/null) temp=$(cat "$t/temp" 2>/dev/null)"
  [ -f "$t/sustainable_power" ] && echo -n " spw=$(cat "$t/sustainable_power" 2>/dev/null)"
  echo
done

echo "== PPM =="
echo -n "enabled="; cat /proc/ppm/enabled 2>/dev/null
echo
cat /proc/ppm/profile 2>/dev/null | head -4
for c in /proc/ppm/dump_cluster_0_dvfs_table /proc/ppm/dump_cluster_1_dvfs_table; do
  echo "-- $c --"; head -4 "$c" 2>/dev/null
done

echo "== suspend/wakeup =="
echo -n "state="; cat /sys/power/state 2>/dev/null; echo
echo -n "wakeup_count="; cat /sys/power/wakeup_count 2>/dev/null; echo
for w in /sys/class/wakeup/wakeup*/; do
  [ -d "$w" ] || continue
  echo -n "${w##*/}: $(cat "$w/name" 2>/dev/null) active_count=$(cat "$w/active_count" 2>/dev/null) "
  echo -n "event_count=$(cat "$w/event_count" 2>/dev/null) "
  echo -n "wakeup_count=$(cat "$w/wakeup_count" 2>/dev/null)"
  echo
done

echo "== memory =="
grep -E "MemFree|MemAvailable|SwapTotal|SwapFree|Shmem|Slab:" /proc/meminfo 2>/dev/null | head

echo "== end snapshot =="
} > "$S" 2>/dev/null
echo "wrote $S"