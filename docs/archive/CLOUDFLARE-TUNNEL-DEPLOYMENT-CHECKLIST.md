# Cloudflare Tunnel Deployment Checklist (#348)

**Status**: Pre-Deployment Ready  
**Target**: 192.168.168.31 (Primary Production Host)  
**Estimated Deployment Time**: 15-20 minutes  
**Last Updated**: April 17, 2026

---

## Pre-Deployment Requirements

### 1. **Cloudflare Credentials & Configuration**

- [ ] Cloudflare account active and accessible (https://dash.cloudflare.com)
- [ ] kushnir.cloud zone added to Cloudflare account
- [ ] Cloudflare Account ID obtained (e.g., `123abc456def`)
- [ ] Cloudflare Zone ID for kushnir.cloud obtained (e.g., `789ghi012jkl`)
- [ ] Cloudflare API Token created with permissions:
  - [ ] Zone.Zone:read
  - [ ] Zone.DNS:edit
  - Token stored in Vault or .env

### 2. **Cloudflare Tunnel Creation**

Execute on 192.168.168.31 (production host):

```bash
ssh akushnir@192.168.168.31
cd code-server-enterprise

# Install cloudflared CLI (if not already installed)
# Download: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation/

# Create tunnel for primary host
cloudflared tunnel create code-server-primary
# Output: Tunnel created successfully, ID: {uuid}
# Token stored at: ~/.cloudflared/{uuid}.json

# Create tunnel for replica host (optional, for failover)
cloudflared tunnel create code-server-replica
# Output: Tunnel created successfully, ID: {uuid2}
# Token stored at: ~/.cloudflared/{uuid2}.json

# Store tokens in .env or Vault
export CLOUDFLARE_TUNNEL_TOKEN=$(cat ~/.cloudflared/{uuid}.json | jq -r '.TunnelToken')
```

### 3. **Environment Variables**

Ensure the following are in .env or Vault on 192.168.168.31:

```bash
CLOUDFLARE_API_TOKEN=xxx...xxx
CLOUDFLARE_ACCOUNT_ID=123abc456def
CLOUDFLARE_ZONE_ID=789ghi012jkl
CLOUDFLARE_TUNNEL_TOKEN=ey...xxx
CLOUDFLARE_TUNNEL_NAME_PREFIX=code-server
CLOUDFLARE_TUNNEL_VERSION=2024.1.5
```

### 4. **Network & DNS**

- [ ] Port 443 (HTTPS) accessible from 192.168.168.31 to Cloudflare edge
- [ ] No outbound firewall blocks on cloudflared egress
- [ ] DNS resolution working: `dig kushnir.cloud` resolves
- [ ] No conflicting A records for ide.kushnir.cloud (should be CNAME)

---

## Deployment Steps

### Phase 1: Terraform Configuration (5 min)

```bash
ssh akushnir@192.168.168.31
cd code-server-enterprise

# Load environment variables
source .env

# Initialize Terraform backend
cd terraform
terraform init -backend-config=backend-config.hcl

# Validate configuration
terraform validate
# Expected: Success, all blocks valid

# Plan deployment
terraform plan -out=cloudflare-plan.tfplan
# Review plan output, verify:
# - cloudflare_tunnel resources created
# - DNS CNAME records configured
# - WAF rules deployed
# - Health checks enabled
```

### Phase 2: Terraform Apply (5 min)

```bash
# Apply the plan
terraform apply cloudflare-plan.tfplan

# Expected output:
# Apply complete! Resources added = X (tunnels, DNS, WAF rules, etc.)

# Verify state
terraform state list | grep cloudflare_tunnel
# Expected: cloudflare_tunnel.code_server_primary, .code_server_replica
```

### Phase 3: Docker Service Deployment (3 min)

```bash
# Back to code-server-enterprise root
cd /path/to/code-server-enterprise

# Verify docker-compose has cloudflared service
grep -A 20 "cloudflared:" docker-compose.yml

# Start cloudflared service
docker-compose up -d cloudflared

# Verify container started
docker-compose ps cloudflared
# Expected: UP X seconds (healthy)

# Check logs
docker-compose logs cloudflared --tail 30
# Expected: "Connected to tunnel" OR "Tunnel authenticated"
```

### Phase 4: Verification Tests (10 min)

#### A. **Tunnel Status**

```bash
# From production host
docker exec cloudflared cloudflared tunnel info
# Expected: Shows tunnel ID, authenticated status, zone name
```

#### B. **DNS Resolution**

```bash
# From local machine
dig ide.kushnir.cloud
# Expected CNAME: ide.kushnir.cloud CNAME {uuid}.cfargotunnel.com
# Expected A record: {uuid}.cfargotunnel.com A {Cloudflare IP}

# Verify NOT pointing to private IP
dig ide.kushnir.cloud +short | grep -q "192.168"
# Expected: Returns nothing (not pointing to 192.168.x.x)

# Global DNS check from multiple locations
# Use online tool: https://dnschecker.org/
# Should show CNAME to cfargotunnel.com from all regions
```

#### C. **HTTPS Connectivity**

```bash
# From local machine
curl -v https://ide.kushnir.cloud/healthz
# Expected:
# < HTTP/2 200
# < content-type: application/json
# { "status": "healthy" }

# Verify TLS version
echo | openssl s_client -connect ide.kushnir.cloud:443 2>/dev/null | grep "TLSv"
# Expected: TLSv1.3 (or TLSv1.2 minimum)

# Verify certificate
curl -vI https://ide.kushnir.cloud 2>&1 | grep -A5 "Server certificate"
# Expected: Let's Encrypt cert, valid for kushnir.cloud
```

#### D. **WAF Rules Validation**

```bash
# Test path traversal block
curl 'https://ide.kushnir.cloud/../etc/passwd'
# Expected: 403 Forbidden (WAF blocked)

# Test SQL injection block
curl 'https://ide.kushnir.cloud/?id=1 OR 1=1'
# Expected: 403 Forbidden (WAF blocked)

# Test legitimate request (still works)
curl 'https://ide.kushnir.cloud/healthz'
# Expected: 200 OK (legitimate traffic passes)
```

#### E. **Prometheus Metrics**

```bash
# From inside the network
curl http://localhost:9090/api/v1/query?query=cloudflared_tunnel_status
# Expected: metric returned, value = 1 (tunnel connected)

curl http://localhost:9090/api/v1/query?query='cloudflared_tunnel_latency_ms'
# Expected: latency metric visible (e.g., 50-100ms)

# Check in Prometheus UI
# Open: http://192.168.168.31:9090
# Query: cloudflared_tunnel_status{tunnel="code_server_primary"}
# Expected: Returns 1 (connected)
```

#### F. **AlertManager Rules**

```bash
# Check alert rules loaded
curl http://localhost:9093/api/v1/alerts
# Expected: See Cloudflare tunnel alerts listed

# Verify no active alerts (tunnel should be healthy)
curl http://localhost:9093/api/v1/alerts?status=firing
# Expected: No "CloudflareTunnelDown" or "CloudflareTunnelLatency" alerts
```

---

## Post-Deployment Verification (SLA)

| Check | Command | Expected | SLA |
|-------|---------|----------|-----|
| **Tunnel Up** | `dig ide.kushnir.cloud` | CNAME to cfargotunnel.com | 100% |
| **HTTPS Works** | `curl https://ide.kushnir.cloud` | HTTP 200 | 100% |
| **TLS 1.3** | `openssl s_client` | TLSv1.3 | 100% |
| **WAF Blocks Attacks** | `curl ?id=1 OR 1=1` | 403 Forbidden | 100% |
| **Metrics Visible** | Prometheus query | cloudflared_tunnel_status=1 | 100% |
| **Latency** | Prometheus metric | < 200ms p99 | < 200ms |
| **Uptime** | Cloudflare dashboard | > 99.99% | 99.99% SLA |

---

## Rollback Procedure (< 60 seconds)

If issues arise post-deployment:

```bash
# Option 1: Quick Service Rollback
docker-compose stop cloudflared
# Traffic will fail-open (Cloudflare returns 503) until tunnel returns

# Option 2: DNS Rollback
# In Cloudflare dashboard:
# 1. Change ide.kushnir.cloud CNAME back to direct A record
# 2. Update A record to point to on-prem load balancer
# 3. Verify DNS propagation
# Impact: 5-10 minute TTL propagation

# Option 3: Terraform Rollback
cd terraform
terraform destroy -target=cloudflare_tunnel.code_server_primary -auto-approve
# Removes tunnel resource, stops Cloudflare routing

# Option 4: Full Revert (Git)
git revert HEAD  # Reverts cloudflare commit
git push origin phase-7-deployment
# Requires re-running CI/CD pipeline
```

**Recommended**: Keep the service simple enough that "stop cloudflared" works as immediate rollback.

---

## Monitoring & Operations

### Continuous Monitoring

- **Prometheus**: http://192.168.168.31:9090
  - Query: `cloudflared_tunnel_status{tunnel="code_server_primary"}`
  - Query: `cloudflared_tunnel_latency_ms`
  - Query: `cloudflared_waf_blocked_requests_total`

- **Grafana**: http://192.168.168.31:3000
  - Dashboard: "Cloudflare Tunnel Status" (auto-created)
  - Shows: Tunnel health, latency, WAF events, error rates

- **AlertManager**: http://192.168.168.31:9093
  - Alerts: CloudflareTunnelDown, CloudflareTunnelLatency, CloudflareWAFBlockSpike

### Daily Health Checks

```bash
# Daily 9am check (production host)
#!/bin/bash
set -e

echo "🔍 Cloudflare Tunnel Daily Health Check"

# 1. Tunnel status
tunnel_status=$(curl -s http://localhost:9090/api/v1/query?query=cloudflared_tunnel_status | jq '.data.result[0].value[1]' | sed 's/"//g')
echo "✅ Tunnel Status: $tunnel_status (1=up, 0=down)"

# 2. DNS resolution
dig_result=$(dig ide.kushnir.cloud +short | tail -1)
echo "✅ DNS Resolution: $dig_result"

# 3. HTTPS connectivity
http_code=$(curl -s -o /dev/null -w "%{http_code}" https://ide.kushnir.cloud/healthz)
echo "✅ HTTPS Status: HTTP $http_code"

# 4. Container health
container_status=$(docker-compose ps cloudflared | grep -c "healthy" || echo "0")
echo "✅ Container Health: $container_status/1 healthy"

echo ""
echo "✨ All checks passed!"
```

---

## Known Issues & Workarounds

### Issue: Tunnel token invalid or expired

**Solution**: Regenerate tunnel token
```bash
cloudflared tunnel delete code-server-primary
cloudflared tunnel create code-server-primary
# Extract new token and update .env / Vault
```

### Issue: DNS not resolving (still points to old A record)

**Solution**: Wait for TTL or flush cache
```bash
# Client machine:
ipconfig /flushdns  # Windows
# or
sudo dscacheutil -flushcache  # macOS
# or
sudo systemctl restart systemd-resolved  # Linux

# Check propagation: https://dnschecker.org/
```

### Issue: WAF blocking legitimate traffic

**Solution**: Check WAF rule logs and adjust
```bash
# In Cloudflare dashboard:
# 1. Go to Security > WAF > Managed Rules
# 2. Check "Block" vs "Challenge" mode
# 3. Review recent blocked requests
# 4. Add exceptions for false positives
```

### Issue: High latency through tunnel (> 500ms)

**Solution**: Check network path
```bash
# From production host:
ping -c 3 1.1.1.1  # Check upstream connectivity
# Check outbound iptables rules
iptables -L -v -n | grep -i "cloudflared\|443"
# May need to whitelist cloudflared egress in firewall
```

---

## Success Criteria

- [ ] All terraform resources created (state shows 8+ resources)
- [ ] docker-compose ps shows cloudflared healthy
- [ ] `dig ide.kushnir.cloud` returns CNAME to cfargotunnel.com
- [ ] `curl https://ide.kushnir.cloud/healthz` returns 200
- [ ] TLS version is 1.3 (verified with openssl)
- [ ] WAF rules block path traversal (403 response)
- [ ] Prometheus metrics visible (cloudflared_tunnel_status = 1)
- [ ] No active alerts in AlertManager
- [ ] Latency < 200ms p99
- [ ] Uptime SLA > 99.99%

---

## Issue #348 Completion Checklist

- [x] Terraform configuration prepared (terraform/cloudflare.tf)
- [x] Variables defined (terraform/variables.tf)
- [x] Docker service defined (docker-compose.yml)
- [x] Deployment script ready (scripts/deploy-cloudflare-tunnel.sh)
- [x] Prometheus alert rules added (config/prometheus/alert-rules.yml)
- [x] Environment variables documented (.env.example)
- [x] Operations runbook created (docs/runbooks/CLOUDFLARE-TUNNEL-OPERATIONS.md)
- [x] Troubleshooting guide created (docs/CLOUDFLARE-TUNNEL-TROUBLESHOOTING.md)
- [ ] **PENDING**: Actual deployment to production (requires SSH access to 192.168.168.31)
- [ ] **PENDING**: Verification tests (requires real Cloudflare credentials)
- [ ] **PENDING**: WAF rule testing (requires test client traffic)
- [ ] **PENDING**: Final PR merge to main

---

## Next Steps

1. **Obtain Cloudflare Credentials**
   - Register kushnir.cloud in Cloudflare dashboard
   - Generate API tokens with appropriate permissions
   - Store in .env or Vault on 192.168.168.31

2. **Create Tunnel Credentials**
   - SSH to 192.168.168.31
   - Run `cloudflared tunnel create code-server-primary`
   - Extract token and update .env

3. **Execute Deployment**
   - Follow "Deployment Steps" section above
   - Run terraform apply + docker-compose up
   - Execute verification tests

4. **Monitor & Observe**
   - Watch Prometheus metrics for 1 hour post-deployment
   - Verify AlertManager has no firing alerts
   - Check Cloudflare dashboard for tunnel status

5. **Merge to Main**
   - Once verified in production
   - Create PR with "production-ready" approval
   - Merge to main branch
   - Trigger CI/CD for default branch

---

**Deployment Ready**: ✅  
**Prerequisites Complete**: ⏳ (waiting for Cloudflare credentials)  
**SLA Target**: 99.99% uptime  
**Rollback Time**: < 60 seconds
