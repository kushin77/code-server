# DNS Architecture

**Status:** Production reference  
**Issue:** #1536 — Networking, DNS & Performance  
**Governance:** GOV-002

---

## DNS Layers

| Layer | Resolver | Scope |
|-------|----------|-------|
| External DNS | Cloudflare (authoritative) | `*.kushnir.cloud` public FQDNs |
| Internal overlay | `/etc/hosts` on 192.168.168.31/42 | LAN hostname aliases |
| Docker service discovery | Docker Compose embedded DNS | Container-to-container |

---

## Cloudflare DNS Records

| Record | Type | Value | TTL |
|--------|------|-------|-----|
| `kushnir.cloud` | A | 192.168.168.31 | 300 |
| `ide.kushnir.cloud` | A | 192.168.168.31 | 300 |
| `api.kushnir.cloud` | A | 192.168.168.31 | 300 |
| `grafana.kushnir.cloud` | A | 192.168.168.31 | 300 |
| `*.kushnir.cloud` | A | 192.168.168.31 | 300 |

*TTL 300s (5 min) allows fast failover if IP changes.*

---

## Internal Host Aliases

Add to `/etc/hosts` on both 192.168.168.31 and 192.168.168.42:

```
# code-server-enterprise internal hostnames
192.168.168.31   primary-host primary.internal
192.168.168.42   replica-host replica.internal
192.168.168.56   nas-host nas.internal eiq-nas
```

---

## Docker Compose Service Discovery

All inter-service communication uses Compose service names (no IPs):

```
code-server → http://api:3100
api         → postgres://postgres:5432/app
api         → redis://redis:6379
caddy       → http://code-server:8080
grafana     → http://prometheus:9090
```

Verify discovery is working:
```bash
# From inside caddy container:
docker exec -it caddy nslookup code-server
docker exec -it caddy nslookup api
docker exec -it caddy nslookup prometheus
```

---

## Env Var Reference

All external host references must use these variables (defined in `scripts/_common/hosts.sh`):

| Variable | Default | Purpose |
|----------|---------|---------|
| `PRIMARY_HOST` | 192.168.168.31 | Primary compute node |
| `REPLICA_HOST` | 192.168.168.42 | HA replica node |
| `NAS_HOST` | 192.168.168.56 | NAS storage node |
| `DOMAIN` | kushnir.cloud | Root domain |
| `IDE_HOST` | ide.kushnir.cloud | VS Code Server public URL |
| `API_HOST` | api.kushnir.cloud | API public URL |

Usage in scripts:
```bash
source "$(dirname "$0")/_common/hosts.sh"
ssh "${SSH_USER}@${PRIMARY_HOST}" "docker ps"
scp config.yml "${SSH_USER}@${REPLICA_HOST}:/etc/app/"
```

---

## DNS Failover Validation

```bash
# Simulate primary host unreachable — verify Cloudflare still resolves
dig @1.1.1.1 ide.kushnir.cloud +short

# Verify TTL is production-appropriate (<= 300s)
dig kushnir.cloud SOA | grep -E "refresh|ttl"

# Test with curl using explicit DNS resolution
curl --resolve ide.kushnir.cloud:443:192.168.168.31 \
     https://ide.kushnir.cloud/healthz
```

---

*GOV-002: All infrastructure references must use env vars, not hardcoded IPs.*
