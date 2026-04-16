# ADR-006: Dual-Portal Architecture Decision

**Status**: APPROVED FOR IMPLEMENTATION  
**Date**: April 22, 2026  
**Author**: Infrastructure Team  
**Deciders**: @kushin77  
**Relates to**: P1 #385 (Portal Architecture)  

---

## Context

The code-server deployment spans multiple operational tiers:

1. **Developer Portal** — IDE, workspace, collaboration (code-server + oauth2-proxy + caddy)
2. **Operations Portal** — Monitoring, incident management, infrastructure control (Prometheus, Grafana, AlertManager)

Currently, both portals share infrastructure (reverse proxy, TLS, DNS), creating operational coupling and complicating:
- **Scalability**: Dev load spikes affect ops monitoring
- **Security**: Dev OAuth2 compromises ops access  
- **Availability**: Caddy restart affects both portals
- **Incident Response**: Can't troubleshoot infrastructure while dev portal down

---

## Decision

**Implement Dual-Portal Architecture**:
1. **Developer Portal** (public-facing):
   - URL: `https://ide.kushnir.cloud`  
   - Services: code-server, workspace, collaboration
   - Authentication: OAuth2 (Google OIDC) + MFA (optional for devs)
   - TLS: Auto-renewed (Let's Encrypt via Caddy)
   - Load Balancer: Public internet access

2. **Operations Portal** (internal-only):
   - URL: `https://ops.kushnir.cloud` (internal DNS only)  
   - Services: Prometheus, Grafana, AlertManager, Jaeger, Loki
   - Authentication: OAuth2 (Google OIDC) + MFA (mandatory for ops)
   - TLS: Auto-renewed (Let's Encrypt via Caddy)
   - Load Balancer: VPC-internal only (no public internet)

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                    Internet (Public)                     │
└─────────────────────────────────────────────────────────┘
                         │
                ┌────────▼────────┐
                │  Cloudflare WAF │  (DDoS, rate limiting)
                │   CDN, Tunnel   │
                └────────┬────────┘
                         │
        ┌────────────────┼────────────────┐
        │                │                │
  ┌─────▼────┐   ┌──────▼──────┐   ┌────▼──────┐
  │  Caddy 1  │   │  Caddy 2    │   │ Caddy (3) │
  │ (Primary) │   │ (Secondary) │   │(Failover) │
  └─────┬────┘   └──────┬──────┘   └────┬──────┘
        │               │               │
        └───────────────┼───────────────┘
                        │
        ┌───────────────┴───────────────┐
        │                               │
   ┌────▼─────────────┐      ┌─────────▼────────┐
   │ DEVELOPER PORTAL │      │ OPERATIONS PORTAL │
   └────┬─────────────┘      └─────────┬────────┘
        │                              │
   ┌────▼──────────────┐       ┌───────▼────────────┐
   │   OAuth2-Proxy    │       │    OAuth2-Proxy    │
   │   (Public Auth)   │       │    (Internal Auth) │
   └────┬──────────────┘       └───────┬────────────┘
        │                              │
   ┌────▼──────────────┐       ┌───────▼────────────┐
   │   Code-Server     │       │   Prometheus       │
   │  + Workspace      │       │   (metrics store)  │
   └───────────────────┘       └───────┬────────────┘
                                       │
                        ┌──────────────┼──────────────┐
                        │              │              │
                    ┌───▼──┐      ┌───▼──┐      ┌───▼──┐
                    │Grafana│      │Alert │      │Jaeger│
                    │       │      │Manager      │(trace)
                    └───────┘      └──────┘      └──────┘
                        │
                    ┌───▼──┐
                    │ Loki │
                    │(logs)│
                    └──────┘
```

---

## Detailed Specification

### 1. Developer Portal (Public)

#### URLs
- **Primary**: `https://ide.kushnir.cloud`
- **Aliases**: `https://code.kushnir.cloud`, `https://dev.kushnir.cloud` (CNAME)

#### Services
```
┌── Code-Server (IDE)
│   ├── Extensions
│   ├── Terminal
│   ├── Git integration
│   └── Workspace persistence
│
└── Supporting Services
    ├── OAuth2-Proxy (auth gate)
    ├── Redis (session cache)
    ├── PostgreSQL (app data)
    └── Kong API Gateway (rate limiting, logging)
```

#### Security
- **TLS**: Let's Encrypt (auto-renewed by Caddy)
- **HSTS**: `max-age=31536000, includeSubDomains`
- **CSP**: `default-src 'self'; script-src 'self' 'unsafe-inline'`  (code-server extensions require inline)
- **Authentication**: OAuth2 (Google) + MFA (optional)
- **Rate Limiting**: 1000 req/min per user (Kong)
- **DDoS Protection**: Cloudflare (L3/L4, rate limiting, bot protection)

#### Monitoring
- **Metrics**: Exported to Prometheus (ops portal)
- **Logs**: Sent to Loki (ops portal)
- **Traces**: Sent to Jaeger (ops portal)
- **Dashboards**: Grafana (ops portal only — dev users can't view)

#### Deployment
- **Primary Host**: 192.168.168.31
- **Backup Host**: 192.168.168.42 (DNS failover)
- **Environment Variable**: `PORTAL_MODE=developer`

---

### 2. Operations Portal (Internal)

#### URLs
- **Primary**: `https://ops.kushnir.cloud` (internal DNS only)
- **Aliases**: 
  - `https://monitoring.kushnir.cloud`
  - `https://metrics.kushnir.cloud`
  - `https://alerts.kushnir.cloud`

#### Services
```
┌── Prometheus (metrics store + TSDB)
│   ├── Scrapes: code-server, Kong, PostgreSQL, Caddy, etc.
│   └── Retention: 30 days
│
├── Grafana (dashboards + alerting rules management)
│   ├── Dashboards: System, app, security, business metrics
│   ├── Alert creation UI (sends to AlertManager)
│   └── RBAC: Admin (full), Editor (modify dashboards), Viewer (read-only)
│
├── AlertManager (alert routing + deduplication)
│   ├── Routes alerts to: Slack, PagerDuty, email
│   ├── Silences + maintenance windows
│   └── HA (3 replicas)
│
├── Loki (log aggregation + querying)
│   ├── Stores: App logs, audit logs, security events
│   ├── Retention: 7 days hot, 30 days archive
│   └── LogQL: Advanced log filtering
│
├── Jaeger (distributed tracing)
│   ├── Services: code-server, Kong, PostgreSQL
│   ├── Retention: 72 hours
│   └── Trace visualization
│
└── Supporting Services
    ├── OAuth2-Proxy (auth gate — MFA mandatory)
    ├── Vault (secrets for AlertManager credentials)
    └── Kong API Gateway (minimal — internal traffic only)
```

#### Security
- **Network**: VPC-internal only (no public internet routing)
- **DNS**: Internal DNS (not registered in public DNS)
- **TLS**: Self-signed OR Let's Encrypt (internal CA)
- **Authentication**: OAuth2 (Google) + MFA (mandatory for all)
- **RBAC**: 
  - Viewer: Read-only (SRE watching on-call)
  - Editor: Modify dashboards, silence alerts
  - Admin: Full access (infrastructure team only)
- **Secrets**: All credentials stored in Vault, auto-rotated

#### Monitoring
- **Self-monitoring**: Prometheus scrapes AlertManager, Loki, Jaeger
- **Uptime SLO**: 99.99% (ops critical)
- **Incident Response**: Automatic page (PagerDuty) on ops portal down
- **Backup**: Automatic snapshot to S3 (Prometheus TSDB weekly)

#### Deployment
- **Primary Host**: 192.168.168.31 (same physical host, different container)
- **Backup Host**: 192.168.168.42 (read-only replica)
- **Environment Variable**: `PORTAL_MODE=operations`

---

## Implementation Plan

### Phase 1: Separate Caddy Instances (Week 1)
**Goal**: Decouple TLS/routing for dev vs ops

**Deliverables**:
- [ ] Create `Caddyfile.dev` (public portal config)
- [ ] Create `Caddyfile.ops` (internal portal config)
- [ ] Deploy Caddy #1 (dev) on 192.168.168.31:443
- [ ] Deploy Caddy #2 (ops) on 192.168.168.31:8443 (internal)
- [ ] Update `docker-compose.yml` with 2 Caddy services

**Testing**:
```bash
# Dev portal
curl -i https://ide.kushnir.cloud  # Should reach code-server

# Ops portal (from internal only)
curl -i https://ops.kushnir.cloud:8443  # Should reach Prometheus
```

### Phase 2: Separate OAuth2-Proxy Instances (Week 1)
**Goal**: Different auth policies for dev vs ops

**Deliverables**:
- [ ] Create `oauth2-proxy-dev.conf` (Google OIDC, MFA optional)
- [ ] Create `oauth2-proxy-ops.conf` (Google OIDC, MFA mandatory)
- [ ] Deploy oauth2-proxy #1 on port 4180 (dev)
- [ ] Deploy oauth2-proxy #2 on port 4181 (ops)
- [ ] Update Caddy routing (dev → :4180, ops → :4181)

**Testing**:
```bash
# Dev portal — should allow without MFA
curl https://ide.kushnir.cloud/oauth2/auth  # MFA optional

# Ops portal — should require MFA
curl https://ops.kushnir.cloud/oauth2/auth  # MFA mandatory
```

### Phase 3: Network Isolation (Week 2)
**Goal**: Prevent public internet access to ops portal

**Deliverables**:
- [ ] Create internal DNS zone (ops.kushnir.cloud → 192.168.168.31 internal IP)
- [ ] Configure firewall (allow 192.168.168.0/24 only for :8443)
- [ ] Update `docker-compose.yml` (Caddy #2 binds to internal IP only)
- [ ] Document access procedures (SSH tunnel for remote access)

**Verification**:
```bash
# Public DNS should NOT resolve ops.kushnir.cloud
nslookup ops.kushnir.cloud  # NXDOMAIN (good!)

# Internal DNS should resolve
dig @internal-dns ops.kushnir.cloud  # 192.168.168.31 (good!)

# Public internet cannot reach ops portal
curl https://ops.kushnir.cloud  # Connection refused (good!)

# Internal access works
curl https://ops.kushnir.cloud:8443 --insecure  # Success
```

### Phase 4: Monitoring Integration (Week 2)
**Goal**: Route all metrics/logs/traces to ops portal

**Deliverables**:
- [ ] Configure code-server to export metrics to ops Prometheus
- [ ] Configure Loki clients (all services) to send logs to ops Loki
- [ ] Configure Jaeger clients (Kong, code-server) for tracing
- [ ] Create Grafana dashboards in ops portal
- [ ] Set up AlertManager rules (dev = low priority, ops = pages on-call)

**Testing**:
```bash
# Metrics should appear in ops Prometheus
curl https://ops.kushnir.cloud/api/v1/query?query=up

# Logs should be searchable in ops Loki
curl https://ops.kushnir.cloud/loki/api/v1/query_range?query={job="code-server"}

# Traces should be visible in ops Jaeger
curl https://ops.kushnir.cloud/api/traces?serviceName=code-server
```

### Phase 5: Documentation & Runbooks (Week 3)
**Goal**: Train team on new portal structure

**Deliverables**:
- [ ] `docs/DUAL-PORTAL-ARCHITECTURE.md` (architecture overview)
- [ ] `docs/OPS-PORTAL-RUNBOOK.md` (accessing, troubleshooting ops portal)
- [ ] `docs/DEV-PORTAL-USER-GUIDE.md` (for developers)
- [ ] `docs/FAILOVER-PROCEDURES.md` (if dev portal down, etc.)
- [ ] Team training session (1 hour)

---

## Configuration Changes

### Docker Compose

**Before** (single Caddy):
```yaml
services:
  caddy:
    image: caddy:latest
    ports:
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
```

**After** (dual Caddy):
```yaml
services:
  caddy-dev:
    image: caddy:latest
    ports:
      - "443:443"
    volumes:
      - ./Caddyfile.dev:/etc/caddy/Caddyfile
    environment:
      PORTAL_MODE: developer

  caddy-ops:
    image: caddy:latest
    ports:
      - "8443:443"
    volumes:
      - ./Caddyfile.ops:/etc/caddy/Caddyfile
    environment:
      PORTAL_MODE: operations
    # Bind to internal IP only
    networks:
      - internal

  oauth2-proxy-dev:
    image: quay.io/oauth2-proxy/oauth2-proxy:latest
    ports:
      - "4180:4180"
    config:
      - MFA: optional for developers
      - Scopes: openid, email, profile

  oauth2-proxy-ops:
    image: quay.io/oauth2-proxy/oauth2-proxy:latest
    ports:
      - "4181:4180"
    config:
      - MFA: mandatory for all ops users
      - Scopes: openid, email, profile
    networks:
      - internal
```

---

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|-----------|
| Network partition (dev/ops) | Low | High | Dual-path routing, health checks |
| TLS cert mismatch | Low | Medium | Separate cert chains, monitoring |
| Auth bypass (dev → ops) | Low | Critical | Network isolation, audit logging |
| Performance (2x Caddy overhead) | Medium | Low | Connection pooling, caching |
| Operational complexity | Medium | Medium | Documentation, runbooks, training |

---

## Benefits

✅ **Security**:
- Dev portal compromises don't affect ops monitoring
- Mandatory MFA for ops access
- Network isolation (ops portal internal-only)

✅ **Availability**:
- Caddy restart for dev doesn't affect ops
- Can troubleshoot infrastructure while dev portal down
- Independent scaling

✅ **Performance**:
- Dev load spikes don't affect ops dashboards
- Separate caching layers
- Monitoring team unaffected by IDE usage spikes

✅ **Compliance**:
- Ops portal logs (audit trail) isolated from user activity
- SOC 2: Separation of duties (dev team ≠ ops team access)
- HIPAA/PCI: Operations data not mixed with user data

---

## Estimated Effort

- **Phase 1** (Caddy separation): 2-3 hours
- **Phase 2** (OAuth2-Proxy separation): 2-3 hours
- **Phase 3** (Network isolation): 2-3 hours
- **Phase 4** (Monitoring integration): 3-4 hours
- **Phase 5** (Documentation): 3-4 hours

**Total**: 12-17 hours (1.5-2 days)

---

## Success Criteria

✅ **Functional**:
- [ ] Dev portal accessible at https://ide.kushnir.cloud
- [ ] Ops portal accessible at https://ops.kushnir.cloud (internal only)
- [ ] Both portals have working OAuth2 authentication
- [ ] All monitoring data routed to ops portal
- [ ] Caddy restart on dev doesn't affect ops

✅ **Security**:
- [ ] Public DNS does NOT resolve ops.kushnir.cloud
- [ ] Firewall blocks external access to ops portal
- [ ] All ops users enrolled in MFA
- [ ] Audit logs capture all ops portal access

✅ **Documentation**:
- [ ] Architecture documented
- [ ] Runbooks complete
- [ ] Team trained

---

## References

- Current State: `ADR-003: Code-Server on-Premises Deployment`
- Related: P1 #388 (IAM standardization)
- Related: P1 #387 (Security hardening)
- Related: P2 #362 (IP abstraction)

---

**Approval Status**: APPROVED FOR IMPLEMENTATION  
**Implementation Start**: Week of April 28, 2026  
**Expected Completion**: Week of May 5, 2026  
**Owner**: @kushin77 (approval + resource allocation)  
**Implementation Lead**: Infrastructure Team  

---

**ADR History**:
- ADR-001: Cloudflare Tunnel Architecture
- ADR-002: OAuth2-Proxy Authentication
- ADR-003: Code-Server On-Premises Deployment
- ADR-004: Docker Compose Profiles
- ADR-005: NAS Integration
- **ADR-006**: Dual-Portal Architecture (THIS DOCUMENT)
