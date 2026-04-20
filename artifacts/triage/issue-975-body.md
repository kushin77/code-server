## Severity: HIGH (management attack surface — 4 findings)

---

## Finding 1 — Prometheus, Grafana, AlertManager ports bound to all interfaces (docker-compose.yml:755, 790, 818)

```yaml
prometheus:
  ports: ["9090:9090"]    # bound to 0.0.0.0 — reachable from entire LAN

grafana:
  ports: ["3000:3000"]    # bound to 0.0.0.0

alertmanager:
  ports: ["9093:9093"]    # bound to 0.0.0.0
```

Also: `--web.enable-lifecycle` flag on Prometheus allows unauthenticated `POST /-/reload` and `POST /-/quit` from any LAN host.

### Risk
Any host on the 192.168.168.0/24 network can:
- Read all Prometheus metrics (which include internal service topology, performance data)
- POST `/-/reload` to reload Prometheus config with a malicious rule file
- Access Grafana and read all dashboards (default admin/admin123 from docker-compose)
- Silence or delete AlertManager alerts during an incident

---

## Finding 2 — Caddy admin API (port 2019) bound to all interfaces (docker-compose.yml:379)

```yaml
caddy:
  ports:
    - "80:80"
    - "443:443"
    - "2019:2019"   # ← Caddy admin API, no authentication
```

Caddy's admin API (`:2019`) allows unauthenticated:
- Hot-reload of Caddy config (`POST /load`)
- Inspection of all active routes and upstream connections
- Stopping Caddy (`POST /stop`)

An attacker who can reach `:2019` can inject a new Caddy config redirecting auth traffic to a rogue upstream.

---

## Finding 3 — PostgreSQL bound to host port 5433 (docker-compose.yml:413)

```yaml
postgres:
  ports: ["5433:5432"]   # ← direct DB access from LAN
```

The database is directly reachable from any LAN host. PostgreSQL authentication is the only barrier. If credentials are guessed or leaked, the attacker has direct SQL access.

---

## Finding 4 — Grafana uses HTTP root URL

```yaml
GF_SERVER_ROOT_URL: http://${DEPLOY_HOST:-localhost}:3000
```

Grafana auth cookies (`grafana_session`) are served over HTTP. They can be intercepted on the LAN (HTTP is cleartext on local network too if not behind TLS).

---

## Required Changes

### Remove all direct port bindings; route through Caddy with auth

```yaml
# prometheus.yml — bind to localhost only
prometheus:
  ports: []   # remove public binding
  command:
    - '--web.enable-lifecycle=false'   # disable reload API in production

# grafana — no public port
grafana:
  ports: []
  environment:
    GF_SERVER_ROOT_URL: https://grafana.${APEX_DOMAIN}
    GF_SERVER_PROTOCOL: https
    GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_ADMIN_PASSWORD}   # from GSM

# alertmanager — no public port
alertmanager:
  ports: []

# caddy admin API — bind to localhost only
# In Caddyfile:
admin localhost:2019 {
  origins localhost
}

# postgres — remove host port binding entirely
postgres:
  ports: []   # only reachable via net-data Docker network
```

### Add Caddy routes for internal management access (with auth)
```caddy
grafana.kushnir.cloud {
  tls {
    on_demand
  }
  # Require valid oauth2-proxy session before serving
  forward_auth oauth2-proxy:4180 { ... }
  reverse_proxy grafana:3000
}
```

---

## Definition of Done
- [ ] `docker compose config` shows no `9090`, `3000`, `9093` port bindings
- [ ] Prometheus `--web.enable-lifecycle` disabled in production
- [ ] Caddy admin API bound to `localhost:2019` only
- [ ] PostgreSQL has no host port binding (`docker inspect` confirms no `5433`)
- [ ] Grafana accessible only through authenticated Caddy reverse proxy
- [ ] Grafana admin password sourced from GSM (not hardcoded `admin123`)
- [ ] `nmap -p 9090,3000,9093,2019,5433 192.168.168.31` returns all filtered/closed
- [ ] Parent #967 updated with evidence

Fixes #967 (EPIC)
