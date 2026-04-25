# P3 Services Deployment & Integration Guide

**Date**: April 25, 2026  
**Status**: ✅ IaC Implementation Complete  
**Commits**: 2630fd77 (verification), latest (config & monitoring)  
**Related Issues**: P3 #1558 (Paperclip), #1559 (Reputation Engine), #1561 (Execution Scheduler)

---

## Overview

Complete Infrastructure as Code (IaC) for P3 services deployment and integration:

- **Reputation Engine** (#1559): Real-time agent reputation scoring
- **Execution Scheduler** (#1561): Task execution orchestration
- **Paperclip Control Plane** (#1558): Approval & policy management
- **OPA Policy Engine**: Centralized access control

---

## Quick Start

### 1. Configure P3 Services

```bash
# Source the P3 configuration
source scripts/_common/_p3-services-config.env

# Override defaults if needed
export LOG_LEVEL=DEBUG
export REPUTATION_ENGINE_PORT=9002

# View all configuration
grep '^export' scripts/_common/_p3-services-config.env | grep -v '#'
```

### 2. Deploy Services

```bash
# Option A: Using docker-compose (all services)
docker-compose up -d reputation-engine execution-scheduler paperclip opa

# Option B: Selective deployment
docker-compose up -d reputation-engine
docker-compose up -d execution-scheduler
docker-compose up -d paperclip
```

### 3. Monitor Service Health

```bash
# Start continuous monitoring
bash scripts/ops/monitor-p3-services-health.sh

# One-time health check with report
MAX_ITERATIONS=1 JSON_OUTPUT=true bash scripts/ops/monitor-p3-services-health.sh
```

### 4. Run Integration Verification

```bash
# Full integration verification (10 comprehensive tests)
bash scripts/ci/verify-p3-services-full-integration.sh

# View the JSON report
cat artifacts/p3-verification-*.json | jq .
```

---

## Architecture

### Service Communication

```
┌──────────────────────────────────────────────────────────────┐
│                    Paperclip Control Plane                    │
│               (Approval Workflows & OPA Policies)             │
│                          :8010                               │
└────────────┬─────────────────────────────────────────────────┘
             │
    ┌────────┴────────┐
    │                 │
    ↓                 ↓
┌──────────────┐  ┌─────────────────────┐
│  Execution   │  │   Reputation Engine │
│  Scheduler   │  │   (Scoring & Audits)│
│   :8080      │  │        :8002        │
└──┬───────────┘  └─────────┬───────────┘
   │                        │
   └────────┬───────────────┘
            │
            ↓
    ┌───────────────┐
    │  PostgreSQL   │
    │  + Redis      │
    │  + Kafka      │
    └───────────────┘
```

### Data Flow

1. **Task Submission** → Execution Scheduler
2. **Approval Request** → Paperclip Control Plane
3. **OPA Policy Check** → Policy Engine
4. **Execution** → Agent (CODE_REVIEWER, etc.)
5. **Scoring** → Reputation Engine
6. **Audit Log** → PostgreSQL + Audit Table

---

## Configuration Files

### Single Source of Truth (SSOT)

**File**: `scripts/_common/_p3-services-config.env`

All P3 configuration in one place:
- Service endpoints (URLs, ports)
- Database connection strings
- Redis cache configuration
- Kafka event streams
- Authentication & authorization
- Resource limits
- Logging & observability
- Health check parameters

### Environment Overrides

```bash
# Override specific service
export EXECUTION_SCHEDULER_PORT=9080

# Override logging
export LOG_LEVEL=DEBUG
export STRUCTURED_LOGGING_ENABLED=true

# Override resource limits
export EXECUTION_SCHEDULER_MEMORY=2G
export EXECUTION_SCHEDULER_CPU=2

# Re-source configuration
source scripts/_common/_p3-services-config.env
```

---

## Verification & Testing

### IaC Verification Script (10 Tests)

**File**: `scripts/ci/verify-p3-services-full-integration.sh`

Tests performed:
1. ✅ Service health checks (all 4 services)
2. ✅ Database connectivity & schema
3. ✅ Redis cache connectivity
4. ✅ Inter-service communication
5. ✅ OPA policy integration
6. ✅ End-to-end task workflow
7. ✅ Service isolation & authorization
8. ✅ Audit logging & compliance
9. ✅ Resource constraints
10. ✅ Idempotency (IaC principle)

**Run verification**:
```bash
bash scripts/ci/verify-p3-services-full-integration.sh

# Output: JSON report with test results
cat artifacts/p3-verification-*.json | jq '.test_results'
```

### Health Monitoring

**File**: `scripts/ops/monitor-p3-services-health.sh`

Real-time monitoring of all services:
```bash
# Continuous monitoring (Ctrl+C to stop)
bash scripts/ops/monitor-p3-services-health.sh

# One-time check with 10s intervals
MAX_ITERATIONS=5 bash scripts/ops/monitor-p3-services-health.sh

# Generate JSON report
JSON_OUTPUT=true bash scripts/ops/monitor-p3-services-health.sh

# Quiet mode (no console output)
QUIET_MODE=true MAX_ITERATIONS=1 bash scripts/ops/monitor-p3-services-health.sh
```

---

## Deployment Checklist

### Pre-Deployment

- [ ] Review `_p3-services-config.env` for environment-specific overrides
- [ ] Verify PostgreSQL, Redis, Kafka are running
- [ ] Set environment variables: `export LOG_LEVEL=INFO`
- [ ] Run: `bash scripts/ci/validate-dns-architecture.sh ci`
- [ ] Run: `bash scripts/ci/verify-p3-services-full-integration.sh`

### Deployment

- [ ] Deploy services: `docker-compose up -d reputation-engine execution-scheduler paperclip opa`
- [ ] Wait 30s for startup
- [ ] Monitor health: `bash scripts/ops/monitor-p3-services-health.sh`
- [ ] Run integration tests: `bash scripts/ci/verify-p3-services-full-integration.sh`
- [ ] Verify all tests pass (exit code 0)

### Post-Deployment

- [ ] Check logs: `docker-compose logs reputation-engine`
- [ ] Verify audit trail: `tail -f logs/audit/*.log`
- [ ] Test API endpoints manually
- [ ] Monitor for 5 minutes: `MAX_ITERATIONS=30 MONITOR_INTERVAL=10 bash scripts/ops/monitor-p3-services-health.sh`

---

## Troubleshooting

### Service Not Responding

```bash
# Check service status
docker-compose ps reputation-engine

# Check logs
docker-compose logs reputation-engine --tail=50

# Restart service
docker-compose restart reputation-engine

# Verify health endpoint
curl -v http://reputation-engine:8002/health
```

### Database Connection Issues

```bash
# Source configuration
source scripts/_common/_p3-services-config.env

# Test connection
psql "$DATABASE_URL" -c "SELECT 1"

# Check pool settings
echo $DB_POOL_MAX_SIZE
```

### Redis Cache Problems

```bash
# Test Redis connection
redis-cli -h $REDIS_HOST -p $REDIS_PORT PING

# Check memory usage
redis-cli -h $REDIS_HOST -p $REDIS_PORT INFO memory

# Clear cache (if needed)
redis-cli -h $REDIS_HOST -p $REDIS_PORT FLUSHDB
```

### OPA Policy Errors

```bash
# Test OPA endpoint
curl http://opa:8181/health

# Query policy
curl -X POST http://opa:8181/v1/compile \
  -H "Content-Type: application/json" \
  -d '{
    "query": "data.kushnir.approval_required",
    "input": {"risk_level": "HIGH"}
  }'
```

---

## GOV-002 Compliance

### ✅ Infrastructure as Code (IaC)

- All P3 configuration versioned in Git
- No manual configuration steps
- Repeatable deployments
- Environment-driven (no hardcoding)

### ✅ Immutability

- `set -euo pipefail` in all scripts
- Configuration via environment variables only
- No state mutations
- Read-only test/verification scripts

### ✅ Idempotency

- All scripts safe to re-run
- Multiple executions produce same result
- Database migrations are idempotent
- Configuration sourcing is idempotent

### ✅ Determinism

- Same configuration → Same deployment
- Reproducible results
- Audit trail via Git history
- Consistent across environments

---

## Files & Locations

| File | Purpose | LOC |
|------|---------|-----|
| `scripts/_common/_p3-services-config.env` | Configuration SSOT | 210 |
| `scripts/ops/monitor-p3-services-health.sh` | Health monitoring | 250 |
| `scripts/ci/verify-p3-services-full-integration.sh` | Integration verification | 617 |
| `docker-compose.yml` | Service definitions | (existing) |
| `docs/P3-SERVICES-DEPLOYMENT-GUIDE.md` | This guide | (doc) |

---

## Related Issues

| Issue | Service | Status |
|-------|---------|--------|
| P3 #1559 | Reputation Engine | ✅ Complete |
| P3 #1561 | Execution Scheduler | ✅ Complete |
| P3 #1558 | Paperclip Control Plane | ✅ Complete (partial OPA) |
| P3 #1536 Phase 3 | DNS IaC | ✅ Complete |

---

## Next Steps

1. **Deploy to Secondary Replica** (192.168.168.42)
2. **Test Multi-Node Failover** (VRRP VIP failover)
3. **Phase 4 Kubernetes Migration Readiness**
4. **Global Distribution & Edge Deployment** (P3 #1768)

---

**Document Version**: 1.0  
**Last Updated**: 2026-04-25  
**Author**: GitHub Copilot  
**Status**: Ready for Production Deployment
