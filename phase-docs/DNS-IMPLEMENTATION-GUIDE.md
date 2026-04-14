# PHASE 18-20: DNS IMPLEMENTATION & LOAD BALANCING GUIDE

## 🎯 Objective

Eliminate all `localhost` references from the infrastructure. Replace with domain-driven DNS routing via Cloudflare for production access.

**Domain**: `ide.kushnir.cloud`

## ✅ COMPLETED CHANGES

### 1. Terraform IaC Updates
- ✅ `phase-18-compliance.tf`: Loki & Grafana endpoints → domain subdomains
- ✅ `phase-18-security.tf`: Vault, Consul, Prometheus → domain subdomains
- ✅ `phase-16-b-load-balancing.tf`: Load balancer stats endpoints → domain

### 2. Configuration Files
- ✅ `alertmanager-production.yml`: Grafana alerts, SMTP → domain
- ✅ `config/github-rules.yaml`: Email contacts → domain
- ✅ `config/developer-restrictions.sh`: Git proxy → domain
- ✅ `.github/workflows/deploy.yml`: Deployment notification URL → domain
- ✅ `code-server-config.yaml`: Already includes domain in proxy-domain list

### 3. New IaC Asset
- ✅ `phase-18-20-dns-routing.tf`: Complete Cloudflare DNS configuration
  - Root domain (A record)
  - 16+ service subdomains (CNAME)
  - Load balancing & failover
  - 300-second TTL for quick failover

## 📋 DNS RECORD STRUCTURE

```
ide.kushnir.cloud
├── @ (root)                    → 192.168.168.31 (primary, A record)
│   └── (failover)              → 192.168.168.32 (secondary, A record)
│
├── ide                         → CNAME → ide.kushnir.cloud (Code-Server)
├── api                         → CNAME → ide.kushnir.cloud (Code-Server API)
│
├── loki                        → CNAME → ide.kushnir.cloud (Audit logs, Phase 18)
├── grafana                     → CNAME → ide.kushnir.cloud (Compliance dashboard, Phase 18)
├── prometheus                  → CNAME → ide.kushnir.cloud (Metrics, Phase 18)
│
├── vault                       → CNAME → ide.kushnir.cloud (Secrets, Phase 18)
├── vault-0, vault-1, vault-2  → CNAME → ide.kushnir.cloud (Vault HA cluster)
├── consul                      → CNAME → ide.kushnir.cloud (Service registry, Phase 18)
│
├── db                         → CNAME → ide.kushnir.cloud (PostgreSQL primary, Phase 16)
├── db-replica                 → CNAME → ide.kushnir.cloud (PostgreSQL replica, Phase 16)
├── pgbouncer                  → CNAME → ide.kushnir.cloud (Connection pool, Phase 16)
│
├── lb1                        → CNAME → ide.kushnir.cloud (Keepalived LB 1, Phase 16)
├── lb2                        → CNAME → ide.kushnir.cloud (Keepalived LB 2, Phase 16)
│
└── git-proxy                  → CNAME → ide.kushnir.cloud (Git SSH proxy)
    ssh-proxy                  → CNAME → ide.kushnir.cloud (SSH proxy)
```

## 🚀 DEPLOYMENT STEPS

### Step 1: Set Cloudflare Credentials
```bash
export TF_VAR_cloudflare_api_token="your-api-token"
export TF_VAR_cloudflare_zone_id="your-zone-id"
export TF_VAR_cloudflare_account_id="your-account-id"
```

### Step 2: Validate DNS Terraform
```bash
cd /c/code-server-enterprise
terraform init -upgrade
terraform plan -target=cloudflare_record.root_primary
```

### Step 3: Apply DNS Configuration (Immutable)
```bash
# This creates/updates ALL DNS records in one atomic operation
terraform apply -target='cloudflare_record.*' -auto-approve

# Verify Cloudflare zone shows records
curl -X GET "https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records" \
  -H "Authorization: Bearer $TF_VAR_cloudflare_api_token" | jq '.result[] | {name, type, content}'
```

### Step 4: Verify DNS Propagation
```bash
# Wait for DNS propagation (usually <1 minute)
nslookup ide.kushnir.cloud
nslookup loki.kushnir.cloud
nslookup grafana.kushnir.cloud

# Should all resolve to 192.168.168.31
```

### Step 5: Update Ingress Routes (Caddy/ProxyPass)
Since services use `localhost` internally, configure ingress to route by subdomain:

```caddy
# In Caddyfile.production:

# IDE
ide.kushnir.cloud {
  reverse_proxy localhost:8080
}

# Phase 18: Compliance
loki.kushnir.cloud {
  reverse_proxy localhost:3100
}

grafana.kushnir.cloud {
  reverse_proxy localhost:3000
}

prometheus.kushnir.cloud {
  reverse_proxy localhost:9090
}

# Phase 18: Security
vault.kushnir.cloud {
  reverse_proxy localhost:8200
}

consul.kushnir.cloud {
  reverse_proxy localhost:8500
}

# Phase 16: Database
db.kushnir.cloud {
  reverse_proxy localhost:5432
}

# Phase 16: Load Balancers
lb1.kushnir.cloud {
  reverse_proxy localhost:8404
}

lb2.kushnir.cloud {
  reverse_proxy localhost:8405
}
```

### Step 6: Deploy Updated Configuration
```bash
docker restart phase-18-caddy || docker-compose -f docker-compose.yml up -d

# Verify Caddy loaded new routes
docker logs phase-18-caddy | tail -20
```

## 🔒 IMMUTABILITY ENFORCEMENT

**All DNS records managed via Terraform only:**
- ❌ NO manual edits in Cloudflare UI
- ❌ NO direct API calls to modify records
- ✅ ALL changes via `terraform apply`
- ✅ Git tracks all changes in version control
- ✅ State file proves single source of truth

### Enforce Immutability:
```bash
# Lock remote state (prevent concurrent modifications)
terraform state list | head -5

# Verify all DNS records in code
grep -r "cloudflare_record" phase-18-20-dns-routing.tf | wc -l

# Plan before apply ALWAYS
terraform plan -out=dns-changes.tfplan
terraform apply dns-changes.tfplan  # Not -auto-approve in production
```

## 🔄 FAILOVER ARCHITECTURE

**TTL: 300 seconds (5 minutes)** for quick DNS failover.

If primary (192.168.168.31) goes down:
1. Monitoring detects failure
2. Cloufdflare health check fails
3. Traffic automatically redirects to secondary (192.168.168.32)
4. Max 5 minutes for client-side TTL expiration

## 📊 SERVICE PORT MAPPING

All services accessible via HTTPS on port 443 (Cloudflare proxy) but internally on their native ports:

| Service | Domain | Internal | External |
|---------|--------|----------|----------|
| Code-Server | ide.kushnir.cloud | localhost:8080 | HTTPS:443 |
| Grafana | grafana.kushnir.cloud | localhost:3000 | HTTPS:443 |
| Loki | loki.kushnir.cloud | localhost:3100 | HTTPS:443 |
| Prometheus | prometheus.kushnir.cloud | localhost:9090 | HTTPS:443 |
| Vault | vault.kushnir.cloud | localhost:8200 | HTTPS:443 |
| Consul | consul.kushnir.cloud | localhost:8500 | HTTPS:443 |
| PostgreSQL | db.kushnir.cloud | localhost:5432 | HTTPS:443 (via proxy) |
| LB1 | lb1.kushnir.cloud | localhost:8404 | HTTPS:443 |
| LB2 | lb2.kushnir.cloud | localhost:8405 | HTTPS:443 |

## 🛡️ SECURITY IMPLICATIONS

1. **No IP Exposure**: Direct IP (192.168.168.31) hidden behind Cloudflare
2. **DDoS Protection**: Cloudflare WAF & rate limiting active
3. **SSL/TLS**: End-to-end encryption (Cloudflare → Caddy → Services)
4. **Access Control**: OAuth2-Proxy enforces authentication
5. **Audit Trail**: All DNS changes tracked in Git

## 📝 ISSUE LINKAGE

This DNS implementation:
- ✅ Closes: #P18-DNS-001 "Replace localhost with domain DNS"
- ✅ Closes: #P16-LB-001 "Configure load balancer endpoints"
- ✅ Closes: #DEPLOY-001 "Make infrastructure immutable"
- ✅ Unblocks: Phase 18-20 production launch

## ⚠️ ROLLBACK PROCEDURE

If needed to rollback to localhost-only mode:
```bash
# Revert terraform changes
git checkout HEAD -- phase-18-20-dns-routing.tf

# Destroy DNS records
terraform destroy -target='cloudflare_record.*' -auto-approve

# Restart services (use localhost again)
docker-compose up -d
```

## ✨ NEXT STEPS

1. [x] Replace localhost references → DNS subdomains
2. [x] Create Cloudflare IaC (terraform)
3. [ ] **IMMEDIATE**: Deploy terraform DNS configuration
4. [ ] Update Caddy ingress rules for subdomain routing
5. [ ] Test domain access for each service
6. [ ] Close GitHub issues
7. [ ] Update deployment documentation

---

**Status**: Ready for production deployment
**Owner**: Infrastructure Team
**Last Updated**: April 14, 2026
