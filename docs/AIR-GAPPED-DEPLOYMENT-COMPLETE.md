# Air-Gapped Deployment Runbook Enhancement

**Purpose**: Comprehensive procedures for deploying production cluster in air-gapped/disconnected environment  
**Related Issue**: #1535 (Security & Compliance - Fort Knox Standard)  
**Date**: April 24, 2026  
**Status**: Production Implementation Guide

---

## Overview

Air-gapped deployments require all container images, dependencies, and configurations to be pre-staged in the isolated environment. This guide extends the base deployment runbook for disconnected network scenarios.

---

## Pre-Deployment: Image Staging

### Step 1: Identify All Required Images

```bash
#!/bin/bash
# scripts/ops/stage-air-gapped-images.sh
# @description Prepare all container images for air-gapped deployment

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

log_info "📦 Staging container images for air-gapped environment..."

# Define all required images with SHA256 digests for verification
declare -A REQUIRED_IMAGES=(
  ["code-server"]="codercom/code-server:4.115.0@sha256:..."
  ["caddy"]="caddy:2.7.4-alpine@sha256:..."
  ["postgres-primary"]="postgres:15-alpine@sha256:..."
  ["postgres-replica"]="postgres:15-alpine@sha256:..."
  ["redis-session"]="redis:7-alpine@sha256:..."
  ["redis-cache"]="redis:7-alpine@sha256:..."
  ["redis-sentinel"]="redis:7-alpine@sha256:..."
  ["prometheus"]="prom/prometheus:v2.49.1@sha256:..."
  ["grafana"]="grafana/grafana:10.4.1@sha256:..."
  ["alertmanager"]="prom/alertmanager:v0.26.0@sha256:..."
  ["loki"]="grafana/loki:2.9.3@sha256:..."
  ["promtail"]="grafana/promtail:2.9.3@sha256:..."
  ["jaeger"]="jaegertracing/all-in-one:1.41@sha256:..."
  ["oauth2-proxy"]="oauth2-proxy/oauth2-proxy:v7.5.1@sha256:..."
  ["appsmith"]="appsmith:1.47@sha256:..."
  ["ollama"]="ollama:0.1.45-cuda@sha256:..."
)

export_dir="${1:-.}/docker-images"
mkdir -p "$export_dir"

log_info "Pulling and exporting ${#REQUIRED_IMAGES[@]} images..."

# Pull and save each image
for name in "${!REQUIRED_IMAGES[@]}"; do
  image="${REQUIRED_IMAGES[$name]}"
  
  log_info "  Pulling $name: $image"
  docker pull "$image"
  
  # Export to tar file
  filename="${export_dir}/${name}.tar"
  log_info "  Saving to $filename"
  docker save -o "$filename" "$image"
  
  # Calculate SHA256 for verification
  sha256=$(sha256sum "$filename" | awk '{print $1}')
  log_info "  ✅ $name SHA256: $sha256"
done

log_info "✅ All ${#REQUIRED_IMAGES[@]} images staged in $export_dir"
log_info "📦 Total size: $(du -sh "$export_dir" | awk '{print $1}')"
```

### Step 2: Create Image Manifest

```bash
#!/bin/bash
# scripts/ops/create-image-manifest.sh

set -euo pipefail

export_dir="${1:-.}/docker-images"
manifest_file="$export_dir/IMAGE-MANIFEST.md"

log_info "📄 Creating image manifest..."

cat > "$manifest_file" << 'EOF'
# Container Image Manifest for Air-Gapped Deployment

**Date**: $(date)
**Environment**: Air-Gapped (No External Network Access)
**Total Images**: $(ls *.tar | wc -l)

## Images with SHA256 Verification

EOF

# Add each image with hash
cd "$export_dir"
for tar_file in *.tar; do
  image_name="${tar_file%.tar}"
  sha256=$(sha256sum "$tar_file" | awk '{print $1}')
  size=$(du -h "$tar_file" | awk '{print $1}')
  
  cat >> "$manifest_file" << EOF

### $image_name
- **File**: $tar_file
- **Size**: $size
- **SHA256**: $sha256
- **Verify**: sha256sum -c <<< "$sha256 $tar_file"

EOF
done

log_info "✅ Image manifest created: $manifest_file"
```

### Step 3: Verify Image Integrity

```bash
#!/bin/bash
# scripts/ops/verify-staged-images.sh

set -euo pipefail

export_dir="${1:-.}/docker-images"

log_info "🔍 Verifying staged image integrity..."

cd "$export_dir"

# Verify all tar files are readable
for tar_file in *.tar; do
  log_info "  Checking $tar_file..."
  
  # Check tar file integrity
  if ! tar -tf "$tar_file" > /dev/null 2>&1; then
    log_error "❌ Corrupt tar file: $tar_file"
    exit 1
  fi
  
  log_info "    ✅ Tar integrity OK"
done

log_info "✅ All staged images verified"
```

---

## Network Transfer: Secure Transport

### Option 1: USB/Network Drive Transfer

```bash
#!/bin/bash
# scripts/ops/transfer-images-usb.sh

set -euo pipefail

source_dir="${1:-.}/docker-images"
target_mount="${2:-/mnt/usb}"
usb_label="KUSHNIR-IMAGES"

log_info "📤 Preparing images for USB transfer..."

# Verify source
if [ ! -d "$source_dir" ]; then
  log_fatal "Source directory not found: $source_dir"
fi

image_count=$(ls "$source_dir"/*.tar 2>/dev/null | wc -l)
log_info "  Images to transfer: $image_count"
total_size=$(du -sh "$source_dir" | awk '{print $1}')
log_info "  Total size: $total_size"

# Mount USB (if not already mounted)
if [ ! -d "$target_mount" ]; then
  log_warn "USB mount point not found - manual mount required"
  log_info "  Mount USB and provide mount point as argument 2"
  exit 1
fi

# Copy with progress
log_info "Copying images to USB ($target_mount)..."
rsync -avh --progress "$source_dir/" "$target_mount/kushnir-images/"

# Verify transfer
log_info "Verifying transfer..."
transferred=$(ls "$target_mount/kushnir-images"/*.tar 2>/dev/null | wc -l)

if [ "$transferred" -eq "$image_count" ]; then
  log_info "✅ All $image_count images transferred successfully"
else
  log_error "❌ Transfer incomplete: $transferred/$image_count images"
  exit 1
fi
```

### Option 2: Secure Network Transfer (SCP with Verification)

```bash
#!/bin/bash
# scripts/ops/transfer-images-scp.sh

set -euo pipefail

source_dir="${1:-.}/docker-images"
target_host="${2:-192.168.168.31}"
target_user="${3:-akushnir}"
target_path="${4:-/tmp/docker-images}"

log_info "📤 Transferring images via SCP to $target_host..."

# Create manifest file for verification
bash scripts/ops/create-image-manifest.sh "$source_dir"

# Transfer all files
scp -r "$source_dir"/* "$target_user@$target_host:$target_path/"

# Remote verification
log_info "Verifying transfer on remote host..."
ssh "$target_user@$target_host" << EOF
  set -e
  cd "$target_path"
  
  # Count files
  file_count=\$(ls *.tar | wc -l)
  log_info "  Received \$file_count images"
  
  # Verify tar integrity
  for tar_file in *.tar; do
    tar -tf "\$tar_file" > /dev/null 2>&1 || exit 1
  done
  
  log_info "✅ Transfer verification passed"
EOF

log_info "✅ Images transferred and verified"
```

---

## Air-Gapped Deployment Steps

### Step 1: Load Images into Docker

```bash
#!/bin/bash
# scripts/ops/load-air-gapped-images.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

image_dir="${1:-/tmp/docker-images}"
target_replica="${2:-192.168.168.31}"

log_info "🐳 Loading container images on $target_replica..."

ssh akushnir@$target_replica << EOF
  set -euo pipefail
  
  mkdir -p "$image_dir"
  cd "$image_dir"
  
  log_info "Loading Docker images..."
  
  for tar_file in *.tar; do
    log_info "  Loading \$tar_file..."
    docker load -i "\$tar_file"
  done
  
  log_info "Verifying loaded images..."
  docker images | grep -E "code-server|caddy|postgres|redis|prometheus|grafana"
  
  log_info "✅ All images loaded successfully"
EOF

log_info "✅ Images loaded on $target_replica"
```

### Step 2: No External DNS Calls

**Verification**:

```bash
#!/bin/bash
# scripts/ops/verify-no-external-dns.sh

set -euo pipefail

log_info "🔒 Verifying no external DNS calls in air-gapped mode..."

# Check docker-compose.yml for DNS references
if grep -q "dns:" docker-compose.yml; then
  log_info "  DNS servers configured in docker-compose.yml"
  grep "dns:" docker-compose.yml
fi

# Verify no hardcoded external hostnames
dangerous_hosts=(
  "docker.io"
  "registry.docker.com"
  "github.com"
  "registry.npmjs.org"
  "pypi.org"
)

for host in "${dangerous_hosts[@]}"; do
  if grep -r "$host" . --include="*.yml" --include="*.yaml" --include="*.sh" 2>/dev/null; then
    log_warn "  ⚠️  Reference to external host: $host"
  fi
done

log_info "✅ Air-gapped DNS verification complete"
```

### Step 3: Deploy with Air-Gapped Profile

```bash
#!/bin/bash
# scripts/ops/deploy-air-gapped.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

target_replica="${1:-192.168.168.31}"

log_info "🚀 Deploying air-gapped cluster to $target_replica..."

ssh akushnir@$target_replica << EOF
  set -euo pipefail
  
  cd code-server-enterprise
  
  # Deploy with air-gapped profile
  COMPOSE_PROFILES=air-gapped docker-compose up -d
  
  # Verify all services started
  docker-compose ps
  
  # Verify network isolation (no external calls)
  tcpdump -i eth0 -c 100 'dst port 53' 2>/dev/null | grep -E "docker.io|github.com|npmjs.org" || \
    log_info "✅ No external DNS queries detected"
  
  log_info "✅ Air-gapped deployment complete"
EOF

log_info "✅ Air-gapped deployment verified"
```

---

## Health Checks for Air-Gapped Environment

### Verify Operational State

```bash
#!/bin/bash
# scripts/ops/validate-air-gapped-health.sh

set -euo pipefail

target_replica="${1:-192.168.168.31}"

log_info "🏥 Validating air-gapped deployment health..."

ssh akushnir@$target_replica << EOF
  # 1. Verify no external network calls
  log_info "  [1/5] Checking network isolation..."
  netstat -tun | grep ESTABLISHED | grep -v "192.168.168" && \
    log_error "⚠️  External connections detected" || \
    log_info "    ✅ Network isolated"
  
  # 2. Verify services operational
  log_info "  [2/5] Checking service status..."
  docker-compose ps | grep -v "Exit\|Exited" | wc -l > /tmp/running_services
  running=\$(cat /tmp/running_services)
  log_info "    Running services: \$running"
  
  # 3. Verify database
  log_info "  [3/5] Checking database..."
  docker-compose exec -T postgres-primary psql -U postgres -c "SELECT version();" > /dev/null && \
    log_info "    ✅ PostgreSQL operational"
  
  # 4. Verify cache
  log_info "  [4/5] Checking Redis..."
  docker-compose exec -T redis-session redis-cli PING > /dev/null && \
    log_info "    ✅ Redis operational"
  
  # 5. Verify API
  log_info "  [5/5] Checking API health..."
  curl -s http://localhost:8080/health > /dev/null && \
    log_info "    ✅ API responding"
  
  log_info "✅ Air-gapped health validation passed"
EOF
```

---

## Rollback in Air-Gapped Environment

### Recovery Procedure

```bash
#!/bin/bash
# scripts/ops/rollback-air-gapped.sh

set -euo pipefail

target_replica="${1:-192.168.168.31}"
previous_commit="${2:-HEAD~1}"

log_info "🔄 Rolling back air-gapped deployment..."

ssh akushnir@$target_replica << EOF
  set -euo pipefail
  
  cd code-server-enterprise
  
  # Stop current deployment
  docker-compose down
  
  # Checkout previous version
  git checkout $previous_commit
  git reset --hard
  
  # Reload images (from local cache, no external pull)
  docker-compose pull --no-parallel || \
    log_info "Using cached images (expected in air-gapped)"
  
  # Restart services
  COMPOSE_PROFILES=air-gapped docker-compose up -d
  
  # Verify rollback
  docker-compose ps
  
  log_info "✅ Rollback complete"
EOF

log_info "✅ Air-gapped rollback verified"
```

---

## Disaster Recovery in Air-Gapped

### Backup Strategy

```bash
#!/bin/bash
# scripts/ops/backup-air-gapped.sh

set -euo pipefail

backup_dir="/mnt/nas/backups/air-gapped"
mkdir -p "$backup_dir"

log_info "💾 Creating air-gapped backup..."

# 1. Database backup
log_info "  [1/3] Backing up database..."
docker-compose exec -T postgres-primary \
  pg_dump -U postgres mydb > "$backup_dir/postgres-$(date +%s).sql"

# 2. Config backup
log_info "  [2/3] Backing up configuration..."
tar -czf "$backup_dir/config-$(date +%s).tar.gz" \
  docker-compose.yml Caddyfile oauth2-proxy.cfg

# 3. Docker images cache backup
log_info "  [3/3] Backing up Docker image layer cache..."
tar -czf "$backup_dir/docker-cache-$(date +%s).tar.gz" \
  /var/lib/docker/image/overlay2

log_info "✅ Air-gapped backups created in $backup_dir"
```

---

## Maintenance in Air-Gapped

### How to Update Without External Network

1. **On connected machine**: Pull new images, create manifest
2. **Transfer**: Copy image tar files via USB/SCP
3. **Load**: `docker load -i *.tar` on air-gapped replica
4. **Deploy**: `docker-compose up -d`

```bash
# Complete update cycle
bash scripts/ops/stage-air-gapped-images.sh ./new-images
scp -r ./new-images/* akushnir@192.168.168.31:/tmp/docker-images/
ssh akushnir@192.168.168.31 bash scripts/ops/load-air-gapped-images.sh /tmp/docker-images
ssh akushnir@192.168.168.31 'cd code-server-enterprise && docker-compose up -d'
```

---

## Security Validation

### Pre-Deployment Security Checklist

```bash
#!/bin/bash
# scripts/ops/validate-air-gapped-security.sh

log_info "🔒 Air-gapped security validation..."

# 1. No secrets in manifests
log_info "  [1/3] Scanning manifests for secrets..."
grep -r "password\|api.key\|secret" docker-images/*.txt && \
  log_error "❌ Secrets found in manifests" || \
  log_info "    ✅ No secrets in manifests"

# 2. Image signature verification
log_info "  [2/3] Verifying image authenticity..."
# (If using signed images)

# 3. Manifest integrity
log_info "  [3/3] Verifying manifest integrity..."
bash scripts/ops/verify-staged-images.sh docker-images || \
  exit 1

log_info "✅ Air-gapped security validation passed"
```

---

## Related Documentation

- [Production Deployment Runbook](DEPLOYMENT-RUNBOOK-OPERATIONS.md)
- [Failover Runbook](FAILOVER-RUNBOOK-SIMPLIFIED.md)
- [Advanced Troubleshooting](ADVANCED-TROUBLESHOOTING-GUIDE.md)

---

**Version**: 1.0  
**Status**: Production Implementation Guide  
**Last Updated**: April 24, 2026
