#!/usr/bin/env bash
# @file        scripts/lib/compression.sh
# @module      lib/compression
# @description HTTP/2 and compression optimization for performance
# @governance  GOV-002: Version-controlled, immutable infrastructure
# Issue #1536: Networking, DNS & Performance — Caching Strategy

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/_common/logging.sh"

# ── Configuration ─────────────────────────────────────────────────────────────

# Compression thresholds
COMPRESSION_MIN_SIZE="${COMPRESSION_MIN_SIZE:-500}"  # Minimum bytes to compress
COMPRESSION_LEVEL="${COMPRESSION_LEVEL:-6}"           # gzip level 1-9 (default 6)
HTTP2_ENABLED="${HTTP2_ENABLED:-true}"                # Enable HTTP/2

# ── Caddy HTTP/2 Configuration ────────────────────────────────────────────────

# Generate Caddy compression block
caddy_compression_config() {
  cat <<'EOF'
# HTTP/2 enabled by default in Caddy v2
# Automatic gzip compression for text-based responses

encode gzip {
    # Minimum size for compression (bytes)
    minimum_length 500

    # Compressible content types
    match {
        header Content-Type application/json*
        header Content-Type application/javascript*
        header Content-Type application/xml*
        header Content-Type text/*
        header Content-Type image/svg+xml*
    }
}

# Brotli compression (optional, for modern browsers)
encode brotli {
    minimum_length 500
    
    match {
        header Content-Type application/json*
        header Content-Type text/*
    }
}
EOF
}

# ── Docker Compose HTTP/2 Setup ───────────────────────────────────────────────

# Configure HTTP/2 in docker-compose.yml
docker_compose_http2_config() {
  cat <<'EOF'
# docker-compose HTTP/2 Configuration

# Caddy service with HTTP/2
  caddy:
    image: caddy:latest
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
    environment:
      - ACME_AGREE=true
      - LOG_LEVEL=info
    networks:
      - backend

# Redis service for caching
  redis:
    image: redis:7-alpine
    command: >
      redis-server
      --maxmemory 2gb
      --maxmemory-policy allkeys-lru
      --appendonly yes
      --appendfsync everysec
    volumes:
      - redis_data:/data
    ports:
      - "6379:6379"
    networks:
      - backend
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

volumes:
  caddy_data:
  caddy_config:
  redis_data:

networks:
  backend:
    driver: bridge
EOF
}

# ── Caddyfile HTTP/2 Configuration ────────────────────────────────────────────

# Full Caddyfile with HTTP/2, compression, and caching headers
generate_http2_caddyfile() {
  local apex_domain="${APEX_DOMAIN:-kushnir.cloud}"
  local ide_domain="ide.${apex_domain}"

  cat <<EOF
# HTTP/2 Reverse Proxy with Compression & Caching
# Caddy v2 Caddyfile

# Main domain with HTTP/2
${apex_domain} {
    # Automatic HTTPS and HTTP/2
    http.max_conns_per_ip_endpoint 100
    
    # Compression
    encode gzip {
        minimum_length 500
        match {
            header Content-Type application/json*
            header Content-Type application/javascript*
            header Content-Type text/*
        }
    }
    
    # Security headers
    header Strict-Transport-Security "max-age=31536000; includeSubDomains"
    header X-Content-Type-Options "nosniff"
    header X-Frame-Options "SAMEORIGIN"
    header X-XSS-Protection "1; mode=block"
    
    # Cache headers
    @cached {
        path_regexp ^/static/
        path_regexp ^/assets/
    }
    
    header @cached Cache-Control "public, max-age=31536000"
    
    @dynamic {
        path_regexp ^/api/
    }
    
    header @dynamic Cache-Control "no-cache, must-revalidate"
    
    # Reverse proxy to backend
    reverse_proxy localhost:3100 {
        # HTTP/2 connection pooling
        policy random_choice 4
        
        # Keep-alive settings
        header_up Connection "Upgrade"
        header_up Upgrade "websocket"
        
        # Timeouts
        timeout 30s
    }
}

# IDE domain
${ide_domain} {
    http.max_conns_per_ip_endpoint 100
    
    encode gzip {
        minimum_length 500
    }
    
    header Strict-Transport-Security "max-age=31536000; includeSubDomains"
    header Cross-Origin-Opener-Policy "same-origin"
    header Cross-Origin-Embedder-Policy "require-corp"
    
    reverse_proxy localhost:8443 {
        policy random_choice 2
        timeout 60s
    }
}
EOF
}

# ── Performance Metrics ───────────────────────────────────────────────────────

# Measure HTTP/2 effectiveness
measure_http2_performance() {
  local url="${1:-https://kushnir.cloud}"
  
  if ! command -v curl &>/dev/null; then
    echo "ERROR: curl not found"
    return 1
  fi

  echo "=== HTTP/2 Performance Metrics ==="
  echo ""
  echo "Testing: ${url}"
  echo ""

  # Get response metrics
  curl -w "
  HTTP Version: %{http_version}
  Protocol:     %{protocol}
  Time to First Byte: %{time_starttransfer}s
  Total Time: %{time_total}s
  Size:       %{size_download} bytes
  Speed:      %{speed_download} bytes/s
  " -o /dev/null -s -L "${url}"

  echo ""
}

# Check gzip compression effectiveness
check_compression() {
  local url="${1:-https://kushnir.cloud/api/health}"

  echo "=== Compression Effectiveness ==="
  echo ""

  if ! command -v curl &>/dev/null; then
    echo "ERROR: curl not found"
    return 1
  fi

  # Size without compression
  local uncompressed_size
  uncompressed_size=$(curl -s -L "${url}" | wc -c)

  # Size with compression
  local compressed_size
  compressed_size=$(curl -s -H "Accept-Encoding: gzip" -L "${url}" | wc -c)

  local ratio=0
  if [ ${uncompressed_size} -gt 0 ]; then
    ratio=$(( (compressed_size * 100) / uncompressed_size ))
  fi

  echo "Original size:     ${uncompressed_size} bytes"
  echo "Compressed size:   ${compressed_size} bytes"
  echo "Compression ratio: ${ratio}%"
  echo ""

  if [ ${ratio} -lt 70 ]; then
    echo "✓ Compression effective (< 70%)"
    return 0
  else
    echo "⚠ Compression has limited effect (> 70%)"
    return 1
  fi
}

# ── Export Functions ───────────────────────────────────────────────────────────

export -f caddy_compression_config
export -f docker_compose_http2_config
export -f generate_http2_caddyfile
export -f measure_http2_performance
export -f check_compression
