#!/usr/bin/env bash
# @file        fix-ssl.sh
# @module      operations/ssl-maintenance
# @description SSL certificate and Caddy SSL configuration recovery
# @owner       Infrastructure Team
# @status      ACTIVE
#
set -e

# Stop Caddy
echo "Stopping Caddy..."
docker stop caddy || true
sleep 2

# Find Caddy volume mount point
echo "Finding Caddy volume..."
MOUNT_POINT=$(docker volume inspect caddy_data | grep Mountpoint | awk -F'"' '{print $4}')
echo "Caddy volume mount: $MOUNT_POINT"

# Create directory if needed
mkdir -p "$MOUNT_POINT"

# Create self-signed certificate
echo "Creating self-signed certificate..."
openssl req -x509 -newkey rsa:4096 -keyout "${MOUNT_POINT}/caddy_key.pem" -out "${MOUNT_POINT}/caddy_cert.pem" -days 365 -nodes -subj "/CN=*.kushnir.cloud"

echo "Certificate created:"
ls -la "$MOUNT_POINT"/*.pem

# Restart Caddy
echo "Starting Caddy..."
docker start caddy
sleep 30

echo "Testing HTTPS..."
curl -k -I https://192.168.168.31 2>&1 | head -15
