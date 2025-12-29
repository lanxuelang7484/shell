#!/bin/sh
# cpu_25_percent.sh - POSIX compliant

set -eu

TARGET=25
HYSTERESIS=5
INTERVAL=5
LOG="/var/log/cpu_stabilizer.log"
PID_FILE="/tmp/load_pids.txt"

LOW=$((TARGET - HYSTERESIS))
HIGH=$((TARGET + HYSTERESIS))

log() {
    echo "[$(date)] $*" | tee -a "$LOG"
}

get_cpu_usage() {
    awk '/^cpu / {
        total = $2+$3+$4+$5+$6+$7+$8+$9
        idle = $5+$6
        print total, idle
        exit
    }' /proc/stat
}

calc_cpu() {
    set -- $(get_cpu_usage)
    t1_total=$1; t1_idle=$2
    sleep 1
    set -- $(get_cpu_usage)
    t2_total=$1; t2_idle=$2

    diff_idle=$((t2_idle - t1_idle))
    diff_total=$((t2_total - t1_total))
    if [ "$diff_total" -eq 0 ]; then
        echo 0
        return
    fi
    echo $(( (diff_total - diff_idle) * 100 / diff_total ))
}

stop_load() {
    if [ -f "$PID_FILE" ]; then
        while IFS= read -r pid; do
            kill "$pid" 2>/dev/null && wait "$pid" 2>/dev/null || true
        done < "$PID_FILE"
        rm -f "$PID_FILE"
    fi
}

start_load() {
    cores=$(nproc)
    need=$(( TARGET * cores / 100 ))
    [ "$need" -lt 1 ] && need=1
    [ "$need" -gt "$cores" ] && need="$cores"

    stop_load
    log "启动 $need 个负载进程"

    i=0
    while [ "$i" -lt "$need" ]; do
        ( while :; do :; done ) &
        echo $! >> "$PID_FILE"
        i=$((i + 1))
    done
}

ACTIVE=0
log "启动 CPU 稳定器（迟滞控制）"

trap 'stop_load; exit' INT TERM

while :; do
    current=$(calc_cpu)
    log "CPU: ${current}%"

    if [ "$ACTIVE" -eq 0 ]; then
        if [ "$current" -lt "$LOW" ]; then
            start_load
            ACTIVE=1
        fi
    else
        if [ "$current" -gt "$HIGH" ]; then
            stop_load
            ACTIVE=0
        fi
    fi

    sleep "$INTERVAL"
done
