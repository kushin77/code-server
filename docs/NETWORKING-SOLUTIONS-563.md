# Public Accessibility Solutions for Issue #563

## Problem
External clients (e.g., phone on 4G/LTE) cannot reach kushnir.cloud or ide.kushnir.cloud. Root cause: ISP router (WAN IP 173.77.179.148) lacks port forwarding rules to on-prem host (192.168.168.31).

## Root Cause Verification
- ✅ DNS resolves correctly: kushnir.cloud → 173.77.179.148 (ISP WAN IP)
- ✅ Caddy is listening: 0.0.0.0:80 and 0.0.0.0:443 (on-prem host 192.168.168.31)
- ❌ Port forwarding missing: ISP router has no rules to forward 80/443 traffic to 192.168.168.31

## Solution 1: ISP Router Port Forwarding (Recommended - Fastest)

### User Action Required
1. Log into ISP router admin interface (typically 192.168.1.1 or 192.168.168.1)
2. Navigate to Port Forwarding section
3. Create two rules:
   - **HTTP**: External port 80 → Internal IP 192.168.168.31 → Internal port 80
   - **HTTPS**: External port 443 → Internal IP 192.168.168.31 → Internal port 443
4. Save and verify rules are active

### Verification
```bash
# From external network (phone on 4G/LTE):
curl -v https://ide.kushnir.cloud
# Should return 200 OK from code-server, no timeouts

# Or test HTTP:
curl -v http://kushnir.cloud
# Should redirect to https://ide.kushnir.cloud
```

### Pros
- ✅ No code changes required
- ✅ Immediate access once configured
- ✅ Simplest implementation

### Cons
- ⚠️ ISP WAN IP (173.77.179.148) may change (use DDNS if dynamic)
- ⚠️ ISP may block ports 80/443 on residential connections
- ⚠️ Exposes on-prem server directly to internet

### DDNS Setup (if WAN IP is dynamic)
If your ISP assigns a dynamic WAN IP, add a DDNS entry:
1. Install `ddclient` on on-prem host:
   ```bash
   sudo apt-get install ddclient
   ```
2. Configure for your DNS provider (e.g., Cloudflare, Route53)
3. DNS will auto-update when WAN IP changes

---

## Solution 2: IPv6 DNS Records (Secondary - Works with IPv6-capable clients)

### Implementation (Requires DNS Admin Access)
Add AAAA record to DNS zone for kushnir.cloud:
- **Name**: kushnir.cloud
- **Type**: AAAA
- **Value**: 2600:4041:5416:f400:da9e:f3ff:fe35:4148 (on-prem public IPv6)

Also add for ide subdomain:
- **Name**: ide.kushnir.cloud
- **Type**: AAAA
- **Value**: 2600:4041:5416:f400:da9e:f3ff:fe35:4148

### Verification
```bash
# From external network (phone on IPv6):
dig AAAA kushnir.cloud
# Should return: 2600:4041:5416:f400:da9e:f3ff:fe35:4148

# Test HTTPS via IPv6:
curl -6 https://kushnir.cloud
# Should work if device has IPv6 connectivity
```

### Pros
- ✅ No ISP router configuration needed
- ✅ Works for IPv6-capable devices
- ✅ Isolates from IPv4 NAT issues

### Cons
- ⚠️ Limited client support (many phones still IPv4-only)
- ⚠️ Requires AAAA record changes in DNS
- ⚠️ IPv6 adoption not universal

### Current IPv6 Status
- ✅ On-prem host has public IPv6: 2600:4041:5416:f400:da9e:f3ff:fe35:4148
- ✅ Caddy listening on IPv6 (::):80 and (::):443
- ✅ IPv6 connectivity verified on host

---

## Solution 3: Reverse SSH Tunnel or VPN Gateway (Production - Most Secure)

### Implementation
Requires external VPS or cloud instance:
1. Set up reverse SSH tunnel from on-prem to external gateway:
   ```bash
   ssh -R 0.0.0.0:80:localhost:80 \
       -R 0.0.0.0:443:localhost:443 \
       vpn-user@external-gateway.example.com
   ```
2. Update DNS to point to external gateway IP
3. External gateway forwards traffic back through tunnel to on-prem

### Alternative: WireGuard VPN Gateway
```bash
# On-prem client connects to WireGuard server (external gateway)
# Caddy reverse proxies through tunnel
# DNS points to external gateway
```

### Pros
- ✅ Most secure (on-prem not directly exposed)
- ✅ Works with any ISP (no port forwarding needed)
- ✅ NAT traversal

### Cons
- ❌ Requires additional infrastructure (external VPS)
- ❌ Higher latency (traffic through external gateway)
- ❌ External VPS adds operational overhead

---

## Recommended Approach: Hybrid

**Immediate** (Phase 1):
1. Implement Solution 1: ISP router port forwarding (user action)
2. Document in issue #563 with verification evidence

**Medium-term** (Phase 2):
3. Add Solution 2: IPv6 AAAA DNS records (code-controlled)
4. Update documentation

**Long-term** (Phase 3):
5. Consider Solution 3: VPN gateway for production hardening

---

## Current Network Evidence (Verified 2026-04-17)

### On-prem Host
```
Interface: enp0s25
  IPv4: 192.168.168.31/24 (private LAN)
  IPv6: 2600:4041:5416:f400:da9e:f3ff:fe35:4148/64 (public IPv6)
  Gateway: 192.168.168.1 (local router)

Caddy Status:
  Port 80: Listening 0.0.0.0:80 (IPv4 + IPv6)
  Port 443: Listening 0.0.0.0:443 (IPv4 + IPv6)
  Certificates: Valid for kushnir.cloud and ide.kushnir.cloud
```

### DNS Resolution
```
kushnir.cloud           A    173.77.179.148  (ISP WAN IP)
ide.kushnir.cloud       CNAME kushnir.cloud
```

### ISP Router
```
WAN IP: 173.77.179.148 (public)
Port Forwarding: [NOT CONFIGURED]  ← This is the blocker
```

---

## Acceptance Criteria Tracking

- [ ] Solution option selected (1, 2, or 3)
- [ ] Implementation documented
- [ ] External access verified from phone
- [ ] TLS validation passes (no certificate warnings)
- [ ] Issue #563 closed with evidence

---

## See Also
- [Caddyfile Documentation](../Caddyfile) — Current reverse proxy configuration
- [Production Readiness Framework](#381) — Deployment standards
- GitHub Issue #563 — Full discussion
