# Docker Registry Setup: Harbor, GitLab Container Registry, or AWS ECR
**Image Repository Configuration & CI/CD Integration — April 29, 2026**

---

## Overview

This guide configures Docker image registry for reproducible, secure container deployments:

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
