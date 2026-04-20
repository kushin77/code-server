## Severity: HIGH (3 findings — auth path liveness and circuit-breaking)

---

## Finding 1 — oauth2-proxy healthcheck verifies binary, not HTTP liveness (docker-compose.yml:207, 298)

### Evidence
```yaml
# Both oauth2-proxy AND oauth2-proxy-portal use this healthcheck:
healthcheck:
  test: ["CMD", "/bin/oauth2-proxy", "--version"]
  interval: 30s
  timeout: 10s
  retries: 3
```

### Risk
The container can report `healthy` while the HTTP server is:
- Stuck in a startup hang (Google OIDC discovery endpoint unreachable)
- Crashed (only the binary still exists on disk)
- Listening on wrong interface

Docker will not restart a "healthy" container. Caddy continues sending auth requests to it. All users get 502.

### Fix
```yaml
healthcheck:
  test: ["CMD-SHELL", "curl -sf http://localhost:4180/ping || exit 1"]
  interval: 15s
  timeout: 5s
  retries: 3
  start_period: 30s
```
Also fix Caddy's healthcheck (`caddy version` → `curl -sf http://localhost:2019/`).

---

## Finding 2 — No circuit-breaker on oauth2-proxy upstream in Caddyfile (Caddyfile:52-59)

### Evidence
```
# Current auth proxy block in ide.kushnir.cloud:
reverse_proxy oauth2-proxy:4180 {
    header_up Host {upstream_hostport}
    header_up X-Real-IP {remote_host}
    header_up X-Forwarded-For {remote_host}
}
# No health_uri, no fail_duration, no passive health checks
```

### Risk
If oauth2-proxy is unresponsive, Caddy continues sending every auth request to it indefinitely. All auth requests queue up, then time out with 502. There is no circuit-breaker to stop the cascade.

### Fix — Add passive health check with fail_duration:
```caddy
reverse_proxy oauth2-proxy:4180 {
    header_up Host {upstream_hostport}
    header_up X-Real-IP {remote_host}
    header_up X-Forwarded-For {remote_host}

    health_uri      /ping
    health_interval 15s
    fail_duration   30s

    transport http {
        keepalive          30s
        keepalive_idle_conns 100
        response_header_timeout 30s
    }
}
```
Apply the same to `oauth2-proxy-portal:4181`.

---

## Finding 3 — No upstream keepalive tuning on session-broker (Caddyfile:68-82)

### Evidence
```
# session-broker block:
reverse_proxy session-broker:5000 {
    lb_policy cookie ide_session_lb {$IDE_SESSION_LB_SECRET}
    # No keepalive configuration
}
```

### Risk
Under WebSocket-heavy IDE traffic, long-lived connections exhaust the upstream connection pool. Caddy opens a new TCP connection per request to session-broker with no connection reuse.

### Fix
```caddy
reverse_proxy session-broker:5000 {
    lb_policy cookie ide_session_lb {$IDE_SESSION_LB_SECRET}

    health_uri      /health
    health_interval 15s
    fail_duration   30s

    transport http {
        keepalive          60s
        keepalive_idle_conns 200
        dial_timeout       5s
        response_header_timeout 60s
    }
}
```

---

## Definition of Done
- [ ] Both oauth2-proxy services use HTTP liveness healthcheck (`/ping`)
- [ ] Caddy blocks for oauth2-proxy have `fail_duration` and `health_uri`
- [ ] session-broker upstream has keepalive and response_header_timeout tuning
- [ ] All Caddy healthchecks use HTTP endpoints (not binary version checks)
- [ ] `docker inspect` confirms healthcheck commands updated
- [ ] Load test: killing oauth2-proxy triggers Caddy circuit-break within 30s
- [ ] Parent #967 updated with evidence

Fixes #967 (EPIC)
