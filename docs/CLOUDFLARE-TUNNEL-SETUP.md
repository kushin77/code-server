# Cloudflare Tunnel Setup Guide

**Date**: April 15, 2026  
**Platform**: Production (ide.kushnir.cloud)  
**Host**: 192.168.168.31 (primary)  

---

## Overview

Cloudflare Tunnel provides secure, encrypted access to private infrastructure without exposing public IPs or ports. All traffic routes through Cloudflare's global edge network.

**Benefits**:
- ✅ Zero Trust security (identity-based access)
- ✅ DDoS protection included
- ✅ Automatic TLS/SSL
- ✅ Global CDN acceleration
- ✅ Private IP never exposed
- ✅ No firewall rules needed

---

## Architecture

```
[User] → [Cloudflare Edge] → [Tunnel] → [192.168.168.31:8080]
        (TLS termination)    (encrypted)    (private network)
        (DDoS protection)
```

---

## Prerequisites

- Cloudflare account with domain: kushnir.cloud
- Access to 192.168.168.31 via SSH
- DNS control for kushnir.cloud
- API token from Cloudflare dashboard

---

## Quick Start

### Step 1: Get Cloudflare API Token

1. Go to https://dash.cloudflare.com/
2. Sign in to your account
3. Navigate to API Tokens
4. Create Token with permissions:
   - Zone Settings (read)
   - DNS (edit)
   - Tunnels (read & edit)
5. Copy token (keep secret)

### Step 2: Run Setup Script

```bash
# SSH to primary host
ssh akushnir@192.168.168.31

# Navigate to repo
cd code-server-enterprise

# Set credentials (replace with your token)
export CLOUDFLARE_API_TOKEN="your-token-here"
export CLOUDFLARE_ACCOUNT_ID="your-account-id"
export CLOUDFLARE_TUNNEL_TOKEN="your-tunnel-token"
export CLOUDFLARE_TUNNEL_ID="your-tunnel-uuid"

# Run setup
bash scripts/setup-cloudflare-tunnel.sh
```

### Step 3: Verify Access

```bash
# Test DNS resolution
nslookup ide.kushnir.cloud

# Test HTTPS access
curl -v https://ide.kushnir.cloud/healthz

# Check tunnel status
systemctl status cloudflared
```

---

## Manual Setup (If Script Fails)

### Install cloudflared

```bash
# Add Cloudflare repository
curl -L https://pkg.cloudflare.com/cloudflare-release.key | gpg --import
echo "deb [signed-by=/etc/apt/trusted.gpg.d/cloudflare.gpg] https://pkg.cloudflare.com/linux/$(lsb_release -sc) $(lsb_release -sc) main" | \
  tee /etc/apt/sources.list.d/cloudflare-release.list

# Install
apt-get update
apt-get install -y cloudflared
```

### Create Tunnel

```bash
# List existing tunnels
cloudflared tunnel list

# Or create new tunnel
cloudflared tunnel create code-server-production

# Get tunnel credentials
cat ~/.cloudflared/[tunnel-uuid].json
```

### Configure cloudflared

**File**: `/etc/cloudflared/config.yml`

```yaml
tunnel: code-server-production
token: <your-tunnel-token>
credentials-file: /root/.cloudflared/credentials.json

logLevel: info
logfile: /var/log/cloudflared/tunnel.log

ingress:
  # Code-server IDE
  - hostname: ide.kushnir.cloud
    service: http://localhost:8080
    originRequest:
      httpHostHeader: ide.kushnir.cloud
      
  # Monitoring endpoints (optional)
  - hostname: prometheus.ide.kushnir.cloud
    service: http://localhost:9090
    
  - hostname: grafana.ide.kushnir.cloud
    service: http://localhost:3000
    
  # Catch-all
  - service: http_status:503
```

### Create Systemd Service

**File**: `/etc/systemd/system/cloudflared.service`

```ini
[Unit]
Description=Cloudflare Tunnel
After=network.target
StartLimitInterval=0
StartLimitBurst=0

[Service]
Type=simple
User=cloudflare-tunnel
WorkingDirectory=/etc/cloudflared
ExecStart=/usr/bin/cloudflared tunnel --config /etc/cloudflared/config.yml run
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=cloudflared

[Install]
WantedBy=multi-user.target
```

### Enable & Start

```bash
# Create service user
useradd -r -M -s /usr/sbin/nologin cloudflare-tunnel || true

# Enable service
systemctl daemon-reload
systemctl enable cloudflared
systemctl start cloudflared

# Verify
systemctl status cloudflared
```

---

## DNS Configuration

### Cloudflare DNS Records

Add CNAME records in Cloudflare dashboard:

| Type | Name | Target | Proxied |
|------|------|--------|---------|
| CNAME | ide | {tunnel-uuid}.cfargotunnel.com | Yes |
| CNAME | *.ide | {tunnel-uuid}.cfargotunnel.com | Yes |

Or via Terraform:

```bash
# Apply Cloudflare configuration
cd terraform
terraform plan -target=cloudflare_record.ide_main
terraform apply -target=cloudflare_record.ide_main
```

---

## Monitoring

### Check Tunnel Status

```bash
# View logs
journalctl -u cloudflared -f

# Check connectivity
systemctl status cloudflared

# View stats
curl http://localhost:7878/metrics  # Prometheus format
```

### Prometheus Metrics

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'cloudflared'
    metrics_path: '/metrics'
    static_configs:
      - targets: ['localhost:7878']
```

### Alert Rules

```yaml
# prometheus-rules.yml
groups:
  - name: cloudflare
    rules:
      - alert: CloudflareTunnelDown
        expr: up{job="cloudflared"} == 0
        for: 2m
        annotations:
          summary: "Cloudflare Tunnel is not responding"
          
      - alert: CloudflareTunnelHighLatency
        expr: tunnel_latency_ms > 1000
        for: 5m
        annotations:
          summary: "Cloudflare Tunnel latency > 1000ms"
```

---

## Troubleshooting

### Tunnel Not Connecting

**Symptom**: `Connection failed` in logs

**Solution**:
```bash
# 1. Verify token is valid
cat /etc/cloudflared/config.yml | grep token

# 2. Check DNS resolution
nslookup ide.kushnir.cloud

# 3. Restart service
systemctl restart cloudflared

# 4. View detailed logs
journalctl -u cloudflared -n 100 -p debug
```

### DNS Not Resolving

**Symptom**: `nslookup ide.kushnir.cloud` returns NXDOMAIN

**Solution**:
```bash
# 1. Verify DNS records exist
dig ide.kushnir.cloud +short

# 2. Check Cloudflare dashboard
# - Navigate to DNS tab
# - Verify CNAME records are created
# - Check that "Proxied" is enabled (orange cloud)

# 3. Wait for DNS propagation (5-10 minutes)
# Use nslookup with Cloudflare nameserver
nslookup ide.kushnir.cloud 1.1.1.1
```

### Slow Access / High Latency

**Symptom**: Accessing ide.kushnir.cloud is slow

**Solution**:
```bash
# 1. Check tunnel metrics
curl http://localhost:7878/metrics | grep latency

# 2. Verify primary host is responsive
curl http://localhost:8080/healthz

# 3. Check network connectivity
ping 192.168.168.31

# 4. View tunnel performance
# Cloudflare Dashboard → Tunnels → code-server-production
```

### Multiple Tunnel Instances

**Symptom**: Multiple cloudflared processes running

**Solution**:
```bash
# 1. Stop all instances
killall cloudflared || true

# 2. Disable and cleanup
systemctl disable cloudflared
systemctl disable cloudflared@*

# 3. Restart cleanly
systemctl start cloudflared
systemctl status cloudflared
```

---

## Failover & Disaster Recovery

### Primary Goes Down

If 192.168.168.31 fails:

1. Tunnel automatically detects origin is down (within 30 seconds)
2. Returns HTTP 503 Service Unavailable
3. HAProxy (if configured) routes to replica

Recovery:

```bash
# 1. Bring primary back online
ssh akushnir@192.168.168.31
docker-compose up -d

# 2. Wait for services to start (~1 minute)
sleep 60

# 3. Tunnel automatically reconnects
journalctl -u cloudflared | grep "Connection established"

# 4. Monitor health
curl https://ide.kushnir.cloud/healthz
```

### Fallback to IP-Based Access

If Cloudflare tunnel fails completely:

```bash
# Use direct SSH tunneling instead
ssh -L 8080:192.168.168.31:8080 akushnir@192.168.168.31

# Then access locally
curl http://localhost:8080
```

---

## Security Considerations

### Credential Management

- ✅ Never commit tokens to git
- ✅ Store tokens in GitHub Secrets or environment variables
- ✅ Rotate tokens every 90 days
- ✅ Use least-privilege tokens

### Origin Authentication

Enable Cloudflare Origin CA certificates:

```bash
# Generate certificate
cloudflared tunnel ingress-rule --hostname=ide.kushnir.cloud

# Install on origin (192.168.168.31)
cp certificate.pem /etc/cloudflared/
cp key.pem /etc/cloudflared/
```

### DDoS Protection

Cloudflare automatically provides:
- ✅ Network-layer DDoS mitigation (L3/L4)
- ✅ Application-layer protection (L7)
- ✅ Rate limiting
- ✅ WAF (Web Application Firewall)

Configure in Cloudflare dashboard:
1. Security → DDoS Protection → Configure
2. Security → WAF → Add Rules
3. Rate Limiting → Create Rules

---

## Cost

**Cloudflare Tunnel**: Free tier includes:
- ✅ 1 tunnel per account
- ✅ Unlimited bandwidth
- ✅ Basic DDoS protection
- ✅ SSL/TLS included

**Paid tiers** (if needed):
- Pro: $20/month (advanced analytics)
- Business: $200/month (priority support, advanced WAF)

---

## Next Steps

1. ✅ Tunnel configured and tested
2. → Set up HAProxy load balancer (Phase 7d-002)
3. → Configure health checks (Phase 7d-003)
4. → Chaos testing (Phase 7e)

---

## References

- [Cloudflare Tunnel Documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [cloudflared Command Reference](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/run-tunnel/routing-to-tunnel/)
- [Terraform Cloudflare Provider](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs)

---

**Version**: 1.0  
**Last Updated**: April 15, 2026  
**Status**: Production-Ready
