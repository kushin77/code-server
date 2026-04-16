# End-to-End Telemetry Architecture (Issue #377)

**Status**: IMPLEMENTATION IN PROGRESS  
**Effort**: 4-6 weeks  
**Priority**: P0  
**Owner**: Observability Team  

---

## 1. OVERVIEW

Implements global debug telemetry spine from Cloudflare edge through reverse proxy, auth layer, application, and database with mandatory correlation IDs enabling incident response < 5 minutes via trace-driven root cause analysis.

## 2. CORRELATION ID STANDARD

### 2.1 Trace ID Format and Propagation

**Standard**: UUID v4 (36 bytes including hyphens)
```
Format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
Example: a1b2c3d4-e5f6-4789-8abc-def012345678
```

**Generation Points**:
1. **Cloudflare Edge** (primary generator):
   - If `cf-ray` header absent: generate new UUID v4
   - Otherwise: use first 8 chars of `cf-ray` + random suffix
   - Set `x-trace-id` header in origin request

2. **Caddy Reverse Proxy** (pass-through):
   - If `x-trace-id` exists: preserve
   - Otherwise: generate new UUID v4
   - Add to all upstream requests

3. **Application Entry Points** (validate + propagate):
   - Extract `x-trace-id` from request headers
   - If missing: generate new
   - Inject into request context (thread-local or request scope)
   - Add to all downstream requests (databases, caches, services)

### 2.2 Header Propagation Chain

```
Edge (Cloudflare)
    ↓ x-trace-id
Ingress (Caddy)
    ↓ x-trace-id, x-request-id
Auth (oauth2-proxy)
    ↓ x-trace-id, x-request-id, x-user-id (hashed)
Application (code-server, git-proxy)
    ↓ x-trace-id, x-request-id, x-user-id
Services (PostgreSQL, Redis, git backend)
    ↓ trace-id in connection context / query parameters
```

### 2.3 Required Headers

| Header | Source | Destination | Format | Required |
|--------|--------|-------------|--------|----------|
| `x-trace-id` | Cloudflare/Caddy | All services | UUID v4 | YES |
| `x-request-id` | Caddy | Auth/App | UUID v4 | Optional (Caddy auto-gen) |
| `x-user-id` | oauth2-proxy | App services | SHA256(user_id) | Optional |
| `x-session-id` | code-server | Internal | Session UUID | Optional |
| `x-span-id` | Any service | Logs | UUID v4 | Optional (for sub-operations) |

---

## 3. STRUCTURED LOGGING SCHEMA

### 3.1 Canonical Log Fields

Every log message MUST contain:

```json
{
  "timestamp": "2026-04-15T17:47:51.123456Z",
  "level": "info",
  "service": "code-server",
  "region": "us-west-1",
  "host": "prod.ide.internal",
  "environment": "production",
  "trace_id": "a1b2c3d4-e5f6-4789-8abc-def012345678",
  "span_id": "span-001",
  "request_id": "req-789",
  "request_path": "/v1/workspaces",
  "request_method": "GET",
  "user_id_hash": "sha256(user123)",
  "session_id": "sess-xyz",
  "status_code": 200,
  "duration_ms": 145,
  "message": "Request completed successfully",
  "error_fingerprint": "",
  "context": {}
}
```

### 3.2 Field Definitions

| Field | Type | Required | Description | Privacy |
|-------|------|----------|-------------|---------|
| `timestamp` | ISO 8601 | YES | Exact moment of log event | Safe |
| `level` | enum: debug,info,warn,error,fatal | YES | Log severity | Safe |
| `service` | string | YES | Service name (code-server, git-proxy, oauth2-proxy, caddy) | Safe |
| `region` | string | YES | Deployment region | Safe |
| `host` | string | YES | Hostname (not IP address) | Safe |
| `environment` | string | YES | production, staging, dev | Safe |
| `trace_id` | UUID | YES | Global correlation ID | Safe |
| `span_id` | string | NO | Sub-operation ID (useful for chunked logging) | Safe |
| `request_id` | UUID | NO | Request-specific ID for correlation | Safe |
| `request_path` | string | YES | URL path (not query params) | Safe |
| `request_method` | enum: GET,POST,PUT,DELETE,PATCH | YES | HTTP method | Safe |
| `user_id_hash` | SHA256 | NO | Hashed user ID (never plain text) | Safe |
| `session_id` | UUID | NO | Session UUID | Safe |
| `status_code` | int (100-599) | YES (for requests) | HTTP response code | Safe |
| `duration_ms` | int | YES (for requests) | Milliseconds to complete | Safe |
| `message` | string | YES | Human-readable message | Safe |
| `error_fingerprint` | string | YES (on error) | Deterministic error hash for grouping | Safe |
| `context` | object | NO | Additional structured context | Depends on content |

### 3.3 Logging Integration Examples

#### Node.js (code-server)
```javascript
const { createLogger } = require('./telemetry/logger');

const logger = createLogger({
  service: 'code-server',
  region: process.env.REGION,
  environment: process.env.ENV
});

// In request handler
app.use((req, res, next) => {
  const traceId = req.headers['x-trace-id'] || generateUUID();
  res.setHeader('x-trace-id', traceId);
  
  logger.info('Request received', {
    trace_id: traceId,
    request_path: req.path,
    request_method: req.method,
    user_id_hash: hashUserId(req.user?.id)
  });
  
  next();
});
```

#### Python (git-proxy)
```python
import logging
import json
from telemetry.logger import StructuredLogger

logger = StructuredLogger(
    service='git-proxy',
    region=os.getenv('REGION'),
    environment=os.getenv('ENV')
)

@app.before_request
def log_request():
    trace_id = request.headers.get('x-trace-id', generate_uuid())
    request.trace_id = trace_id
    
    logger.info('Request received', {
        'trace_id': trace_id,
        'request_path': request.path,
        'request_method': request.method,
        'user_id_hash': hash_user_id(current_user.id) if current_user else None
    })
```

#### SQL Queries (PostgreSQL)
```sql
-- Include trace ID in query comments for execution logs
SELECT * FROM workspaces
WHERE user_id = :user_id
  /* trace_id: a1b2c3d4-e5f6-4789-8abc-def012345678 */;
```

---

## 4. TELEMETRY PIPELINE ARCHITECTURE

### 4.1 Log Collection Flow

```
Service Logs (JSON stdout)
    ↓ (Docker/Kubernetes log driver)
Fluentd / Fluent Bit (collector)
    ↓ (parse JSON, extract trace_id)
Log Aggregation (Loki or ELK)
    ↓ (indexed by trace_id)
Jaeger (trace visualization)
    ↓ (query by trace_id)
Grafana Dashboards
```

### 4.2 Metrics Pipeline

```
Service Metrics (Prometheus format)
    ↓ (scrape on :9090)
Prometheus (time-series db)
    ↓ (queried by trace_id when available)
Grafana Dashboards (latency, error rate, SLOs)
```

### 4.3 Trace Pipeline

```
Application Instrumentation (OpenTelemetry SDK)
    ↓ (emit spans with trace_id)
Jaeger Collector (:14268)
    ↓ (batch and store)
Jaeger Backend (storage: Elasticsearch or in-memory)
    ↓ (UI: query by trace_id)
Jaeger UI (:16686)
```

---

## 5. DEBUG PROFILE CONTROLS

### 5.1 Log Levels by Environment

| Environment | Default Level | Max Debug Duration | Escalation Required |
|-------------|---------------|-------------------|---------------------|
| Production | `info` | 5 minutes | On-call engineer + audit log |
| Staging | `debug` | Unlimited | None |
| Development | `debug` | Unlimited | None |

### 5.2 Runtime Debug Escalation

**Procedure**: Operator enables debug logging for specific service/trace_id
```bash
# Escalate debug for specific trace ID (5 min auto-revert)
curl -X POST http://localhost:9090/debug/escalate \
  -d '{"trace_id": "a1b2c3d4...", "duration_seconds": 300, "reason": "incident-xyz"}'

# Result: all logs for this trace_id emit at DEBUG level
# Auto-revert at timestamp + 300s
# Audit log: who, when, why, duration
```

**Guardrails**:
- Max escalation: 30 minutes (then manual admin override needed)
- Escalations logged to audit trail with operator name
- Dashboard shows active escalations in real-time
- Auto-disable if error rate spikes > 5%

---

## 6. SLO & TRIAGE OUTPUTS

### 6.1 Latency Decomposition Dashboard

Query traces by trace_id and break down latency by layer:

```
Total: 450ms

Cloudflare Edge → Origin: 120ms
  ↓
Caddy Ingress → oauth2-proxy: 80ms
  ↓
oauth2-proxy → code-server: 150ms
  ↓
code-server → PostgreSQL: 80ms
  ↓
PostgreSQL Response: 20ms
```

**Implementation**: Jaeger Service Dependency Graph + custom Grafana panels

### 6.2 Error Attribution by Layer

```
errors_by_layer{trace_id="xxx"} = {
  "cloudflare": 0,
  "caddy": 0,
  "oauth2_proxy": 0,
  "code_server": 1,  ← Error originated here
  "postgres": 0
}
```

### 6.3 Incident Triage Workflow

1. **Detect**: Alert fires (e.g., error rate > 1%)
2. **Trace**: Use trace_id from logs to access trace details
3. **Decompose**: Identify which layer introduced latency/error
4. **Escalate**: Use debug profile to get detailed logs if needed
5. **Resolve**: Issue fix or rollback
6. **Verify**: Confirm trace shows resolution

---

## 7. IMPLEMENTATION PHASES

### Phase 1 (Week 1-2): Correlation ID Infrastructure
- [ ] Add trace_id generation to Cloudflare Tunnel config
- [ ] Add header pass-through to Caddy config
- [ ] Update all service code to extract/propagate trace_id
- [ ] Test with manual trace walks (e.g., curl with debug tracing)

### Phase 2 (Week 2-3): Structured Logging
- [ ] Create logging libraries for each language (Node/Python/Bash)
- [ ] Refactor existing log statements to use schema
- [ ] Add CI validation for log schema compliance
- [ ] Deploy to production (non-breaking change)

### Phase 3 (Week 3-4): Telemetry Pipeline
- [ ] Deploy Jaeger collector
- [ ] Configure Prometheus scraping
- [ ] Connect log aggregation (Loki)
- [ ] Test query joins by trace_id

### Phase 4 (Week 4-5): Dashboards & Controls
- [ ] Build Grafana latency decomposition dashboard
- [ ] Implement debug escalation API
- [ ] Create incident runbook with trace-driven triage
- [ ] Document for engineering team

### Phase 5 (Week 5-6): Testing & Validation
- [ ] Load test to ensure trace overhead is < 1%
- [ ] Verify 100% trace coverage on production traffic
- [ ] Run chaos test and confirm trace-led incident response works
- [ ] Get sign-off from SRE team

---

## 8. SUCCESS CRITERIA

✅ **100% trace coverage**: Every request from Cloudflare through all layers has trace_id  
✅ **< 5 min triage**: Engineer can perform root cause analysis on any issue using single trace_id  
✅ **Schema validation**: CI blocks logging code that doesn't follow schema  
✅ **Zero-impact overhead**: Trace propagation adds < 1% latency  
✅ **Auditable controls**: Every debug escalation is logged with operator identity  
✅ **Layer attribution**: Dashboard clearly shows which layer contributed to latency/error  

---

## 9. RELATED DOCUMENTATION

- [PRODUCTION-STANDARDS.md](../PRODUCTION-STANDARDS.md) - Observability pillar
- [Alert Rules (SLOs)](../alert-rules.yml) - Alert thresholds
- [Incident Runbook](../docs/runbooks/INCIDENT-RESPONSE.md) - Triage procedures
- Issue #378 (Error fingerprinting) - Auto-triage using error_fingerprint field

---

**Document Owner**: Observability Team  
**Last Updated**: April 15, 2026  
**Next Review**: May 1, 2026 (after Phase 1 completion)
