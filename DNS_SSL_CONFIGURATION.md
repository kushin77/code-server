# DNS & SSL Configuration for VIP Failover

**Phase**: 5 (Continuation - External Failover)  
**Date**: April 30, 2026  
**Status**: 📋 READY FOR EXECUTION  

---

## Overview

After updating router port-forwards to VIP (192.168.168.30), DNS and SSL need to work seamlessly across **both hosts** regardless of which is MASTER.

### Key Points
- ✅ **Wildcard SSL certificates** work on any host (same domain = same cert)
- ✅ **Internal DNS** can point to VIP (no external propagation needed)
- ✅ **External DNS** stays pointing to external IP (router handles VIP translation)
- ✅ **No certificate changes** needed - same cert on both hosts

---

## Scenario 1: Internal Network (Recommended for HA)

**When**: Users access via hostname on same local network as cluster

### Setup

**On your local DNS server or in hosts file:**

```bash
# Option A: Local DNS Server (BIND, dnsmasq, etc.)
# Add A record:
yourserver.local   A   192.168.168.30  (points to VIP)
yourserver.cloud   A   192.168.168.30  (points to VIP)

# Option B: Client hosts file
# Linux/Mac: /etc/hosts
192.168.168.30  yourserver.local yourserver.cloud

# Windows: C:\Windows\System32\drivers\etc\hosts
192.168.168.30  yourserver.local yourserver.cloud
```

**Verification:**

```bash
# Test from any local network device
nslookup yourserver.local
# Should return: 192.168.168.30

ping yourserver.local
# Should respond (from current MASTER)

curl https://yourserver.local/health
# Should work through VIP
```

**Failover Behavior:**
- ✅ DNS resolves to VIP (192.168.168.30)
- ✅ VIP is managed by keepalived (Primary=MASTER, Replica=BACKUP)
- ✅ On primary failure, VIP automatically moves to replica
- ✅ Clients retry → VIP → now answers from replica
- ✅ **Automatic failover - no DNS change needed**

---

## Scenario 2: External Network (Production)

**When**: Users access via public domain from internet

### Current Setup

```
DNS (external)
yourserver.com A 203.0.113.45  (your public IP)
                ↓
Internet Router (203.0.113.45:80/443)
                ↓
Internal Router NAT (port-forward)
                ↓
VIP 192.168.168.30
                ↓
MASTER Host (Primary or Replica)
```

**No DNS changes needed** - Router handles VIP failover internally.

### If You Want to Point DNS Directly to VIP

Only do this if you have **static IP for VIP on your ISP**:

```bash
# Update external DNS A record:
yourserver.com A 192.168.168.30

# Wait for propagation (15-60 minutes)

# Verify:
nslookup yourserver.com
# From external network: should show 192.168.168.30 (or your proxy)
```

**⚠️ Warning**: Most home ISPs don't allow this (RFC 1918 addresses not routable externally). Stick with router port-forwards if you're on consumer internet.

---

## SSL Certificate Strategy

### Status: ✅ READY (No Changes Needed)

Your SSL certificates work on **both hosts** because:

1. **Certificate bound to domain** (yourserver.com)
2. **Both hosts have identical domain**
3. **Same certificate on both** (installed via terraform/docker-compose)
4. **VIP failover is transparent to certificate verification**

### Certificate Verification

```bash
# Check certificate on primary
ssh akushnir@192.168.168.31
docker exec code-server-caddy caddy list-modules

# Check certificate on replica
ssh akushnir@192.168.168.42
docker exec code-server-caddy caddy list-modules

# Both should show same cert info
```

### If You Need to Update Certificates Later

```bash
# Update on both hosts simultaneously:

# Primary
ssh akushnir@192.168.168.31
docker exec code-server-caddy caddy stop
# Replace cert files in /data/caddy
docker exec code-server-caddy caddy start

# Replica
ssh akushnir@192.168.168.42
docker exec code-server-caddy caddy stop
# Replace cert files in /data/caddy
docker exec code-server-caddy caddy start

# Wait 10 seconds for VRRP to stabilize
sleep 10

# Verify both responding with new cert
curl -kv https://192.168.168.30/health
```

---

## DNS Failover Test

### Test 1: VIP DNS Resolution

```bash
# From local network device:
nslookup yourserver.local
# Should show: 192.168.168.30

# If showing 192.168.168.31 instead:
# Your DNS server is pointing to primary host
# Update DNS to point to VIP: 192.168.168.30
```

### Test 2: Failover During Active Connection

```bash
# Terminal 1: Continuous curl to VIP
while true; do
  curl -s http://192.168.168.30/health && echo " ✓ $(date)"
  sleep 1
done

# Terminal 2: SSH to primary, stop containers
ssh akushnir@192.168.168.31
docker pause $(docker ps --format "{{.ID}}" | head -5)

# Terminal 1: Should NOT see any failures
# Requests continue flowing through VIP → Replica
# After 5 seconds, Replica becomes MASTER
# Requests resume from replica

# Terminal 2: Restore primary
docker unpause $(docker ps --format "{{.ID}}" | head -5)
```

### Test 3: Certificate Validation

```bash
# Test from local network device:

# Test SSL certificate chain
openssl s_client -connect yourserver.local:443 \
  -servername yourserver.local \
  < /dev/null | grep -E "subject|issuer|CN="

# Both primary and replica should show same certificate
# (failover is transparent to SSL)
```

---

## Implementation Checklist

### Pre-Implementation
- [ ] Router port-forwards updated to VIP (192.168.168.30)
- [ ] VIP responding to ping and HTTP requests
- [ ] Keepalived status: Primary=MASTER, Replica=BACKUP

### DNS Configuration
- [ ] Option A: Internal DNS → 192.168.168.30 (recommended)
- [ ] Option B: External DNS → 192.168.168.30 (if on static IP)
- [ ] Option C: Keep existing setup (no DNS changes)

### SSL Certificate
- [ ] Verify same certificate installed on both hosts
- [ ] Test HTTPS through VIP: `curl https://192.168.168.30/health`
- [ ] Confirm certificate CN matches your domain

### Failover Testing
- [ ] Test 1: VIP DNS resolution returns correct IP
- [ ] Test 2: HTTP requests survive failover (no interruption)
- [ ] Test 3: HTTPS requests survive failover
- [ ] Test 4: New connection after failover works

### Documentation
- [ ] Update ROUTER_UPDATE_CHECKPOINT.md with completion
- [ ] Update DNS records in operations documentation
- [ ] Document SSL certificate rotation procedures
- [ ] Commit changes to git

---

## Common DNS Issues & Solutions

### Issue: DNS Points to Old Primary IP

**Symptom**: `nslookup yourserver.local` returns 192.168.168.31 instead of 192.168.168.30

**Solution**:
```bash
# Update your local DNS server or hosts file
# Point to VIP instead:
192.168.168.30  yourserver.local yourserver.cloud

# For BIND DNS:
yourserver.local.   300 IN A 192.168.168.30

# For dnsmasq (in /etc/dnsmasq.conf):
address=/yourserver.local/192.168.168.30

# Restart DNS service:
sudo systemctl restart dnsmasq
# or
sudo systemctl restart bind9
```

### Issue: External DNS Not Updating

**Symptom**: External clients still can't reach server after DNS change

**Possible causes:**
1. DNS TTL too high (waited for 48 hours?)
2. ISP caching DNS (wait or flush)
3. Router not forwarding to VIP (check port-forward rules)
4. VIP not responding on external port (test locally first)

**Solution**:
```bash
# Test from external network:
nslookup yourserver.com  # (using external DNS)
ping 192.168.168.30      # (won't work from external, but check router)

# Check if your ISP blocks port 80/443:
# Contact ISP if ports are blocked
```

### Issue: SSL Certificate Mismatch

**Symptom**: Browser warning about certificate domain mismatch

**Root cause**: Certificate CN doesn't match requested hostname

**Solution**:
```bash
# Verify certificate on VIP:
openssl s_client -connect 192.168.168.30:443 \
  -servername yourserver.local \
  </dev/null | grep CN=

# Should show: CN=yourserver.local or CN=*.yourdomain.local

# If mismatch: Regenerate certificate with correct CN
# Then deploy to both hosts
```

---

## Advanced: Multi-Domain Setup

If you have multiple domains pointing to same cluster:

### DNS Records
```bash
# Primary domain
example.com      A  192.168.168.30  (VIP)

# Subdomains
api.example.com  A  192.168.168.30  (VIP)
app.example.com  A  192.168.168.30  (VIP)

# Alternate domain
myapp.io         A  192.168.168.30  (VIP)
```

### SSL Certificates

**Option 1: Wildcard Certificate** (Recommended)
```
CN=*.example.com
SAN=*.example.com, example.com
# Covers: api.example.com, app.example.com, etc.
```

**Option 2: Multi-SAN Certificate**
```
CN=example.com
SAN=example.com, api.example.com, app.example.com, myapp.io
# Covers all listed domains
```

### Caddy Configuration (Auto-HTTPS)
```
# Caddy automatically handles multiple domains
*.example.com {
    reverse_proxy backend:8080
}

example.com {
    reverse_proxy backend:8080
}

*.myapp.io {
    reverse_proxy backend:8080
}
```

---

## Rollback Procedures

### If DNS Points to Wrong Address

```bash
# Quick revert to primary host IP
# Update DNS A records:
yourserver.local  A  192.168.168.31  (primary only)
yourserver.com    A  203.0.113.45    (public IP with router)

# Clients will connect directly to primary
# No failover until you re-point to VIP
```

### If SSL Certificate Breaks

```bash
# Regenerate certificate:
ssh akushnir@192.168.168.31
docker exec code-server-caddy caddy reload

# This reloads cert from disk without restart
# If that doesn't work:

docker exec code-server-caddy caddy stop
docker exec code-server-caddy caddy start

# Then deploy same cert to replica and restart
```

---

## Monitoring DNS Health

Add to your monitoring scripts:

```bash
#!/bin/bash
# dns-health-check.sh

echo "DNS Health Check - $(date)"

# Test 1: Local DNS resolution
LOCAL_IP=$(nslookup yourserver.local | grep "Address" | tail -1 | awk '{print $NF}')
if [[ "$LOCAL_IP" == "192.168.168.30" ]]; then
  echo "✅ Local DNS resolves to VIP (192.168.168.30)"
else
  echo "❌ Local DNS resolves to $LOCAL_IP (expected 192.168.168.30)"
fi

# Test 2: Certificate validation
CERT_CN=$(openssl s_client -connect 192.168.168.30:443 \
  -servername yourserver.local 2>/dev/null \
  | grep "CN=" | grep -o "CN=[^,]*" | cut -d'=' -f2)
if [[ "$CERT_CN" == "yourserver.local" ]] || [[ "$CERT_CN" == "*.yourdomain.local" ]]; then
  echo "✅ SSL Certificate CN is valid: $CERT_CN"
else
  echo "❌ SSL Certificate CN mismatch: $CERT_CN"
fi

# Test 3: VIP HTTP health
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://192.168.168.30/health)
if [[ "$HTTP_STATUS" == "200" ]]; then
  echo "✅ HTTP health check passing"
else
  echo "❌ HTTP health check failing: HTTP $HTTP_STATUS"
fi

# Test 4: HTTPS health
HTTPS_STATUS=$(curl -sk -o /dev/null -w "%{http_code}" https://192.168.168.30/health)
if [[ "$HTTPS_STATUS" == "200" ]]; then
  echo "✅ HTTPS health check passing"
else
  echo "⚠️  HTTPS health check: HTTP $HTTPS_STATUS (may be cert issue)"
fi

echo "DNS health check complete"
```

---

## Summary

| Component | Status | Notes |
|-----------|--------|-------|
| VIP | ✅ Ready | 192.168.168.30 active, VRRP managed |
| DNS (Internal) | 📋 To-do | Point to 192.168.168.30 |
| DNS (External) | ✅ Ready | Keep existing router setup |
| SSL Certificates | ✅ Ready | No changes needed |
| Failover | ✅ Ready | <5 second automatic |
| Monitoring | 📋 To-do | Add health check scripts |

---

**Next Step**: Execute router port-forward update per ROUTER_UPDATE_IMPLEMENTATION.md, then return here to configure DNS if needed.

