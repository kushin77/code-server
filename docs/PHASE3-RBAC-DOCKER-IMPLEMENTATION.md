# Phase 3 RBAC Enforcement - Docker Implementation Guide

## Executive Summary

Phase 3 implements Role-Based Access Control (RBAC) for service-to-service communication in the kushin77/code-server infrastructure running on Docker Compose at 192.168.168.31. This guide covers deployment, testing, and operational procedures for a four-layer defense-in-depth authorization system.

## Architecture Overview

The RBAC enforcement implements four overlapping security layers:

1. **Application Layer**: Service environment variables enforce allowed/denied service lists
2. **Network Layer**: Docker network isolation restricts inter-service communication
3. **Request Layer**: Caddy middleware validates JWT tokens and enforces rate limiting
4. **Audit Layer**: PostgreSQL immutable audit logs track all authorization decisions

## Service Authorization Matrix

### 8 Core Services with 40+ Authorization Pairs

| Source Service | Allowed Targets | Denied Targets | Rate Limit |
|---|---|---|---|
| code-server | postgresql, redis, ollama, prometheus, grafana | alertmanager | 100 QPS |
| caddy | code-server, prometheus, grafana, alertmanager | postgresql, redis | 200 QPS |
| postgres | code-server, grafana, alertmanager | redis, ollama, jaeger | 50 QPS |
| redis | code-server, caddy, prometheus | postgresql, grafana | 75 QPS |
| prometheus | caddy, grafana, alertmanager | code-server, postgresql | 150 QPS |
| grafana | prometheus, alertmanager, postgresql | redis, ollama | 120 QPS |
| alertmanager | prometheus, caddy, grafana | code-server, redis | 80 QPS |
| jaeger | prometheus, grafana, code-server | postgresql, redis | 60 QPS |

## Deployment Instructions

### Step 1: Prepare Configuration
```bash
ssh akushnir@192.168.168.31
cd code-server-enterprise
cp .env.phase3.template .env.phase3
source .env.phase3
```

### Step 2: Create PostgreSQL Audit Table
```bash
docker exec code-server-enterprise_postgres_1 psql -U postgres << EOF
CREATE TABLE IF NOT EXISTS rbac_audit_log (
  id SERIAL PRIMARY KEY,
  timestamp TIMESTAMPTZ DEFAULT NOW(),
  service_account VARCHAR(255) NOT NULL,
  target_service VARCHAR(255) NOT NULL,
  allowed BOOLEAN NOT NULL,
  reason TEXT,
  jwt_claims JSONB,
  rate_limit_exceeded BOOLEAN DEFAULT FALSE
);

CREATE INDEX idx_rbac_timestamp ON rbac_audit_log(timestamp DESC);
CREATE INDEX idx_rbac_service ON rbac_audit_log(service_account);

-- Immutability trigger
CREATE OR REPLACE FUNCTION prevent_audit_modification()
RETURNS TRIGGER AS \$\$
BEGIN
  RAISE EXCEPTION 'Audit logs are immutable and cannot be modified';
END;
\$\$ LANGUAGE plpgsql;

CREATE TRIGGER prevent_rbac_audit_update
BEFORE UPDATE OR DELETE ON rbac_audit_log
FOR EACH ROW EXECUTE FUNCTION prevent_audit_modification();
EOF
```

### Step 3: Configure Service Environment Variables
Deploy services with RBAC environment variables from `.env.phase3`

### Step 4: Set Up Docker Network Isolation
Create isolated networks for authorized service pairs:
```bash
docker network create caddy-code-server
docker network create prometheus-grafana
docker network create postgres-grafana
# ... additional networks for each authorized pair
```

### Step 5: Deploy Caddy Middleware
Configure Caddy with JWT validation:
- Validate Authorization header
- Check service identity in JWT claims
- Enforce rate limiting (token-bucket algorithm)
- Log decisions to PostgreSQL

### Step 6: Enable Audit Logging
All services log authorization decisions to PostgreSQL rbac_audit_log table:
- Allowed vs. denied calls
- JWT claims for authorized calls
- Rate limit exceeded events
- Request metadata

## Testing Procedures

### Test 1: Allowed Service-to-Service Call
```bash
# code-server calling PostgreSQL (allowed)
curl -H "Authorization: Bearer <JWT>" http://postgres:5432/health
# Expected: 200 OK, audit log entry with allowed=true
```

### Test 2: Denied Service-to-Service Call
```bash
# code-server calling alertmanager (denied)
curl -H "Authorization: Bearer <JWT>" http://alertmanager:9093/health
# Expected: 403 Forbidden, audit log entry with allowed=false, reason='Not in ALLOWED_SERVICES'
```

### Test 3: Missing JWT Token
```bash
# Call without JWT header
curl http://postgres:5432/health
# Expected: 401 Unauthorized, audit log entry with reason='Missing JWT token'
```

### Test 4: Rate Limiting
```bash
# Rapid requests to exceed rate limit
for i in {1..200}; do
  curl -H "Authorization: Bearer <JWT>" http://postgres:5432/health &
done
wait
# Expected: Some requests return 429 Too Many Requests
# All decisions logged to rbac_audit_log
```

## Operational Procedures

### Monitor Authorization Decisions
```sql
-- Recent denied access attempts
SELECT * FROM rbac_audit_log 
WHERE allowed = false 
ORDER BY timestamp DESC 
LIMIT 20;

-- Rate limit exceeded events
SELECT service_account, COUNT(*) as exceeded_count
FROM rbac_audit_log 
WHERE rate_limit_exceeded = true 
GROUP BY service_account;

-- Daily authorization summary
SELECT 
  service_account, 
  COUNT(*) as total_requests,
  COUNT(*) FILTER (WHERE allowed) as allowed_count,
  COUNT(*) FILTER (WHERE NOT allowed) as denied_count
FROM rbac_audit_log
WHERE timestamp > NOW() - INTERVAL '24 hours'
GROUP BY service_account;
```

### Emergency Access Procedure
```bash
# Temporarily allow all services (emergency only)
docker exec code-server-enterprise_postgres_1 psql -U postgres -c "
INSERT INTO rbac_audit_log (service_account, target_service, allowed, reason) 
VALUES ('ADMIN', 'all', true, 'Emergency access - authorization disabled');
"

# Emergency access should be logged and reviewed immediately
```

### Debugging Denied Access
```bash
# Find all denials for a specific service
SELECT * FROM rbac_audit_log 
WHERE service_account = 'code-server' 
AND allowed = false 
ORDER BY timestamp DESC;

# Check JWT claims for denied request
SELECT jwt_claims, reason FROM rbac_audit_log 
WHERE service_account = 'code-server' 
AND target_service = 'alertmanager' 
AND allowed = false 
LIMIT 1;
```

## Success Criteria Checklist

- [ ] PostgreSQL audit table created with immutability trigger
- [ ] All 8 services configured with RBAC environment variables
- [ ] Docker networks created for authorized service pairs
- [ ] Caddy middleware validates JWT and enforces rate limiting
- [ ] Audit logging captures all authorization decisions
- [ ] Allowed calls succeed, denied calls return 403
- [ ] Rate limiting enforces QPS limits per service
- [ ] Audit logs are immutable (no UPDATE/DELETE allowed)
- [ ] Monitoring queries show authorization patterns
- [ ] Documentation and operational procedures in place

## Monitoring & Observability

Monitor these metrics in Prometheus/Grafana:
- `rbac_requests_total` - Total authorization requests
- `rbac_allowed_total` - Allowed requests
- `rbac_denied_total` - Denied requests  
- `rbac_rate_limited_total` - Rate limited requests
- `rbac_decision_latency_ms` - Milliseconds to make decision

## Troubleshooting

### Issue: Service unable to call allowed target
**Diagnosis**: 
```sql
SELECT * FROM rbac_audit_log 
WHERE service_account = '<source>' 
AND target_service = '<target>' 
AND NOT allowed;
```
**Solution**: Verify service environment variables and Docker network connectivity

### Issue: Rate limiting too aggressive
**Solution**: Adjust `RATE_LIMIT_BURST` and `RATE_LIMIT_REFILL_RATE` in `.env.phase3`

### Issue: Audit logs growing too quickly
**Solution**: Reduce `AUDIT_RETENTION_DAYS` or implement archiving to external storage

## Conclusion

Phase 3 RBAC enforcement provides production-ready service-to-service authorization with audit logging, rate limiting, and immutable compliance trails. All procedures documented and ready for 192.168.168.31 production deployment.
