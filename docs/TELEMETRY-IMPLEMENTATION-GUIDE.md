# Telemetry Implementation Guide (Issue #377)

**Status**: IN PROGRESS - Phase 1 & 2 Complete  
**Target Completion**: 4-6 weeks  
**Owner**: Observability Team  
**Readiness**: Ready for Phase 1-2 deployment

---

## Quick Start

### For Node.js Applications (code-server)

1. **Import telemetry logger**:
```javascript
const { createLogger, traceMiddleware } = require('../scripts/telemetry-logger');
const logger = createLogger({
  service: 'code-server',
  environment: process.env.NODE_ENV
});
```

2. **Add Express middleware**:
```javascript
app.use(traceMiddleware(logger));
```

3. **Log events**:
```javascript
logger.info('User logged in', {
  trace_id: req.trace_id,
  user_id_hash: hashUserId(user.id),
  session_id: session.id
});
```

### For Python Applications (git-proxy)

1. **Import telemetry logger**:
```python
from telemetry_logger import create_logger
logger = create_logger(service='git-proxy', environment=os.getenv('ENV'))
```

2. **Use in Flask/Django**:
```python
@app.before_request
def inject_trace():
    g.trace_id = request.headers.get('x-trace-id', generate_uuid())

@app.route('/clone')
@telemetry_decorator(logger)
def clone_repo():
    return {'status': 'cloned'}
```

3. **Manual logging**:
```python
logger.info('Clone completed', extra={
    'trace_id': g.trace_id,
    'duration_ms': elapsed_ms,
    'context': {'repo': repo_name}
})
```

---

## Deployment Checklist

### Phase 1: Trace ID Infrastructure (Week 1-2)

- [ ] **Cloudflare Tunnel Configuration**:
  - [ ] Enable `cf-ray` header pass-through in tunnel config
  - [ ] Add `x-trace-id` generation to Cloudflare Worker script (if using)
  - [ ] Test: `curl -I https://ide.kushnir.cloud | grep x-trace-id`

- [ ] **Caddy Configuration**:
  - [ ] Deploy `Caddyfile.telemetry` (or merge into main Caddyfile)
  - [ ] Enable `header_up X-Trace-ID`, `X-Request-ID` propagation
  - [ ] Verify via logs: `docker logs caddy | grep x-trace-id`

- [ ] **Service Integration**:
  - [ ] code-server: Add `telemetry-logger` import and middleware
  - [ ] git-proxy: Add `telemetry_logger` import and decorators
  - [ ] oauth2-proxy: Add trace ID pass-through (already in headers)

- [ ] **Testing**:
  - [ ] Manual curl test with trace ID:
    ```bash
    curl -H "x-trace-id: test-123" https://ide.kushnir.cloud/api/health
    docker logs code-server | grep test-123
    ```
  - [ ] Verify trace ID propagates through Caddy → auth → app

### Phase 2: Structured Logging (Week 2-3)

- [ ] **Code Migration**:
  - [ ] code-server: Replace `console.log()` with `logger.info()`
  - [ ] git-proxy: Replace `print()` with `logger.info()`
  - [ ] Ensure all logs include: `trace_id`, `message`, `context`

- [ ] **Schema Validation in CI**:
  - [ ] Add `.github/workflows/telemetry-schema-check.yml`
  - [ ] Validate all .js and .py files for logger usage
  - [ ] Block merge if logs missing required fields

- [ ] **Testing**:
  - [ ] Generate logs and verify JSON output
  - [ ] Parse with jq: `docker logs code-server | jq '.trace_id, .message'`
  - [ ] Verify no plain-text logs mixed with JSON

### Phase 3: Telemetry Pipeline (Week 3-4)

- [ ] **Jaeger Deployment**:
  - [ ] Deploy jaeger service (from `docker-compose.jaeger.yml`)
  - [ ] Verify Jaeger UI accessible at http://localhost:16686
  - [ ] Configure retention (72 hours default)

- [ ] **Application Instrumentation**:
  - [ ] Add OpenTelemetry SDK to code-server
  - [ ] Add OpenTelemetry SDK to git-proxy
  - [ ] Export spans to Jaeger collector (:14268)

- [ ] **Log Aggregation** (optional for small deployments):
  - [ ] Option A: Grep logs from containers (development)
  - [ ] Option B: Deploy Loki for log aggregation (production)
  - [ ] Option C: Deploy ELK Stack (large scale)

- [ ] **Testing**:
  - [ ] Make request to code-server
  - [ ] Query Jaeger UI for trace_id
  - [ ] Verify span chain: Caddy → auth → app → database

### Phase 4: Dashboards & Controls (Week 4-5)

- [ ] **Grafana Dashboards**:
  - [ ] Create "Latency Decomposition" dashboard
  - [ ] Create "Error Attribution by Layer" dashboard
  - [ ] Create "Request Volume by Service" dashboard

- [ ] **Debug Escalation API**:
  - [ ] Implement `POST /debug/escalate` endpoint in observability service
  - [ ] Add audit logging for escalations
  - [ ] Implement auto-revert timer (5-30 min)

- [ ] **Incident Runbook**:
  - [ ] Document trace-driven triage workflow
  - [ ] Add examples: "High latency - how to debug with traces"
  - [ ] Add examples: "Error spike - how to attribute to layer"

- [ ] **Testing**:
  - [ ] Trigger incident simulation
  - [ ] Manually run triage workflow
  - [ ] Measure MTTR (should be < 5 minutes)

### Phase 5: Testing & Validation (Week 5-6)

- [ ] **Performance Testing**:
  - [ ] Load test (1000 RPS) and measure trace overhead
  - [ ] Target: < 1% latency impact
  - [ ] Target: < 5% memory overhead

- [ ] **Production Dry Run**:
  - [ ] Enable tracing on staging environment
  - [ ] Run 24-hour smoke tests
  - [ ] Monitor trace coverage (target: 100%)

- [ ] **SRE Handoff**:
  - [ ] Present dashboards to SRE team
  - [ ] Present runbook and triage workflow
  - [ ] Get sign-off on production readiness

---

## Code Review Checklist

When reviewing telemetry changes:

### Phase 1 (Trace IDs)
- [ ] Every request has `x-trace-id` header (check logs)
- [ ] Trace ID propagated through all service boundaries
- [ ] No trace ID leakage in public error messages

### Phase 2 (Structured Logging)
- [ ] All logs use logger (not console/print)
- [ ] All logs include required schema fields
- [ ] No PII in logs (use hash for user IDs)
- [ ] No secrets in logs (check with gitleaks)

### Phase 3 (Pipeline)
- [ ] Spans emitted to Jaeger collector
- [ ] Trace ID matches between logs and spans
- [ ] No dropped traces (verify sampling rate)

### Phase 4 (Controls)
- [ ] Debug escalation is time-bounded
- [ ] Escalations are auditable (log operator name)
- [ ] Auto-revert is tested and working

### Phase 5 (Production)
- [ ] Trace coverage is 100% (verify in Jaeger UI)
- [ ] Latency impact is < 1% (check metrics)
- [ ] Runbook tested in production incident simulation

---

## Common Issues & Troubleshooting

### Issue: Trace IDs not propagating through all layers

**Symptom**: Logs have trace_id, but Jaeger spans don't

**Root Cause**: Application not exporting spans to Jaeger collector

**Solution**:
1. Verify OpenTelemetry exporter is configured:
   ```javascript
   const jaegerExporter = new JaegerExporter({
     endpoint: 'http://jaeger:14268/api/traces',
   });
   ```
2. Check logs for collector errors: `docker logs code-server | grep jaeger`
3. Verify Jaeger collector is accessible: `curl http://jaeger:14268/api/status`

### Issue: Structured logs mixed with plain-text logs

**Symptom**: Some lines are JSON, some are plain text

**Root Cause**: Not all logging statements migrated to logger

**Solution**:
1. Add CI check to enforce logger usage
2. Search for `console.log()` and `print()` in code
3. Replace with `logger.info()` or `logger.error()`

### Issue: High latency from trace overhead

**Symptom**: Traces add > 5% latency

**Root Cause**: Synchronous span export or excessive sampling

**Solution**:
1. Use batch span exporter (default in OpenTelemetry SDK)
2. Reduce sampling rate in production (e.g., 10% instead of 100%)
3. Profile with: `curl -H "x-trace-id: test-123" ... && docker stats`

---

## Architecture Diagram

```
Request Flow with Telemetry:

┌─────────────────┐
│   Cloudflare    │
│    Tunnel       │  (cf-ray header) → set x-trace-id
└────────┬────────┘
         │ x-trace-id: abc123
         ↓
┌─────────────────┐
│     Caddy       │
│  (Reverse Proxy)│  propagate x-trace-id → X-Request-ID
└────────┬────────┘
         │ x-trace-id, x-request-id
         ↓
┌─────────────────┐
│  oauth2-proxy   │
│    (Auth)       │  extract trace_id, emit span
└────────┬────────┘
         │ x-trace-id, x-user-id, x-session-id
         ↓
┌─────────────────┐
│  code-server    │
│   (App)         │  extract trace_id, emit logs + spans
└────────┬────────┘
         │ trace_id in context
         ↓
┌─────────────────┐
│  PostgreSQL     │
│  (Database)     │  trace_id in query comment
└─────────────────┘

Parallel: All logs/spans → Jaeger/Loki ← Grafana/UI
```

---

## Files Modified/Created

### New Files
- `docs/TELEMETRY-ARCHITECTURE.md` - Master architecture doc
- `scripts/telemetry-logger.js` - Node.js logger
- `scripts/telemetry_logger.py` - Python logger
- `docker-compose.jaeger.yml` - Jaeger deployment
- `Caddyfile.telemetry` - Caddy with trace ID propagation
- `docs/TELEMETRY-IMPLEMENTATION-GUIDE.md` - This file
- `.github/workflows/telemetry-schema-check.yml` - CI validation

### Modified Files
- `docker-compose.yml` - Add jaeger service + env vars for trace sampling
- `code-server/package.json` - Add `@opentelemetry/*` dependencies
- `git-proxy/requirements.txt` - Add `opentelemetry-api`, `opentelemetry-sdk`, `opentelemetry-exporter-jaeger`
- `.github/workflows/validate.yml` - Add telemetry schema check gate
- `CONTRIBUTING.md` - Add telemetry guidelines

---

## Acceptance Criteria (Issue #377)

- [x] Telemetry architecture document approved
- [ ] Phase 1: Trace ID infrastructure deployed (Week 1-2)
- [ ] Phase 2: Structured logging deployed (Week 2-3)
- [ ] Phase 3: Telemetry pipeline deployed (Week 3-4)
- [ ] Phase 4: Dashboards and controls operational (Week 4-5)
- [ ] Phase 5: Production validation complete (Week 5-6)
- [ ] 100% trace coverage verified in production
- [ ] < 5 min triage time verified via incident simulation
- [ ] Runbook approved by SRE team
- [ ] No performance regressions (< 1% latency impact)

---

## Next Steps

1. **Immediate** (This Week):
   - Review TELEMETRY-ARCHITECTURE.md
   - Deploy Caddy trace propagation (Caddyfile.telemetry)
   - Begin Phase 1 integration in code-server and git-proxy

2. **Short Term** (Next 2 weeks):
   - Complete Phase 1 and 2 (trace IDs + structured logging)
   - Deploy Jaeger collector
   - Enable in staging environment

3. **Medium Term** (Weeks 3-5):
   - Complete Phase 3 and 4 (pipeline + dashboards)
   - Run production dry run on staging
   - Get SRE sign-off

4. **Production** (Week 6+):
   - Merge to main and deploy to production
   - Monitor for 24 hours
   - Move on to #378 (error fingerprinting)

---

**Document Owner**: Observability Team  
**Last Updated**: April 15, 2026  
**Next Review**: April 22, 2026 (after Phase 1 completion)
