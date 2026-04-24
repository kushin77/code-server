#!/usr/bin/env bash
# @file        deploy-oidc-issuer.sh
# @module      deployment/oidc-issuer
# @description OIDC issuer service deployment - oauth2-proxy configuration
# @owner       Infrastructure Team
# @status      ACTIVE
#
cd /home/akushnir/code-server-enterprise

# Start oauth2-oidc-issuer
docker run -d \
  --name oauth2-oidc-issuer \
  --restart unless-stopped \
  --user 101 \
  --network net-edge \
  --expose 4182 \
  -e "OAUTH2_PROXY_PROVIDER=oidc" \
  -e "OAUTH2_PROXY_OIDC_ISSUER_URL=https://ide.kushnir.cloud" \
  -e "OAUTH2_PROXY_HTTP_ADDRESS=0.0.0.0:4182" \
  -e "OAUTH2_PROXY_SKIP_AUTH_REGEX=^/.well-known|^/healthz|^/ping" \
  -e "OAUTH2_PROXY_REQUEST_LOGGING=true" \
  "quay.io/oauth2-proxy/oauth2-proxy:v7.5.1@sha256:e797b3934eb8d7cb2756b67e59be2ef29c18c2b45da763f540ece66d843cec85"

sleep 3
echo "oauth2-oidc-issuer status:"
docker ps | grep oauth2-oidc-issuer
