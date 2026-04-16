# Phase 3: Service-to-Service Authorization Matrix

| From | To | Allowed | Rate Limit | Notes |
|------|-----|---------|-----------|-------|
| code-server | postgresql | ✅ | 100 QPS | IDE → Database queries |
| code-server | redis | ✅ | 100 QPS | IDE → Session cache |
| code-server | ollama | ✅ | 100 QPS | IDE → LLM inference |
| code-server | prometheus | ✅ | 100 QPS | IDE → Metrics for dashboards |
| code-server | alertmanager | ❌ | N/A | IDE should not trigger alerts |
| postgresql | code-server | ✅ | 50 QPS | Database → IDE (connection pooling) |
| postgresql | grafana | ✅ | 50 QPS | Database → Dashboards (data queries) |
| postgresql | prometheus | ✅ | 50 QPS | Database → Metrics (health checks) |
| postgresql | ollama | ❌ | N/A | Database should not call LLM |
| postgresql | alertmanager | ❌ | N/A | Database should not trigger alerts |
| redis | code-server | ✅ | 200 QPS | Cache → IDE (session retrieval) |
| redis | prometheus | ✅ | 200 QPS | Cache → Metrics (cache stats) |
| redis | postgresql | ❌ | N/A | Cache should not call database |
| redis | grafana | ❌ | N/A | Cache should not call dashboard |
| redis | ollama | ❌ | N/A | Cache should not call LLM |
| prometheus | grafana | ✅ | 50 QPS | Metrics → Dashboards (data queries) |
| prometheus | alertmanager | ✅ | 50 QPS | Metrics → Alerts (alert evaluation) |
| prometheus | code-server | ❌ | N/A | Metrics should not call IDE |
| prometheus | redis | ❌ | N/A | Metrics should not call cache |
| prometheus | postgresql | ❌ | N/A | Metrics should not call database |
| grafana | prometheus | ✅ | 30 QPS | Dashboards → Metrics (data retrieval) |
| grafana | code-server | ❌ | N/A | Dashboards should not call IDE |
| grafana | redis | ❌ | N/A | Dashboards should not call cache |
| grafana | postgresql | ❌ | N/A | Dashboards should not call database |
| grafana | ollama | ❌ | N/A | Dashboards should not call LLM |
| ollama | code-server | ✅ | 10 QPS | LLM → IDE (inference results) |
| ollama | postgresql | ❌ | N/A | LLM should not call database |
| ollama | redis | ❌ | N/A | LLM should not call cache |
| ollama | prometheus | ❌ | N/A | LLM should not call metrics |
| alertmanager | prometheus | ✅ | 20 QPS | Alerts → Metrics (alert status) |
| alertmanager | code-server | ❌ | N/A | Alerts should not call IDE |
| alertmanager | redis | ❌ | N/A | Alerts should not call cache |
| alertmanager | postgresql | ❌ | N/A | Alerts should not call database |
| jaeger | code-server | ✅ | 100 QPS | Tracing → IDE (trace queries) |
| jaeger | prometheus | ✅ | 100 QPS | Tracing → Metrics (trace stats) |
| jaeger | grafana | ✅ | 100 QPS | Tracing → Dashboards (visualization) |
| jaeger | postgresql | ❌ | N/A | Tracing should not call database |
| jaeger | redis | ❌ | N/A | Tracing should not call cache |
| jaeger | ollama | ❌ | N/A | Tracing should not call LLM |
| jaeger | alertmanager | ❌ | N/A | Tracing should not trigger alerts |

## Authorization Enforcement Points

### 1. Caddy Middleware (Request Level)
- **JWT Token Validation**: Verify token issuer, audience, expiration
- **Service Authentication**: mTLS or API key verification
- **Rate Limiting**: Token-bucket algorithm per service
- **Audit Logging**: Log all requests to PostgreSQL

### 2. Docker Network Isolation (Network Level)
- Services connected only to allowed networks
- Prevents unauthorized service-to-service communication
- Applied at container startup

### 3. Service Environment Variables (Application Level)
- Each service loads allowed/denied service list from environment
- Enforced at client library level (database drivers, HTTP clients)
- Checked on each outbound request

### 4. PostgreSQL Audit Log (Audit Level)
- All authorization decisions logged (allow/deny)
- Immutable records (cannot be modified after creation)
- Indexed by timestamp, service, allowed status
- Queryable for compliance and debugging

## Audit Log Examples

### Recent Denied Access Attempts
```sql
SELECT * FROM rbac_audit_log 
WHERE allowed = false 
ORDER BY timestamp DESC LIMIT 10;
```

### Service Access Patterns (24h)
```sql
SELECT service_account, COUNT(*) as total, 
  SUM(CASE WHEN allowed THEN 1 ELSE 0 END) as allowed,
  SUM(CASE WHEN NOT allowed THEN 1 ELSE 0 END) as denied
FROM rbac_audit_log
WHERE timestamp > NOW() - INTERVAL '24 hours'
GROUP BY service_account;
```

### Anomalies - Services Calling Unauthorized Targets
```sql
SELECT service_account, target_service, COUNT(*) as denied_attempts
FROM rbac_audit_log
WHERE allowed = false 
  AND timestamp > NOW() - INTERVAL '1 hour'
GROUP BY service_account, target_service
HAVING COUNT(*) > 5
ORDER BY denied_attempts DESC;
```

### Service Authorization Violations by Hour
```sql
SELECT 
  DATE_TRUNC('hour', timestamp) as hour,
  service_account,
  target_service,
  COUNT(*) as denied_count
FROM rbac_audit_log
WHERE allowed = false
GROUP BY DATE_TRUNC('hour', timestamp), service_account, target_service
ORDER BY hour DESC, denied_count DESC;
```

## Implementation Details

### Environment Variables Format
```bash
# Service can call these targets (host:port format)
SERVICE_NAME_ALLOWED_SERVICES="target1:port1,target2:port2,target3:port3"

# Service cannot call these targets
SERVICE_NAME_DENIED_SERVICES="forbidden1:port1,forbidden2:port2"

# Max requests per second for this service
SERVICE_NAME_RATE_LIMIT_QPS="100"
```

### Rate Limiting Algorithm
- **Algorithm**: Token Bucket
- **Burst Size**: 50 tokens (configurable)
- **Refill Rate**: 10 tokens/second (configurable)
- **Enforcement**: Per-service at Caddy middleware level

### JWT Claims Validated
- **iss** (Issuer): Must be `https://oidc.kushnir.cloud`
- **aud** (Audience): Must match target service name (e.g., "postgresql")
- **sub** (Subject): Service account identifier
- **exp** (Expiration): Token must not be expired
- **iat** (Issued At): Token issue time for cache validation

### Audit Log Schema
```sql
CREATE TABLE rbac_audit_log (
  id SERIAL PRIMARY KEY,
  timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  service_account VARCHAR(255) NOT NULL,  -- Source service
  request_service VARCHAR(255) NOT NULL,  -- Intermediate service
  target_service VARCHAR(255) NOT NULL,   -- Destination service
  action VARCHAR(50) NOT NULL,            -- GET, POST, DELETE, etc.
  resource_type VARCHAR(100),             -- Pod, ConfigMap, Secret, etc.
  resource_name VARCHAR(255),             -- Specific resource name
  permission VARCHAR(50) NOT NULL,        -- read, write, execute, etc.
  allowed BOOLEAN NOT NULL,               -- Authorization decision
  reason TEXT,                            -- Why allowed/denied
  source_ip VARCHAR(15),                  -- Source IP address
  trace_id VARCHAR(255) UNIQUE,           -- Correlation ID
  duration_ms INTEGER,                    -- Authorization check latency
  error_message TEXT                      -- Any error details
);
```

### Immutability Protection
```sql
-- Trigger prevents any modification of audit logs
CREATE FUNCTION prevent_audit_log_modification() RETURNS TRIGGER AS $$
BEGIN
  RAISE EXCEPTION 'RBAC audit logs are immutable - cannot modify existing records';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER prevent_audit_modification
BEFORE UPDATE OR DELETE ON rbac_audit_log
FOR EACH ROW
EXECUTE FUNCTION prevent_audit_log_modification();
```

## Monitoring & Observability

### Prometheus Metrics
- `rbac_decisions_total{action='allow|deny',service='...'}`
- `rbac_authorization_duration_seconds{service='...',percentile='p50|p95|p99'}`
- `rbac_cache_hits_total{service='...'}`
- `rbac_rate_limit_exceeded_total{service='...'}`

### Caddy Access Log Format
```
{
  "time": "2026-04-16T15:00:00Z",
  "request": {
    "method": "POST",
    "uri": "/api/v1/query"
  },
  "response": {
    "status": 200 | 401 | 403 | 429
  },
  "rbac": {
    "service_account": "code-server-sa",
    "target_service": "postgresql",
    "allowed": true,
    "reason": "Service authorized per policy",
    "duration_ms": 2.5
  }
}
```

## Testing Service-to-Service Calls

### Test Allowed Call (should succeed)
```bash
# From code-server to postgresql (allowed)
docker-compose exec -T code-server \
  curl -H "Authorization: Bearer $JWT_TOKEN" \
  -H "X-Request-ID: test-123" \
  http://postgresql:5432/health
# Expected: 200 OK or connection response
```

### Test Denied Call (should fail with 403)
```bash
# From code-server to alertmanager (denied)
docker-compose exec -T code-server \
  curl -H "Authorization: Bearer $JWT_TOKEN" \
  http://alertmanager:9093/api/alerts
# Expected: 403 Forbidden
```

### Verify Audit Log Entry
```bash
docker-compose exec -T postgresql psql -U postgres -d postgres \
  -c "SELECT * FROM rbac_audit_log WHERE service_account='code-server-sa' ORDER BY timestamp DESC LIMIT 1;"
```

## Operational Procedures

### Emergency: Grant Temporary Access
```bash
# 1. Add to allowed services temporarily
docker-compose exec -T postgresql psql -U postgres -d postgres \
  -c "UPDATE service_authorization_policies SET allowed_services='...,new_service' WHERE service='code-server';"

# 2. Monitor closely
tail -f docker-compose logs | grep "code-server"

# 3. Remove when done
docker-compose exec -T postgresql psql -U postgres -d postgres \
  -c "UPDATE service_authorization_policies SET allowed_services='...' WHERE service='code-server';"
```

### Debug Denied Access
```bash
# 1. Check service RBAC policy
grep "SERVICE_NAME_ALLOWED_SERVICES" .env.phase3

# 2. Check service logs
docker-compose logs -f code-server | grep "permission\|denied"

# 3. Query audit log for details
docker-compose exec -T postgresql psql -U postgres -d postgres \
  -c "SELECT * FROM rbac_audit_log WHERE allowed=false ORDER BY timestamp DESC LIMIT 5;"

# 4. Verify service network connectivity
docker network inspect code-server_to_postgresql
```

---

**Last Updated**: April 16, 2026  
**Phase**: Phase 3 - RBAC Enforcement  
**Status**: ✅ Complete (Docker-based implementation)
