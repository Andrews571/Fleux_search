#!/system/bin/sh
# Fleux EAS activation probe (read-only).
# Verifies whether Energy-Aware Scheduling is compiled in and active,
# without changing any kernel state.
echo "== EAS compile state =="
echo -n "sched_energy_aware="; cat /proc/sys/kernel/sched_energy_aware 2>/dev/null || echo -n "(unreadable)"
echo

echo "== perf-domain / EAS info in sched_debug (if readable) =="
grep -iE "perf_domain|energy_aware|sched_energy" /proc/sched_debug 2>/dev/null | head -10
echo

echo "== Energy Model sysfs/debugfs (when mounted) =="
for d in /sys/kernel/debug/energy_model /sys/devices/system/cpu/energy_model; do
  if [ -d "$d" ]; then
    echo "-- $d --"
    find "$d" -maxdepth 2 -type f -exec sh -c 'echo "== $1"; cat "$1" 2>/dev/null' _ {} \; 2>/dev/null | head -60
  fi
done

echo "== EM registration evidence in kernel logs (best-effort) =="
dmesg 2>/dev/null | grep -iE "energy model|perf domain" | tail -5
echo

echo "== asymmetric capacity (EAS prerequisite) =="
for c in /sys/devices/system/cpu/cpu[0-9]*/cpu_capacity; do
  [ -f "$c" ] || continue
  echo -n "$(basename $(dirname $c))="
  cat "$c" 2>/dev/null
done
echo

echo "== schedutil governor present (EAS prerequisite) =="
for p in /sys/devices/system/cpu/cpufreq/policy*/scaling_governor; do
  [ -f "$p" ] || continue
  echo -n "$(basename $(dirname $p)): "; cat "$p" 2>/dev/null
done

echo "== interpretation =="
ea=$(cat /proc/sys/kernel/sched_energy_aware 2>/dev/null)
if [ "$ea" = "1" ]; then
  echo "EAS sysctl = 1 (requested active). Check perf-domain lines above for activation."
else
  echo "EAS sysctl = $ea (inactive). To A/B test on-device: echo 1 > /proc/sys/kernel/sched_energy_aware"
  echo "and re-run. Revert with echo 0. This is a runtime test, not a kernel change."
fi