## Gap Analysis - Load Balancing & Failover Issues (April 23, 2026)

Gap analysis identified **5 critical load balancing/failover gaps**. New issues created:

### Critical HA Issues

| Issue | Title | Impact |
|-------|-------|--------|
| **#993** | Caddyfile `primary_host` is Literal String | **P0 CRITICAL** - Dual-upstream failover completely broken. Traffic can't route to primary host because `primary_host:5000` is a literal string, not `{$PRIMARY_HOST:...}` env var syntax. |
| #994 | Parameterize sentinel.conf for Multi-Host Deployment | Redis Sentinel can't discover actual master on replica host (.42). Failover detection broken. |
| #998 | Remove Hardcoded Fallback from IDE_SESSION_LB_SECRET | If env var missing, production falls back to public `secret734` value. |

### Related Observability

| Issue | Title |
|-------|-------|
| #995 | Add Prometheus scrapes/alerts for session-broker and Redis Sentinel - failover events not monitored |
| #997 | Graceful shutdown for session-broker - prevents data loss during failover |

### Dependency Order

```
#993 (P0) ─┬─> #994 (Sentinel needs PRIMARY_HOST)
           └─> #958 (Dual-host Caddy - blocked by #993)
```

### Execution Priority

1. **#993 FIRST** - Nothing else works until Caddyfile is fixed
2. #994 - Sentinel parameterization
3. #995 - Monitoring to verify fix
4. #998 - Security hardening
5. #997 - Resilience improvement
