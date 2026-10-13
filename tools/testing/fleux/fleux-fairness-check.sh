#!/system/bin/sh
# Fleux preliminary scheduler-fairness sanity check (read-only, userspace).
# Runs two identical CPU-bound hogs for WALL seconds, one at nice 0 and one
# at nice 10, then prints the ratio of CPU time consumed.
#
# IMPORTANT: this is a *preliminary* indicator only. Integer BSD nice values
# yield a fixed weight ratio (~1.25x for dl/d0 weighting at nice 10 in CFS
# defaults). Authoritative fairness validation needs sustained contention,
# BPF/tracefs probes and kernel instrumentation. Never treat this script's
# output as proof of EEVDF/CFS correctness.
WALL="${1:-10}"    # seconds
OUT=/data/local/tmp/fleux_fairness_$$
mkdir -p /data/local/tmp

hog() { while :; do :; done; }

( hog & p1=$!; renice 10 -p "$p1" >/dev/null 2>&1;
  hog & p2=$!; sleep "$WALL";
  t1=$(awk '{print $14}' /proc/$p1/stat 2>/dev/null)   # utime ticks
  t2=$(awk '{print $14}' /proc/$p2/stat 2>/dev/null)   # utime ticks
  HZ=$(getconf CLK_TCK 2>/dev/null || echo 100)
  kill "$p1" "$p2" 2>/dev/null
  echo "hog@nice0  cpu_ticks=$t1  cpu_s=$((t1/HZ))"
  echo "hog@nice10 cpu_ticks=$t2  cpu_s=$((t2/HZ))"
  [ "${t1:-0}" -gt 0 ] || t1=1
  echo "ratio nice0/nice10 = $(awk "BEGIN{printf \"%.3f\", $t1/$t2}") (theory ~1.25-1.29)"
  rm -rf "$OUT"
) 2>/dev/null