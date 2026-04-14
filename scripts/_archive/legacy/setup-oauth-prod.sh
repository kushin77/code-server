#!/bin/bash
set -e
cd /home/akushnir/code-server-enterprise

echo "=== Fetching secrets from GSM ==="
CLIENT_ID=$(gcloud secrets versions access latest --secret=prod-portal-google-oauth-client-id --project=nexusshield-prod)
CLIENT_SECRET=$(gcloud secrets versions access latest --secret=prod-portal-google-oauth-client-secret --project=nexusshield-prod)
COOKIE_SECRET=$(gcloud secrets versions access latest --secret=prod-portal-oauth2-cookie-secret --project=nexusshield-prod)

echo "=== Writing .env ==="
cat > .env <<ENVEOF
DOMAIN=ide.kushnir.cloud
GOOGLE_CLIENT_ID=${CLIENT_ID}
GOOGLE_CLIENT_SECRET=${CLIENT_SECRET}
OAUTH2_PROXY_COOKIE_SECRET=${COOKIE_SECRET}
CODE_SERVER_PASSWORD=admin123
ENVEOF
chmod 600 .env
echo ".env written with $(wc -l < .env) lines"

echo "=== Removing stale oauth2-proxy container ==="
docker stop oauth2-proxy 2>/dev/null || true
docker rm oauth2-proxy 2>/dev/null || true

echo "=== Starting oauth2-proxy via docker-compose ==="
docker-compose --env-file .env up -d oauth2-proxy

echo "=== Switching Caddyfile to oauth2-proxy routing ==="
cat > /home/akushnir/code-server-enterprise/Caddyfile << 'CADDYEOF'
{
    auto_https off
    log default {
        format json
    }
}

:80 {
    encode gzip

    header {
        X-Content-Type-Options nosniff
        X-Frame-Options SAMEORIGIN
        Referrer-Policy strict-origin-when-cross-origin
        -Server
    }

    # OAUTH MODE — routed through oauth2-proxy for authentication
    reverse_proxy oauth2-proxy:4180 {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
    }

    log {
        output stdout
        format json
    }
}
CADDYEOF
sleep 3
docker restart caddy

echo "=== Waiting 12s for oauth2-proxy to start ==="
sleep 12

echo "=== Status ==="
docker ps --filter name=oauth2-proxy --format "table {{.Names}}\t{{.Status}}"
docker logs oauth2-proxy --tail 15 2>&1

echo ""
echo "=== Quick smoke test ==="
curl -s -o /dev/null -w "oauth2-proxy /ping: HTTP %{http_code}\n" http://localhost:4180/ping 2>/dev/null || docker exec caddy curl -s -o /dev/null -w "caddy->oauth2-proxy: HTTP %{http_code}\n" http://oauth2-proxy:4180/ping
