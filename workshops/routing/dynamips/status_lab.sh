#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE="${HOME}/virtual_labs/images/c7200-advipservicesk9-mz.152-4.S3.image"

echo "Dynamips:"
/usr/local/bin/dynamips --version 2>&1 | head -n1 || true
echo

echo "Hypervisors:"
for port in 7200 7201; do
    if ss -ltn | awk '{print $4}' | grep -qE "(127\.0\.0\.1|\[::1\]):${port}$"; then
        echo "  $port: listening"
    else
        echo "  $port: stopped"
    fi
done
echo

echo "Expected IOS image:"
if [[ -f "$IMAGE" ]]; then
    echo "  FOUND: $IMAGE"
else
    echo "  MISSING: $IMAGE"
fi
echo

echo "Router console ports currently listening:"
ss -ltn | awk 'NR == 1 || $4 ~ /:(200[1-9]|201[0-4])$/' || true
