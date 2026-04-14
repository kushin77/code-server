# DNS-FIRST ARCHITECTURE GUIDE (Phase 21+)

## 🎯 CRITICAL PRINCIPLE: Environment-Driven DNS Resolution

All infrastructure endpoints are resolved via **DNS names**, NOT hardcoded IPs. Single source of truth: **`DOMAIN`** environment variable.

```
External Access:
  Client → DOMAIN (e.g., 192.168.168.31.nip.io) → Caddy Reverse Proxy
                                                     ↓
Internal Service Discovery (Docker DNS):
  Caddy → code-server:8080 (container DNS, not hardcoded IP)
       → ollama:11434
       → prometheus:9090
       → grafana:3000
       → etc.
```

## 🔧 CONFIGURATION

### 1. Environment Variables (docker-compose.yml)

```yaml
caddy:
  environment:
    # Primary: Domain for external access
    - DOMAIN=${DOMAIN:-192.168.168.31.nip.io}

    # Secondary: ACME email for Let's Encrypt
    - ACME_EMAIL=${ACME_EMAIL:-ops@kushnir.cloud}
```

### 2. Terraform Variables (variables.tf)

```terraform
variable "external_domain" {
  description = "External domain for DNS-based access"
  default     = "192.168.168.31.nip.io"  # On-prem default
}

variable "acme_email" {
  description = "Email for Let's Encrypt ACME"
  default     = "ops@kushnir.cloud"
}
```

### 3. Caddyfile Configuration

The Caddyfile uses `{$DOMAIN}` placeholder to dynamically accept any domain:

```caddy
{$DOMAIN:192.168.168.31.nip.io}

:80 {
    # IDE endpoint
    @ide_requests host code-server.{$DOMAIN:192.168.168.31.nip.io}
    handle @ide_requests {
        reverse_proxy code-server:8080
    }

    # Metrics endpoint
    @prometheus_requests host prometheus.{$DOMAIN:192.168.168.31.nip.io}
    handle @prometheus_requests {
        reverse_proxy prometheus:9090
    }
}
```

## 📊 DEPLOYMENT SCENARIOS

### Scenario 1: On-Premises (Current Phase 21)

**Configuration:**
```bash
export DOMAIN=192.168.168.31.nip.io
export ACME_EMAIL=  # Empty → auto_https off
```

**DNS Resolution:**
- External: `192.168.168.31.nip.io` → HTTP (no TLS)
- Internal: `code-server:8080` → Container DNS

**Benefit:** No infrastructure cost, instant deployment

### Scenario 2: Production (Phase 22+)

**Configuration:**
```bash
export DOMAIN=kushnir.cloud
export ACME_EMAIL=ops@kushnir.cloud
```

**DNS Resolution:**
- External: `kushnir.cloud` → Cloudflare DNS → HTTPS (Let's Encrypt)
- Internal: Same as on-prem (no IP changes)

**Benefit:** Real TLS certificates, professional branding

### Scenario 3: IP Failover (No Code Changes)

**ON-PREM TO DIFFERENT IP:**
```bash
# From 192.168.168.31 → 192.168.168.40
export DOMAIN=192.168.168.40.nip.io
docker compose up -d  # Redeploy
```

**Result:** All service endpoints automatically update. Clients seamlessly reconnect.

**Why This Works:**
- Caddyfile doesn't hardcode IPs → nip.io resolves to new IP
- Service-to-service communication uses container DNS (IP-transparent)
- Load balancers/proxies forward to new Docker network → works automatically

## 🏗️ ARCHITECTURE DECISIONS

### 1. Why nip.io for On-Premises?

| Feature | localhost | IP:port | nip.io |
|---------|-----------|---------|--------|
| Hardcoded IP? | ❌ Single box only | ✅ Brittle | ❌ Dynamic |
| Works across network? | ❌ No | ✅ Yes | ✅ Yes |
| HTTPS support? | ⚠️ Self-signed | ⚠️ Self-signed | ✅ With ACME |
| Domain subdomains? | ❌ No | ❌ No | ✅ Yes |
| Zero infrastructure? | ✅ No DNS setup | ✅ No DNS setup | ✅ No DNS setup |

**Winner: nip.io** (zero DNS infrastructure, respects domain subdomains, scales to production)

### 2. Why Not Hardcode Domains in Code?

**WRONG WAY (Phase 20 and earlier):**
```caddy
# ❌ Hardcoded — breaks when IP changes
@ide_requests host code-server.ide.kushnir.cloud
reverse_proxy code-server:8080
```

**PROBLEM:** Update IP from 192.168.168.31 → .32 requires code changes, redeployment

**RIGHT WAY (Phase 21+):**
```caddy
# ✅ Environment-driven — works with any IP/domain
@ide_requests host code-server.{$DOMAIN:192.168.168.31.nip.io}
reverse_proxy code-server:8080
```

**BENEFIT:** Single `export DOMAIN=<new-ip>.nip.io` → full redeploy works

### 3. Why Container DNS for Internal Services?

**CORRECT:** Services communicate via container name
```caddy
reverse_proxy code-server:8080  # Docker DNS resolves this → 172.28.0.2:8080
```

**WRONG:** Hardcode IP addresses
```caddy
reverse_proxy 172.28.0.2:8080  # ❌ Brittle, breaks on container restart
```

**Benefit of Container DNS:**
- IPs ephemeral (Docker rebalances on restart)
- Service name stable (docker-compose service name)
- Built-in health checks & failover (Docker networking)

## 📍 SERVICE DISCOVERY CHAIN

### Example: Code-Server IDE Access

1. **EXTERNAL:**
   ```
   Browser → http://code-server.192.168.168.31.nip.io
        ↓ (DNS: nip.io returns 192.168.168.31)
        → Caddy on 192.168.168.31:80
   ```

2. **INTERNAL (Caddy → code-server):**
   ```
   Caddy container (172.28.0.3:80)
        → resolves "code-server" via Docker DNS
        → gets IP 172.28.0.2 (code-server container)
        → connects to 172.28.0.2:8080
   ```

3. **NO HARDCODED IPs:**
   - If code-server restarts → Docker DNS returns new IP
   - If Caddy restarts → Docker network reassigns IP
   - Both services find each other automatically

## 🔄 MIGRATION PATH: IP/Domain Change

### Current State:
```
DOMAIN=192.168.168.31.nip.io
Host IP: 192.168.168.31
```

### Desired State (migrate to new host):
```
DOMAIN=192.168.168.40.nip.io
Host IP: 192.168.168.40
```

### Migration Steps:

1. **SSH to new host (192.168.168.40):**
   ```bash
   ssh akushnir@192.168.168.40
   cd code-server-enterprise
   ```

2. **Clone/pull latest code:**
   ```bash
   git clone https://github.com/kushin77/code-server-enterprise.git .
   ```

3. **Update environment:**
   ```bash
   # Set new domain for THIS host
   export DOMAIN=192.168.168.40.nip.io
   export ACME_EMAIL=ops@kushnir.cloud
   ```

4. **Deploy:**
   ```bash
   docker compose up -d
   ```

5. **Update DNS (if using production domain):**
   ```bash
   # Cloudflare API: Update A record → 192.168.168.40
   curl -X PUT https://api.cloudflare.com/client/v4/zones/.../dns_records/... \
     -H "Authorization: Bearer <token>" \
     -d '{"content": "192.168.168.40"}'
   ```

6. **Verify all services:**
   ```bash
   # All these should work:
   curl http://192.168.168.40.nip.io/healthz
   curl http://code-server.192.168.168.40.nip.io/healthz
   curl http://prometheus.192.168.168.40.nip.io/api/v1/targets
   ```

**Result:** Zero code changes, infrastructure moves seamlessly.

## 🔒 SECURITY IMPLICATIONS

### On-Premises (nip.io + HTTP)
- ✅ No TLS overhead (faster, 0% CPU cost)
- ✅ nip.io resolves to private IP (not exposed on public internet)
- ✅ Container network isolated (no external routing)
- ⚠️ No encryption (acceptable for on-prem only)

### Production (kushnir.cloud + HTTPS)
- ✅ Full TLS via Let's Encrypt (automatic renewal)
- ✅ Public DNS (explicit firewall rules needed)
- ✅ Encryption in transit (GDPR/SOC2 compliant)
- ⚠️ Certificate renewal adds 10ms overhead (negligible)

## 📝 IMPLEMENTATION CHECKLIST

- [x] Caddyfile uses `{$DOMAIN}` placeholder
- [x] docker-compose.yml passes DOMAIN + ACME_EMAIL
- [x] Terraform variables.tf defines external_domain + acme_email
- [x] code-server-config.yaml includes wildcard proxy domains
- [x] All service routes use container DNS (e.g., `prometheus:9090`)
- [x] No hardcoded IPs in Caddy/config files
- [x] On-prem default: `192.168.168.31.nip.io`
- [x] Production ready: Change one variable → full migration

## 🚀 NEXT PHASES

### Phase 22: Production Migration
1. Register `kushnir.cloud` domain
2. Set Cloudflare DNS → 192.168.168.31 (initial)
3. Set `DOMAIN=kushnir.cloud` + `ACME_EMAIL=ops@kushnir.cloud`
4. Caddyfile auto-generates Let's Encrypt cert
5. All endpoints switch to HTTPS

### Phase 23: High Availability
1. Set up second host (192.168.168.32)
2. `DOMAIN=kushnir.cloud` (shared)
3. Cloudflare failover: 192.168.168.31 → 192.168.168.32
4. Clients reconnect automatically

### Phase 24+: Global CDN
1. Cloudflare CDN caching for static assets
2. Edge locations worldwide
3. Single `DOMAIN` variable → global deployment

## 📚 FILES MODIFIED (Phase 21)

1. **Caddyfile** — DNS-first reverse proxy config
2. **config/caddy/Caddyfile** — Same (for terraform generation)
3. **docker-compose.yml** — DOMAIN + ACME_EMAIL env vars
4. **docker-compose.tpl** — Template for codegen
5. **variables.tf** — external_domain + acme_email variables
6. **main.tf** — locals include new variables
7. **code-server-config.yaml** — Dynamic proxy-domain list

## ✅ VERIFICATION

```bash
# Check Caddyfile loaded with correct DOMAIN
docker exec caddy caddy reload

# Check reverse proxy routes
curl -v http://192.168.168.31.nip.io/healthz
curl -v http://code-server.192.168.168.31.nip.io/

# Check metrics accessible
curl http://prometheus.192.168.168.31.nip.io/api/v1/targets

# Check service-to-service DNS
docker exec prometheus nslookup caddy
docker exec caddy nslookup prometheus
```

## 🔗 RELATED ARCHITECTURE

- **Phase 20:** Hardcoded domains (deprecated)
- **Phase 21:** DNS-first with nip.io (current)
- **Phase 22+:** Production migration to kushnir.cloud
- **ADR-001:** Cloudflare Tunnel Architecture (alternative approach)
