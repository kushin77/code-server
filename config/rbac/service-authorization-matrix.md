# Service Authorization Matrix - Phase 3 RBAC Enforcement

## Overview

This matrix defines all allowed and denied service-to-service communication for the kushin77/code-server infrastructure. 40+ service pair combinations with explicit allow/deny rules, rate limiting, and audit logging.

## Authorization Matrix

### Code-Server (IDE Service)

| Target Service | Permission | Rate Limit | Rationale |
|---|---|---|---|
| PostgreSQL | ✅ ALLOW | 50 QPS | Data persistence required |
| Redis | ✅ ALLOW | 75 QPS | Session caching |
| Ollama | ✅ ALLOW | 60 QPS | LLM inference |
| Prometheus | ✅ ALLOW | 150 QPS | Metrics collection |
| Grafana | ✅ ALLOW | 120 QPS | Dashboard access |
| Caddy | ✅ ALLOW | 200 QPS | Reverse proxy |
| AlertManager | ❌ DENY | 0 QPS | No direct alerts |
| Jaeger | ❌ DENY | 0 QPS | No distributed tracing |

### Caddy (Reverse Proxy)

| Target Service | Permission | Rate Limit | Rationale |
|---|---|---|---|
| Code-Server | ✅ ALLOW | 100 QPS | Route traffic |
| Prometheus | ✅ ALLOW | 150 QPS | Metrics endpoint |
| Grafana | ✅ ALLOW | 120 QPS | Dashboard routing |
| AlertManager | ✅ ALLOW | 80 QPS | Alert UI |
| PostgreSQL | ❌ DENY | 0 QPS | No direct DB access |
| Redis | ❌ DENY | 0 QPS | No direct cache access |
| Ollama | ❌ DENY | 0 QPS | No AI inference |
| Jaeger | ❌ DENY | 0 QPS | No trace access |

### PostgreSQL (Database)

| Target Service | Permission | Rate Limit | Rationale |
|---|---|---|---|
| Code-Server | ✅ ALLOW | 100 QPS | App data |
| Grafana | ✅ ALLOW | 120 QPS | Dashboard queries |
| AlertManager | ✅ ALLOW | 80 QPS | Alert storage |
| Redis | ❌ DENY | 0 QPS | No cache sync |
| Ollama | ❌ DENY | 0 QPS | No AI data |
| Prometheus | ❌ DENY | 0 QPS | No metrics DB |
| Jaeger | ❌ DENY | 0 QPS | No traces |
| Caddy | ❌ DENY | 0 QPS | No direct DB |

### Redis (Cache)

| Target Service | Permission | Rate Limit | Rationale |
|---|---|---|---|
| Code-Server | ✅ ALLOW | 100 QPS | Session state |
| Caddy | ✅ ALLOW | 200 QPS | Request caching |
| Prometheus | ✅ ALLOW | 150 QPS | Metrics caching |
| PostgreSQL | ❌ DENY | 0 QPS | No DB queries |
| Grafana | ❌ DENY | 0 QPS | Dashboard state |
| AlertManager | ❌ DENY | 0 QPS | Alert state |
| Ollama | ❌ DENY | 0 QPS | No AI cache |
| Jaeger | ❌ DENY | 0 QPS | No trace cache |

### Prometheus (Metrics)

| Target Service | Permission | Rate Limit | Rationale |
|---|---|---|---|
| Caddy | ✅ ALLOW | 200 QPS | Scrape metrics |
| Grafana | ✅ ALLOW | 120 QPS | Query metrics |
| AlertManager | ✅ ALLOW | 80 QPS | Trigger alerts |
| Code-Server | ❌ DENY | 0 QPS | No app metrics |
| PostgreSQL | ❌ DENY | 0 QPS | No DB metrics |
| Redis | ❌ DENY | 0 QPS | No cache metrics |
| Ollama | ❌ DENY | 0 QPS | No AI metrics |
| Jaeger | ❌ DENY | 0 QPS | No distributed tracing |

### Grafana (Dashboards)

| Target Service | Permission | Rate Limit | Rationale |
|---|---|---|---|
| Prometheus | ✅ ALLOW | 150 QPS | Query metrics |
| AlertManager | ✅ ALLOW | 80 QPS | Alert integration |
| PostgreSQL | ✅ ALLOW | 50 QPS | Custom queries |
| Redis | ❌ DENY | 0 QPS | No cache queries |
| Code-Server | ❌ DENY | 0 QPS | No IDE access |
| Caddy | ❌ DENY | 0 QPS | No proxy config |
| Ollama | ❌ DENY | 0 QPS | No AI dashboard |
| Jaeger | ❌ DENY | 0 QPS | No tracing |

### AlertManager (Alerting)

| Target Service | Permission | Rate Limit | Rationale |
|---|---|---|---|
| Prometheus | ✅ ALLOW | 150 QPS | Alert rules |
| Caddy | ✅ ALLOW | 200 QPS | Route alerts |
| Grafana | ✅ ALLOW | 120 QPS | Dashboard display |
| Code-Server | ❌ DENY | 0 QPS | No IDE alerts |
| PostgreSQL | ❌ DENY | 0 QPS | No direct DB |
| Redis | ❌ DENY | 0 QPS | No cache access |
| Ollama | ❌ DENY | 0 QPS | No AI alerts |
| Jaeger | ❌ DENY | 0 QPS | No trace alerts |

### Jaeger (Distributed Tracing)

| Target Service | Permission | Rate Limit | Rationale |
|---|---|---|---|
| Prometheus | ✅ ALLOW | 150 QPS | Trace metrics |
| Grafana | ✅ ALLOW | 120 QPS | Visualization |
| Code-Server | ✅ ALLOW | 100 QPS | Trace instrumentation |
| PostgreSQL | ❌ DENY | 0 QPS | No direct traces |
| Redis | ❌ DENY | 0 QPS | No cache traces |
| Caddy | ❌ DENY | 0 QPS | No proxy tracing |
| AlertManager | ❌ DENY | 0 QPS | No alert traces |
| Ollama | ❌ DENY | 0 QPS | No AI traces |

### Ollama (AI Service)

| Target Service | Permission | Rate Limit | Rationale |
|---|---|---|---|
| Code-Server | ✅ ALLOW | 100 QPS | LLM inference |
| Prometheus | ✅ ALLOW | 150 QPS | Model metrics |
| Grafana | ✅ ALLOW | 120 QPS | Model dashboards |
| PostgreSQL | ❌ DENY | 0 QPS | No model DB |
| Redis | ❌ DENY | 0 QPS | No cache |
| Caddy | ❌ DENY | 0 QPS | No routing |
| AlertManager | ❌ DENY | 0 QPS | No alerts |
| Jaeger | ❌ DENY | 0 QPS | No traces |

## Implementation Details

### PostgreSQL Audit Schema

```sql
CREATE TABLE rbac_audit_log (
  id SERIAL PRIMARY KEY,
  timestamp TIMESTAMPTZ DEFAULT NOW(),
  service_account VARCHAR(255) NOT NULL,
  target_service VARCHAR(255) NOT NULL,
  allowed BOOLEAN NOT NULL,
  reason TEXT,
  jwt_claims JSONB,
  rate_limit_exceeded BOOLEAN DEFAULT FALSE,
  response_time_ms INTEGER,
  user_agent TEXT
);

CREATE INDEX idx_rbac_timestamp ON rbac_audit_log(timestamp DESC);
CREATE INDEX idx_rbac_service ON rbac_audit_log(service_account, target_service);
CREATE INDEX idx_rbac_allowed ON rbac_audit_log(allowed);
```

### Immutability Trigger

```sql
CREATE OR REPLACE FUNCTION prevent_audit_modification()
RETURNS TRIGGER AS $$
BEGIN
  RAISE EXCEPTION 'RBAC audit logs are immutable';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER prevent_rbac_update
BEFORE UPDATE ON rbac_audit_log FOR EACH ROW
EXECUTE FUNCTION prevent_audit_modification();

CREATE TRIGGER prevent_rbac_delete
BEFORE DELETE ON rbac_audit_log FOR EACH ROW
EXECUTE FUNCTION prevent_audit_modification();
```

### JWT Claims Example

```json
{
  "iss": "code-server-phase3",
  "aud": "internal-services",
  "sub": "code-server",
  "iat": 1713350400,
  "exp": 1713354000,
  "service_id": "code-server-token-abc123",
  "allowed_targets": ["postgresql:5432", "redis:6379", "ollama:11434"],
  "rate_limit_qps": 100
}
```

### Rate Limiting Algorithm (Token Bucket)

```
Burst Capacity: 50 tokens
Refill Rate: 10 tokens/second
Allowed QPS: Service-specific (10-200)

Decision Logic:
if tokens >= cost:
  tokens -= cost
  allow request
  log(allowed=true)
else:
  deny request
  log(allowed=false, reason='Rate limit exceeded')
  return 429 Too Many Requests
```

## Operational Queries

### Find All Denied Access Attempts
```sql
SELECT timestamp, service_account, target_service, reason
FROM rbac_audit_log
WHERE allowed = false
ORDER BY timestamp DESC
LIMIT 50;
```

### Check Service-Specific Authorization Pattern
```sql
SELECT service_account, target_service, COUNT(*) as request_count,
       COUNT(*) FILTER (WHERE allowed) as allowed_count,
       COUNT(*) FILTER (WHERE NOT allowed) as denied_count
FROM rbac_audit_log
WHERE service_account = 'code-server'
GROUP BY service_account, target_service
ORDER BY request_count DESC;
```

### Audit Log Size Management
```sql
-- Monthly archive
INSERT INTO rbac_audit_log_archive
SELECT * FROM rbac_audit_log
WHERE timestamp < NOW() - INTERVAL '90 days';

DELETE FROM rbac_audit_log
WHERE timestamp < NOW() - INTERVAL '90 days';
```

## Testing Guide

### Test Allowed Call
```bash
# Code-server → PostgreSQL (allowed)
curl -H "Authorization: Bearer $JWT" \
  -X GET http://postgres:5432/health
# Expected: Success with audit log entry (allowed=true)
```

### Test Denied Call
```bash
# Code-server → AlertManager (denied)
curl -H "Authorization: Bearer $JWT" \
  -X GET http://alertmanager:9093/health
# Expected: 403 Forbidden with audit log entry (allowed=false)
```

### Test Rate Limiting
```bash
# Send requests exceeding rate limit
for i in {1..150}; do
  curl -H "Authorization: Bearer $JWT" \
    http://postgres:5432/health &
done
wait
# Expected: Some requests return 429 Too Many Requests
```

## Conclusion

This authorization matrix ensures secure service-to-service communication with complete audit trails, rate limiting, and immutable compliance logging for production deployment at 192.168.168.31.
