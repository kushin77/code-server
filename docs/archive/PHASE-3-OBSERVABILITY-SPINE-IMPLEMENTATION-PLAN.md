# PHASE 3: END-TO-END TELEMETRY SPINE — Implementation Plan
**Issue**: #377  
**Status**: STARTING  
**Timeline**: Weeks 3-6 (April 16-May 13, 2026)  
**Effort**: 4-6 weeks  

---

## EXECUTIVE SUMMARY

Implement a global debug telemetry spine from Cloudflare edge to container internals, with mandatory correlation IDs and consistent structured log schema. This enables incident response < 15 minutes by ensuring every request can be traced across all layers: Cloudflare → Caddy → oauth2-proxy → code-server → git-proxy → PostgreSQL/Redis.

**Success Criterion**: Single `trace_id` queryable across 6 service layers for complete request visibility

---

## PHASE 3 ACCEPTANCE CRITERIA (FROM #377)

- [ ] 100% ingress requests receive/propagate correlation ID
- [ ] Cloudflare→Caddy→oauth2→app→data chain queryable by single trace ID
- [ ] Structured schema validation enforced in CI for logging integrations
- [ ] Incident runbook supports trace-led root cause in < 5 minutes
- [ ] Debug escalation mode is auditable, timebound, and auto-reverting
- [ ] Dashboard shows layer-by-layer latency and error contribution

---

## ARCHITECTURE OVERVIEW

### Components
```
[Cloudflare Edge]
        ↓ (propagate trace_id header)
[Caddy Reverse Proxy]
        ↓ (add routing metrics)
[oauth2-proxy]
        ↓ (add auth metrics)
[code-server App]
        ↓ (add application metrics)
[git-proxy]
        ↓ (add git operation metrics)
[PostgreSQL] + [Redis]
        ↓ (send structured logs)
[OpenTelemetry Collector]
        ↓
[Jaeger Backend] → [Query API] → [Dashboard + API]
```

### Key Components

1. **Trace ID Generation**
   - Format: `trace_id` header (standard: UUID v4 or 16-byte hex)
   - Source: Cloudflare Worker or Caddy (first touch point)
   - Propagation: W3C Trace Context standard (traceparent header)

2. **OpenTelemetry Instrumentation**
   - Frontend: `@opentelemetry/web` + `@opentelemetry/auto-instrumentations-node`
   - Backend: Python OpenTelemetry SDK (if applicable)
   - Databases: PostgreSQL query instrumentation via pyscopg2
   - Cache: Redis instrumentation via redis-py wrapper

3. **Centralized Collection**
   - OpenTelemetry Collector (Docker container)
   - Receives traces from all services via gRPC
   - Batch processor (reduce overhead)
   - Export to Jaeger backend

4. **Storage & Visualization**
   - Jaeger backend (ElasticSearch or in-memory for staging)
   - Jaeger UI for trace visualization
   - Query API for programmatic access (for incident automation)

5. **Structured Logging**
   - JSON schema for all logs
   - Required fields: timestamp, service, trace_id, span_id, level, message
   - Context propagation via correlation IDs

---

## DETAILED IMPLEMENTATION PLAN

### TASK 1: Trace ID Propagation Standard (Days 1-3)

**Deliverables**:
- [ ] Architecture document defining trace/correlation header format
- [ ] HTTP header standard (W3C Trace Context + custom headers)
- [ ] Caddy configuration to generate and propagate trace IDs
- [ ] Test suite for header propagation across all layers

**Implementation**:

1. **Header Standard Definition**:
   - Primary: `traceparent` (W3C standard): `00-trace_id-span_id-sampled`
   - Custom: `x-correlation-id` (human-readable, 64 hex chars from trace_id)
   - Format: trace_id = 16-byte hex (32 chars), span_id = 8-byte hex (16 chars)
   - Example: `traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01`

2. **Caddy Configuration**:
   - Add trace ID generation middleware
   - Propagate headers to all upstream services
   - Log trace ID in access logs

3. **Service Configuration** (all services):
   - Extract `traceparent` header on ingress
   - Propagate in all outbound HTTP calls
   - Propagate in database/cache calls via context
   - Log trace_id in structured logs

4. **Tests**:
   - End-to-end: Send request with no trace ID → verify Caddy generates it
   - Propagation: Send request → verify trace ID appears in all service logs
   - Format validation: Verify trace ID format matches W3C standard

---

### TASK 2: OpenTelemetry Collector Deployment (Days 4-6)

**Deliverables**:
- [ ] OpenTelemetry Collector Docker image configured
- [ ] docker-compose.yml updated with otel-collector service
- [ ] YAML configuration for trace collection pipeline
- [ ] Health check and monitoring for collector

**Implementation**:

1. **Collector Configuration**:
   - gRPC receiver on :4317 (standard port)
   - otlp/http receiver on :4318
   - Batch processor (timeout: 10s, max_batch_size: 512)
   - Jaeger exporter (localhost:14250)

2. **docker-compose Integration**:
   ```yaml
   otel-collector:
     image: otel/opentelemetry-collector:latest
     ports:
       - "4317:4317"  # gRPC receiver
       - "4318:4318"  # HTTP receiver
     volumes:
       - ./otel-collector-config.yaml:/etc/otel-collector/config.yaml
   ```

3. **Health Check**:
   - /healthz endpoint
   - Alert if collector is unhealthy

---

### TASK 3: Jaeger Backend Deployment (Days 7-10)

**Deliverables**:
- [ ] Jaeger all-in-one Docker image deployed
- [ ] UI accessible on port 16686
- [ ] Backend trace storage configured
- [ ] Query API tested

**Implementation**:

1. **Jaeger Configuration**:
   - Image: `jaegertracing/all-in-one:latest` (1.50+)
   - Memory storage for development/staging
   - ES backend for production (can add later)
   - Sampling strategy: 100% for development, configurable for production

2. **docker-compose Integration**:
   ```yaml
   jaeger:
     image: jaegertracing/all-in-one:latest
     ports:
       - "16686:16686"  # UI
       - "14250:14250"  # gRPC receiver
     environment:
       - COLLECTOR_OTLP_ENABLED=true
   ```

3. **Tests**:
   - Send sample trace via OTLP API
   - Verify trace appears in Jaeger UI
   - Query trace via API

---

### TASK 4: code-server Frontend Instrumentation (Days 11-15)

**Deliverables**:
- [ ] OpenTelemetry Web SDK integrated
- [ ] Automatic instrumentation for HTTP calls
- [ ] Manual span creation for key user interactions
- [ ] Trace context propagation in all API calls
- [ ] Test suite

**Implementation**:

1. **Dependencies** (package.json):
   - `@opentelemetry/api`
   - `@opentelemetry/sdk-web`
   - `@opentelemetry/instrumentation-fetch`
   - `@opentelemetry/instrumentation-xml-http-request`
   - `@opentelemetry/exporter-trace-otlp-http`

2. **Initialization**:
   ```javascript
   // In main app file
   import { initOTel } from './otel-setup';
   initOTel(); // Must run before app initialization
   ```

3. **Automatic Instrumentation**:
   - Fetch API calls automatically traced
   - XMLHttpRequest calls automatically traced
   - Trace context injected into `x-trace-id` header

4. **Manual Spans** (key interactions):
   - Page loads
   - User authentication flows
   - File operations (open/save/delete)
   - Git operations

5. **Tests**:
   - Open DevTools → Network tab
   - Verify `x-trace-id` header present in all requests
   - Open Jaeger UI → search by trace ID
   - Verify all frontend interactions appear as spans

---

### TASK 5: code-server Backend Instrumentation (Days 16-20)

**Deliverables**:
- [ ] OpenTelemetry SDK integrated for backend runtime
- [ ] HTTP server instrumentation
- [ ] Trace context extraction from incoming requests
- [ ] Manual spans for key business operations
- [ ] Test suite

**Implementation**:

1. **Dependencies**:
   - `@opentelemetry/api`
   - `@opentelemetry/sdk-node`
   - `@opentelemetry/auto-instrumentations-node`
   - `@opentelemetry/exporter-trace-otlp-http`

2. **Initialization** (very start of app):
   ```javascript
   import { initOTel } from './otel-setup';
   initOTel(); // Before any other imports
   ```

3. **Automatic Instrumentation**:
   - HTTP server requests
   - HTTP client calls (outbound)
   - Express middleware (if applicable)
   - Database queries (via instrumentation)

4. **Manual Spans**:
   - Authentication checks
   - File system operations
   - Git operations
   - Business logic operations

5. **Trace Context Propagation**:
   - Extract `traceparent` from incoming request
   - Propagate in outbound HTTP calls
   - Propagate in database/cache queries

---

### TASK 6: PostgreSQL Query Instrumentation (Days 21-23)

**Deliverables**:
- [ ] PostgreSQL query tracing enabled
- [ ] Slow query detection configured
- [ ] Query logs include trace ID and span ID
- [ ] Test suite

**Implementation**:

1. **PostgreSQL Native Tracing**:
   - Enable `log_statement = all` in development
   - Filter to slow queries (> 100ms) in production
   - Include `trace_id` in query context (PostgreSQL 13+)

2. **Connection String Update**:
   - Add trace ID to connection string or prepared statement comment
   - Example: `SELECT /* trace_id: 4bf92f3577b34da6a3ce929d0e0e4736 */ ...`

3. **Log Format**:
   - JSON log format with trace_id field
   - Integration with ELK or Loki for log aggregation

4. **Tests**:
   - Execute query → verify log includes trace_id
   - Query slow logs → verify trace_id present

---

### TASK 7: Redis Instrumentation (Days 24-26)

**Deliverables**:
- [ ] Redis command tracing via wrapper
- [ ] Cache hit/miss detection
- [ ] Trace ID propagation in cache context
- [ ] Test suite

**Implementation**:

1. **Redis Instrumentation**:
   - Wrap redis-py client calls
   - Measure cache hit rate and latency
   - Create spans for cache operations

2. **Telemetry Data**:
   - Operation (GET/SET/DEL)
   - Key pattern
   - Hit/miss indicator
   - Latency

3. **Tests**:
   - Cache GET hit → verify span shows "hit"
   - Cache GET miss → verify span shows "miss"
   - Trace query → verify all cache ops visible

---

### TASK 8: Structured Logging Schema (Days 27-28)

**Deliverables**:
- [ ] Unified JSON log schema defined
- [ ] Log validation schema (JSON Schema)
- [ ] CI enforcement for log compliance
- [ ] Documentation for developers

**Implementation**:

1. **Required Fields** (every log):
   ```json
   {
     "timestamp": "2026-04-16T10:30:45.123Z",
     "service": "code-server",
     "environment": "production",
     "level": "info|warn|error|debug",
     "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
     "span_id": "00f067aa0ba902b7",
     "message": "User logged in",
     "user_id": "u12345" // (hashed/pseudonymized for privacy)
   }
   ```

2. **Optional Fields** (context-dependent):
   - `request_path`: HTTP request path
   - `http_method`: GET/POST/etc
   - `http_status`: Response status code
   - `error_fingerprint`: Hash of error message for deduplication
   - `duration_ms`: Operation duration
   - `additional_context`: Free-form JSON object

3. **Schema Validation**:
   - Create `logging-schema.json`
   - Add CI check to validate logs from tests
   - Block PRs with non-compliant logging

---

### TASK 9: Incident Runbook Integration (Days 29-30)

**Deliverables**:
- [ ] Trace-based RCA runbook created
- [ ] Jaeger query examples documented
- [ ] Incident escalation workflow with trace ID search
- [ ] Training guide

**Implementation**:

1. **RCA Runbook Template**:
   ```markdown
   # Incident RCA: [Issue Name]
   
   1. Get incident trace ID from alert
   2. Open Jaeger UI → Search → Enter trace_id
   3. Look for errors in trace timeline
   4. Identify first error (root cause)
   5. Check logs for that service
   6. Collect all error context
   7. Determine root cause
   8. Implement fix
   ```

2. **Common Queries**:
   - All requests with status=500
   - All requests with duration > 1000ms
   - All requests with errors in span tags
   - Trace ID pattern search

3. **Automation**:
   - AlertManager integration: Include trace ID in alert
   - Alert text: "Incident [trace_id]. Query: [jaeger_url]/search?traceID=[trace_id]"

---

### TASK 10: Dashboard & SLOs (Days 31-35)

**Deliverables**:
- [ ] Grafana dashboard with layer-by-layer latency breakdown
- [ ] P50/P95/P99 latency graphs by service layer
- [ ] Error rate by layer
- [ ] SLO targets for telemetry coverage
- [ ] Test under load

**Implementation**:

1. **Dashboard Panels**:
   - **Latency Decomposition**: Stack graph showing time in each layer
     - Cloudflare→Caddy (edge latency)
     - Caddy→oauth2-proxy (auth latency)
     - oauth2-proxy→code-server (app latency)
     - code-server→PostgreSQL (database latency)
   - **Error Attribution**: Pie chart of errors by layer
   - **Request Volume**: Requests per second by layer
   - **Trace Coverage**: % of requests with complete traces

2. **SLO Targets**:
   - Trace collection latency: < 1 second
   - Trace query latency: < 100ms
   - P99 end-to-end latency: < 1000ms
   - Error rate: < 0.1%

3. **Load Testing**:
   - Send 1000 req/sec
   - Verify telemetry pipeline doesn't bottleneck (< 5% latency increase)
   - Verify trace loss < 0.1%

---

## TESTING STRATEGY

### Unit Tests
- [ ] Trace ID generation (format validation)
- [ ] Header propagation (extraction/injection)
- [ ] OpenTelemetry span creation
- [ ] Structured log validation

### Integration Tests
- [ ] End-to-end: Request with trace ID → Jaeger receives complete trace
- [ ] Service-to-service: Trace ID propagates across all layers
- [ ] Database queries: Include trace context
- [ ] Cache operations: Span created for each operation

### Load Tests
- [ ] 1000 req/sec with telemetry enabled
- [ ] Measure latency increase from telemetry
- [ ] Verify trace loss < 0.1%
- [ ] Check collector/Jaeger resource usage

### Chaos Tests
- [ ] Kill collector → verify traces dropped gracefully
- [ ] Kill Jaeger → verify no app errors
- [ ] High cardinality trace IDs → verify cardinality limits

---

## ROLLOUT STRATEGY

### Phase 3a: Development (Weeks 3-4)
- Deploy telemetry stack locally
- Instrument code-server
- Test end-to-end tracing

### Phase 3b: Staging (Weeks 4-5)
- Deploy to staging environment
- Run load tests (100 req/sec)
- Verify SLO targets met
- Train team on Jaeger UI and queries

### Phase 3c: Production (Week 5-6)
- Deploy OpenTelemetry Collector to production
- Deploy Jaeger backend (in-memory initially)
- Gradual sampling increase:
  - Week 5: 1% sampling
  - Week 5.5: 10% sampling
  - Week 6: 100% sampling
- Monitor for performance impact
- Auto-rollback if latency increases > 10%

---

## SUCCESS METRICS

| Metric | Target | Measurement |
|--------|--------|-------------|
| **Trace Coverage** | 100% of ingress requests | % of requests with trace_id |
| **Trace Propagation** | 100% across all layers | % of traces with spans in all 6 layers |
| **Query Latency** | < 100ms | Jaeger query API p99 |
| **Telemetry Overhead** | < 5% app latency increase | Baseline latency comparison |
| **MTTR** | < 15 minutes | Incident response time with traces |

---

## BLOCKERS & DEPENDENCIES

### Hard Dependencies
- None (independent implementation)

### Soft Dependencies
- #380 (governance) — Use governance framework for telemetry standards
- #381 (readiness gates) — Will benefit from telemetry for SLO validation

### Known Risks
| Risk | Probability | Mitigation |
|------|---|---|
| Telemetry overhead hurts performance | Medium | Start with 1% sampling; monitor latency; auto-rollback if needed |
| Trace data explosion | Low | Implement retention policy (7-day default); configure sampling |
| Team doesn't adopt traces for debugging | Medium | Training + runbook + incentivize usage |

---

## DELIVERABLES CHECKLIST

### Week 3
- [ ] Trace ID propagation standard documented
- [ ] Caddy configured with trace ID generation
- [ ] OpenTelemetry Collector deployed locally
- [ ] Jaeger backend deployed locally

### Week 4
- [ ] Frontend instrumentation complete
- [ ] Backend instrumentation complete
- [ ] PostgreSQL query tracing enabled
- [ ] Redis instrumentation complete

### Week 5
- [ ] Structured logging schema defined and enforced
- [ ] Incident runbook created
- [ ] Dashboard created in Grafana
- [ ] Load testing completed

### Week 6
- [ ] Production deployment (1% → 10% → 100% sampling)
- [ ] SLO targets validated
- [ ] Team training completed
- [ ] #377 issue marked complete

---

**Next Step**: Begin TASK 1 (Trace ID Propagation Standard)  
**Estimated Timeline**: 4-6 weeks from start  
**Owner**: Observability Engineering  
**Status**: READY TO START
