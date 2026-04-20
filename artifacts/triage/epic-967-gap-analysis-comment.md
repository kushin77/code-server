## Gap Analysis - Additional Issues Created (Session April 23, 2026)

Comprehensive gap analysis identified **18 gaps** across infrastructure. Created 7 new issues:

### P0 (Critical - Blocking HA)

| Issue | Title | Impact |
|-------|-------|--------|
| #993 | **Caddyfile `primary_host` is Literal String** | Dual-upstream failover completely broken |

### P1 (High - This Sprint)

| Issue | Title | Category |
|-------|-------|----------|
| #994 | Parameterize sentinel.conf for Multi-Host Deployment | Redis HA |
| #995 | Add Prometheus Scrapes and Alerts for session-broker and Redis Sentinel | Observability |
| #996 | Add Unit Tests for redis-session-store.ts | Testing |
| #997 | Implement Graceful Shutdown for session-broker | Lifecycle |
| #998 | Remove Hardcoded Fallback from IDE_SESSION_LB_SECRET | Security |
| #999 | Replace AlertManager Placeholder Webhooks with GSM Secrets | Alerting |

### Cross-References

- **HA EPIC #954**: #993, #994, #995, #997, #998 directly affect failover
- **QA EPIC #982**: #996 adds tests for session store
- **Observability**: #995, #999 improve monitoring coverage
- **Security**: #993, #998, #999 address configuration vulnerabilities

### Gap Analysis Coverage

| Category | Gaps Found | Issues Created |
|----------|------------|----------------|
| Load Balancing/Failover | 5 | 3 (#993, #994, #998) |
| Infrastructure Lifecycle | 3 | 1 (#997) |
| Testing | 3 | 1 (#996) |
| Security | 3 | 1 (#999) |
| Observability | 3 | 1 (#995) |
| Governance | 1 | 0 (low priority) |
| **Total** | **18** | **7** |

### Remaining P2/P3 Gaps (Deferred)

- BATS tests not in CI (P2)
- No load/stress testing (P2)
- Prometheus on net-edge (P2)
- PgBouncer password exposure (P2)
- Stale documentation references (P3)
