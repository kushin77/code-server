#!/bin/bash
# @file        terraform/modules/keepalived/build/entrypoint.sh
# @module      keepalived/container
# @description Writes keepalived.conf from KEEPALIVED_CONF env var and starts daemon
#
set -euo pipefail

CONFIG_FILE="/etc/keepalived/keepalived.conf"

# Write config from env var
if [ -z "${KEEPALIVED_CONF:-}" ]; then
    echo "[entrypoint] ERROR: KEEPALIVED_CONF env var is required" >&2
    exit 1
fi

printf '%s\n' "$KEEPALIVED_CONF" > "$CONFIG_FILE"
chmod 640 "$CONFIG_FILE"

echo "[entrypoint] keepalived.conf written ($(wc -c < "$CONFIG_FILE") bytes)"

# Exec keepalived in foreground
exec /usr/sbin/keepalived -n -D -l -G -f "$CONFIG_FILE"
