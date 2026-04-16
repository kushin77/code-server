# Cloudflare Tunnel Troubleshooting Guide

**Last Updated**: April 15, 2026  
**Service**: ide.kushnir.cloud  
**Status Dashboard**: https://dash.cloudflare.com/

---

## Quick Diagnosis

```bash
# Run this command to get diagnostic info
ssh akushnir@192.168.168.31 << 'EOF'
echo "=== TUNNEL STATUS ==="
docker-compose ps cloudflared
docker-compose logs cloudflared --tail 20

echo "=== CONTAINER CONNECTIVITY ==="
docker exec cloudflared cloudflared tunnel info

echo "=== DNS RESOLUTION ==="
docker exec cloudflared nslookup ide.kushnir.cloud

echo "=== ORIGIN REACHABILITY ==="
docker exec cloudflared curl -v http://code-server:8080/healthz

echo "=== PROMETHEUS METRICS ==="
curl -s 'http://prometheus:9090/api/v1/query?query=cloudflared_tunnel_status' | jq .

echo "=== DOCKER NETWORK ==="
docker network inspect enterprise | jq '.[] | {Name, Containers}'
EOF
```

---

## Symptom-Based Troubleshooting

### **Symptom A: `curl https://ide.kushnir.cloud` → Connection Timeout**

**What it means**: Request doesn't even reach Cloudflare edge (DNS failure or BGP issue)

**Diagnosis**:
```bash
# Check DNS resolution
nslookup ide.kushnir.cloud 1.1.1.1

# Expected output:
# Non-authoritative answer:
# ide.kushnir.cloud  canonical name = {tunnel-uuid}.cfargotunnel.com
# {tunnel-uuid}.cfargotunnel.com  address = {Cloudflare IP like 172.64.x.x}

# If you get 192.168.168.31, YOUR PRIVATE IP IS EXPOSED!
# This should NEVER happen for ide.kushnir.cloud
```

**If DNS is wrong**:
```bash
# Check Terraform state
cd terraform
terraform state show cloudflare_record.ide_tunnel

# Verify DNS record is CNAME (not A record)
# Expected:
# type    = "CNAME"
# value   = "{tunnel-uuid}.cfargotunnel.com"
# proxied = true

# If wrong, fix it
terraform apply -target=cloudflare_record.ide_tunnel
# Wait 5 minutes for DNS propagation

# Force clear local DNS cache
sudo resolvectl flush-caches  # Linux
sudo dscacheutil -flushcache  # macOS
ipconfig /flushdns            # Windows
```

**If DNS is correct but still timeout**:
- Check your internet connection
- Try from different network (to rule out ISP DNS hijacking)
- Ping Cloudflare edge: `ping 1.1.1.1`

---

### **Symptom B: `curl https://ide.kushnir.cloud` → HTTP 502 Bad Gateway**

**What it means**: Cloudflare received your request, but tunnel can't deliver it to origin

**Diagnosis**:
```bash
# Step 1: Is cloudflared container running?
docker-compose ps cloudflared

# Expected: Up X minutes (healthy)
# If "Exited" or "Restarting", the tunnel is down

# Step 2: Check cloudflared logs
docker-compose logs cloudflared | tail -30

# Expected patterns:
# ✓ "Connected to tunnel"
# ✓ "Listening for requests on hostname"
# ✗ "Failed to authenticate"  → token invalid
# ✗ "Connection refused"      → can't reach origin

# Step 3: Is code-server reachable?
docker exec cloudflared curl -v http://code-server:8080/healthz

# Expected: 200 OK
# If connection refused, origin is down
```

**Recovery**:
```bash
# CASE 1: cloudflared exited
docker-compose logs cloudflared | grep -i "error"
# Fix the error, restart:
docker-compose restart cloudflared
docker-compose logs cloudflared --tail 20  # verify "Connected"

# CASE 2: code-server is down
docker-compose ps code-server
docker-compose logs code-server | tail -30

# Restart code-server
docker-compose restart code-server
sleep 10  # wait for startup
docker-compose logs code-server | tail -5

# Test again
docker exec cloudflared curl -v http://code-server:8080/healthz

# CASE 3: Docker network issue
# The container can't reach other containers by name
docker network inspect enterprise

# If "code-server" not in Containers list:
docker-compose up -d code-server
docker network connect enterprise code-server  # force reconnect

# Restart tunnel
docker-compose restart cloudflared
```

---

### **Symptom C: `curl https://ide.kushnir.cloud` → HTTP 403 Forbidden**

**What it means**: Your request was blocked by Cloudflare WAF rules

**Diagnosis**:
```bash
# Check response headers
curl -v https://ide.kushnir.cloud/?test=1

# Look for header: cf-ray: xxxxxxx-LAX
# This ID is the blocked request in Cloudflare logs

# Access Cloudflare Security Events
# https://dash.cloudflare.com → Security → Events
# Paste the CF-RAY ID to find the blocked request
# It will show which WAF rule blocked it
```

**Recovery**:
```bash
# Option 1: Disable overly aggressive rule
# In Terraform, find the rule ID from Cloudflare Events
# Edit terraform/cloudflare.tf
# Change: mode = "block"  →  mode = "challenge"  (JavaScript challenge instead)

cd terraform
terraform apply
# Test again

# Option 2: Whitelist your IP
# In terraform/cloudflare.tf, add exception:
resource "cloudflare_firewall_rule" "whitelist_home" {
  zone_id     = data.cloudflare_zone.kushnir_cloud.id
  description = "Whitelist home IP"
  filter_id   = cloudflare_firewall_filter.home_ip.id
  action      = "allow"
}

resource "cloudflare_firewall_filter" "home_ip" {
  zone_id    = data.cloudflare_zone.kushnir_cloud.id
  expression = "(ip.src eq YOUR_IP_HERE)"
}

cd terraform && terraform apply

# Option 3: Check if it's a legitimate false positive
# Example: query string contains "1 or 1=1" (SQL injection test)
# If intentional test, you need to fix your URL or disable that rule temporarily
```

---

### **Symptom D: Tunnel Connected but Prometheus Shows Down**

**What it means**: Cloudflared is running, but Prometheus metric says `cloudflared_tunnel_status = 0`

**Diagnosis**:
```bash
# Cloudflared might not be exporting metrics yet
# (it takes ~30 seconds after startup)

# Check if Falco is running
docker-compose logs falco | tail -30

# Wait 1 minute and re-query
sleep 60
curl 'http://prometheus:9090/api/v1/query?query=cloudflared_tunnel_status' | jq .
```

**Recovery**:
```bash
# Ensure cloudflared metrics are enabled
docker-compose config cloudflared | grep -i metric

# Check prometheus scrape config
cat config/prometheus/prometheus.yml | grep -A 5 'cloudflared'

# Expected:
# - job_name: 'cloudflared'
#   static_configs:
#     - targets: ['cloudflared:7878']

# If missing, add it and reload Prometheus
echo "
- job_name: 'cloudflared'
  static_configs:
    - targets: ['cloudflared:7878']
" >> config/prometheus/prometheus.yml

docker exec prometheus kill -HUP 1  # reload config
sleep 10
curl 'http://prometheus:9090/api/v1/query?query=cloudflared_tunnel_status' | jq .
```

---

### **Symptom E: DNS Shows 192.168.168.31 Instead of Cloudflare IP**

**🚨 CRITICAL: Your private IP is exposed!**

**What it means**: DNS record is misconfigured (A record instead of CNAME)

**Immediate Action**:
```bash
# STOP everything
docker-compose down

# Check Terraform
cd terraform
git log --oneline cloudflare.tf | head -5
# See if someone modified the DNS record

# Verify what's deployed
terraform state show cloudflare_record.ide_tunnel
# Should show: type = "CNAME", proxied = true
# If type = "A" or proxied = false, CRITICAL

# Fix it
terraform apply -target=cloudflare_record.ide_tunnel

# Verify the fix
dig ide.kushnir.cloud

# Should show CNAME to cfargotunnel.com, NOT A record to 192.168.168.31
```

**Root Cause Analysis**:
- Someone ran `terraform apply` with wrong variables
- Old DNS record from before Tunnel migration
- Cloudflare UI manual edit (overrides Terraform)

**Prevention**:
```bash
# Protect the Terraform state
cd terraform
# Ensure terraform.tfstate is in .gitignore (never commit secrets)
grep 'terraform.tfstate' ../.gitignore

# Use Terraform locking
terraform state lock cloudflare_record.ide_tunnel

# Only allow DNS changes via Terraform (not Cloudflare UI)
```

---

## Advanced Debugging

### **Check Tunnel Connectivity from Inside Container**

```bash
ssh akushnir@192.168.168.31

# Inside cloudflared container:
docker exec cloudflared sh << 'EOF'

# 1. Check tunnel connection
cloudflared tunnel info
# Look for: "ID: {uuid}", "Status: connected"

# 2. Check DNS (from container perspective)
nslookup ide.kushnir.cloud
# Should resolve to Cloudflare IP, NOT 192.168.168.31

# 3. Check routing
cloudflared tunnel route show
# Should show: ide.kushnir.cloud → http://192.168.168.31:8080

# 4. Forcefully authenticate
cloudflared tunnel login
# Will prompt for Cloudflare origin certificate

# 5. Check metrics endpoint
curl localhost:7878/metrics | grep tunnel_status
# Should show: cloudflared_tunnel_status 1

EOF
```

### **Monitor Real-Time Traffic**

```bash
# Watch all tunnel requests (verbose)
docker exec cloudflared cloudflared tunnel run --loglevel debug 2>&1 | grep -i "http\|connected\|error"

# Or check tcpdump (traffic between tunnel and origin)
sudo tcpdump -i docker0 'tcp port 8080' -v

# From origin perspective:
docker exec code-server netstat -an | grep 8080
# Should show ESTABLISHED connections from cloudflared container IP
```

### **Tunnel Token Issues**

```bash
# View current token (redacted)
cat .env | grep CLOUDFLARE_TUNNEL_TOKEN | cut -c1-50

# Decode token to check expiry
ENCODED=$(cat .env | grep CLOUDFLARE_TUNNEL_TOKEN | cut -d= -f2)
echo "$ENCODED" | base64 -d | strings | head -20

# If token is invalid/expired, rotate it
# https://dash.cloudflare.com → Tunnels → code-server-production → Rotate Token
# Update .env and restart cloudflared
```

---

## Performance Issues

### **High Latency (>500ms)**

**Diagnosis**:
```bash
# Check latency metric
curl 'http://prometheus:9090/api/v1/query?query=cloudflared_tunnel_latency_seconds' | jq .

# High latency usually due to:
# 1. Cloudflare edge location far from user (network routing)
# 2. Origin server slow (code-server CPU-bound)
# 3. Tunnel congestion (multiple users hammering it)

# Check origin performance
time curl http://code-server:8080/healthz
# If this takes > 200ms, origin is the bottleneck
```

**Recovery**:
```bash
# 1. Check code-server CPU/memory
docker stats code-server

# If high: restart code-server
docker-compose restart code-server

# 2. Check network quality
ping -c 5 8.8.8.8  # to Cloudflare edge

# 3. Select closer Cloudflare edge
# Can't override (Cloudflare chooses geographically)
# But can improve origin → ensure code-server is responsive
```

---

## Rollback Procedure

**If Cloudflare Tunnel causes problems, quickly disable it:**

```bash
# 1. Revert to previous commit
git log --oneline | head -10
git revert <commit-with-cloudflare-changes>

# 2. Update DNS to point directly to origin (temporary)
dig ide.kushnir.cloud +short
# Should show: current A record pointing to 192.168.168.31

# If it doesn't, manually set A record in Cloudflare:
# https://dash.cloudflare.com → DNS → create A record
# ide.kushnir.cloud → 192.168.168.31 (TEMPORARY)

# 3. Restart all services
docker-compose restart
docker-compose ps

# 4. Test
curl https://ide.kushnir.cloud/healthz

# 5. Root cause analysis
# Document what went wrong in `incident-YYY-MM-DD.md`
```

---

## Escalation

If you can't resolve the issue in 15 minutes:

1. **Slack**: #production-incidents → @kushin77
2. **Email**: ops@kushnir.cloud with:
   - Symptom description
   - Output of: `docker-compose logs cloudflared --tail 50`
   - Output of: `curl -v https://ide.kushnir.cloud/` (with headers)
3. **Cloudflare Status Page**: Check https://www.cloudflarestatus.com/

---

**This document auto-links errors to their solutions. Bookmark for quick reference!**
