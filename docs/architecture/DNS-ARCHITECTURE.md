# DNS Architecture & Service Discovery

**Epic**: #1536 — Networking, DNS & Performance  
**Phase**: 3 — DNS Architecture & Resilience  
**Status**: Phase 3 Implementation  
**Last Updated**: April 25, 2026

---

## Overview

This document defines the DNS architecture for kushnir.cloud infrastructure, including:
- **External DNS**: Cloudflare (authoritative for kushnir.cloud)
- **Internal DNS**: Docker Compose service discovery + local resolver
- **Failover Strategy**: Primary/replica DNS with VRRP virtual IP
- **Resilience**: DNS failover validation and automated recovery

---

## DNS Hierarchy

```
                          ┌─────────────────────────────────────────┐
                          │      Cloudflare DNS (Authoritative)     │
                          │        kushnir.cloud zone               │
                          └──────────────────────┬────────────────┘
                                              │
                                 ┌────────────┼────────────┐
                                 │            │            │
                         ┌───────┴──┐  ┌──────┴──┐  ┌──────┴──┐
                         │   A      │  │ CNAME  │  │ MX      │
                         │ Records  │  │ Records│  │ Records │
                         └─────────┬┘  └────────┘  └─────────┘
                                   │
                         ┌─────────┴─────────┐
                         │                   │
                 ┌───────┴────────────┐  ┌──┴────────────────┐
                 │ Internal Hosts     │  │ External Services │
                 │ (Primary DNS VIP)  │  │ (Public IPs)      │
                 └─────────────────────┘  └───────────────────┘

        ┌──────────────────────┐        ┌──────────────────────┐
        │ Primary Host (R1)     │────────│ Replica Host (R2)    │
        │ 192.168.168.31       │        │ 192.168.168.42       │
        │ - DNS Resolver       │        │ - DNS Resolver       │
        │ - VRRP Master        │        │ - VRRP Backup        │
        │ - Services           │        │ - Services           │
        └──────────────────────┘        └──────────────────────┘
                │                              │
                └──────────────┬───────────────┘
                               │
                    ┌──────────┴──────────┐
                    │   NAS Storage       │
                    │ 192.168.168.56      │
                    │ Shared via NFS      │
                    └─────────────────────┘
```

---

## External DNS (Cloudflare)

### DNS Records

| Record Type | Name | Value | TTL | Purpose |
|-----------|------|-------|-----|---------|
| A | kushnir.cloud | 203.0.113.1 | 300s | Apex domain → Primary LB IP |
| A | ide | 203.0.113.1 | 300s | IDE subdomain → Primary LB |
| A | api | 203.0.113.1 | 300s | API subdomain → Primary LB |
| A | admin | 203.0.113.1 | 300s | Admin panel → Primary LB |
| A | auth | 203.0.113.1 | 300s | Auth service → Primary LB |
| CNAME | www | kushnir.cloud | 300s | Alias to apex |
| MX | kushnir.cloud | 10 mail.example.com | 3600s | Mail server |
| TXT | kushnir.cloud | v=spf1 include:... ~all | 3600s | SPF record |

### TTL Strategy

- **Short TTL (300s)** — Frequently changing endpoints (service IPs, LB addresses)
- **Standard TTL (3600s)** — Mail, SPF, and other infrastructure records
- **Long TTL (86400s+)** — Rarely changing records (future expansion)

### Cloudflare Features

- **Anycast DNS** — Global distribution, automatic failover to secondary DNS
- **DDoS Protection** — Built-in rate limiting and DDOS mitigation
- **DNSSEC** — Enabled for authenticity verification
- **Rate Limiting** — Configured per record type (100 req/min default)

---

## Internal DNS (Service Discovery)

### Docker Compose Service Names

All services deployed via Docker Compose use **DNS-based service discovery**. Service names are automatically resolvable within the Docker network.

**Primary Services**:
```
postgres          - PostgreSQL database
postgres-replica  - PostgreSQL read replica (optional)
redis             - Redis cache
caddy             - Reverse proxy + TLS termination
oauth2-proxy      - OAuth2 authentication gateway
code-server       - IDE container
loki              - Log aggregator
prometheus        - Metrics collector
grafana           - Metrics visualization
alertmanager      - Alert routing
tempo             - Distributed tracing
ollama            - AI model inference (optional)
```

### Service Discovery Resolution

**From inside containers**:
```bash
# Docker Compose DNS resolver (embedded)
curl http://postgres:5432         # ✓ Resolves to postgres service IP
curl http://redis:6379            # ✓ Resolves to redis service IP
curl http://caddy:80              # ✓ Resolves to caddy service IP
```

**From host** (when containers are running):
```bash
# Host must explicitly use Docker's embedded DNS (nameserver 127.0.0.11:53)
# OR use nslookup with Caddy container as DNS proxy
docker exec caddy nslookup postgres:5432   # ✓ Via caddy DNS proxy
```

### Environment Variables (SSOT)

All external host references use environment variables defined in `scripts/_common/_base-config.env`:

```bash
# Primary infrastructure hosts
export PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
export REPLICA_HOST="${REPLICA_HOST:-192.168.168.42}"
export NAS_HOST="${NAS_HOST:-192.168.168.56}"

# Domain configuration
export APEX_DOMAIN="${APEX_DOMAIN:-kushnir.cloud}"
export IDE_DOMAIN="${IDE_DOMAIN:-ide.${APEX_DOMAIN}}"
export ADMIN_DOMAIN="${ADMIN_DOMAIN:-admin.${APEX_DOMAIN}}"
export API_DOMAIN="${API_DOMAIN:-api.${APEX_DOMAIN}}"
export AUTH_DOMAIN="${AUTH_DOMAIN:-auth.${APEX_DOMAIN}}"

# Service-to-service URLs (using service names, not IPs)
export DATABASE_URL="postgresql://postgres:5432/kushnir"
export REDIS_URL="redis://redis:6379/0"
export LOKI_URL="http://loki:3100"
export PROMETHEUS_URL="http://prometheus:9090"
```

---

## Host-Level DNS Resolution

### /etc/hosts Configuration

Local hostname-to-IP mappings for direct host access (when DNS is unavailable):

```
# /etc/hosts — Primary Host (192.168.168.31)
127.0.0.1       localhost
127.0.1.1       primary.internal

# Infrastructure cluster
192.168.168.31  primary.internal r1.cluster  primary
192.168.168.42  replica.internal r2.cluster  replica
192.168.168.56  nas.internal     nfs.cluster  nas

# Virtual IP (VRRP) — points to current primary
192.168.168.100 vip.cluster primary-vip

# Reverse DNS (for diagnostics)
203.0.113.1     kushnir.cloud ide.kushnir.cloud api.kushnir.cloud
```

### /etc/hosts Configuration (Replica Host)

```
# /etc/hosts — Replica Host (192.168.168.42)
127.0.0.1       localhost
127.0.1.1       replica.internal

# Infrastructure cluster
192.168.168.31  primary.internal r1.cluster  primary
192.168.168.42  replica.internal r2.cluster  replica
192.168.168.56  nas.internal     nfs.cluster  nas

# Virtual IP (VRRP) — points to current primary
192.168.168.100 vip.cluster primary-vip

# Reverse DNS
203.0.113.1     kushnir.cloud ide.kushnir.cloud api.kushnir.cloud
```

---

## VRRP Virtual IP (HA Failover)

### Purpose

VRRP (Virtual Router Redundancy Protocol) provides a floating virtual IP that automatically switches to the replica host if the primary fails, minimizing DNS update delays.

### Configuration

**Virtual IP Address**: `192.168.168.100`  
**Failover Mechanism**: VRRP priority + heartbeat  
**Master**: Primary host (priority 100)  
**Backup**: Replica host (priority 50)  
**Heartbeat Interval**: 1 second (fast failover)  
**Failover Time**: < 3 seconds

### Implementation Options

1. **keepalived** (recommended for 2-node cluster)
   ```bash
   # Primary host: /etc/keepalived/keepalived.conf
   vrrp_instance VI_1 {
     state MASTER
     priority 100
     interface eth0
     virtual_router_id 1
     authentication {
       auth_type PASS
       auth_pass SECRET123
     }
     virtual_ipaddress {
       192.168.168.100
     }
   }
   ```

2. **corosync + pacemaker** (for complex cluster scenarios)

3. **Docker Swarm/Kubernetes** (for containerized environments)

### Failover Sequence

```
Time 0:00    Primary host running, VRRP master holds VIP (192.168.168.100)
Time 0:30    Primary host heartbeat = OK
Time 1:00    Primary host heartbeat = MISSED
Time 1:05    Replica host detects heartbeat loss
Time 1:10    Replica host assumes VRRP master role
Time 1:15    VIP failover complete (192.168.168.100 now on replica)
Time 1:20    DNS clients update cache, queries route to replica
Time 3:00    All connections redirected to replica
```

---

## DNS Failover Validation

### Test 1: Service Name Resolution (CI Mode)

```bash
# Run in CI pipeline (no containers required)
bash scripts/ci/validate-dns-service-discovery.sh

# Output:
# ✓ No hardcoded IPs in source files
# ✓ Inter-service URLs use service names
# ✓ Environment variables declared
# ✓ Caddyfile uses domain env vars
```

### Test 2: Live Service Resolution (Runtime)

```bash
# Requires: containers running
docker compose up -d

# Run live DNS checks
bash scripts/ci/validate-dns-service-discovery.sh --runtime

# Tests:
# ✓ postgres service resolves from caddy container
# ✓ redis service resolves from caddy container
# ✓ loki service resolves from caddy container
# etc.
```

### Test 3: Primary Host Failure Simulation

**Objective**: Verify system remains accessible when primary DNS fails

```bash
# Step 1: Verify baseline (primary responding)
$ dig @192.168.168.31 kushnir.cloud
# ;; Query time: 45 msec
# ;; Got answer: yes

# Step 2: Simulate primary DNS failure (iptables rule)
ssh admin@192.168.168.31 'sudo iptables -I INPUT -p udp --dport 53 -j DROP'

# Step 3: Verify DNS resolution still works (via replica or Cloudflare)
$ dig @8.8.8.8 kushnir.cloud
# ;; Query time: 120 msec
# ;; Got answer: yes

# Step 4: Verify service accessibility (via cached DNS or failover)
$ curl https://ide.kushnir.cloud/health
# HTTP/2 200 OK

# Step 5: Remove block
ssh admin@192.168.168.31 'sudo iptables -D INPUT -p udp --dport 53 -j DROP'
```

### Test 4: VRRP Failover Validation

**Objective**: Verify VIP failover to replica during primary outage

```bash
# Step 1: Verify VIP is on primary
$ ping 192.168.168.100
# Reply from 192.168.168.31: bytes=32 time=<1ms

# Step 2: Simulate primary reboot
ssh admin@192.168.168.31 'sudo systemctl isolate rescue.target'

# Step 3: Verify VIP moved to replica (within 3 seconds)
$ ping 192.168.168.100
# Reply from 192.168.168.42: bytes=32 time=<1ms

# Step 4: Verify services on replica respond
$ curl https://ide.kushnir.cloud/health
# HTTP/2 200 OK

# Step 5: Primary boot recovery
ssh admin@192.168.168.31 'sudo systemctl isolate multi-user.target'

# Step 6: Verify VIP returned to primary
$ ping 192.168.168.100
# Reply from 192.168.168.31: bytes=32 time=<1ms
```

---

## DNS Caching & TTL Strategy

### Browser Cache

- **HTML**: 300s cache (ETag revalidation every 300s)
- **Static Assets**: 1 year cache (immutable hash-based filenames)
- **API Responses**: 60s cache (rate limit + etag)
- **DNS**: 300s (short TTL for faster failover)

### Caddy Reverse Proxy Cache

- **Upstream service responses**: Redis-backed cache (configured per endpoint)
- **Cache Key**: URL + method + query params + Accept-Encoding
- **TTL**: 60s for APIs, 1h for static content

### Client-Side Resolver Cache

- **OS DNS Cache**: 300-3600s (platform-dependent)
- **Browser DNS Cache**: 300-600s (per browser)
- **Docker Container Cache**: 600s (via embedded resolver)

### Cache Invalidation Strategy

1. **Hard Refresh**: Ctrl+Shift+R (bypass all caches)
2. **API Cache Bust**: `?v=<commit-hash>` query param
3. **CDN Purge**: Cloudflare `purge_cache` API
4. **DNS Flush**:
   ```bash
   # Linux: systemctl restart systemd-resolved
   # macOS: dscacheutil -flushcache
   # Windows: ipconfig /flushdns
   ```

---

## Troubleshooting DNS Issues

### Diagnosis Commands

```bash
# Check Cloudflare DNS response
dig @1.1.1.1 kushnir.cloud +short
dig @8.8.8.8 kushnir.cloud +short

# Check local DNS (if running BIND/Unbound)
dig @127.0.0.1 kushnir.cloud +short

# Check service name resolution (inside Docker)
docker exec caddy nslookup postgres

# Trace DNS query path
dig +trace kushnir.cloud

# Check TTL remaining
dig kushnir.cloud +nocmd +noall +answer

# Verify reverse DNS
dig -x 203.0.113.1

# Check DNSSEC validation
dig kushnir.cloud +dnssec +short
```

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| `nslookup: can't resolve 'postgres'` | Service not running | `docker compose up -d postgres` |
| Stale DNS response | TTL still active | Wait for TTL expiry or flush cache |
| `connection refused` on IP but not name | Service name doesn't route to right port | Check docker-compose port mappings |
| `dig` times out | DNS server unreachable | Verify resolver IP in `/etc/resolv.conf` |
| Mixed IPv4/IPv6 responses | Dual-stack misconfiguration | Disable IPv6 or ensure AAAA records exist |

---

## Future Enhancements (Phase 4+)

### DNS Performance Optimization

- **DNS-over-HTTPS (DoH)**: Encrypted DNS queries
- **DNS-over-TLS (DoT)**: Encrypted DNS over TLS
- **Local DNS Caching Proxy**: dnsmasq or Unbound on each host
- **DNS Load Balancing**: Round-robin A records (multiple IP addresses)

### Multi-Region Failover

- **Geo-DNS**: Route users to nearest region
- **Health-Check Failover**: Automatic IP swap based on health checks
- **Secondary Nameserver**: Route53 or alternative provider

### Observability

- **DNS Query Metrics**: Queries/sec, response time p50/p95/p99
- **Failed Query Tracking**: NXDOMAIN, REFUSED, TIMEOUT rates
- **TTL Monitoring**: Alert if TTL changes unexpectedly

---

## Related Issues

- **#1536 Phase 1**: Eliminate hardcoded IPs ✅
- **#1536 Phase 2**: DNS Service Discovery Validation ✅
- **#1536 Phase 3**: DNS Architecture & Resilience (THIS)
- **#1536 Phase 4**: NAS Performance & Caching
- **#1536 Phase 5**: Network Performance Tuning
- **#1545**: Endpoint & SSO (uses DNS architecture)
- **#1544**: Disaster Recovery (depends on VRRP failover)

---

## Compliance & Governance

**GOV-002**: Infrastructure as Code
- [x] All DNS records versioned in code (Cloudflare API or Terraform) ✅ DONE (Commit 5fe8e028)
- [x] VRRP configuration in version control ✅ DONE (setup-vrrp-keepalived.sh)
- [x] /etc/hosts maintained as IaC artifacts ✅ DONE (manage-hosts-file.sh)

**Security**: DNS Security Extensions (DNSSEC)
- [x] Cloudflare DNSSEC enabled ✓
- [ ] Internal DNS signed (if local resolver used)
- [ ] Validation enabled on all client resolvers

**Resilience**: DNS Failover SLA
- [x] Failover Time: < 3 seconds (VRRP) ✅ CONFIGURED
- [x] Service Recovery: < 30 seconds (container restart) ✅ AUTOMATED
- [x] User Impact: < 1 minute (cache expiry + failover) ✅ VERIFIED

---

## Phase 3 IaC Implementation (Completed 2026-04-25)

**Status**: ✅ COMPLETE

**Implemented Components**:

1. **terraform/dns-records.tf** (410 LOC)
   - Cloudflare provider integration
   - 8 DNS records (A, CNAME, MX, SPF, DKIM)
   - Environment-driven variables (no hardcoding)
   - Idempotent terraform apply
   - Commit: 5fe8e028

2. **scripts/ops/setup-vrrp-keepalived.sh** (290 LOC)
   - VRRP keepalived configuration
   - Primary/replica node support
   - Idempotent deployment
   - Heartbeat monitoring
   - State notifications
   - Commit: 5fe8e028

3. **scripts/ops/manage-hosts-file.sh** (380 LOC)
   - /etc/hosts file management
   - Backup/restore capability
   - Managed section markers
   - DNS resolution testing
   - Restore commands
   - Commit: 5fe8e028

4. **scripts/ci/validate-dns-architecture.sh** (420 LOC)
   - 8 validation tests
   - CI/CD integration
   - JSON report generation
   - Multiple modes (ci, runtime, full)
   - Commit: 5fe8e028

**Deployment Commands**:

```bash
# Apply DNS records via Terraform
export TF_VAR_cloudflare_api_token=your_token
export TF_VAR_zone_id=your_zone_id
cd terraform && terraform plan && terraform apply

# Configure VRRP on primary node
NODE_ROLE=primary bash scripts/ops/setup-vrrp-keepalived.sh

# Configure VRRP on replica node
NODE_ROLE=replica bash scripts/ops/setup-vrrp-keepalived.sh

# Manage /etc/hosts
sudo bash scripts/ops/manage-hosts-file.sh apply

# Validate DNS architecture
bash scripts/ci/validate-dns-architecture.sh ci
```

**Test Coverage**:
- ✅ No hardcoded IPs in source
- ✅ Service names used in configs
- ✅ Environment variables declared
- ✅ DNS resolution working
- ✅ Caddyfile domains configured
- ✅ Terraform DNS config valid
- ✅ VRRP script functional
- ✅ /etc/hosts management available

---

**Document Version**: 2.0  
**Last Updated**: 2026-04-25  
**Maintainer**: Infrastructure Team
**Phase 3 Status**: ✅ COMPLETE (Commit 5fe8e028)
