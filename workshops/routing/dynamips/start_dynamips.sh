#!/usr/bin/env bash
set -Eeuo pipefail

ROUTING_DIR="${HOME}/virtual_labs/routing"
STATE_DIR="${HOME}/.local/state/routing-workshop"

mkdir -p "$STATE_DIR"
cd "$ROUTING_DIR"

start_one() {
    local port="$1"
    local pidfile="$STATE_DIR/dynamips-${port}.pid"
    local logfile="$STATE_DIR/dynamips-${port}.log"

    if [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
        echo "Dynamips hypervisor $port already running as PID $(cat "$pidfile")."
        return 0
    fi

    nohup /usr/local/bin/dynamips -H "127.0.0.1:${port}" >"$logfile" 2>&1 &
    echo $! >"$pidfile"

    for _ in {1..20}; do
        if ss -ltn | awk '{print $4}' | grep -qE "(127\.0\.0\.1|\[::1\]):${port}$"; then
            echo "Dynamips hypervisor $port started."
            return 0
        fi
        sleep 0.25
    done

    echo "Dynamips hypervisor $port did not become ready. See $logfile" >&2
    return 1
}

start_one 7200
start_one 7201
