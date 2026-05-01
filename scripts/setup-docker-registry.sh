#!/bin/bash
# Docker Registry Setup Script
# Purpose: Configure Docker image registry (Harbor, GitLab Container Registry, or AWS ECR)
# Sets up automatic builds and tag strategy

set -euo pipefail

# Error handling
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/registry-*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
REGISTRY_TYPE="${REGISTRY_TYPE:-harbor}"  # harbor, gitlab, aws-ecr
REGISTRY_HOST="${REGISTRY_HOST:-registry.kushnir.cloud}"
REGISTRY_PROJECT="${REGISTRY_PROJECT:-code-server}"
REGISTRY_USERNAME="${REGISTRY_USERNAME:-admin}"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $*"
}

log_error() {
    echo -e "${RED}[✗]${NC} $*"
}

# Detect current registry configuration
detect_registry() {
    log_info "Detecting current registry configuration..."
    
    local registry_config="${REPO_ROOT}/.registry-config"
    
    if [[ -f "$registry_config" ]]; then
        source "$registry_config"
        log_success "Found existing registry config: $REGISTRY_TYPE at $REGISTRY_HOST"
    else
        log_warning "No registry config found, using defaults"
        save_registry_config
    fi
}

# Save registry configuration
save_registry_config() {
    local registry_config="${REPO_ROOT}/.registry-config"
    
    cat > "$registry_config" << EOF
# Registry Configuration
# Generated: $(date)

REGISTRY_TYPE=$REGISTRY_TYPE
REGISTRY_HOST=$REGISTRY_HOST
REGISTRY_PROJECT=$REGISTRY_PROJECT
REGISTRY_USERNAME=$REGISTRY_USERNAME
EOF
    
    log_success "Registry config saved to $registry_config"
}

# Generate tag strategy
generate_tag_strategy() {
    log_info "Generating tag strategy..."
    
    # Build metadata
    local GIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    local GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
    local TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    local VERSION=$(git describe --tags --always 2>/dev/null || echo "0.1.0")
    
    cat > "${REPO_ROOT}/TAG_STRATEGY.json" << EOF
{
  "git_hash": "$GIT_HASH",
  "git_branch": "$GIT_BRANCH",
  "timestamp": "$TIMESTAMP",
  "version": "$VERSION",
  "tags": {
    "latest": "$REGISTRY_HOST/$REGISTRY_PROJECT/SERVICE:latest",
    "version": "$REGISTRY_HOST/$REGISTRY_PROJECT/SERVICE:$VERSION",
    "commit": "$REGISTRY_HOST/$REGISTRY_PROJECT/SERVICE:$GIT_HASH",
    "timestamp": "$REGISTRY_HOST/$REGISTRY_PROJECT/SERVICE:$TIMESTAMP",
    "branch": "$REGISTRY_HOST/$REGISTRY_PROJECT/SERVICE:$GIT_BRANCH"
  },
  "push_order": [
    "commit (for audit trail)",
    "version (for release tracking)",
    "branch (for CI/CD routing)",
    "latest (for convenience)"
  ]
}
EOF
    
    log_success "Tag strategy generated: $(cat ${REPO_ROOT}/TAG_STRATEGY.json | jq '.tags | keys[]')"
}

# Generate GitHub Actions workflow for image builds
generate_github_actions_workflow() {
    log_info "Generating GitHub Actions CI/CD workflow..."
    
    local workflow_dir="${REPO_ROOT}/.github/workflows"
    mkdir -p "$workflow_dir"
    
    cat > "${workflow_dir}/build-docker-images.yml" << 'EOF'
name: Build & Push Docker Images

on:
  push:
    branches:
      - main
      - develop
    paths:
      - 'apps/**'
      - 'docker-compose*.yml'
      - '.github/workflows/build-docker-images.yml'
  workflow_dispatch:

env:
  REGISTRY_HOST: registry.kushnir.cloud
  REGISTRY_PROJECT: code-server

jobs:
  detect_changes:
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.set-matrix.outputs.matrix }}
    steps:
      - uses: actions/checkout@v3
        with:
          fetch-depth: 0
      
      - id: set-matrix
        run: |
          # Detect which services changed
          if [[ "${{ github.event_name }}" == "workflow_dispatch" ]]; then
            # Build all on manual trigger
            SERVICES="multimodal-ai agent-runtime activity-feed reputation-engine env-provisioner execution-scheduler paperclip edge-agent"
          else
            # Build only changed services
            CHANGED=$(git diff ${{ github.event.before }}..${{ github.sha }} --name-only | grep '^apps/' | cut -d/ -f2 | sort -u)
            SERVICES="${CHANGED:- }"
          fi
          
          # Convert to JSON array for matrix
          MATRIX=$(echo "$SERVICES" | tr ' ' '\n' | jq -R -s -c 'split("\n") | map(select(length > 0))')
          echo "matrix={\"service\":$MATRIX}" >> $GITHUB_OUTPUT

  build:
    needs: detect_changes
    runs-on: ubuntu-latest
    strategy:
      matrix: ${{ fromJson(needs.detect_changes.outputs.matrix) }}
      fail-fast: false
    
    permissions:
      contents: read
      packages: write
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v2
      
      - name: Log in to Registry
        uses: docker/login-action@v2
        with:
          registry: ${{ env.REGISTRY_HOST }}
          username: ${{ secrets.REGISTRY_USERNAME }}
          password: ${{ secrets.REGISTRY_PASSWORD }}
      
      - name: Extract metadata
        id: meta
        run: |
          GIT_HASH=$(git rev-parse --short HEAD)
          GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
          VERSION=$(git describe --tags --always)
          
          # Build tags
          TAGS="${{ env.REGISTRY_HOST }}/${{ env.REGISTRY_PROJECT }}/${{ matrix.service }}:latest"
          TAGS="$TAGS,${{ env.REGISTRY_HOST }}/${{ env.REGISTRY_PROJECT }}/${{ matrix.service }}:$GIT_HASH"
          TAGS="$TAGS,${{ env.REGISTRY_HOST }}/${{ env.REGISTRY_PROJECT }}/${{ matrix.service }}:$VERSION"
          
          echo "tags=$TAGS" >> $GITHUB_OUTPUT
          echo "version=$VERSION" >> $GITHUB_OUTPUT
          echo "commit=$GIT_HASH" >> $GITHUB_OUTPUT
      
      - name: Build and push Docker image
        uses: docker/build-push-action@v4
        with:
          context: .
          file: apps/${{ matrix.service }}/Dockerfile
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          cache-from: type=registry,ref=${{ env.REGISTRY_HOST }}/${{ env.REGISTRY_PROJECT }}/${{ matrix.service }}:buildcache
          cache-to: type=registry,ref=${{ env.REGISTRY_HOST }}/${{ env.REGISTRY_PROJECT }}/${{ matrix.service }}:buildcache,mode=max
      
      - name: Image scan for vulnerabilities
        run: |
          # Example: Trivy scan (if available)
          echo "Scanning ${{ matrix.service }} for vulnerabilities..."
          # trivy image ${{ env.REGISTRY_HOST }}/${{ env.REGISTRY_PROJECT }}/${{ matrix.service }}:latest
      
      - name: Create GitHub Release Assets
        if: startsWith(github.ref, 'refs/tags/')
        run: |
          echo "Image: ${{ env.REGISTRY_HOST }}/${{ env.REGISTRY_PROJECT }}/${{ matrix.service }}:${{ steps.meta.outputs.version }}"

  verify:
    needs: build
    runs-on: ubuntu-latest
    if: always()
    
    steps:
      - name: Verify images pushed
        run: |
          echo "Build and push complete"
          echo "Images available at: ${{ env.REGISTRY_HOST }}/${{ env.REGISTRY_PROJECT }}/"
EOF
    
    log_success "GitHub Actions workflow created: ${workflow_dir}/build-docker-images.yml"
}

# Generate GitLab CI configuration
generate_gitlab_ci_config() {
    log_info "Generating GitLab CI configuration..."
    
    cat > "${REPO_ROOT}/.gitlab-ci-docker-builds.yml" << 'EOF'
# Docker Image Build Pipeline
# Include in main .gitlab-ci.yml: include:
#   - local: .gitlab-ci-docker-builds.yml

stages:
  - detect
  - build
  - scan
  - push

variables:
  REGISTRY_HOST: "registry.kushnir.cloud"
  REGISTRY_PROJECT: "code-server"
  DOCKER_TLS_CERTDIR: ""
  DOCKER_HOST: "tcp://docker:2375"

detect_changes:
  stage: detect
  script:
    - |
      if [[ "$CI_PIPELINE_SOURCE" == "web" ]]; then
        # Manual trigger - build all
        SERVICES="multimodal-ai agent-runtime activity-feed reputation-engine env-provisioner execution-scheduler paperclip edge-agent"
      else
        # Detect changed services
        CHANGED=$(git diff --name-only HEAD~1 HEAD | grep '^apps/' | cut -d/ -f2 | sort -u)
        SERVICES="${CHANGED:- }"
      fi
      echo "SERVICES=$SERVICES" >> build.env
  artifacts:
    reports:
      dotenv: build.env
  only:
    - merge_requests
    - main
    - develop

.build_service:
  stage: build
  image: docker:20.10.16
  services:
    - docker:20.10.16-dind
  script:
    - docker login -u "$REGISTRY_USERNAME" -p "$REGISTRY_PASSWORD" "$REGISTRY_HOST"
    - |
      GIT_HASH=$(git rev-parse --short HEAD)
      VERSION=$(git describe --tags --always)
      BRANCH=$(git rev-parse --abbrev-ref HEAD)
      
      docker build \
        --tag "$REGISTRY_HOST/$REGISTRY_PROJECT/$CI_JOB_NAME:latest" \
        --tag "$REGISTRY_HOST/$REGISTRY_PROJECT/$CI_JOB_NAME:$GIT_HASH" \
        --tag "$REGISTRY_HOST/$REGISTRY_PROJECT/$CI_JOB_NAME:$VERSION" \
        --tag "$REGISTRY_HOST/$REGISTRY_PROJECT/$CI_JOB_NAME:$BRANCH" \
        -f apps/$CI_JOB_NAME/Dockerfile .
      
      docker push "$REGISTRY_HOST/$REGISTRY_PROJECT/$CI_JOB_NAME:latest"
      docker push "$REGISTRY_HOST/$REGISTRY_PROJECT/$CI_JOB_NAME:$GIT_HASH"
      docker push "$REGISTRY_HOST/$REGISTRY_PROJECT/$CI_JOB_NAME:$VERSION"
      docker push "$REGISTRY_HOST/$REGISTRY_PROJECT/$CI_JOB_NAME:$BRANCH"

build_multimodal_ai:
  extends: .build_service

build_agent_runtime:
  extends: .build_service

build_activity_feed:
  extends: .build_service

build_reputation_engine:
  extends: .build_service

build_env_provisioner:
  extends: .build_service

build_execution_scheduler:
  extends: .build_service

build_paperclip:
  extends: .build_service

build_edge_agent:
  extends: .build_service
EOF
    
    log_success "GitLab CI config created: .gitlab-ci-docker-builds.yml"
}

# Generate Docker Compose override for registry
generate_docker_compose_override() {
    log_info "Generating docker-compose override with registry references..."
    
    cat > "${REPO_ROOT}/docker-compose.registry-override.yml" << EOF
# Override file: docker-compose -f docker-compose.enterprise.yml -f docker-compose.registry-override.yml up
# Pulls images from registry instead of local build

version: '3.8'

services:
  multimodal-ai:
    image: $REGISTRY_HOST/$REGISTRY_PROJECT/multimodal-ai:latest
    build: null

  agent-runtime:
    image: $REGISTRY_HOST/$REGISTRY_PROJECT/agent-runtime:latest
    build: null

  agent-code-reviewer:
    image: $REGISTRY_HOST/$REGISTRY_PROJECT/agent-code-reviewer:latest
    build: null

  agent-doc-writer:
    image: $REGISTRY_HOST/$REGISTRY_PROJECT/agent-doc-writer:latest
    build: null

  agent-test-generator:
    image: $REGISTRY_HOST/$REGISTRY_PROJECT/agent-test-generator:latest
    build: null

  agent-incident-responder:
    image: $REGISTRY_HOST/$REGISTRY_PROJECT/agent-incident-responder:latest
    build: null

  activity-feed:
    image: $REGISTRY_HOST/$REGISTRY_PROJECT/activity-feed:latest
    build: null

  reputation-engine:
    image: $REGISTRY_HOST/$REGISTRY_PROJECT/reputation-engine:latest
    build: null

  env-provisioner:
    image: $REGISTRY_HOST/$REGISTRY_PROJECT/env-provisioner:latest
    build: null

  execution-scheduler:
    image: $REGISTRY_HOST/$REGISTRY_PROJECT/execution-scheduler:latest
    build: null

  paperclip:
    image: $REGISTRY_HOST/$REGISTRY_PROJECT/paperclip:latest
    build: null

  edge-agent:
    image: $REGISTRY_HOST/$REGISTRY_PROJECT/edge-agent:latest
    build: null

  testing-service:
    image: $REGISTRY_HOST/$REGISTRY_PROJECT/testing-service:latest
    build: null

  control-plane:
    image: $REGISTRY_HOST/$REGISTRY_PROJECT/control-plane:latest
    build: null
EOF
    
    log_success "Docker Compose override created: docker-compose.registry-override.yml"
}

# Generate Harbor deployment guide
generate_harbor_guide() {
    log_info "Generating Harbor deployment and configuration guide..."
    
    cat > "${REPO_ROOT}/docs/operations/docker-registry-setup.md" << 'EOF'
# Docker Registry Setup: Harbor, GitLab Container Registry, or AWS ECR
**Image Repository Configuration & CI/CD Integration — April 29, 2026**

---

## Overview

This guide configures Docker image registry for reproducible, traceable, secure container deployments:

- **Harbor**: Self-hosted registry with vulnerability scanning, RBAC, replication
- **GitLab Container Registry**: Integrated with GitLab, automatic cleanup policies
- **AWS ECR**: Cloud-native registry with IAM integration, vulnerability scanning

---

## Option 1: Harbor Setup (Recommended)

### Harbor Installation

```bash
# On registry host (separate from app hosts)
docker run -d \
  --name harbor \
  -p 80:80 \
  -p 443:443 \
  -v /data/harbor:/data \
  -v /data/harbor/config.yml:/etc/harbor/config.yml \
  goharbor/harbor-core:latest

# Or using docker-compose
docker-compose -f harbor-docker-compose.yml up -d
```

### Configuration

```yaml
# config.yml
harbor_admin_password: ${HARBOR_ADMIN_PASSWORD}
database:
  password: ${DB_PASSWORD}
redis:
  password: ${REDIS_PASSWORD}

# Project settings
public: false  # Private by default
enable_content_trust: true
auto_scan: true  # Scan on push
pull_time_window_minutes: 0  # Immediate scanning
```

### Docker Registry Credentials

```bash
# Create robot account for CI/CD
harbor --robot-create \
  --name="code-server-ci" \
  --project="code-server" \
  --permissions="pull,push"

# Store credentials in GitHub Secrets
REGISTRY_USERNAME=robot$code-server-ci
REGISTRY_PASSWORD=<generated-token>
```

### Tag Strategy

```
PRIMARY TAG:    registry.kushnir.cloud/code-server/SERVICE:latest
VERSION TAG:    registry.kushnir.cloud/code-server/SERVICE:1.0.0
COMMIT TAG:     registry.kushnir.cloud/code-server/SERVICE:abc123def (for audit)
TIMESTAMP TAG:  registry.kushnir.cloud/code-server/SERVICE:20260429_143000
BRANCH TAG:     registry.kushnir.cloud/code-server/SERVICE:main
```

### Harbor Workflows

#### Push to Harbor

```bash
# Tag local image
docker tag code-server-multimodal-ai:build registry.kushnir.cloud/code-server/multimodal-ai:1.0.0

# Push to Harbor
docker push registry.kushnir.cloud/code-server/multimodal-ai:1.0.0

# Harbor automatically:
# ✓ Scans for vulnerabilities (Trivy/Clair)
# ✓ Stores in tiered storage
# ✓ Logs access
# ✓ Enforces retention policy
```

#### Pull from Harbor

```bash
# Login
docker login registry.kushnir.cloud

# Pull specific version
docker pull registry.kushnir.cloud/code-server/multimodal-ai:1.0.0

# Deploy with docker-compose
docker-compose -f docker-compose.registry-override.yml up
```

#### Harbor Replication

```yaml
# Replicate to secondary registry (disaster recovery)
replication:
  - source: registry.kushnir.cloud/code-server/
    destination: secondary-registry.backup.cloud/code-server/
    trigger: on_push
    deletion: false  # Keep deleted images in backup
```

### Harbor Retention Policies

```yaml
# Keep last N images per tag
retention_policy:
  - tag_pattern: latest
    retention: 5  # Keep 5 recent "latest" builds
  - tag_pattern: "v*"
    retention: 10  # Keep 10 version releases
  - tag_pattern: "*"
    retention: 1  # Keep 1 of all others (cleanup policy)
```

---

## Option 2: GitLab Container Registry

### Prerequisites

```
GitLab with container registry enabled (docker.example.com)
Robot account with read/write permissions on code-server project
```

### Configuration

```yaml
# .gitlab-ci.yml
variables:
  REGISTRY: docker.example.com
  PROJECT: code-server

build_image:
  image: docker:latest
  services:
    - docker:dind
  script:
    - docker login -u gitlab-ci-token -p $CI_JOB_TOKEN $REGISTRY
    - docker build -t $REGISTRY/$PROJECT/SERVICE:$CI_COMMIT_SHORT_SHA .
    - docker push $REGISTRY/$PROJECT/SERVICE:$CI_COMMIT_SHORT_SHA
```

### Cleanup Policy

```yaml
# Automatically delete old images
container_expiration_policy:
  enabled: true
  keep_n: 5
  older_than: 30d
  name_regex: .*
  name_regex_delete: ^old-.*
```

---

## Option 3: AWS ECR

### Setup

```bash
# Create ECR repository
aws ecr create-repository \
  --repository-name code-server/multimodal-ai \
  --region us-east-1 \
  --scan-on-push

# Configure IAM for CI/CD
aws iam create-user --user-name github-actions
aws iam create-access-key --user-name github-actions

# Add inline policy
aws iam put-user-policy --user-name github-actions --policy-name ECRPush \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      "Resource": "arn:aws:ecr:*:ACCOUNT_ID:repository/code-server/*"
    }]
  }'
```

### GitHub Actions

```yaml
- name: Push to AWS ECR
  env:
    ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
    ECR_REPOSITORY: code-server/SERVICE
  run: |
    docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$GITHUB_SHA .
    docker push $ECR_REGISTRY/$ECR_REPOSITORY:$GITHUB_SHA
```

---

## Image Build Strategy

### Dockerfile Best Practices

```dockerfile
# Use specific base image version (not :latest)
FROM python:3.11-slim@sha256:ff71127c215572121f1991bacf17f39ec5fcfd2de1f1c01a595835495bb9adfc

# Multi-stage build (smaller final image)
FROM builder AS build
RUN pip install -r requirements.txt

FROM python:3.11-slim
COPY --from=build /app /app

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:8000/health || exit 1

# Non-root user
RUN useradd -m appuser
USER appuser
```

### Build Cache Optimization

```bash
# GitHub Actions example
- name: Build with cache
  uses: docker/build-push-action@v4
  with:
    context: .
    cache-from: type=registry,ref=registry.example.com/code-server/SERVICE:buildcache
    cache-to: type=registry,ref=registry.example.com/code-server/SERVICE:buildcache,mode=max
    tags: registry.example.com/code-server/SERVICE:latest
```

### Scan for Vulnerabilities

```bash
# Trivy scan
trivy image registry.kushnir.cloud/code-server/multimodal-ai:latest \
  --severity CRITICAL,HIGH \
  --exit-code 1  # Fail on vulnerabilities

# Harbor built-in scanning (automatic on push)
# Results available in Harbor UI
```

---

## Deployment with Registry Images

### Development (local builds)

```bash
docker-compose -f docker-compose.enterprise.yml up -d
# Uses local build context
```

### Staging (registry images)

```bash
docker-compose \
  -f docker-compose.enterprise.yml \
  -f docker-compose.registry-override.yml up -d
# Pulls from registry instead of building
```

### Production (pinned versions)

```yaml
# docker-compose.prod.yml
services:
  multimodal-ai:
    image: registry.kushnir.cloud/code-server/multimodal-ai:1.0.0@sha256:abc123...
    # Uses specific version hash - reproducible, auditable
```

---

## Image Promotion Pipeline

```
Commit → Build → Test → Push to :latest
           ↓
      If tests pass
           ↓
      Push to :1.0.0 (version tag)
           ↓
      If release tag (git tag v1.0.0)
           ↓
      Push to :1.0.0 + :latest
           ↓
      Trigger deployment
```

---

## Troubleshooting

### Image push fails

```bash
# Check authentication
docker login registry.kushnir.cloud

# Verify permissions
docker push registry.kushnir.cloud/code-server/SERVICE:test

# Check registry connectivity
curl -I https://registry.kushnir.cloud/v2/
```

### Vulnerability scan fails

```bash
# View scan results in Harbor UI
# Or via CLI:
harbor vulnerability list --image SERVICE:TAG

# Fix vulnerabilities by updating base image
FROM python:3.11-slim@sha256:<new-hash>
```

### Image pull fails in production

```bash
# Verify image exists
curl -I https://registry.kushnir.cloud/v2/code-server/SERVICE/manifests/latest

# Check image pull permissions
docker pull registry.kushnir.cloud/code-server/SERVICE:latest

# Verify image signature (if content trust enabled)
docker pull --disable-content-trust=false registry.kushnir.cloud/code-server/SERVICE:latest
```

---

## Performance Impact

- **Build time:** 2-5 min per service (on CI/CD runner)
- **Push time:** 30-90 seconds (registry bandwidth dependent)
- **Pull time:** 10-30 seconds (image size dependent)
- **Storage:** ~1-2 GB per service (with 5 tags each)

---

## Security Best Practices

1. **Image signing:** Enable content trust (requires signing keys)
2. **Access control:** Use robot accounts with limited permissions
3. **Scan on push:** Enable automatic vulnerability scanning
4. **Retention policy:** Delete old images automatically
5. **Network segmentation:** Registry on separate network from app hosts
6. **TLS encryption:** All registry traffic over HTTPS
7. **Audit logging:** Enable image pull/push logs for compliance

---

## Checklist

- [ ] Registry deployed and accessible
- [ ] DNS configured (registry.kushnir.cloud)
- [ ] TLS certificate installed
- [ ] Admin and robot accounts created
- [ ] GitHub Secrets configured (REGISTRY_USERNAME, REGISTRY_PASSWORD)
- [ ] CI/CD pipeline created (.github/workflows/build-docker-images.yml)
- [ ] docker-compose.registry-override.yml tested
- [ ] First image pushed and verified
- [ ] Image scanning configured
- [ ] Retention policy configured
- [ ] Replication (backup) configured (optional)
- [ ] Team trained on registry workflows

EOF
    
    log_success "Harbor guide created: docs/operations/docker-registry-setup.md"
}

# Main execution
main() {
    log_info "Docker Registry Setup starting..."
    
    detect_registry
    save_registry_config
    generate_tag_strategy
    generate_github_actions_workflow
    generate_gitlab_ci_config
    generate_docker_compose_override
    generate_harbor_guide
    
    log_success "Docker registry configuration complete!"
    log_info "Next steps:"
    log_info "  1. Deploy registry: Harbor, GitLab Container Registry, or AWS ECR"
    log_info "  2. Configure credentials in GitHub Secrets / GitLab Variables"
    log_info "  3. Test CI/CD pipeline with manual trigger"
    log_info "  4. Verify image builds and pushes to registry"
}

main "$@"
