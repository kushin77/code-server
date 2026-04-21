# DNS Architecture & Configuration — kushin77/code-server

**Last Updated**: April 21, 2026  
**Status**: ✅ PRODUCTION READY  
**Architecture**: Cloudflare-based load balancing with automatic failover

---

## DNS Overview

The `kushnir.cloud` domain uses Cloudflare for DNS management, TLS termination, and intelligent failover routing. This provides global CDN acceleration, DDoS protection, and automatic failover without requiring on-prem VRRP or additional complexity.

### Current Architecture

```
Internet Traffic (HTTPS)
        ↓
Cloudflare Edge (173.77.179.148)
  - TLS termination
  - WAF / DDoS protection
  - Geo-routing
  - Health monitoring
        ↓
Primary Host (192.168.168.31)
  - code-server IDE
  - All core services
        ↓ (if primary fails)
Replica Host (192.168.168.42)
  - Standby copy
  - Automatic takeover
```

---

## DNS Records

### Primary Record: ide.kushnir.cloud

| Property | Value | Type |
|----------|-------|------|
| Record | ide.kushnir.cloud | A |
| Primary IP | 192.168.168.31 | On-prem primary |
| TTL | 60 seconds | Low for fast failover |
| Proxy | ✅ Proxied (orange cloud) | Cloudflare |
| Health Check | ✅ Enabled | HTTP /health endpoint |

### Failover Configuration

| Property | Value |
|----------|-------|
| Failover Pool | 192.168.168.42 (replica) |
| Health Check Endpoint | /health |
| Health Check Interval | 30 seconds |
| Failure Threshold | 2 consecutive failures |
| Failover Response | Automatic |

---

## Health Check Configuration

### Endpoint
```
URL: http://192.168.168.31/health
Method: GET
Expected Status: 200 OK
Expected Body: "OK"
```

### Monitoring Parameters
```
Check Interval:        30 seconds (how often Cloudflare checks)
Timeout:              5 seconds (max wait for response)
Retries:              2 (before marking as unhealthy)
Unhealthy Threshold:  2 (consecutive failures)
Healthy Threshold:    1 (consecutive success)
```

### Failover Trigger
```
Condition: Primary health check fails 2 consecutive times
Timeline:
  T+0s:   Health check request sent
  T+5s:   Timeout (no response)
  T+30s:  Next health check sent
  T+35s:  Timeout again
  T+60s:  Marked unhealthy, failover triggered
  T+62s:  DNS record updated to replica IP
  T+63s:  Clients see replica IP in DNS

Total Time: ~60 seconds from failure to failover
```

---

## Setup Instructions

### 1. Cloudflare Dashboard Access

```
1. Log into: https://dash.cloudflare.com
2. Navigate to: kushnir.cloud zone
3. Tab: "DNS" or "Traffic"
4. Look for: ide.kushnir.cloud A record
```

### 2. Configure Health Check

```
Dashboard Path:
  Transforms → Health Checks → Create

Settings:
  - Type: HTTPS
  - Protocol: HTTP
  - Path: /health
  - Port: 80 (HTTP, since behind Cloudflare)
  - Interval: 30 seconds
  - Timeout: 5 seconds
  - Regions: US, EU, APAC (or All)
  - Notifications: Enable
```

### 3. Configure Failover Pool

```
Dashboard Path:
  Reliability → Load Balancing → Create Pool

Primary Pool:
  Name: Primary
  Monitor: Health check from step 2
  Origin: 192.168.168.31

Failover Pool:
  Name: Replica
  Monitor: Same health check
  Origin: 192.168.168.42

Load Balancer (points to Primary, failover to Replica):
  Default Pool: Primary
  Fallback Pool: Replica
  TTL: 60 seconds
```

### 4. Verify Configuration

```bash
# From local machine:
nslookup ide.kushnir.cloud
# Expected: Returns 192.168.168.31 (primary IP)

# Check if Cloudflare shows primary as healthy:
# Dashboard → Health Checks → Check status
# Expected: Status = "Healthy" (blue check mark)

# Simulate failure by stopping primary health endpoint:
ssh akushnir@192.168.168.31
docker stop caddy  # Stops health endpoint

# Wait 60 seconds, then check DNS:
nslookup ide.kushnir.cloud
# Expected: Returns 192.168.168.42 (replica IP after failover)

# Restart and verify failback:
docker start caddy
sleep 60
nslookup ide.kushnir.cloud
# Expected: Returns back to 192.168.168.31
```

---

## DNS Query Flow

### Normal Flow (Primary Healthy)

```
Client Query: "What is ide.kushnir.cloud?"
       ↓
Cloudflare DNS Resolver
       ↓
Perform Health Check: GET /health on 192.168.168.31
       ↓ (200 OK)
Return Primary IP: 192.168.168.31
       ↓
Client connects to 192.168.168.31 (primary)
```

### Failover Flow (Primary Down)

```
Client Query: "What is ide.kushnir.cloud?"
       ↓
Cloudflare DNS Resolver
       ↓
Perform Health Check: GET /health on 192.168.168.31
       ↓ (Timeout/Error)
Check Failover Pool: 192.168.168.42
       ↓
Perform Health Check: GET /health on 192.168.168.42
       ↓ (200 OK)
Return Replica IP: 192.168.168.42
       ↓
Client connects to 192.168.168.42 (replica)
```

---

## TTL (Time To Live) Explanation

**Setting**: 60 seconds

**Meaning**: 
- When client queries kushnir.cloud, the result is cached for 60 seconds
- If DNS changes, it takes maximum 60 seconds for all clients to see new IP

**Why 60 seconds?**
- Low TTL = Faster failover (good for HA)
- High TTL = Better performance (less DNS queries)
- 60 seconds is balanced compromise

**Failover Impact**:
```
T+0s:   Primary fails
T+60s:  DNS record switches to replica
T+0-60s: Some old clients still connect to primary (may see errors)
T+60s+: All clients routing to replica
```

---

## Subdomain Configuration

### ide.kushnir.cloud → Primary Web IDE
```
A Record: 192.168.168.31
TTL: 60
Proxied: Yes (Cloudflare)
Health Check: Enabled
```

### api.kushnir.cloud → Backend API (Optional)
```
A Record: 192.168.168.31
TTL: 60
Proxied: Yes (Cloudflare)
Health Check: Optional (if different service)
```

### Example: Adding New Subdomain

```
Dashboard → DNS Records → Create Record
  Type: A
  Name: api
  IPv4: 192.168.168.31
  TTL: 60
  Proxy: ON (Cloudflare)
  
Result: api.kushnir.cloud → 192.168.168.31
```

---

## TLS/SSL Configuration

### Current Setup
- **TLS Mode**: Full (strict)
- **Certificate**: Cloudflare managed (auto-renewal)
- **Protocol**: TLS 1.2+
- **HSTS**: Enabled (max-age=31536000)
- **Minimum TLS Version**: TLS 1.2

### Testing HTTPS

```bash
# Verify certificate chain
openssl s_client -connect kushnir.cloud:443

# Check certificate details
curl -v https://kushnir.cloud/health
# Expected: HTTP 200 (proxied to backend via Cloudflare)

# Check HSTS header
curl -I https://kushnir.cloud
# Expected: strict-transport-security: max-age=31536000
```

---

## Monitoring & Alerts

### What to Monitor

1. **Health Check Status**
   - Dashboard: Reliability → Health Checks
   - Alert: If status = "Unhealthy"
   - Action: SSH to primary, check service logs

2. **Failover Events**
   - Dashboard: Analytics & Analytics Engine
   - Alert: If failover occurs (DNS changed)
   - Action: Investigate primary failure, execute recovery

3. **DNS Query Volume**
   - Dashboard: Analytics
   - Normal: ~10-100 queries/min per domain
   - Alert: If queries drop to 0 (DNS misconfigured)

### Setting Up Alerts (Cloudflare)

```
Dashboard → Notifications → Alert Notifications

Alert 1: Health Check Status Changed
  Trigger: Health check status = Unhealthy
  Notify: Email + Slack

Alert 2: DNS Record Changed
  Trigger: DNS record modified
  Notify: Email

Alert 3: DDoS Attack Detected
  Trigger: DDoS mitigation triggered
  Notify: Email + Slack
```

---

## Troubleshooting

### Issue 1: DNS Not Resolving

```bash
# Check if Cloudflare nameservers are correct
whois kushnir.cloud | grep "Name Server"

# Verify nameservers:
# Expected:
#   ns1.cloudflare.com
#   ns2.cloudflare.com
#   ns3.cloudflare.com
#   ns4.cloudflare.com

# Flush DNS cache and re-query
nslookup -type=A ide.kushnir.cloud

# Check from multiple locations
nslookup ide.kushnir.cloud 8.8.8.8  # Google DNS
nslookup ide.kushnir.cloud 1.1.1.1  # Cloudflare DNS
```

### Issue 2: Failover Not Working

```bash
# Verify health check endpoint is accessible
curl -v http://192.168.168.31/health
# Expected: HTTP 200 OK

# Check Cloudflare health check status
# Dashboard → Reliability → Health Checks
# Expected: Status = "Healthy" (blue check)

# If unhealthy:
  1. SSH to primary
  2. Check service: docker ps | grep caddy
  3. Check logs: docker logs caddy | tail -20
  4. Restart if needed: docker restart caddy

# Manually test failover
# Stop health endpoint:
docker stop caddy

# Wait 60 seconds, check DNS:
nslookup ide.kushnir.cloud
# Expected: Returns 192.168.168.42 (replica)

# Restart:
docker start caddy
sleep 60

# Check DNS again:
nslookup ide.kushnir.cloud
# Expected: Returns back to 192.168.168.31
```

### Issue 3: Slow Failover

**Typical Failover Time**: 60-90 seconds

**Components**:
- Health check interval: 30 seconds
- Timeout: 5 seconds
- Failure threshold: 2 failures
- DNS propagation: Up to 60 seconds

**If Too Slow**:
- Reduce health check interval (Cloudflare)
- Reduce timeout (Cloudflare)
- Reduce failure threshold (Cloudflare)
- **Trade-off**: May cause false positives

---

## Disaster Recovery

### Scenario: Primary Host Completely Down

```
Timeline:
T+0min:   Primary host fails completely
T+1min:   Cloudflare health check fails
T+2min:   DNS record updated to replica
T+2-5min: Clients redirect to replica
T+5min:   Service restored via replica

Actions:
1. Check primary: `ssh akushnir@192.168.168.31`
2. If no response, may have power/network failure
3. Check IPMI/console access
4. Contact data center if hardware issue
5. Document in incident report
```

### Scenario: Replica Also Down

```
If both hosts fail:
- Service is completely down
- DNS still points to primary (last known good)
- Clients may get connection refused

Recovery:
1. Restart either host (primary preferred)
2. Deploy services: `docker compose up -d`
3. Verify health endpoint: `curl /health`
4. Cloudflare should automatically re-route traffic
5. Check DNS: `nslookup ide.kushnir.cloud`
```

---

## Future Enhancements

### Option 1: VRRP Virtual IP (On-Prem HA)
```
Benefit: Failover without Cloudflare dependency
Cost: Additional complexity, keepalived setup
Timeline: Phase 2 (3-6 months out)
```

### Option 2: Multi-Region Replication
```
Benefit: Geographic redundancy
Cost: Additional hosts, cross-region networking
Timeline: Phase 3 (6-12 months out)
```

### Option 3: Kubernetes DNS SRV Records
```
Benefit: Service discovery automation
Cost: Kubernetes cluster setup
Timeline: Long-term (if migrating to K8s)
```

---

## Related Documentation

- [DEPLOYMENT-RUNBOOK.md](DEPLOYMENT-RUNBOOK.md) — Deployment procedures
- [FAILOVER-TESTING-RESULTS.md](FAILOVER-TESTING-RESULTS.md) — Test results and performance
- [INFRASTRUCTURE-RECOVERY-COMPLETE-APRIL-21-2026.md](../INFRASTRUCTURE-RECOVERY-COMPLETE-APRIL-21-2026.md) — Recovery procedures

---

## Quick Reference

```bash
# Check DNS resolution
nslookup ide.kushnir.cloud

# Check health endpoint
curl http://192.168.168.31/health

# SSH to primary
ssh akushnir@192.168.168.31

# SSH to replica
ssh akushnir@192.168.168.42

# Check service status
docker ps --format "table {{.Names}}\t{{.Status}}"

# View health check logs (Cloudflare Dashboard)
https://dash.cloudflare.com → Reliability → Health Checks
```

---

**Last Updated**: April 21, 2026  
**Next Review**: April 28, 2026 (Weekly)  
**Owner**: @kushin77  
**Approver**: Production Engineering Team
