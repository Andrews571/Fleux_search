#!/system/bin/sh
# Fleux A/B workload harness (read-only except the caller-supplied sysctls).
# Runs 4 CPU-bound hogs + 4 timer-wakeup wakers unpinned for SECONDS, then
# reports per-CPU busy ticks (/proc/stat) and per-policy cpufreq behaviour
# (avg / max / time-at-max / transition proxy) sampled every ~0.5s.
#
# usage: sh ab_wl.sh LABEL SECONDS OUTDIR
#
# NOTE: the harness does not change kernel state. The caller applies/reverts
# the knob under test between legs. On ROMs that mount /proc/sys read-only,
# a temporary `mount -o remount,rw /proc/sys` is required (revert afterward).
set -u
L=$1; D=$2; OUT=$3/${1}
mkdir -p "$3"
awk '/^cpu[0-9]+ /{print $1, $2, $3, $4, $5, $6, $7, $8}' /proc/stat > $OUT.stat0

# 4 CPU-bound hogs + 4 timer-wakeup wakers (no affinity: placement is the probe)
sh -c 'while :; do :; done' & h1=$!
sh -c 'while :; do :; done' & h2=$!
sh -c 'while :; do :; done' & h3=$!
sh -c 'while :; do :; done' & h4=$!
sh -c 'while :; do usleep 700; done' & w1=$!
sh -c 'while :; do usleep 700; done' & w2=$!
sh -c 'while :; do usleep 700; done' & w3=$!
sh -c 'while :; do usleep 700; done' & w4=$!

rm -f $OUT.samples
i=0
while [ $i -lt $((D*2)) ]; do
  T=$(awk '{print $1}' /proc/uptime)
  f0=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq 2>/dev/null)
  f6=$(cat /sys/devices/system/cpu/cpufreq/policy6/scaling_cur_freq 2>/dev/null)
  echo "$T ${f0:-0} ${f6:-0}" >> $OUT.samples
  i=$((i+1)); sleep 0.5
done

kill $h1 $h2 $h3 $h4 $w1 $w2 $w3 $w4 2>/dev/null
sleep 0.3
awk '/^cpu[0-9]+ /{print $1, $2, $3, $4, $5, $6, $7, $8}' /proc/stat > $OUT.stat1

echo "== leg $L (wall $D s) =="
awk 'NR==FNR{a[$1]=$0;next} {split(a[$1],x," ");split($0,y," "); b=(y[2]+y[3]+y[4])-(x[2]+x[3]+x[4]); printf "%s busy_ticks=%d\n",$1,b}' $OUT.stat0 $OUT.stat1

n=0; s0=0; s6=0; mx0=0; mx6=0; sw0=0; sw6=0; pm0=0; pm6=0; prv0=""; prv6=""
while read -r t f0 f6; do
  n=$((n+1))
  s0=$((s0+f0)); s6=$((s6+f6))
  [ "$f0" -gt "$mx0" ] 2>/dev/null && mx0=$f0
  [ "$f6" -gt "$mx6" ] 2>/dev/null && mx6=$f6
  [ "$f0" = "2000000" ] && pm0=$((pm0+1))
  [ "$f6" = "2050000" ] && pm6=$((pm6+1))
  [ -n "$prv0" ] && [ "$f0" != "$prv0" ] && sw0=$((sw0+1))
  [ -n "$prv6" ] && [ "$f6" != "$prv6" ] && sw6=$((sw6+1))
  prv0=$f0; prv6=$f6
done < $OUT.samples
[ "$n" -gt 0 ] || n=1
echo "freq: samples=$n policy0 avg=$((s0/n)) max=$mx0 atmax%=$((100*pm0/n)) switches=$sw0 | policy6 avg=$((s6/n)) max=$mx6 atmax%=$((100*pm6/n)) switches=$sw6"