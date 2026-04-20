## Full child issue index — April 20, 2026 full codebase audit

All 42 findings tracked across 14 child issues. Numbers are final.

### P0 — CRITICAL (fix before next production push)

| Issue | Title | Audit Ref |
|-------|-------|-----------|
| #968 | Hardcoded Caddyfile LB cookie secret `secret734` — git-committed, forgeable sessions | A-01, B-03 |
| #969 | oauth2-proxy + session-broker run as root — Docker socket is host escape path | A-02, A-04 |
| #971 | Redis has no authentication + shared CODE_SERVER_PASSWORD across all user sessions | A-03, G-01 |
| #972 | secret-rotation.sh is 100% stub code — no actual secret rotation occurs | F-01 |

### P1 — HIGH (this sprint)

| Issue | Title | Audit Ref |
|-------|-------|-----------|
| #973 | oauth2-proxy healthcheck binary-only + no Caddy circuit-breaker on auth upstream | B-04, B-05, B-08, C-01 |
| #974 | session-broker: sessionProxyHost 127.0.0.1 fallback, no rate limiting, mutable :dev image | G-02, G-03, J-01 |
| #975 | Auth path completely dark — no Prometheus scrape for oauth2-proxy or session-broker | E-01, E-02, E-03, E-05 |
| #976 | Management ports exposed without auth — Prometheus/Grafana/AlertManager/Caddy admin/Postgres | A-05, A-06, A-09, A-10 |
| #977 | alertmanager.yml wrong file mounted + placeholder stubs — zero alerts ever delivered | A-07, E-04, E-06, H-02 |
| #978 | Dockerfile.code-server: curl|sh for Rust + unverified marketplace VSIX downloads | C-02, C-03, J-02 |
| #979 | No remote Terraform backend (state local-only) + root-level deprecated .tf files active | D-01, D-02, D-03, D-04 |
| #980 | deploy.yml apply job truncated — merges to main do NOT deploy to production + Snyk disabled | I-01, I-02, J-03 |

### P2 — MEDIUM (next sprint)

| Issue | Title | Audit Ref |
|-------|-------|-----------|
| #981 | Hygiene batch: Jaeger in-memory, interactive failover, duplicate compose keys, eval injection | C-04, F-02, F-03, F-04, F-05, H-01, H-03 |

### Cross-references to existing EPIC children (#954)

These existing issues have related findings confirmed by this audit:
- **#957** (Redis HA / Sentinel) — blocked on **#971** (Redis must have auth before HA is meaningful)
- **#959** (Appsmith NAS volume) — audit confirms appsmith-data is still a local volume (finding B-07)
- **#960** (CSRF resilience) — audit confirms `SameSite=None` is live in production (finding A-08)
- **#961** (session-broker HA) — blocked on **#974** (must fix sessionProxyHost + rate limiting first)
- **#963** (redeploy standard) — blocked on **#980** (deploy.yml currently has no deploy step — all merges are no-ops)
- **#965** (observability) — blocked on **#975** (no scrape targets for auth path exist yet)
- **#966** (runbook) — blocked on **#977** (alertmanager isn't delivering any alerts currently)

### Execution order (dependency-aware)

```
IMMEDIATE (P0 — before any production push):
  #968 → rotate LB secret + git history scrub
  #969 → drop root from oauth2-proxy + session-broker containers
  #971 → Redis auth + per-session passwords (prerequisite for #957)
  #972 → implement actual secret rotation script (prerequisite for rotating #968)

P1 SPRINT:
  #980 → URGENT: fix deploy.yml (current deploys are no-ops)
  #977 → fix alertmanager mount + stubs (needed before any incident)
  #975 → add Prometheus scrape targets (parallel)
  #976 → remove management port exposure (parallel)
  #973 → fix oauth2-proxy healthcheck + Caddy circuit-breaker
  #974 → session-broker hardening (unblocks #961)
  #978 → Dockerfile supply chain hardening (parallel)
  #979 → Terraform remote backend (parallel)

P2 BACKLOG:
  #981 → hygiene batch
```

### Severity summary
| CRITICAL | HIGH | MEDIUM | LOW | Total |
|----------|------|--------|-----|-------|
| 7 | 20 | 11 | 4 | **42** |
