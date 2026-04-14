#!/bin/bash
set -e

# Optimized Docker build with layer caching
# Expected speedup: 4-6x for warm builds (cached layers reused)

BUILD_TARGET="${1:-code-server}"
DOCKERFILE=""
TAG=""

case "$BUILD_TARGET" in
  code-server)
    DOCKERFILE="Dockerfile.code-server"
    TAG="code-server-patched:latest"
    ;;
  caddy)
    DOCKERFILE="Dockerfile.caddy"
    TAG="caddy-proxy:latest"
    ;;
  *)
    echo "Usage: $0 <code-server|caddy>"
    exit 1
    ;;
esac

export DOCKER_BUILDKIT=1

echo "[BUILD] Starting $BUILD_TARGET (with layer caching)..."
START=$(date +%s)

docker build \
  --file "$DOCKERFILE" \
  --tag "$TAG" \
  --cache-from "$TAG" \
  --progress=auto \
  .

END=$(date +%s)
DURATION=$((END - START))

echo ""
echo "[BUILD] Completed in ${DURATION}s"
echo "✓ Image: $TAG"
