#!/system/bin/sh
# Fleux GPU DVFS probe (read-only). Dumps OPP table, load, limit indices,
# voltage and thermal context from the MediaTek gpufreq proc interface.
echo "== gpufreq nodes =="
ls /proc/ | grep -i "gpufreq" | sed 's/^/  /'
echo
for f in gpufreq_opp_dump gpufreq_var_dump gpufreq_power_dump \
         gpufreq_opp_volt_dump; do
  echo "-- $f --"
  cat "/proc/$f" 2>/dev/null | head -8
  echo
done

echo "== GPU temperature context =="
for t in /sys/class/thermal/thermal_zone*/; do
  [ -d "$t" ] || continue
  type=$(cat "$t/type" 2>/dev/null)
  case "$type" in
    *gpu*|*tscpu*|*ap*)
      echo "${t##*/} $type: $(cat "$t/temp" 2>/dev/null) (x1000 mC if >1000)"
      ;;
  esac
done

echo "== interpretation =="
echo "g_max_upper_limited_idx=0  -> maximum OPP allowed by limits/thermal (0=top freq)"
echo "g_min_lower_limited_idx=N  -> minimum OPP floor (N=highest index = lowest freq)"
echo "Compare g_limiter entries / gpu_loading before and after any change."
echo "Rule: no OC/voltage change without hardware-backed PLL/POSDIV/voltage data."