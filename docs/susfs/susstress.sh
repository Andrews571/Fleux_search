#!/system/bin/sh
# SUSFS 4.19 read-hooks stress harness (fixed).
# Run as root in the ksu domain.  Usage: sh susstress.sh [seconds]
DUR=${1:-150}
KS=/data/adb/ksu/bin/ksu_susfs
LOG=/data/local/tmp/susstress.log
K=/data/local/tmp/ktest
SD=/data/local/tmp/susdir

echo "=== SUSSTRESS START $(date) ===" > $LOG
echo "duration=${DUR}s" >> $LOG
echo "kernel=$(uname -r)" >> $LOG
echo "uid=$(id)" >> $LOG
echo "workers=6" >> $LOG

# --- give the hooks something to act on ---
[ -e "$K" ] || echo 123456 > $K
[ -d "$SD" ] || mkdir -p $SD
mkdir -p $SD/sub 2>/dev/null
echo hello > $SD/sub/f1 2>/dev/null

# --- enable runtime logging so any read path shows up in dmesg ---
echo "--- SUSFS setup ---" >> $LOG
$KS enable_log 1 >>$LOG 2>&1
$KS add_sus_kstat "$K" >>$LOG 2>&1
$KS update_sus_kstat "$K" >>$LOG 2>&1
$KS add_sus_path "$SD" >>$LOG 2>&1

# --- reader workers (root / ksu domain) ---
echo "--- Starting 6 root readers ---" >> $LOG
i=0
while [ $i -lt 6 ]; do
  (
    end=$(( $(date +%s) + DUR ))
    while [ $(date +%s) -lt $end ]; do
      stat -c '%d %i %s %n' $K $SD $SD/sub/f1 >/dev/null 2>&1
      stat -f $SD >/dev/null 2>&1
      ls -la $SD >/dev/null 2>&1
      cat /proc/self/mountinfo >/dev/null 2>&1
      cat /proc/self/maps >/dev/null 2>&1
      ls -la /proc/self/fd >/dev/null 2>&1
      cat /proc/self/fdinfo/0 >/dev/null 2>&1
    done
  ) &
  i=$((i+1))
done

# --- app-uid reader (exercises app-uid gated SUS_KSTAT) ---
END=$(( $(date +%s) + DUR ))
su 10000 -c '
  while [ $(date +%s) -lt '"$END"' ]; do
    stat /data/local/tmp/ktest >/dev/null 2>&1
    stat -f /data/local/tmp >/dev/null 2>&1
    cat /proc/self/mountinfo >/dev/null 2>&1
    cat /proc/self/maps >/dev/null 2>&1
  done
' >>$LOG 2>&1 &
echo "app-uid reader launched (until $END)" >> $LOG

# --- concurrent list churn (writer vs reader race) ---
(
  end=$(( $(date +%s) + DUR ))
  while [ $(date +%s) -lt $end ]; do
    $KS update_sus_kstat $K >/dev/null 2>&1
    $KS update_sus_kstat_full_clone $K >/dev/null 2>&1
    $KS add_sus_path_loop $SD/sub >/dev/null 2>&1
    sleep 0.2
  done
) &

# --- app-launch loop to generate zygote/umounted traffic ---
(
  end=$(( $(date +%s) + DUR ))
  while [ $(date +%s) -lt $end ]; do
    monkey -p com.android.settings -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
    am start -a android.intent.action.VIEW -d file:///storage/emulated/0/ >/dev/null 2>&1
    sleep 3
  done
) &

wait
$KS enable_log 0 >>$LOG 2>&1
echo "=== SUSSTRESS DONE $(date) ===" >> $LOG
echo "--- dmesg tail ---" >> $LOG
dmesg 2>/dev/null | tail -8 >> $LOG
echo "SUSSTRESS_DONE"
