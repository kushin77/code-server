#!/usr/bin/env bash
# @file        scripts/ops/benchmark-build-cache.sh
# @module      infrastructure/performance
# @description Baseline build cache hit ratio and dependency resolution performance

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

# Configuration
OUTPUT_DIR="artifacts/triage"
REPO_ROOT="${SCRIPT_DIR}/.."

# ─────────────────────────────────────────────────────────────────────────────
# Helper: JSON output
# ─────────────────────────────────────────────────────────────────────────────
json_result() {
  local metric="$1" value="$2" unit="$3"
  echo "{\"metric\": \"$metric\", \"value\": $value, \"unit\": \"$unit\", \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Preflight checks
# ─────────────────────────────────────────────────────────────────────────────
log_info "Running build cache baseline benchmark..."

mkdir -p "$OUTPUT_DIR"
: > "$OUTPUT_DIR/build-cache-baseline.json"

# Check dependencies
if ! command -v pnpm &> /dev/null; then
  log_warn "pnpm not installed. Install via: npm install -g pnpm"
  exit 1
fi

log_info "pnpm version: $(pnpm --version)"

# ─────────────────────────────────────────────────────────────────────────────
# pnpm install cache hit ratio (warm cache)
# ─────────────────────────────────────────────────────────────────────────────
log_info "Testing pnpm install with warm cache..."

cd "$REPO_ROOT"

# First install populates cache
log_info "Running warm install (cache already populated)..."
start_time=$(date +%s.%N)
pnpm install --frozen-lockfile --silent 2>&1 | tee "${OUTPUT_DIR}/pnpm-warm-install.log" || true
end_time=$(date +%s.%N)

warm_install_time=$(echo "scale=2; $end_time - $start_time" | bc)
json_result "pnpm_warm_install_time" "$warm_install_time" "seconds" >> "$OUTPUT_DIR/build-cache-baseline.json"

log_info "pnpm warm install time: ${warm_install_time}s"

# Extract cache hit ratio from pnpm store status
if pnpm store status &>/dev/null; then
  store_info=$(pnpm store status 2>&1 || echo "")
  log_info "pnpm store status:"
  echo "$store_info" | tee -a "${OUTPUT_DIR}/pnpm-store-status.log" || true
fi

# ─────────────────────────────────────────────────────────────────────────────
# pnpm cold cache (remove node_modules and reinstall)
# ─────────────────────────────────────────────────────────────────────────────
log_info "Testing pnpm install with cold cache (rebuilding node_modules)..."

rm -rf "$REPO_ROOT/node_modules"

start_time=$(date +%s.%N)
pnpm install --frozen-lockfile --silent 2>&1 | tee "${OUTPUT_DIR}/pnpm-cold-install.log" || true
end_time=$(date +%s.%N)

cold_install_time=$(echo "scale=2; $end_time - $start_time" | bc)
json_result "pnpm_cold_install_time" "$cold_install_time" "seconds" >> "$OUTPUT_DIR/build-cache-baseline.json"

log_info "pnpm cold install time: ${cold_install_time}s"

# Calculate cache efficiency
cache_speedup=$(echo "scale=2; $cold_install_time / $warm_install_time" | bc)
json_result "pnpm_cache_speedup_factor" "$cache_speedup" "ratio" >> "$OUTPUT_DIR/build-cache-baseline.json"
log_info "Cache speedup factor: ${cache_speedup}x (warm vs cold)"

# ─────────────────────────────────────────────────────────────────────────────
# Workspace build time (TypeScript compilation)
# ─────────────────────────────────────────────────────────────────────────────
log_info "Testing TypeScript build time (warm cache)..."

if [[ -f "$REPO_ROOT/package.json" ]] && grep -q '"build"' "$REPO_ROOT/package.json"; then
  start_time=$(date +%s.%N)
  pnpm run build 2>&1 | tee "${OUTPUT_DIR}/build-warm.log" || true
  end_time=$(date +%s.%N)
  
  build_time=$(echo "scale=2; $end_time - $start_time" | bc)
  json_result "typescript_build_time" "$build_time" "seconds" >> "$OUTPUT_DIR/build-cache-baseline.json"
  
  log_info "TypeScript build time: ${build_time}s"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Docker layer cache efficiency (if Dockerfile exists)
# ─────────────────────────────────────────────────────────────────────────────
if command -v docker &> /dev/null && [[ -f "$REPO_ROOT/Dockerfile.code-server" ]]; then
  log_info "Testing Docker layer cache efficiency..."
  
  if [[ "${DOCKER_BUILDKIT:-0}" == "1" ]] || docker buildx version &>/dev/null; then
    log_info "Building with Docker BuildKit cache..."
    
    # First build (cold cache)
    start_time=$(date +%s.%N)
    docker build -f "$REPO_ROOT/Dockerfile.code-server" \
      --tag "code-server:baseline-cold" \
      --cache-from=type=local,src=/tmp/docker-cache \
      -o type=local,dest=/tmp/docker-cache \
      . 2>&1 | tee "${OUTPUT_DIR}/docker-cold-build.log" || true
    end_time=$(date +%s.%N)
    
    docker_cold_time=$(echo "scale=2; $end_time - $start_time" | bc)
    json_result "docker_cold_build_time" "$docker_cold_time" "seconds" >> "$OUTPUT_DIR/build-cache-baseline.json"
    
    # Second build (warm cache)
    start_time=$(date +%s.%N)
    docker build -f "$REPO_ROOT/Dockerfile.code-server" \
      --tag "code-server:baseline-warm" \
      --cache-from=type=local,src=/tmp/docker-cache \
      -o type=local,dest=/tmp/docker-cache \
      . 2>&1 | tee "${OUTPUT_DIR}/docker-warm-build.log" || true
    end_time=$(date +%s.%N)
    
    docker_warm_time=$(echo "scale=2; $end_time - $start_time" | bc)
    json_result "docker_warm_build_time" "$docker_warm_time" "seconds" >> "$OUTPUT_DIR/build-cache-baseline.json"
    
    log_info "Docker cold build: ${docker_cold_time}s, warm build: ${docker_warm_time}s"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Disk usage analysis
# ─────────────────────────────────────────────────────────────────────────────
log_info "Analyzing cache and build artifact disk usage..."

node_modules_size=$(du -sh "$REPO_ROOT/node_modules" 2>/dev/null | cut -f1 || echo "unknown")
pnpm_store_size=$(pnpm store status 2>&1 | grep -i "size" | head -1 || echo "unknown")

log_info "node_modules size: $node_modules_size"
log_info "pnpm store size: $pnpm_store_size"

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
log_info "✅ Build cache baseline benchmark complete"
log_info "Results saved to: $OUTPUT_DIR/build-cache-baseline.json"

if command -v jq &> /dev/null; then
  jq -s . "$OUTPUT_DIR/build-cache-baseline.json" > "${OUTPUT_DIR}/build-cache-baseline.formatted.json" 2>/dev/null || true
  log_info "Formatted results: ${OUTPUT_DIR}/build-cache-baseline.formatted.json"
fi

log_info ""
log_info "Comparison against targets:"
log_info "  - pnpm warm install: target ≤60s (${warm_install_time}s measured)"
log_info "  - pnpm cache speedup: target ≥2.0x (${cache_speedup}x measured)"
log_info "  - TypeScript build: target ≤60s"
log_info "  - Docker warm build: target ≤2x faster than cold"
