#!/bin/bash
set -e

echo "Generating 16-byte hex cookie secret..."
NEW_SECRET=$(openssl rand -hex 16)
echo "Generated: $NEW_SECRET"

echo "Updating .env..."
sed -i "s/OAUTH2_PROXY_COOKIE_SECRET=.*/OAUTH2_PROXY_COOKIE_SECRET=$NEW_SECRET/" ~/code-server-enterprise/.env

echo "Updated value:"
grep OAUTH2_PROXY_COOKIE_SECRET ~/code-server-enterprise/.env

echo "Restarting oauth2-proxy..."
cd ~/code-server-enterprise
docker restart oauth2-proxy

echo "Waiting 5 seconds..."
sleep 5

echo "Status:"
docker ps -f 'name=oauth2-proxy' --format 'table {{.Names}}\t{{.Status}}'

echo "Caddy status:"
docker ps -f 'name=caddy' --format 'table {{.Names}}\t{{.Status}}'

if docker ps -f 'name=caddy' --format '{{.Names}}' | grep -q caddy; then
  echo "Testing HTTP..."
  curl -s -o /dev/null -w 'Port 80: %{http_code}\n' http://localhost/ || echo "No response yet"
fi
