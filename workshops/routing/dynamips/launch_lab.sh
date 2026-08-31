#!/usr/bin/env bash
set -Eeuo pipefail

ROUTING_DIR="${HOME}/virtual_labs/routing"
IMAGE="${HOME}/virtual_labs/images/c7200-advipservicesk9-mz.152-4.S3.image"

cd "$ROUTING_DIR"
"$ROUTING_DIR/start_dynamips.sh"

if [[ ! -f "$IMAGE" ]]; then
    echo
    echo "WARNING: expected IOS image is missing:"
    echo "  $IMAGE"
    echo
fi

exec dynagen topology.net
