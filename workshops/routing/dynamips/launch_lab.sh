#!/usr/bin/env bash

set -Eeuo pipefail

ROUTING_DIR="${HOME}/virtual_labs/routing"
IMAGE="${HOME}/virtual_labs/images/c7200-advipservicesk9-mz.152-4.S3.image"
SCREEN_NAME="routing"

cd "$ROUTING_DIR"

"$ROUTING_DIR/start_dynamips.sh"

if [[ ! -f "$IMAGE" ]]; then
    echo
    echo "WARNING: expected IOS image is missing:"
    echo "  $IMAGE"
    echo
fi

if screen -list | grep -q "[.]${SCREEN_NAME}[[:space:]]"; then
    echo "A screen session named '${SCREEN_NAME}' is already running."
    echo
    echo "Attach with:"
    echo "  screen -r ${SCREEN_NAME}"
    exit 0
fi

echo "Starting Dynagen inside screen session '${SCREEN_NAME}'..."

screen -dmS "$SCREEN_NAME" bash -lc "cd '$ROUTING_DIR' && exec dynagen topology.net"

sleep 2

if screen -list | grep -q "[.]${SCREEN_NAME}[[:space:]]"; then
    echo
    echo "Dynagen started successfully."
    echo
    echo "Attach with:"
    echo "  screen -r ${SCREEN_NAME}"
    echo
    echo "Then at the Dynagen prompt run:"
    echo "  start /all"
else
    echo
    echo "ERROR: Dynagen screen session did not remain running."
    echo "Run this manually to investigate:"
    echo "  cd '$ROUTING_DIR'"
    echo "  dynagen topology.net"
    exit 1
fi
