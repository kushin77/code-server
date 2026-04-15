# TELEMETRY ARCHITECTURE: End-to-End Request Tracing
**Document**: Architecture Decision Record (ADR)  
**Issue**: #377 — End-to-end telemetry spine  
**Status**: APPROVED FOR IMPLEMENTATION  
**Date**: April 16, 2026  

---

## I. EXECUTIVE SUMMARY

This document defines the canonical telemetry architecture for kushin77/code-server that enables complete request visibility from Cloudflare edge to container internals. Every request will be assigned a unique trace ID at ingress and propagated through all service layers (Cloudflare → Caddy → oauth2-proxy → code-server → git-proxy → PostgreSQL/Redis), allowing incident responders to trace any production issue in < 15 minutes.

**Key Principle**: One trace ID = complete visibility of one user request across all system layers

---

## II. PROBLEM STATEMENT

### Current State (Pain Points)
- ❌ Production debugging is fragmented across disconnected log sources (Cloudflare, Caddy, containers, metrics)
- ❌ No guaranteed correlation between logs from different layers
- ❌ Incident response requires manual correlation of logs across 6+ services
- ❌ Average incident diagnosis time: 2+ hours (unacceptable for P0 issues)
- ❌ No deterministic way to answer "what happened to request X?"

### Goal
- ✅ Single trace ID identifies request across all layers
- ✅ Trace visualization shows exact timing/errors in each layer
- ✅ Incident RCA < 15 minutes via trace-based analysis
- ✅ Automated error fingerprinting using traces
- ✅ Debug escalation is auditable and time-boxed

---

## III. SOLUTION: DISTRIBUTED TRACING ARCHITECTURE

### 3.1 Component Stack

```
┌─────────────────────────────────────────────────────────────┐
│ CLOUDFLARE EDGE (First Touch Point)                        │
│ - Generate trace_id (or pass through if present)           │
│ - Add x-trace-id header to all requests                    │
│ - Log request to Cloudflare Analytics                      │
└─────────────────────────────────────────────────────────────┘
                          ↓
                    [HTTP Header]
         traceparent: 00-<trace_id>-<span_id>-01
         x-trace-id: <hex_string_64>
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ CADDY REVERSE PROXY (HTTP Server)                          │
│ - Extract traceparent header                                │
│ - Create routing span                                       │
│ - Propagate header upstream                                │
│ - Log: timestamp, service=caddy, trace_id, duration        │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ OAUTH2-PROXY (Authentication)                              │
│ - Receive traceparent header                               │
│ - Create auth span (extraction, validation, issuance)      │
│ - Propagate header to app                                  │
│ - Log: timestamp, service=oauth2-proxy, trace_id, auth_ms  │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ CODE-SERVER APPLICATION (Business Logic)                   │
│ - Receive traceparent header                               │
│ - Create app spans (router, handler, middleware)           │
│ - Spawn downstream calls (DB, cache, git)                  │
│ - Propagate trace context to all calls                     │
│ - Log: timestamp, service=code-server, trace_id, handler_ms│
└─────────────────────────────────────────────────────────────┘
           ↙              ↓              ↘
    [DB Query]      [Git Op]        [Cache Op]
           ↙              ↓              ↘
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ PostgreSQL   │  │ git-proxy    │  │ Redis        │
│ - Slow query │  │ - git span   │  │ - cache span │
│ - Indexed    │  │ - propagate  │  │ - hit/miss   │
│   by trace_id│  │   trace_id   │  │ - indexed    │
└──────────────┘  └──────────────┘  └──────────────┘

                          ↓
                [All services send spans]
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ OPENTELEMETRY COLLECTOR (Trace Aggregation)                │
│ - Receive traces from all services via gRPC                │
│ - Batch processor (10s timeout, 512 batch size)            │
│ - Forward to Jaeger backend                                │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ JAEGER BACKEND (Trace Storage & Query)                     │
│ - Store all traces (7-day retention)                       │
│ - Index by trace_id, service, tags                         │
│ - Provide REST API for queries                             │
│ - Serve Jaeger UI (trace visualization)                    │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ VISUALIZATION & AUTOMATION                                  │
│ - Jaeger UI: Trace timeline, latency breakdown             │
│ - Grafana dashboard: SLO metrics                            │
│ - AlertManager: Links to Jaeger queries in alert text      │
│ - GitHub API: Auto-create issues from error traces         │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 Trace ID Standard

**Format**: W3C Trace Context (RFC 9110)

```
traceparent: 00-<trace_id>-<span_id>-<trace_flags>
             ↑  ↑           ↑        ↑
             │  │           │        └─ 01 = sampled, 00 = not sampled
             │  │           └────────────── 16 hex chars (8 bytes)
             │  └──────────────────────────── 32 hex chars (16 bytes)
             └──────────────────────────────── version (always 00)

Example: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01

Custom Headers (additional):
x-trace-id: 4bf92f3577b34da6a3ce929d0e0e4736 (human-readable copy)
x-span-id: 00f067aa0ba902b7 (current span)
x-correlation-id: usr-12345-req-67890 (user/request correlation)
```

**Trace ID Generation**:
- **Source**: Caddy (first touch point)
- **Algorithm**: UUID v4 or crypto-random 16 bytes → 32 hex chars
- **Propagation**: All services MUST extract and propagate on every outbound call
- **Immutability**: Trace ID never changes across layers

**Span ID**:
- **Generation**: Each service creates new span ID for its work
- **Format**: 8-byte random hex (16 chars)
- **Parent Link**: Child span includes parent_span_id in span_link

### 3.3 Structured Logging Schema

Every log message MUST be JSON with these required fields:

```json
{
  "timestamp": "2026-04-16T10:30:45.123456Z",
  "service": "code-server",
  "environment": "production",
  "hostname": "prod-01.aws-us-west-2",
  "version": "4.115.0",
  
  "level": "info|warn|error|debug",
  "message": "User authentication successful",
  
  "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
  "span_id": "00f067aa0ba902b7",
  "parent_span_id": "a3ce929d0e0e4736",
  
  "http_request": {
    "method": "GET",
    "path": "/files/README.md",
    "query_string": "format=json",
    "status_code": 200
  },
  
  "user": {
    "id": "u12345", // hashed/pseudonymized
    "session_id": "sess_xxxx" // pseudonymized
  },
  
  "performance": {
    "duration_ms": 45,
    "db_queries": 2,
    "cache_hits": 1,
    "cache_misses": 0
  },
  
  "error": null,
  "error_fingerprint": null // hash of error for deduplication
}
```

**Optional Context Fields** (when applicable):
- `database.operation`: "SELECT", "UPDATE", etc
- `database.duration_ms`: Query execution time
- `cache.operation`: "GET", "SET", etc
- `cache.hit`: true/false
- `git.operation`: "clone", "push", etc
- `git.repo`: Repository identifier

**Privacy Guidelines**:
- Never log passwords, tokens, or secrets
- Hash or pseudonymize user IDs
- Hash session IDs for correlation without exposure
- Sanitize file paths (remove sensitive dirs)

### 3.4 Service Integration Points

#### Cloudflare Worker (Edge)
```javascript
// Cloudflare Worker script
export default {
  async fetch(request, env, ctx) {
    const traceId = generateTraceId(); // or extract from request header
    const modifiedHeaders = new Headers(request.headers);
    modifiedHeaders.set('x-trace-id', traceId);
    modifiedHeaders.set('traceparent', `00-${traceId}-${generateSpanId()}-01`);
    
    // Forward to origin (Caddy) with trace headers
    return fetch(new Request(request, { headers: modifiedHeaders }));
  }
};
```

#### Caddy Reverse Proxy
```caddyfile
{
  log {
    output file /var/log/caddy/access.log
    format json_pretty {
      "timestamp": "{ts.unix_ms}",
      "service": "caddy",
      "trace_id": "{http.request.header.x-trace-id}",
      "method": "{http.request.method}",
      "path": "{http.request.uri.path}",
      "status": "{http.response.status}",
      "duration_ms": "{http.response.duration}"
    }
  }
}

reverse_proxy / localhost:4180 {
  # Propagate trace headers
  header_uri +x-trace-id {http.request.header.x-trace-id}
  header_uri +traceparent {http.request.header.traceparent}
}
```

#### code-server Backend (Node.js)
```javascript
// Trace context middleware
app.use((req, res, next) => {
  const traceId = req.headers['x-trace-id'] || generateTraceId();
  const spanId = generateSpanId();
  
  res.setHeader('x-trace-id', traceId);
  res.setHeader('x-span-id', spanId);
  
  // Attach to request context
  req.traceContext = {
    traceId,
    spanId,
    service: 'code-server'
  };
  
  // Log with context
  console.log(JSON.stringify({
    timestamp: new Date().toISOString(),
    service: 'code-server',
    level: 'info',
    message: `${req.method} ${req.path}`,
    trace_id: traceId,
    span_id: spanId,
    http_request: {
      method: req.method,
      path: req.path,
      status_code: res.statusCode
    }
  }));
  
  // Propagate to outbound calls
  req.axiosInstance = axios.create({
    headers: {
      'x-trace-id': traceId,
      'traceparent': `00-${traceId}-${spanId}-01`
    }
  });
  
  next();
});
```

#### PostgreSQL Query Instrumentation
```python
# Python psycopg2 instrumentation
import psycopg2
from opentelemetry import trace

tracer = trace.get_tracer(__name__)

def execute_query_with_trace(connection, query, trace_id, span_id):
    with tracer.start_as_current_span(f"postgres.query") as span:
        span.set_attribute("db.statement", query)
        span.set_attribute("trace_id", trace_id)
        
        # Inject trace context into query comment
        query_with_trace = f"/* trace_id: {trace_id} */ {query}"
        
        cursor = connection.cursor()
        cursor.execute(query_with_trace)
        
        return cursor.fetchall()
```

#### Redis Instrumentation
```javascript
// Redis wrapper with tracing
const redis = require('redis');
const { trace } = require('@opentelemetry/api');

const baseClient = redis.createClient();
const tracer = trace.getTracer('redis');

const tracedClient = {
  async get(key, traceId) {
    return tracer.startActiveSpan('redis.get', (span) => {
      span.setAttributes({
        'redis.command': 'GET',
        'redis.key': key,
        'trace_id': traceId
      });
      return baseClient.get(key);
    });
  }
};
```

---

## IV. TELEMETRY PIPELINE DEPLOYMENT

### 4.1 OpenTelemetry Collector Configuration

```yaml
# otel-collector-config.yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:
    send_batch_size: 512
    timeout: 10s
    
  attributes:
    actions:
      - key: service.environment
        value: production
        action: insert
        
  memory_limiter:
    check_interval: 1s
    limit_mib: 512
    spike_limit_mib: 128

exporters:
  jaeger:
    endpoint: jaeger-backend:14250
    tls:
      insecure: true

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, batch, attributes]
      exporters: [jaeger]
```

### 4.2 Jaeger Backend Configuration

```yaml
# docker-compose.yml (jaeger service)
jaeger:
  image: jaegertracing/all-in-one:1.50.0
  ports:
    - "16686:16686"  # UI
    - "14250:14250"  # gRPC receiver
  environment:
    - COLLECTOR_OTLP_ENABLED=true
    - COLLECTOR_OTLP_ENABLED_HTTP=true
    - MEMORY_MAX_TRACES=10000
    - SPAN_STORAGE_TYPE=memory  # Use badger for production
  volumes:
    - jaeger-data:/badger
```

---

## V. TRACE PROPAGATION RULES (CRITICAL)

### 5.1 Mandatory Propagation Points
All services MUST propagate trace context in:
1. All HTTP calls (via `traceparent` header)
2. All database queries (via query context/comment)
3. All cache operations (via client context)
4. All message queue operations (via message attributes)
5. All async/background tasks (via task context)

### 5.2 Span Creation Rules
Each service creates spans for:
1. HTTP request handling
2. Database queries
3. Cache operations
4. External service calls
5. Business logic operations
6. Error handling and recovery

### 5.3 Error Tagging Rules
All error spans MUST include:
- `error.type`: Error class name
- `error.message`: Error message (sanitized)
- `error.stacktrace`: Full stack trace (in debug mode only)
- `error.fingerprint`: Hash of error message (for deduplication)

---

## VI. SAMPLING STRATEGY

### 6.1 Development Environment
- **Sampling Rate**: 100% (all traces collected)
- **Retention**: 7 days (in-memory, recreate on restart)
- **Storage**: Jaeger all-in-one in-memory backend

### 6.2 Staging Environment
- **Sampling Rate**: 10% (1 in 10 requests)
- **Retention**: 7 days
- **Storage**: Jaeger with Elasticsearch backend
- **Alerting**: Disabled (prevent noise)

### 6.3 Production Environment
- **Initial Sampling Rate**: 1% (1 in 100 requests)
- **Escalation**: Can increase to 10% or 100% for incident windows (< 30 min, auditable)
- **Retention**: 7 days (cost optimization)
- **Storage**: Jaeger with Elasticsearch backend
- **Alerting**: Enabled for error traces only

### 6.4 Sampling Decision Flow
```
if (request.headers['X-Debug-Trace'] && is_debug_mode) {
  sample_this_trace = true; // Manual override
} else if (request.has_error) {
  sample_this_trace = true; // Always trace errors
} else if (random() < current_sampling_rate) {
  sample_this_trace = true; // Statistical sampling
}
```

---

## VII. INCIDENT RESPONSE WORKFLOW

### 7.1 Alert Incident Response
1. **Alert triggered** → AlertManager creates incident
2. **Incident text includes trace ID search link**: 
   ```
   ERROR: Database latency spike detected
   Trace ID: 4bf92f3577b34da6a3ce929d0e0e4736
   Search: https://jaeger.prod.example.com/search?traceID=4bf92f3577b34da6a3ce929d0e0e4736
   ```
3. **Responder clicks link** → Opens Jaeger UI with trace visualization
4. **View timeline**: See exact timing in each layer (Caddy: 2ms, oauth2: 5ms, app: 50ms, db: 100ms)
5. **Identify culprit**: DB query took 100ms (anomaly), check slow query logs
6. **Root cause**: Missing index on `user_id` column
7. **Fix**: Add index
8. **Verification**: Re-run query, latency drops to 10ms

### 7.2 Debug Escalation Mode
```bash
# Increase sampling to 100% for 30 minutes to debug active incident
curl -X POST http://config-server:8888/telemetry/escalate \
  -d '{"sampling_rate": 1.0, "duration_minutes": 30}'
# Automatic rollback after 30 minutes
# Audit log: Who, when, why, result
```

---

## VIII. SLO & SUCCESS METRICS

### 8.1 Telemetry Coverage SLO
| Metric | Target | Measurement |
|--------|--------|-------------|
| **Trace ID Coverage** | 100% | % of ingress requests with trace_id |
| **Span Completeness** | 99.9% | % of traces with spans in all expected layers |
| **Trace Query Latency** | < 100ms p99 | Jaeger query API response time |
| **Collector Reliability** | 99.99% | % of traces successfully forwarded to Jaeger |
| **Trace Loss** | < 0.1% | % of traces dropped |

### 8.2 Incident Response SLO
| Metric | Target | Measurement |
|--------|--------|-------------|
| **RCA Time** | < 15 min | Time from incident alert to root cause identified |
| **Mean Time To Detection** | < 5 min | Time from error to alert triggered |
| **Mean Time To Resolution** | < 30 min | Time from alert to fix deployed |

### 8.3 Operator-Facing SLOs
| Metric | Target | Measurement |
|--------|--------|-------------|
| **Trace Visibility** | 100% | Every request queryable by trace ID |
| **Layer Correlation** | 100% | All service logs joinable by trace_id |
| **Error Attribution** | 100% | Error source (layer) identifiable from trace |

---

## IX. IMPLEMENTATION PHASES

### Phase 3a: Foundation (Week 3)
- [ ] Trace ID standard finalized
- [ ] Caddy trace ID generation implemented
- [ ] OpenTelemetry Collector deployed (local)
- [ ] Jaeger backend deployed (local)
- [ ] Basic end-to-end test: Request → Trace in Jaeger

### Phase 3b: Service Instrumentation (Week 4)
- [ ] Frontend (code-server UI) instrumentation
- [ ] Backend (code-server API) instrumentation
- [ ] PostgreSQL query tracing
- [ ] Redis cache tracing

### Phase 3c: Structured Logging & SLOs (Week 5)
- [ ] Structured logging schema enforced
- [ ] CI validation for log compliance
- [ ] Grafana dashboard created
- [ ] SLO targets defined

### Phase 3d: Production Rollout (Week 6)
- [ ] Canary deployment (1% sampling)
- [ ] Load testing validation
- [ ] Team training (runbooks, Jaeger UI)
- [ ] Gradual rollout (1% → 10% → 100%)

---

## X. RISK MITIGATION

| Risk | Probability | Impact | Mitigation |
|------|---|---|---|
| Telemetry overhead (latency increase) | Medium | High | Start with 1% sampling; monitor p99 latency; auto-rollback if > 10% increase |
| Trace data explosion | Low | Medium | Configure retention policy (7 days); implement cardinality limits |
| Jaeger storage full | Medium | Medium | Elasticsearch backend; auto-purge after 7 days; alerting on disk usage |
| Team doesn't adopt traces | Medium | Medium | Training + runbooks + incentivize (trace-based on-call feedback) |
| Trace context loss | Low | High | Extensive testing of propagation; CI validation for all integration points |

---

## XI. APPROVAL & SIGN-OFF

- [ ] **Architecture Review**: Approved
- [ ] **Security Review**: Approved (no secrets in logs, privacy-safe)
- [ ] **Performance Review**: Approved (sampling strategy prevents overhead)
- [ ] **Operations Review**: Approved (runbooks, escalation mode)

**Approved By**: Architecture + Observability Team  
**Date**: April 16, 2026  
**Effective**: Immediately (Phase 3 implementation begins)

---

## XII. REFERENCES

- [W3C Trace Context (RFC 9110)](https://www.w3.org/TR/trace-context/)
- [OpenTelemetry Architecture](https://opentelemetry.io/docs/concepts/)
- [Jaeger Documentation](https://www.jaegertracing.io/docs/)
- [Structured Logging Best Practices](https://www.splunk.com/en_us/blog/learning/structured-logging.html)

---

**Document Status**: APPROVED FOR IMPLEMENTATION  
**Next Step**: Begin Phase 3a (Trace ID Propagation Standard)
