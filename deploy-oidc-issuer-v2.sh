#!/bin/bash
cd /home/akushnir/code-server-enterprise || exit 1

# Load configuration
source <(grep -E '^(OAUTH2_PROXY_COOKIE_SECRET|GOOGLE_CLIENT_ID|GOOGLE_CLIENT_SECRET)=' .env)

# Start oauth2-oidc-issuer with proper OIDC configuration
docker run -d \
  --name oauth2-oidc-issuer \
  --restart unless-stopped \
  --user 101 \
  --network net-edge \
  --expose 4182 \
  -e "OAUTH2_PROXY_PROVIDER=oidc" \
  -e "OAUTH2_PROXY_OIDC_ISSUER_URL=https://accounts.google.com" \
  -e "OAUTH2_PROXY_CLIENT_ID=${GOOGLE_CLIENT_ID}" \
  -e "OAUTH2_PROXY_CLIENT_SECRET=${GOOGLE_CLIENT_SECRET}" \
  -e "OAUTH2_PROXY_COOKIE_SECRET=${OAUTH2_PROXY_COOKIE_SECRET}" \
  -e "OAUTH2_PROXY_HTTP_ADDRESS=0.0.0.0:4182" \
  -e "OAUTH2_PROXY_EMAIL_DOMAINS=*" \
  -e "OAUTH2_PROXY_SKIP_AUTH_REGEX=^/.well-known|^/healthz|^/ping" \
  -e "OAUTH2_PROXY_REQUEST_LOGGING=true" \
  -e "OAUTH2_PROXY_AUTHENTICATED_EMAILS_FILE=/etc/oauth2-proxy/allowed-emails.txt" \
  -v /home/akushnir/code-server-enterprise/allowed-emails.txt:/etc/oauth2-proxy/allowed-emails.txt:ro \
  "quay.io/oauth2-proxy/oauth2-proxy:v7.5.1@sha256:e797b3934eb8d7cb2756b67e59be2ef29c18c2b45da763f540ece66d843cec85"

sleep 5
echo "oauth2-oidc-issuer status:"
docker ps | grep oauth2-oidc-issuer || echo "Container failed to start"
docker logs oauth2-oidc-issuer 2>&1 | tail -5
