# Error Fingerprinting Schema & Framework

**Status**: Design Phase 1 - READY FOR IMPLEMENTATION  
**Priority**: P1 (Critical observability component)  
**Owner**: Backend Team  
**Timeline**: May 1-5, 2026

---

## Overview

Error fingerprinting aggregates similar errors into groups, enabling:
- Deduplication (1000 identical errors = 1 fingerprint)
- Trend analysis (error rate over time)
- Targeted alerting (avoid alert fatigue)
- Root cause analysis (common failure patterns)
- Impact quantification (affected services + users)

---

## Fingerprinting Algorithm

### Fingerprint Calculation

```
fingerprint = SHA256(
  service_name +          # "code-server" vs "api"
  error_type +            # "PostgreSQL::ConnectionError"
  error_message +         # Normalized: remove IDs, timestamps
  file +                  # "src/db.js"
  line_number             # 42
)
```

### Normalization Rules

1. **Remove Dynamic Values**:
   - UUIDs → `<UUID>`
   - Timestamps → `<TIMESTAMP>`
   - IP addresses → `<IP>`
   - Port numbers → `<PORT>`
   - User IDs → `<USER_ID>`

2. **Normalize Paths**:
   - `/home/coder/workspace/file.js` → `file.js`
   - Full URLs → domain only

3. **Collapse Whitespace**:
   - `error message\n  with\n   newlines` → `error message with newlines`

---

## Error Fingerprint Data Model

### Loki Log Entry

```json
{
  "timestamp": "2026-04-29T14:23:45.123Z",
  "level": "ERROR",
  "service": "code-server",
  "fingerprint": "3a5f2b8c1d9e4f6a7b2c3d4e5f6a7b8c",
  "error": {
    "type": "PostgreSQL::ConnectionError",
    "message": "Connection timeout to <IP>:<PORT> after <MS>ms",
    "source": {
      "file": "db.js",
      "line": 42,
      "function": "query"
    }
  },
  "context": {
    "user_id": "<USER_ID>",
    "operation": "fetch_workspace",
    "duration_ms": 5123,
    "workspace_id": "<UUID>"
  }
}
```

### Prometheus Metrics

```
errors_total{service="code-server",fingerprint="3a5f...",type="PostgreSQL::ConnectionError"} 147
errors_by_service{service="code-server"} 147
errors_by_operation{operation="fetch_workspace"} 147
```

---

## Success Criteria

- [ ] All error logs include fingerprint field
- [ ] Fingerprints uniquely identify error patterns
- [ ] Dashboard shows error trends with <5s latency
- [ ] Alerts trigger within 2 minutes of spike
- [ ] Team can quickly identify root causes using fingerprints
- [ ] False positive rate < 5%

---

**Status**: Design ready for Phase 1 implementation  
**Owner**: Backend Team  
**Timeline**: May 1-5, 2026
