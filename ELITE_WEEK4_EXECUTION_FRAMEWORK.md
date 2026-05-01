# ELITE Week 4 Execution Framework: ELITE-13 to ELITE-16
**Status**: Ready for Execution  
**Scheduled**: May 24-28, 2026  
**Owner**: Engineering Leads per phase  
**Duration**: 5 days (4 phases: 1 day + 2 days + 1 day + 1 day)  
**Prerequisite**: Week 3 complete (ELITE-10-12 done by May 22)

---

## Week 4 Overview

Week 4 focuses on architecture hardening and advanced deployment patterns. Event-driven architecture, API gateway, GitOps deployment, and performance optimization transform the platform from reactive infrastructure to proactive, event-driven enterprise architecture.

**Success Definition**: All 4 phases complete by May 28, architecture fully hardened.

---

## ELITE-13: Event-Driven Architecture (May 24)

**Phase Lead**: Backend Architecture Lead  
**Team**: 14 engineers + architects  
**Duration**: 1 day (8 hours)

### Objectives
- Deploy Kafka/Redpanda event streaming for all async operations
- Implement event sourcing patterns
- Build dead letter queue (DLQ) handling
- Create event schema registry

### Day Agenda

#### 08:00-09:00: Event Architecture Design
- [ ] Map all synchronous operations suitable for async
- [ ] Define event schema standards
- [ ] Design topic naming conventions
- [ ] Plan consumer group strategy
- [ ] Review existing Redpanda deployment

**Topic Naming Convention**:
```
{domain}.{aggregate}.{event_type}.{version}

Examples:
  code-server.workspace.created.v1
  code-server.user.authenticated.v1
  code-server.build.completed.v1
  code-server.deployment.started.v1
```

#### 09:00-12:00: Event Schema Registry & Producers
```python
# scripts/ops/event-schema-registry.py
"""
Schema registry for all code-server events.
Validates events against registered schemas before publishing.
"""
import json, hashlib
from typing import Dict, Any

SCHEMAS = {
    "code-server.workspace.created.v1": {
        "type": "object",
        "required": ["workspace_id", "user_id", "created_at", "config"],
        "properties": {
            "workspace_id": {"type": "string", "format": "uuid"},
            "user_id": {"type": "string", "format": "uuid"},
            "created_at": {"type": "string", "format": "date-time"},
            "config": {
                "type": "object",
                "required": ["language", "version", "resources"],
                "properties": {
                    "language": {"type": "string"},
                    "version": {"type": "string"},
                    "resources": {
                        "type": "object",
                        "required": ["cpu", "memory"],
                        "properties": {
                            "cpu": {"type": "number", "minimum": 0.1},
                            "memory": {"type": "integer", "minimum": 128}
                        }
                    }
                }
            }
        }
    },
    "code-server.user.authenticated.v1": {
        "type": "object",
        "required": ["user_id", "session_id", "authenticated_at", "method"],
        "properties": {
            "user_id": {"type": "string", "format": "uuid"},
            "session_id": {"type": "string"},
            "authenticated_at": {"type": "string", "format": "date-time"},
            "method": {"type": "string", "enum": ["password", "oauth", "saml", "token"]}
        }
    }
}

def validate_event(topic: str, event: Dict[str, Any]) -> tuple[bool, str]:
    schema = SCHEMAS.get(topic)
    if not schema:
        return False, f"No schema registered for topic: {topic}"
    # Simplified validation (production would use jsonschema library)
    for field in schema.get("required", []):
        if field not in event:
            return False, f"Missing required field: {field}"
    return True, "valid"

def publish_event(topic: str, event: Dict[str, Any], producer) -> bool:
    valid, msg = validate_event(topic, event)
    if not valid:
        raise ValueError(f"Schema validation failed: {msg}")
    
    # Add envelope metadata
    envelope = {
        "schema_version": "1",
        "event_id": hashlib.sha256(json.dumps(event, sort_keys=True).encode()).hexdigest()[:16],
        "topic": topic,
        "payload": event
    }
    producer.produce(topic, json.dumps(envelope).encode())
    return True
```

#### 13:00-16:00: DLQ & Consumer Groups
```bash
# Configure DLQ topics for each domain
DOMAINS=("workspace" "user" "build" "deployment" "billing")

for DOMAIN in "${DOMAINS[@]}"; do
  # Create main topic
  kafka-topics.sh --bootstrap-server redpanda:9092 --create \
    --topic "code-server.${DOMAIN}.events.v1" \
    --partitions 6 \
    --replication-factor 2 \
    --config "retention.ms=604800000"  # 7 days
  
  # Create DLQ topic
  kafka-topics.sh --bootstrap-server redpanda:9092 --create \
    --topic "code-server.${DOMAIN}.events.v1.dlq" \
    --partitions 1 \
    --replication-factor 2 \
    --config "retention.ms=2592000000"  # 30 days
  
  echo "Created topics for domain: $DOMAIN"
done

# Verify topics created
kafka-topics.sh --bootstrap-server redpanda:9092 --list | grep "code-server"
```

#### 16:00-17:00: Event Architecture Documentation
- [ ] Event-driven architecture guide (12+ pages)
- [ ] Schema registry documentation
- [ ] DLQ handling procedures
- [ ] Consumer group management

### ELITE-13 Deliverables
✅ Event schema registry for all domains  
✅ Topic naming + DLQ topology  
✅ Producer/consumer templates  
✅ Schema validation library  
✅ Event architecture guide (12+ pages)  

### Success Criteria
| Item | Target |
|------|--------|
| Event schemas | All domains covered |
| DLQ topics | 1 per domain |
| Schema validation | 100% enforced |
| Documentation | 12+ pages |

---

## ELITE-14: API Gateway & Service Discovery (May 25-26)

**Phase Lead**: API Platform Lead  
**Team**: 15 engineers + architects  
**Duration**: 2 days (16 hours)

### Objectives
- Deploy centralized API gateway (Kong/Caddy)
- Implement service discovery (Consul)
- Build API versioning strategy
- Create developer portal

### Day 1 (May 25): API Gateway Deployment

#### 08:00-09:00: Gateway Architecture Design
- [ ] Map all external API endpoints (76 services)
- [ ] Design routing rules
- [ ] Plan authentication middleware
- [ ] Design rate limiting strategy per API tier
- [ ] Review existing Caddyfile configuration

#### 09:00-12:00: Caddy Gateway Configuration
```caddyfile
# Caddyfile - Production API Gateway (ELITE-14)
{
    admin off
    log {
        format json
        level INFO
    }
    metrics
}

# Global rate limiting
(rate_limit) {
    rate_limit {
        zone {args[0]}
        events {args[1]}
        window {args[2]}
    }
}

# API Gateway - v1
api.code-server.internal {
    # Authentication middleware
    forward_auth http://code-server-auth:4181 {
        uri /auth/verify
        copy_headers X-User-Id X-User-Role X-Tenant-Id
    }

    # Route to services with versioning
    handle /v1/workspaces* {
        import rate_limit workspace 100 1m
        reverse_proxy code-server-workspace:8080 {
            health_uri /health
            health_interval 10s
        }
    }

    handle /v1/users* {
        import rate_limit users 50 1m
        reverse_proxy code-server-users:8080
    }

    handle /v1/builds* {
        import rate_limit builds 20 1m
        reverse_proxy code-server-builder:8080
    }

    # API docs (no auth required)
    handle /docs* {
        reverse_proxy code-server-portal:3000
    }

    # Health check (no auth, no rate limit)
    respond /health 200
}

# Internal service mesh
*.code-server.internal {
    tls internal
    reverse_proxy {
        dynamic a {
            name {labels.1}.code-server.internal
            port 8080
        }
    }
}
```

#### 13:00-16:00: Service Discovery (Consul)
```hcl
# terraform/modules/consul/services.tf
resource "consul_service" "code_server_services" {
  for_each = var.services

  name    = each.key
  address = each.value.address
  port    = each.value.port
  tags    = ["code-server", each.value.tier, "v1"]

  check {
    check_id = "${each.key}-health"
    name     = "${each.key} HTTP Health"
    http     = "http://${each.value.address}:${each.value.port}/health"
    interval = "10s"
    timeout  = "5s"
    deregister_critical_service_after = "1m"
  }

  meta = {
    version       = "1.0.0"
    environment   = "production"
    managed_by    = "terraform"
    elite_phase   = "ELITE-14"
  }
}

# DNS-based service discovery
resource "consul_config_entry" "service_resolver" {
  for_each = var.services
  kind     = "service-resolver"
  name     = each.key

  config_json = jsonencode({
    DefaultSubset = "active"
    Subsets = {
      active = { Filter = "Service.Tags contains \"active\"" }
      canary = { Filter = "Service.Tags contains \"canary\"" }
    }
    Failover = {
      "*" = { Service = "${each.key}-replica" }
    }
  })
}
```

#### 16:00-17:00: Day 1 Review
- [ ] Gateway routing verified
- [ ] Service discovery tested
- [ ] Authentication middleware confirmed

### Day 2 (May 26): API Versioning & Developer Portal

#### 08:00-11:00: API Versioning Strategy
```bash
# API version management script
cat > scripts/ops/api-version-manager.sh << 'APIVER'
#!/usr/bin/env bash
set -euo pipefail

ACTION=$1  # deploy|deprecate|retire
SERVICE=$2
VERSION=$3

case "$ACTION" in
  deploy)
    echo "Deploying API version: $SERVICE/$VERSION"
    # Add version to Caddy routing
    cat >> /etc/caddy/routes.d/"${SERVICE}.conf" << ROUTE
handle /v${VERSION}/${SERVICE}* {
    reverse_proxy code-server-${SERVICE}:80${VERSION}
}
ROUTE
    ;;
  
  deprecate)
    echo "Deprecating API: $SERVICE/$VERSION"
    # Add deprecation header via Caddy middleware
    cat >> /etc/caddy/deprecation.d/"${SERVICE}-v${VERSION}.conf" << DEP
header /v${VERSION}/${SERVICE}* Sunset "$(date -d '+6 months' -u +%a, %d %b %Y 00:00:00 GMT)"
header /v${VERSION}/${SERVICE}* Deprecation "$(date -u +%a, %d %b %Y 00:00:00 GMT)"
header /v${VERSION}/${SERVICE}* Link "<https://api.code-server.internal/v$(( VERSION + 1 ))/${SERVICE}>; rel=\"successor-version\""
DEP
    ;;
  
  retire)
    echo "Retiring API: $SERVICE/$VERSION"
    # Return 410 Gone
    cat >> /etc/caddy/retired.d/"${SERVICE}-v${VERSION}.conf" << RETIRED
handle /v${VERSION}/${SERVICE}* {
    respond "API version v${VERSION} has been retired. Please upgrade to the latest version." 410
}
RETIRED
    ;;
esac
APIVER
chmod +x scripts/ops/api-version-manager.sh
```

#### 11:00-15:00: Developer Portal Deployment
```yaml
# docker-compose additions for developer portal
services:
  code-server-portal:
    image: code-server/developer-portal:latest
    container_name: code-server-portal
    environment:
      - API_BASE_URL=https://api.code-server.internal
      - VAULT_ADDR=http://vault:8200
      - DOCS_VERSION=v1
    volumes:
      - ./apps/portal:/app
      - ./docs/api:/app/docs/api:ro
    labels:
      - "managed=terraform"
      - "elite-phase=ELITE-14"
    networks:
      - code-server-network
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:3000/health"]
      interval: 30s
```

#### 15:00-17:00: ELITE-14 Completion Documentation
- [ ] API gateway configuration guide (15+ pages)
- [ ] Service discovery runbook
- [ ] API versioning procedures
- [ ] Developer portal user guide

### ELITE-14 Deliverables
✅ API gateway with authentication + rate limiting  
✅ Service discovery via Consul  
✅ API versioning framework  
✅ Developer portal deployed  
✅ Gateway guide (15+ pages)  

### Success Criteria
| Item | Target |
|------|--------|
| API routing | All 76 services |
| Service discovery | Live + healthy |
| Versioning | Framework deployed |
| Developer portal | Accessible |

---

## ELITE-15: GitOps Deployment Pipeline (May 27)

**Phase Lead**: DevOps Platform Lead  
**Team**: 12 engineers + DevOps  
**Duration**: 1 day (8 hours)

### Objectives
- Implement GitOps workflow (ArgoCD/Flux pattern)
- Build deployment state reconciliation
- Create environment promotion pipeline
- Integrate with Terraform automation

### Day Agenda

#### 08:00-09:00: GitOps Design
- [ ] Define GitOps repository structure
- [ ] Design environment promotion (dev→staging→prod)
- [ ] Map Terraform state to declarative config
- [ ] Plan drift detection automation

#### 09:00-12:00: GitOps Controller Implementation
```bash
# scripts/ops/gitops-sync.sh - Local GitOps controller
#!/usr/bin/env bash
set -euo pipefail

REPO_URL=${GITOPS_REPO:-"origin"}
BRANCH=${GITOPS_BRANCH:-"release/v1.0.0-production"}
SYNC_INTERVAL=${SYNC_INTERVAL:-60}

echo "[$(date -u)] GitOps controller starting"
echo "  Repo: $REPO_URL | Branch: $BRANCH | Interval: ${SYNC_INTERVAL}s"

while true; do
  # Fetch latest state
  git fetch "$REPO_URL" "$BRANCH" --quiet
  
  LOCAL=$(git rev-parse HEAD)
  REMOTE=$(git rev-parse "remotes/${REPO_URL}/${BRANCH}")
  
  if [ "$LOCAL" != "$REMOTE" ]; then
    echo "[$(date -u)] State drift detected: $LOCAL → $REMOTE"
    
    # Pull changes
    git merge --ff-only "remotes/${REPO_URL}/${BRANCH}"
    
    # Determine what changed
    CHANGED=$(git diff --name-only "$LOCAL" "$REMOTE")
    
    # Apply changes selectively
    if echo "$CHANGED" | grep -q "^terraform/"; then
      echo "  Applying Terraform changes..."
      terraform -chdir=terraform/environments/private apply -auto-approve
    fi
    
    if echo "$CHANGED" | grep -q "^docker-compose"; then
      echo "  Reloading compose services..."
      docker-compose -f docker-compose.enterprise.yml up -d --no-recreate
    fi
    
    if echo "$CHANGED" | grep -q "^configs/"; then
      echo "  Reloading service configurations..."
      docker kill --signal=SIGHUP $(docker ps -q --filter "label=managed=terraform") 2>/dev/null || true
    fi
    
    echo "[$(date -u)] GitOps sync complete: $REMOTE"
    
    # Post sync notification to Slack
    curl -s -X POST "${SLACK_WEBHOOK:-}" \
      -d "{\"text\":\"✅ GitOps sync: deployed ${REMOTE:0:8} to production\"}" || true
  fi
  
  sleep "$SYNC_INTERVAL"
done
```

#### 13:00-16:00: Environment Promotion Pipeline
```bash
# scripts/ops/promote-environment.sh
#!/usr/bin/env bash
set -euo pipefail

FROM_ENV=$1  # dev|staging
TO_ENV=$2    # staging|production
VERSION=${3:-$(git rev-parse HEAD)}

echo "[$(date -u)] Promoting $VERSION: $FROM_ENV → $TO_ENV"

# Pre-flight checks
echo "Step 1: Verify source environment health"
bash scripts/ci/check-environment-health.sh "$FROM_ENV" || exit 1

echo "Step 2: Run promotion gate tests"
bash scripts/ci/promotion-gate-tests.sh "$FROM_ENV" "$TO_ENV" || exit 1

echo "Step 3: Create promotion PR"
git checkout -b "promote/${FROM_ENV}-to-${TO_ENV}/${VERSION:0:8}"
sed -i "s/image_tag = .*/image_tag = \"$VERSION\"/" \
  "terraform/environments/${TO_ENV}/terraform.tfvars"
git add terraform/environments/"${TO_ENV}"/terraform.tfvars
git commit -m "chore: promote $VERSION from $FROM_ENV to $TO_ENV"

echo "Step 4: Apply to target environment"
terraform -chdir="terraform/environments/${TO_ENV}" apply -auto-approve

echo "Step 5: Verify target environment"
bash scripts/ci/check-environment-health.sh "$TO_ENV" || {
  echo "Promotion FAILED - initiating rollback"
  bash scripts/ops/auto-rollback.sh "$TO_ENV" "$VERSION" && exit 1
}

echo "[$(date -u)] Promotion complete: $VERSION in $TO_ENV ✅"
```

#### 16:00-17:00: GitOps Documentation
- [ ] GitOps workflow guide (12+ pages)
- [ ] Promotion pipeline procedures
- [ ] Drift detection runbook
- [ ] Rollback procedures for GitOps

### ELITE-15 Deliverables
✅ GitOps controller running on production  
✅ Environment promotion pipeline  
✅ Drift detection automated  
✅ Rollback integrated with GitOps  
✅ GitOps guide (12+ pages)  

### Success Criteria
| Item | Target |
|------|--------|
| Sync interval | 60 seconds |
| Promotion time | <10 minutes |
| Drift detection | Automated |
| Rollback | <5 minutes |

---

## ELITE-16: Performance Optimization & Profiling (May 28)

**Phase Lead**: Performance Engineering Lead  
**Team**: 10 engineers + SREs  
**Duration**: 1 day (8 hours)

### Objectives
- Conduct platform-wide performance profiling
- Identify and resolve top-10 bottlenecks
- Deploy continuous profiling
- Establish performance regression gates

### Day Agenda

#### 08:00-09:00: Performance Baseline Assessment
```bash
# Establish performance baseline
cat > scripts/ci/performance-baseline.sh << 'PERFBASE'
#!/usr/bin/env bash
set -euo pipefail

echo "=== Performance Baseline Assessment ==="
echo "Time: $(date -u)"

# 1. API endpoint latency
for ENDPOINT in /health /api/v1/workspaces /api/v1/users; do
  LATENCY=$(curl -s -w "%{time_total}" -o /dev/null "http://localhost:8080${ENDPOINT}")
  echo "Endpoint $ENDPOINT: ${LATENCY}s"
done

# 2. Database query performance
psql -h 192.168.168.31 -U postgres << 'SQL'
SELECT
  query,
  calls,
  mean_exec_time as avg_ms,
  max_exec_time as max_ms
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;
SQL

# 3. Container resource utilization
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" \
  $(docker ps -q --filter "label=managed=terraform") \
  | sort -k2 -rn | head -20

echo "=== Baseline Complete ==="
PERFBASE
chmod +x scripts/ci/performance-baseline.sh
bash scripts/ci/performance-baseline.sh
```

#### 09:00-12:00: Bottleneck Resolution
```bash
# Top bottleneck fixes (data-driven from baseline)

# Fix 1: Enable PostgreSQL query caching
psql -h 192.168.168.31 -U postgres << 'SQL'
-- Enable pg_stat_statements
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Optimize slow queries
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_workspaces_user_id 
  ON workspaces(user_id) WHERE deleted_at IS NULL;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_sessions_user_id_active
  ON sessions(user_id, created_at DESC) WHERE expires_at > NOW();

-- Update statistics
ANALYZE;
SQL

# Fix 2: Redis connection pooling
cat > configs/redis/pooling.conf << 'REDIS'
maxmemory-policy allkeys-lru
tcp-keepalive 300
hz 20
aof-use-rdb-preamble yes
lazyfree-lazy-eviction yes
lazyfree-lazy-expire yes
REDIS

# Fix 3: Nginx worker optimization
cat > configs/nginx/worker.conf << 'NGINX'
worker_processes auto;
worker_rlimit_nofile 65535;
events {
    worker_connections 4096;
    use epoll;
    multi_accept on;
}
http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    keepalive_requests 1000;
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
}
NGINX
```

#### 13:00-15:30: Continuous Profiling Setup
```yaml
# Pyroscope continuous profiling configuration
# configs/pyroscope/config.yaml
server:
  http_listen_port: 4040
  grpc_listen_port: 4041

storage:
  backend: filesystem
  filesystem:
    dir: /var/lib/pyroscope

scrape_configs:
  - job_name: code-server-api
    static_configs:
      - targets: ['code-server-api:6060']
    params:
      seconds: ['15']
    profiling_config:
      pprof_config:
        memory:
          enabled: true
        block:
          enabled: true
        goroutine:
          enabled: true
        mutex:
          enabled: true
        cpu:
          enabled: true
          delta: true
```

#### 15:30-17:00: Performance Gates & Week 4 Completion
```bash
# scripts/ci/performance-gate.sh
#!/usr/bin/env bash
set -euo pipefail

echo "=== Performance Regression Gate ==="

# Test API latency
P95=$(curl -s "http://prometheus:9090/api/v1/query?query=histogram_quantile(0.95,rate(http_request_duration_seconds_bucket[5m]))*1000" \
  | jq -r '.data.result[0].value[1]' | cut -d. -f1)

THRESHOLD=100  # 100ms P95 target

if [ "${P95:-999}" -gt "$THRESHOLD" ]; then
  echo "❌ FAIL: P95 latency ${P95}ms exceeds ${THRESHOLD}ms threshold"
  exit 1
fi

echo "✅ PASS: P95 latency ${P95}ms (threshold: ${THRESHOLD}ms)"

# Test error rate
ERROR_RATE=$(curl -s "http://prometheus:9090/api/v1/query?query=sum(rate(http_requests_total{code=~\"5..\"}[5m]))/sum(rate(http_requests_total[5m]))*100" \
  | jq -r '.data.result[0].value[1]' | cut -d. -f1)

ERROR_THRESHOLD=1  # 1% error rate threshold

if [ "${ERROR_RATE:-100}" -gt "$ERROR_THRESHOLD" ]; then
  echo "❌ FAIL: Error rate ${ERROR_RATE}% exceeds ${ERROR_THRESHOLD}% threshold"
  exit 1
fi

echo "✅ PASS: Error rate ${ERROR_RATE}% (threshold: ${ERROR_THRESHOLD}%)"
echo "=== Performance Gate: PASSED ==="
```

### ELITE-16 Deliverables
✅ Performance baseline established  
✅ Top-10 bottlenecks identified + resolved  
✅ Continuous profiling deployed (Pyroscope)  
✅ Performance regression gate in CI  
✅ Performance guide (12+ pages)  

### Success Criteria
| Item | Target |
|------|--------|
| P95 latency | <100ms after optimization |
| Error rate | <0.05% |
| Bottlenecks resolved | 10/10 |
| Profiling | Continuous |

---

## Week 4 Completion Summary (May 28 17:00 UTC)

| Phase | Status | Key Deliverable |
|-------|--------|-----------------|
| ELITE-13 | ⏳ | Event-driven architecture |
| ELITE-14 | ⏳ | API gateway + service discovery |
| ELITE-15 | ⏳ | GitOps deployment pipeline |
| ELITE-16 | ⏳ | Performance optimization |

**Target**: All 4 phases complete → 50+ pages → ready for Week 5 (final)
