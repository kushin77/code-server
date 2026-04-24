#!/usr/bin/env bash
# @file        scripts/ops/preflight-air-gap-images.sh
# @module      operations/deployment
# @description Pre-download all Docker images to NAS for air-gapped deployment
# @owner       devops
# @status      production-ready
#
# Usage: PREFLIGHT_NAS_PATH=/mnt/nas bash preflight-air-gap-images.sh
# After running, configure docker on air-gapped hosts to use local image registry

source "$SCRIPT_DIR/_common/init.sh"

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

PREFLIGHT_NAS_PATH="${PREFLIGHT_NAS_PATH:-/mnt/nas/air-gap-images}"
PREFLIGHT_REGISTRY="${PREFLIGHT_REGISTRY:-docker.io}"
PREFLIGHT_BATCH_SIZE="${PREFLIGHT_BATCH_SIZE:-4}"  # Parallel downloads

# All container images required for KC stack
declare -a IMAGES=(
  # Databases
  "postgres:16"
  "redis:7"
  
  # Core Services
  "caddy:2.7.6-alpine"
  "code-server:latest"
  
  # AI & Models
  "ollama/ollama:latest"
  
  # Observability
  "grafana/grafana:latest"
  "prom/prometheus:latest"
  "grafana/loki:2.9.3"
  
  # Policy & Security
  "openpolicyagent/opa:latest"
  
  # Utilities
  "curlimages/curl:latest"
  "alpine:latest"
)

# ─────────────────────────────────────────────────────────────────────────────
# Preflight Checks
# ─────────────────────────────────────────────────────────────────────────────

log_info "Air-Gapped Image Preflight - Starting download cycle"
log_info "NAS Path: $PREFLIGHT_NAS_PATH"
log_info "Registry: $PREFLIGHT_REGISTRY"
log_info "Images to download: ${#IMAGES[@]}"

# Verify NAS path exists or create it
if ! mkdir -p "$PREFLIGHT_NAS_PATH"; then
  log_fatal "Cannot create NAS path: $PREFLIGHT_NAS_PATH"
fi

# Verify Docker is running
if ! command -v docker &> /dev/null; then
  log_fatal "docker not found - required for image pulling"
fi

if ! docker info &> /dev/null; then
  log_fatal "Docker daemon not responding"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Download Images in Parallel Batches
# ─────────────────────────────────────────────────────────────────────────────

log_info "Pulling ${#IMAGES[@]} images (${PREFLIGHT_BATCH_SIZE} in parallel)..."

DOWNLOAD_FAILURES=0
DOWNLOAD_SUCCESS=0

# Download and save each image
for i in "${!IMAGES[@]}"; do
  image="${IMAGES[$i]}"
  batch_position=$((i % PREFLIGHT_BATCH_SIZE))
  
  # Normalize image name for filesystem
  image_safe="${image//\//_}"
  image_safe="${image_safe//:/_}"
  image_file="${PREFLIGHT_NAS_PATH}/${image_safe}.tar.gz"
  
  (
    if [ -f "$image_file" ]; then
      log_info "[${i}/$((${#IMAGES[@]} - 1))] $image already cached"
      exit 0
    fi
    
    log_info "[${i}/$((${#IMAGES[@]} - 1))] Pulling $image..."
    
    if ! docker pull "$image" &> /dev/null; then
      log_error "[${i}/$((${#IMAGES[@]} - 1))] Failed to pull $image"
      exit 1
    fi
    
    log_info "[${i}/$((${#IMAGES[@]} - 1))] Saving $image to $image_file..."
    
    if ! docker save "$image" | gzip > "$image_file"; then
      log_error "[${i}/$((${#IMAGES[@]} - 1))] Failed to save $image"
      exit 1
    fi
    
    log_info "[${i}/$((${#IMAGES[@]} - 1))] ✅ $image ($(du -h "$image_file" | cut -f1))"
    
  ) &
  
  # Wait if we've spawned PREFLIGHT_BATCH_SIZE parallel jobs
  if [ $((batch_position + 1)) -eq $PREFLIGHT_BATCH_SIZE ]; then
    wait
  fi
done

# Wait for remaining jobs
wait

# ─────────────────────────────────────────────────────────────────────────────
# Verification & Summary
# ─────────────────────────────────────────────────────────────────────────────

log_info "Image download complete"

# Count downloaded images
DOWNLOADED=$(find "$PREFLIGHT_NAS_PATH" -name "*.tar.gz" | wc -l)
TOTAL_SIZE=$(du -sh "$PREFLIGHT_NAS_PATH" | cut -f1)

log_info "Images cached: $DOWNLOADED / ${#IMAGES[@]}"
log_info "Total size: $TOTAL_SIZE"
log_info "Location: $PREFLIGHT_NAS_PATH"

# ─────────────────────────────────────────────────────────────────────────────
# Generate Load Script for Air-Gapped Hosts
# ─────────────────────────────────────────────────────────────────────────────

LOAD_SCRIPT="${PREFLIGHT_NAS_PATH}/load-images.sh"
cat > "$LOAD_SCRIPT" << 'LOAD_SCRIPT_EOF'
#!/usr/bin/env bash
# Load pre-downloaded images into Docker on air-gapped host
set -euo pipefail

IMAGES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log_info() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1" >&2; }
log_error() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2; }

log_info "Loading images from $IMAGES_DIR..."

for image_file in "$IMAGES_DIR"/*.tar.gz; do
  if [ -f "$image_file" ]; then
    log_info "Loading $(basename "$image_file")..."
    if ! gzip -dc "$image_file" | docker load; then
      log_error "Failed to load $(basename "$image_file")"
      exit 1
    fi
  fi
done

log_info "All images loaded successfully"
docker images | head -10
LOAD_SCRIPT_EOF

chmod +x "$LOAD_SCRIPT"

log_info "Generated load script: $LOAD_SCRIPT"
log_info "To load on air-gapped host: bash $LOAD_SCRIPT"

# ─────────────────────────────────────────────────────────────────────────────
# Output Summary
# ─────────────────────────────────────────────────────────────────────────────

cat << EOF

╔════════════════════════════════════════════════════════════════════════╗
║           Air-Gapped Image Preflight Complete                         ║
╠════════════════════════════════════════════════════════════════════════╣
║ Images Downloaded: $DOWNLOADED / ${#IMAGES[@]}
║ Total Size:        $TOTAL_SIZE
║ Location:          $PREFLIGHT_NAS_PATH
║ Load Script:       $LOAD_SCRIPT
╠════════════════════════════════════════════════════════════════════════╣
║ NEXT STEPS FOR AIR-GAPPED DEPLOYMENT:
║
║ 1. On each air-gapped host (192.168.1.31, 192.168.1.42):
║    a) Mount NAS:
║       mount -t nfs $PREFLIGHT_NAS_PATH /opt/images
║    b) Load images:
║       bash /opt/images/load-images.sh
║
║ 2. Verify images loaded:
║    docker images | wc -l  # Should show $DOWNLOADED images
║
║ 3. Deploy using Terraform:
║    terraform apply -var="deployment_mode=air-gapped"
║
║ 4. Run health check:
║    bash scripts/verify-drop-deployment.sh
║
╚════════════════════════════════════════════════════════════════════════╝

EOF

log_info "Air-gap preflight complete ✅"
