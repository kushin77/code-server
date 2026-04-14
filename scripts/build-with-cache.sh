#!/bin/bash
set -e

# Build with maximum Docker cache utilization
# Expected speedup: 4-6x for warm builds (cached layers)

BUILD_TARGET= 
REGISTRY=
BUILDKIT_PROGRESS=

export DOCKER_BUILDKIT=1
export BUILDKIT_PROGRESS=

echo \[] Building with cache optimization...\

case \\ in
  code-server)
    DOCKERFILE=\Dockerfile.code-server\
    TAG=\code-server-patched:latest\
    ;;
  caddy)
    DOCKERFILE=\Dockerfile.caddy\
    TAG=\caddy-proxy:latest\
    ;;
  *)
    echo \Unknown build target: \
    exit 1
    ;;
esac

START=

# Build with cache from previous images
docker build \\
  --file \\ \\
  --tag \\ \\
  --cache-from \\ \\
  --progress=\\ \\
  .

END=
DURATION=

echo \\
echo \[] Build completed in s\
echo \✓ ready\
