# VPN Enterprise Endpoint Scan Troubleshooting Runbook

**Priority**: P1 (Production Security Critical)  
**Audience**: On-Call Engineers, SRE, Security Team  
**Last Updated**: April 17, 2026

---

## Quick Summary

The VPN Enterprise Endpoint Scan (`scripts/vpn-enterprise-endpoint-scan.sh`) validates that enterprise endpoints (Code-server, APIs, UIs) are **only accessible through the configured VPN interface**. If this scan fails, it indicates:

- ❌ Potential public exposure of protected services
- ❌ Network policy violation (enterprise endpoint accessible without VPN)
- ❌ Configuration drift (VPN routing rules not applied)

**SLA**: 30 minutes to resolve or escalate to security team.

---

## 1. Identify the Failure

### From GitHub Actions

1. **Go to** [Actions → VPN Enterprise Endpoint Scan](../../.github/workflows/vpn-enterprise-endpoint-scan.yml)
2. **Click** the failed run
3. **Download artifacts** from the run summary:
   - `test-results/vpn-endpoint-scan/<timestamp>/summary.json`
   - `test-results/vpn-endpoint-scan/<timestamp>/debug-errors.log`

### From Local Run

```bash
# Run the scan locally
bash scripts/vpn-enterprise-endpoint-scan.sh

# Check output
ls -lt test-results/vpn-endpoint-scan/ | head -1
cat test-results/vpn-endpoint-scan/*/summary.json | jq .
```

### Key Fields in `summary.json`

```json
{
  "status": "FAILURE|PARTIAL|SUCCESS",
  "target": {
    "baseUrl": "http://code-server.192.168.168.31.nip.io:8080",
    "vpnInterface": "wg0",
    "vpnSubnet": "10.0.0.0/8"
  },
  "diagnosticsSummary": {
    "playwright": {
      "consoleErrors": 5,
      "pageErrors": 0,
      "requestFailures": 2
    },
    "puppeteer": {
      "consoleErrors": 3,
      "pageErrors": 1,
      "requestFailures": 1
    }
  },
  "opportunities": [
    {
      "issue": "endpoint-accessible-without-vpn",
      "service": "code-server",
      "port": 8080,
      "recommendation": "Restrict ingress to VPN subnet only"
    }
  ]
}
```

---

## 2. Diagnosis by Error Type

### Error: "Endpoint accessible without VPN (direct IP)"

**Root Cause**: Service is reachable via direct IP (not just VPN subnet).

**Diagnosis**:
```bash
# Test direct access (should FAIL)
curl http://192.168.168.31:8080 -v --max-time 3

# Test VPN access (should SUCCEED)
curl http://code-server.192.168.168.31.nip.io:8080 -v --max-time 3
```

**Remediation**:

1. **Update Caddy (ingress) to reject non-VPN IPs**:
   ```caddyfile
   code-server.{$DOMAIN} {
     @notVPN not remote_ip 10.0.0.0/8
     handle @notVPN {
       respond "Access denied: VPN required" 403
     }
     reverse_proxy http://code-server:8080
   }
   ```

2. **Update Kubernetes NetworkPolicy (if using K8s)**:
   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: code-server-vpn-only
   spec:
     podSelector:
       matchLabels:
         app: code-server
     ingress:
     - from:
       - namespaceSelector:
           matchLabels:
             name: vpn
       ports:
       - protocol: TCP
         port: 8080
   ```

3. **Update Docker container (if using compose)**:
   ```yaml
   code-server:
     ports:
       - "127.0.0.1:8080:8080"  # localhost only, no direct IP access
   ```

4. **Restart services**:
   ```bash
   docker-compose restart caddy code-server
   ```

---

### Error: "VPN Interface Not Found (wg0)"

**Root Cause**: WireGuard interface is down or misconfigured.

**Diagnosis**:
```bash
# Check WireGuard status
wg show

# Check interface is up
ip link show wg0

# Check routes
ip route | grep wg0
```

**Remediation**:

1. **Bring up WireGuard**:
   ```bash
   sudo wg-quick up wg0
   # or if custom interface name:
   sudo wg-quick up /etc/wireguard/custom.conf
   ```

2. **Verify configuration**:
   ```bash
   cat /etc/wireguard/wg0.conf
   ```

3. **Test connectivity**:
   ```bash
   ping 10.0.0.1  # VPN server
   ```

---

### Error: "Request Failed: ECONNREFUSED"

**Root Cause**: Service is down or not listening on the declared port.

**Diagnosis**:
```bash
# Check if service is running
docker ps | grep code-server
docker logs code-server | tail -20

# Check port is listening
netstat -tlnp | grep 8080  # or lsof -i :8080
```

**Remediation**:

1. **Restart the service**:
   ```bash
   docker-compose restart code-server
   docker-compose logs -f code-server
   ```

2. **Check service health**:
   ```bash
   curl http://localhost:8080 -v
   ```

3. **Check resource limits** (OOM, disk full):
   ```bash
   docker stats code-server
   df -h
   free -h
   ```

---

### Error: "Playwright/Puppeteer Navigation Timeout"

**Root Cause**: Browser navigation to endpoint timed out (slow network, service slow, or firewall blocking).

**Diagnosis**:
```bash
# Check latency to endpoint
ping code-server.192.168.168.31.nip.io

# Check DNS resolution
nslookup code-server.192.168.168.31.nip.io

# Test manual navigation
curl -v http://code-server.192.168.168.31.nip.io:8080
```

**Remediation**:

1. **Increase timeout in scan script** (if legitimate latency):
   ```bash
   # Edit scripts/vpn-enterprise-endpoint-scan.sh
   PLAYWRIGHT_TIMEOUT=30000  # default 10s → 30s
   ```

2. **Check DNS**: 
   ```bash
   dig code-server.192.168.168.31.nip.io @8.8.8.8
   ```

3. **Check firewall rules**:
   ```bash
   sudo iptables -L -n | grep 8080
   ```

---

## 3. Escalation Path

If issue persists after remediation:

1. **Collect evidence**:
   ```bash
   # Scan output
   cat test-results/vpn-endpoint-scan/*/summary.json | jq . > /tmp/vpn-scan.json
   
   # Network diagnostics
   wg show > /tmp/wg-show.txt
   ip route > /tmp/routes.txt
   docker ps > /tmp/containers.txt
   docker logs caddy > /tmp/caddy.log
   docker logs code-server > /tmp/code-server.log
   
   # Firewall rules
   sudo iptables -L -n > /tmp/iptables.txt
   ```

2. **Create P1 incident**:
   ```
   Title: "VPN Endpoint Scan Failure - Potential Security Exposure"
   Labels: P1, vpn-scan-failure, security
   Description: [Attach artifacts from step 1]
   ```

3. **Notify**:
   - `@security-team` (Slack #security)
   - `@sre-oncall` (Slack #sre)
   - Security audit trail log

---

## 4. Preventive Measures

### Automated Testing
- Run scan on every commit: `.github/workflows/vpn-enterprise-endpoint-scan.yml`
- Run scan on schedule: Daily 02:00 UTC
- Auto-escalate P1 if scan fails (GitHub Actions → create issue)

### Monitoring
Add to Prometheus/Grafana:
```yaml
vpn_scan_last_success_timestamp  # when scan last passed
vpn_scan_failure_total            # cumulative failures
vpn_scan_duration_seconds         # scan runtime
```

### Documentation
- Keep `docs/dns-architecture.md` updated with VPN topology
- Document all enterprise endpoints in `.env`
- Add VPN override matrix to deployment runbook

---

## 5. Testing Your Fix Locally

```bash
#!/bin/bash

# 1. Ensure WireGuard is up
sudo wg-quick up wg0

# 2. Verify VPN subnet reachability
ping 10.0.0.1

# 3. Run scan
bash scripts/vpn-enterprise-endpoint-scan.sh

# 4. Check results
cat test-results/vpn-endpoint-scan/*/summary.json | jq .status

# Expected: "SUCCESS" or "PARTIAL" (with all opportunities remediated)
```

---

## References

- **VPN Architecture**: [DNS-IMPLEMENTATION-GUIDE.md](../dns-architecture.md)
- **Deployment Guide**: [DEPLOYMENT-EXECUTION-PROCEDURE.md](../../DEPLOYMENT-EXECUTION-PROCEDURE.md)
- **Caddy Config**: [Caddyfile](../../Caddyfile)
- **Scan Script**: [vpn-enterprise-endpoint-scan.sh](../../scripts/vpn-enterprise-endpoint-scan.sh)

---

**Last Reviewed**: April 17, 2026  
**Owner**: SRE Team  
**On-Call**: See PagerDuty escalation policy
