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

# Ensure the base router configuration directory exists. The installer copies
# dynamips/configs/ recursively into ~/virtual_labs/routing/configs/.
if [[ ! -d "${ROUTING_DIR}/configs" ]]; then
    echo
    echo "ERROR: router base configuration directory is missing:"
    echo "  ${ROUTING_DIR}/configs"
    echo
    echo "Re-run the workshop installer from the cloned GitHub repository."
    exit 1
fi

missing_configs=0
for i in $(seq 1 14); do
    if [[ ! -f "${ROUTING_DIR}/configs/R${i}.cfg" ]]; then
        echo "ERROR: missing ${ROUTING_DIR}/configs/R${i}.cfg" >&2
        missing_configs=1
    fi
done

if [[ "$missing_configs" -ne 0 ]]; then
    echo
    echo "One or more router base configuration files are missing."
    exit 1
fi

# Avoid starting a second Dynagen instance if the named screen session exists.
if screen -list | grep -q "[.]${SCREEN_NAME}[[:space:]]"; then
    echo
    echo "Dynagen screen session '${SCREEN_NAME}' is already running."
    echo "Attach with:"
    echo "  screen -r ${SCREEN_NAME}"
    exit 0
fi

echo
echo "Starting Dynagen in detached screen session '${SCREEN_NAME}'."

screen -dmS "$SCREEN_NAME" \
    bash -lc "cd '$ROUTING_DIR' && exec dynagen topology.net"

sleep 2

if screen -list | grep -q "[.]${SCREEN_NAME}[[:space:]]"; then
    echo
    echo "Dynagen is running in screen session '${SCREEN_NAME}'."
    echo
    echo "Attach with:"
    echo "  screen -r ${SCREEN_NAME}"
    echo
    echo "At the Dynagen prompt run:"
    echo "  start /all"
else
    echo
    echo "ERROR: Dynagen did not remain running."
    echo "Run manually for troubleshooting:"
    echo "  cd '$ROUTING_DIR'"
    echo "  dynagen topology.net"
    exit 1
fi
