# DNS Service Discovery Architecture (Issue #888)

## Overview

This document defines the canonical internal DNS naming scheme and enforcement policy for the code-server-enterprise infrastructure. All inter-service communication must use DNS names instead of hardcoded IP addresses.

**Status**: Per issue #888, DNS service discovery is a P1 requirement.
**Effective Date**: April 19, 2026

## Canonical DNS Scheme

### Host Names (Physical/Virtual Machines)

| Logical Name | DNS Name | IPv4 Address | Purpose |
|---|---|---|---|
| Primary Host | `primary.prod.internal` | `192.168.168.31` | Main deployment target, production services |
| Replica Host | `replica.prod.internal` | `192.168.168.42` | Failover/standby, high-availability backup |
| VIP (Virtual IP) | `vip.prod.internal` | `192.168.168.30` | Load balancer virtual IP (VRRP/HSRP if applicable) |
| NAS Storage | `nas.prod.internal` | `192.168.168.56` | Network-attached storage mount point |

### Service Names (Docker/Kubernetes Services)

| Service | DNS Name | Port | Protocol |
|---|---|---|---|
| PostgreSQL | `postgres.svc.internal` | 5432 | TCP |
| Redis | `redis.svc.internal` | 6379 | TCP |
| Code-server IDE | `code-server.svc.internal` | 8080 | HTTP/WS |
| OAuth2 Proxy | `oauth2-proxy.svc.internal` | 4180 | HTTP |
| Caddy (Reverse Proxy) | `caddy.svc.internal` | 80, 443 | HTTP/HTTPS |
| Prometheus | `prometheus.svc.internal` | 9090 | HTTP |
| Grafana | `grafana.svc.internal` | 3000 | HTTP |
| AlertManager | `alertmanager.svc.internal` | 9093 | HTTP |
| Jaeger | `jaeger.svc.internal` | 16686 | HTTP |

### Public Domain Names

| Domain | Purpose | Backed By |
|---|---|---|
| `kushnir.cloud` | Public apex domain (Portal/OAuth) | `primary.prod.internal` (via Caddy reverse proxy) |
| `ide.kushnir.cloud` | IDE public endpoint | `primary.prod.internal` (via Caddy + OAuth2 proxy) |

## Implementation Strategy

### Option 1: Docker Compose Service Discovery ✅ **RECOMMENDED (Current)**

**How It Works:**
- Docker Compose creates an internal DNS resolver for all containers on a named network
- Containers resolve service names via the Docker embedded DNS server (127.0.0.11:53)
- Service names map to container hostnames automatically

**Configuration:**
```yaml
version: '3.9'
services:
  postgres:
    image: postgres:15
    hostname: postgres              # ← Sets hostname
    networks:
      - internal                    # ← Joined network
  
  code-server:
    image: codercom/code-server
    depends_on:
      - postgres
    networks:
      - internal
    environment:
      DATABASE_URL: postgresql://postgres:5432/codeserver  # ← Uses service name, not IP

networks:
  internal:
    name: code-server-internal
    driver: bridge
```

**Verification:**
```bash
# From inside a container:
nslookup postgres.svc.internal      # Should resolve to Docker network IP
ping redis                          # Docker DNS auto-aliases (no .svc.internal needed inside Docker)
```

### Option 2: Host-Level DNS (/etc/hosts)

For host-to-container or cross-host communication, add entries to `/etc/hosts`:

```bash
# /etc/hosts on primary (192.168.168.31) and replica (192.168.168.42)
127.0.0.1       localhost
192.168.168.31  primary.prod.internal primary
192.168.168.42  replica.prod.internal  replica
192.168.168.30  vip.prod.internal      vip
192.168.168.56  nas.prod.internal      nas

# Service records (mapped to container IPs via Docker)
172.18.0.2      postgres.svc.internal
172.18.0.3      redis.svc.internal
172.18.0.4      code-server.svc.internal
```

**Terraform-Managed** (See terraform/network-variables.tf):
```hcl
resource "local_file" "etc_hosts_primary" {
  filename = "/etc/hosts.d/code-server-internal"
  content  = templatefile("${path.module}/templates/hosts.tpl", {
    primary_host = var.primary_host           # Default: 192.168.168.31
    replica_host = var.replica_host           # Default: 192.168.168.42
    vip_host     = var.vip_host               # Default: 192.168.168.30
    nas_host     = var.nas_host               # Default: 192.168.168.56
  })
  # This ensures /etc/hosts is idempotent and templated
}
```

### Option 3: CoreDNS or dnsmasq (Future)

For more advanced scenarios (multiple data centers, cloud integration):

```bash
# Install dnsmasq on both hosts
apt-get install -y dnsmasq

# /etc/dnsmasq.conf
address=/prod.internal/192.168.168.31          # Primary host
address=/primary.prod.internal/192.168.168.31
address=/replica.prod.internal/192.168.168.42
address=/vip.prod.internal/192.168.168.30
```

## Environment Variable Pattern

All infrastructure code must parameterize DNS/IP references:

### Required Environment Variables (from `.env.schema.json`)

```bash
# Host references
DEPLOY_HOST=192.168.168.31              # Primary target for deployments
DEPLOY_HOST_SUFFIX=31                   # IP suffix for SSH key naming
REPLICA_HOST=192.168.168.42             # Standby/failover host
VIP_HOST=192.168.168.30                 # Virtual IP (if VRRP active)
NAS_HOST=192.168.168.56                 # NAS mount point

# Domain references
DOMAIN=kushnir.cloud                    # Apex domain
IDE_DOMAIN=ide.kushnir.cloud            # IDE subdomain
PORTAL_DOMAIN=kushnir.cloud             # Portal domain (usually = DOMAIN)

# Service discovery
DB_HOST=postgres.svc.internal           # PostgreSQL hostname (Docker internal)
REDIS_HOST=redis.svc.internal           # Redis hostname (Docker internal)
```

### Fallback Pattern (Bash)

```bash
#!/usr/bin/env bash
# Safe pattern for scripts:

DEPLOY_HOST="${DEPLOY_HOST:-192.168.168.31}"  # Use env var, fall back to known default
DB_HOST="${DB_HOST:-postgres.svc.internal}"   # Use DNS name if available
```

### Terraform Pattern

```hcl
variable "primary_host" {
  description = "Primary host IP address"
  type        = string
  default     = "192.168.168.31"  # ← Parameterizable default
}

variable "apex_domain" {
  description = "Apex domain for public endpoints"
  type        = string
  default     = "kushnir.cloud"
}

# Override via: terraform apply -var primary_host=192.168.200.1
```

## Hardcoded IP Policy

### ❌ NOT ALLOWED (Will Fail CI)
```bash
# WRONG - hardcoded in script
ssh akushnir@192.168.168.31 docker ps

# WRONG - hardcoded in Docker Compose
environment:
  POSTGRES_HOST: 192.168.168.31:5432

# WRONG - hardcoded in Terraform (except default in variable definition)
resource "local_file" "config" {
  content = "database_url = postgresql://192.168.168.31/db"
}
```

### ✅ ALLOWED (Compliant Patterns)
```bash
# CORRECT - use env var with fallback
ssh akushnir@${DEPLOY_HOST:-192.168.168.31} docker ps

# CORRECT - use DNS name
environment:
  POSTGRES_HOST: postgres.svc.internal:5432

# CORRECT - use variable with default
resource "local_file" "config" {
  content = "database_url = postgresql://${var.db_host}:5432/db"
}

# CORRECT - in .env files (configuration)
DEPLOY_HOST=192.168.168.31

# CORRECT - in terraform/variables.tf defaults (explicitly parameterized)
default = "192.168.168.31"

# CORRECT - in documentation (clearly marked as examples)
Example: ssh akushnir@192.168.168.31  # ← Commented as example, not production
```

### ⚠️ ALLOWED BUT DISCOURAGED
```bash
# Config files (.env*, docker-compose, terraform defaults, ansible inventory)
# These are allowed to contain literal IPs because they are explicitly configured values
# However, prefer env vars where possible
```

## CI Enforcement (Issue #885 / #888 Combined)

### Pre-Commit Hook
```bash
# .pre-commit-hooks.yaml
- id: check-hardcoded-ips
  name: Reject hardcoded IP addresses in scripts
  entry: bash scripts/ci/check-hardcoded-ips.sh
  language: bash
  files: '\.(sh|ts|js|py)$'
  exclude: '^(\.env|config/|docs/|terraform/)'
  stages: [commit]
```

### CI Workflow
```bash
# .github/workflows/dns-service-discovery-enforcement.yml
# Runs on every PR, fails if hardcoded IPs found in active code
```

## Migration Checklist (For #888 Completion)

- [x] Define canonical DNS naming scheme (this doc)
- [x] Document Makefile parameterization (completed in Makefile)
- [x] Create CI guard script (scripts/ci/check-hardcoded-ips.sh)
- [x] Create CI enforcement workflow (.github/workflows/dns-service-discovery-enforcement.yml)
- [ ] Update Caddyfile to use `${IDE_DOMAIN}` consistently
- [ ] Update K8s OIDC configs to use env vars
- [ ] Test DNS resolution on both primary and replica hosts
- [ ] Update runbooks to reference DNS names instead of IPs
- [ ] Document in ops manual (docs/runbooks/)
- [ ] Close issue #888 with migration evidence

## Verification & Testing

### Docker Service Resolution
```bash
# Inside any container on the internal network:
docker exec code-server nslookup postgres.svc.internal
# Should return Docker network IP (e.g., 172.18.0.2)
```

### Host-Level Resolution
```bash
# On primary or replica host:
nslookup primary.prod.internal  # Should resolve to 192.168.168.31
nslookup replica.prod.internal  # Should resolve to 192.168.168.42
```

### Makefile with Env Vars
```bash
# Use parameterized SSH targets:
DEPLOY_HOST=192.168.200.1 make ssh-31    # Connects to alternate host

# Uses defaults if not set:
make ssh-31                               # Connects to 192.168.168.31
```

## References

- **Issue #888**: Internal DNS service discovery — replace all hardcoded IPs
- **Issue #834**: DNS de-IP initiative (related)
- **Governance**: See .github/copilot-instructions.md (Rule 3 — Configuration Separation)
- **Pre-commit**: .pre-commit-hooks.yaml (hardcoded-ip detection)
- **CI Enforcement**: .github/workflows/dns-service-discovery-enforcement.yml

## Rollback & Incident Response

If DNS resolution fails during production deployment:

1. **Immediate**: Fall back to hardcoded IPs (pre-approved in allowed lists)
2. **Diagnostic**: Check `/etc/hosts` and Docker DNS resolver
3. **Mitigation**: SSH directly to host and run `docker compose logs -f` 
4. **Root Cause**: Validate DNS service (dnsmasq/CoreDNS) is running
5. **Recovery**: Restart DNS service and re-test before resuming

---

**Document Version**: 1.0  
**Last Updated**: April 19, 2026  
**Owner**: @kushin77 (issue #888 lead)  
**Status**: Active (enforced via CI)
