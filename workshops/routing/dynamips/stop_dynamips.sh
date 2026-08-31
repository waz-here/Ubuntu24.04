#!/usr/bin/env bash
set -Eeuo pipefail

STATE_DIR="${HOME}/.local/state/routing-workshop"

for port in 7200 7201; do
    pidfile="$STATE_DIR/dynamips-${port}.pid"
    if [[ -f "$pidfile" ]]; then
        pid="$(cat "$pidfile")"
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            echo "Stopped Dynamips hypervisor $port (PID $pid)."
        fi
        rm -f "$pidfile"
    else
        echo "No PID file for Dynamips hypervisor $port."
    fi
done
