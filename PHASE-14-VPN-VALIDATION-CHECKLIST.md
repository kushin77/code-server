# Phase 14: VPN-Aware Validation Checklist
## Production Launch Gating - DNS, TLS, and End-User Perspective Testing

**Document Purpose**: Comprehensive validation checklist for Phase 14 production launch with explicit VPN-aware testing requirements.

**Status**: IN PROGRESS (Execution Phase)
**Last Updated**: April 13, 2026 - 21:30 UTC
**Audience**: Engineering Team, DevOps, Infrastructure, Security

---

## Executive Summary

Phase 14 production launch hinges on comprehensive validation **from the end-user perspective**. This checklist enforces VPN-aware testing to ensure that all DNS, TLS, and connectivity validation reflects what actual users will experience accessing `ide.kushnir.cloud` through VPN.

**Key Requirement**: All DNS tests must use VPN routing to validate from user perspective (per explicit user guidance).

---

## Pre-Validation Prerequisites ✅

- [ ] **VPN Connectivity Verified**
  - [ ] User connected to production VPN (wireguard/openvpn)
  - [ ] VPN routing active (check: `ip route | grep -i tun`)
  - [ ] VPN DNS resolvers active (check: `cat /etc/resolv.conf`)
  - [ ] Can ping 192.168.168.31 (production host)
  - **Success Criteria**: Ping response with <100ms latency

- [ ] **Production Host Status**
  - [ ] Host is reachable via SSH: `ssh akushnir@192.168.168.31`
  - [ ] Docker daemon running: `docker ps` returns service list
  - [ ] All 6 services deployed: caddy, oauth2-proxy, code-server, ssh-proxy, ollama, redis
  - [ ] No service restart loops in past hour
  - **Success Criteria**: 6/6 services with STATUS containing "Up"

- [ ] **Tools Available**
  - [ ] `dig` available for DNS testing
  - [ ] `curl` available for HTTPS testing
  - [ ] `openssl` available for TLS validation
  - [ ] `timeout` available for tests (standard on Linux/WSL)
  - **Success Criteria**: All tools respond to `--version` or similar

---

## Phase 1: VPN-Aware DNS Resolution Testing ✅

**Objective**: Validate DNS resolves `ide.kushnir.cloud` to 192.168.168.31 from VPN perspective.

### 1.1 DNS Resolution via Default Resolver (VPN DNS)

```bash
# Execute FROM VPN tunnel
dig ide.kushnir.cloud A +short
```

- [ ] **Test Execution**: Command runs without timeout
- [ ] **Expected Result**: Returns `192.168.168.31`
- [ ] **VPN Perspective**: Uses VPN's configured DNS server (not public resolver)
- **Success Criteria**: Response matches 192.168.168.31, query takes <3 seconds

**Test Command**:
```bash
bash /scripts/phase-14-vpn-dns-validation.sh --test-dns
```

### 1.2 DNS Resolution via Google Public DNS (through VPN)

```bash
# Still from VPN tunnel, forcing specific resolver
dig ide.kushnir.cloud A @8.8.8.8 +short
```

- [ ] **Test Execution**: Command runs without timeout
- [ ] **Expected Result**: Returns `192.168.168.31` (even via public DNS)
- [ ] **VPN Perspective**: Validates DNS is globally accessible, not just on VPN DNS
- **Success Criteria**: Response matches 192.168.168.31, query takes <5 seconds

### 1.3 Reverse DNS Lookup (Optional)

```bash
# Validate reverse DNS
dig -x 192.168.168.31 +short
```

- [ ] **Test Execution**: Command completes
- [ ] **Expected Result(s)**: May return NXDOMAIN or hostname
- [ ] **VPN Perspective**: Validates reverse DNS if configured (informational)
- **Success Criteria**: No errors, response is valid DNS format

---

## Phase 2: TLS/HTTPS Certificate Validation ✅

**Objective**: Validate TLS certificate is valid, matches domain, and is acceptable for launch.

### 2.1 TLS Handshake Success (from VPN)

```bash
# Perform TLS handshake through VPN routing
openssl s_client -connect ide.kushnir.cloud:443 -servername ide.kushnir.cloud </dev/null
```

- [ ] **Test Execution**: Command connects successfully
- [ ] **Expected Result**: Shows certificate chain (details below)
- [ ] **VPN Perspective**: Connection routes through VPN to reach production host
- **Success Criteria**: Connection succeeds (exit code 0), certificate displayed

### 2.2 Certificate CN Validation

```bash
# Extract and verify certificate CN
openssl s_client -connect ide.kushnir.cloud:443 -servername ide.kushnir.cloud </dev/null | \
  openssl x509 -noout -subject
```

- [ ] **Test Execution**: Extracts certificate subject
- [ ] **Expected Result**: `subject=CN=ide.kushnir.cloud` (or similar)
- [ ] **Temporary Status**: Self-signed cert is acceptable for Phase 14 launch
- **Success Criteria**: CN matches domain exactly, matches current Caddyfile config

### 2.3 Certificate Issuer Verification (Phase 14 Temporary Status)

```bash
# Check certificate issuer
openssl s_client -connect ide.kushnir.cloud:443 -servername ide.kushnir.cloud </dev/null | \
  openssl x509 -noout -issuer
```

- [ ] **Test Execution**: Displays issuer
- [ ] **Expected Result**: Shows self-signed issuer or "Self Signed" indicator
- [ ] **Phase 14 Status**: Self-signed acceptable (scheduled for CA-signed cert post-launch)
- [ ] **Post-Launch Action**: Migrate to Let's Encrypt/GlobalSign cert within 2 weeks
- **Success Criteria**: Any issuer accepted; plan documented for CA migration

### 2.4 Certificate Expiry Check

```bash
# Verify certificate expiry
openssl s_client -connect ide.kushnir.cloud:443 -servername ide.kushnir.cloud </dev/null | \
  openssl x509 -noout -enddate
```

- [ ] **Test Execution**: Shows expiry date
- [ ] **Expected Result**: Expiry date >30 days in future
- [ ] **Phase 14 Status**: Self-signed cert valid for minimum 90 days from generation
- **Success Criteria**: Expiry date is at least 30 days away

---

## Phase 3: HTTPS Response Validation (from VPN) ✅

**Objective**: Validate HTTP/HTTPS endpoints return expected responses through VPN.

### 3.1 HTTPS Root Path Response

```bash
# Test HTTPS response without SSL verification (self-signed acceptable)
curl -kI ide.kushnir.cloud:443/ 2>&1
```

- [ ] **Test Execution**: Command returns response headers
- [ ] **Expected Results**: 
  - HTTP/1.1 200 OK (if serving directly)
  - HTTP/1.1 301 Moved Permanently (if redirecting)
  - HTTP/1.1 302 Found (if temporary redirect)
- [ ] **VPN Perspective**: Connection routes through VPN to production host
- **Success Criteria**: Any 2xx, 3xx status code (successful response)

### 3.2 HTTPS with OAuth2-Proxy Flow (from VPN)

```bash
# Test OAuth2-proxy redirect (should redirect to Google)
curl -kL ide.kushnir.cloud:443/ 2>&1 | head -50
```

- [ ] **Test Execution**: Follows redirects, returns final response
- [ ] **Expected Result**: Redirect to Google OAuth or cached content
- [ ] **VPN Perspective**: Follow full auth flow through VPN routing
- **Success Criteria**: No HTTP errors (5xx), connection succeeds

### 3.3 Code-Server Service Availability

```bash
# Check code-server backend service (internal)
curl -k https://ide.kushnir.cloud/api/v1/ 2>&1 | head -20
```

- [ ] **Test Execution**: Reaches internal API endpoint
- [ ] **Expected Result**: Returns API response or 404 (both acceptable)
- [ ] **VPN Perspective**: Tests routing to backend services
- **Success Criteria**: Response received (not timeout or connection refused)

---

## Phase 4: SSH Proxy Validation ✅

**Objective**: Validate SSH proxy is accessible through VPN and port forwarding active.

### 4.1 SSH Proxy Port Connectivity

```bash
# Test SSH proxy on standard port
timeout 5 bash -c 'echo QUIT | nc -w 1 192.168.168.31 2222' 2>&1
```

- [ ] **Test Execution**: Connects to SSH proxy port
- [ ] **Expected Result**: Connection accepted (SSH banner optional)
- [ ] **VPN Perspective**: Reaches SSH service through VPN routing
- **Success Criteria**: Connection succeeds, timeout not triggered

### 4.2 SSH Service Banner

```bash
# Get SSH service banner
ssh -p 2222 192.168.168.31 -v 2>&1 | grep -i "protocol\|version\|banner"
```

- [ ] **Test Execution**: Connects and shows SSH version
- [ ] **Expected Result**: Shows OpenSSH version banner
- [ ] **VPN Perspective**: SSH service accessible from VPN
- **Success Criteria**: SSH version detected successfully

### 4.3 SSH Key Authentication (Private Test)

```bash
# Test SSH with specific user key (requires key provisioning)
ssh -p 2222 -i ~/.ssh/phase14_rsa akushnir@192.168.168.31 "echo OK" 2>&1
```

- [ ] **Test Execution**: Authenticates with SSH key
- [ ] **Expected Result**: Executes remote command (see "OK")
- [ ] **VPN Perspective**: Full SSH session through VPN
- **Success Criteria**: Command executes successfully, returns output

---

## Phase 5: Redis Cache Service Validation ✅

**Objective**: Validate Redis service is operational and accessible.

### 5.1 Redis Port Connectivity

```bash
# Test Redis connectivity
timeout 3 bash -c 'echo PING | nc 192.168.168.31 6379' 2>&1
```

- [ ] **Test Execution**: Connects to Redis port
- [ ] **Expected Result**: Returns "+PONG" response
- [ ] **VPN Perspective**: Reaches internal Redis through VPN/docker bridge
- **Success Criteria**: Positive response received

### 5.2 Redis Command Execution (via SSH)

```bash
# Execute redis-cli PING via SSH
ssh -o StrictHostKeyChecking=no akushnir@192.168.168.31 \
  "docker exec redis redis-cli PING"
```

- [ ] **Test Execution**: Executes redis-cli inside container
- [ ] **Expected Result**: "+PONG" response
- [ ] **VPN Perspective**: Tests service health via SSH tunnel
- **Success Criteria**: "PONG" returned

---

## Phase 6: Ollama LLM Service Validation ✅

**Objective**: Validate Ollama service is operational and model loaded.

### 6.1 Ollama Service Status (via SSH)

```bash
# Check Ollama service status
ssh -o StrictHostKeyChecking=no akushnir@192.168.168.31 \
  "docker logs ollama | tail -20"
```

- [ ] **Test Execution**: Retrieves recent logs
- [ ] **Expected Result**: Shows model operations or startup messages
- [ ] **VPN Perspective**: System health visible through SSH tunnel
- **Success Criteria**: No fatal errors in logs

### 6.2 Ollama API Endpoint (via SSH Tunnel)

```bash
# Test Ollama API via local SSH tunnel
ssh -o StrictHostKeyChecking=no -L 11434:ollama:11434 \
  akushnir@192.168.168.31 sleep 30 &
sleep 2
curl http://localhost:11434/api/tags 2>&1 | jq . || echo "JSON parse failed"
```

- [ ] **Test Execution**: Establishes SSH tunnel and queries API
- [ ] **Expected Result**: Returns JSON list of available models
- [ ] **VPN Perspective**: Tests internal service through VPN SSH tunnel
- **Success Criteria**: Valid JSON response, at least 1 model listed

---

## Phase 7: Caddy Reverse Proxy Validation ✅

**Objective**: Validate Caddy reverse proxy configuration and TLS termination.

### 7.1 Caddy Configuration Validation (via SSH)

```bash
# Check Caddy logs for configuration errors
ssh -o StrictHostKeyChecking=no akushnir@192.168.168.31 \
  "docker logs caddy 2>&1 | grep -i error | tail -10"
```

- [ ] **Test Execution**: Retrieves error logs
- [ ] **Expected Result**: No errors, or only expected ignore-safe errors
- [ ] **VPN Perspective**: Checks proxy health through VPN SSH
- **Success Criteria**: No certificate errors, no binding failures

### 7.2 Caddyfile Syntax Validation

```bash
# Validate Caddyfile syntax
ssh -o StrictHostKeyChecking=no akushnir@192.168.168.31 \
  "docker exec caddy caddy validate --config /etc/caddy/Caddyfile"
```

- [ ] **Test Execution**: Caddy validates its own configuration
- [ ] **Expected Result**: "Valid configuration" message or exit code 0
- [ ] **VPN Perspective**: Confirms running configuration is valid
- **Success Criteria**: Validation passes without errors

### 7.3 TLS Certificate Loading

```bash
# Verify TLS certificate is loaded in Caddy
ssh -o StrictHostKeyChecking=no akushnir@192.168.168.31 \
  "ls -lh /home/akushnir/code-server-phase13/ssl/"
```

- [ ] **Test Execution**: Lists SSL directory contents
- [ ] **Expected Result**: Shows cf_origin.crt and cf_origin.key files
- [ ] **VPN Perspective**: Confirms cert files exist and are accessible
- **Success Criteria**: Both crt and key files present, size >0

---

## Phase 8: Load and Stress Testing (Optional) 📊

**Objective**: Optional phase - validate system handles concurrent users.

### 8.1 Basic Load Test (via VPN)

```bash
# Simulate 5 concurrent requests through VPN
for i in {1..5}; do
  curl -k https://ide.kushnir.cloud/ -s -o /dev/null -w "Request $i: %{http_code}\n" &
done
wait
```

- [ ] **Test Execution**: Completes all requests
- [ ] **Expected Result**: All requests return 2xx or 3xx status
- [ ] **VPN Perspective**: Validates concurrent access from VPN
- **Success Criteria**: No failures, all requests successful

### 8.2 Sustained Load Test (5 minutes, via VPN)

```bash
# Run continuous requests for 5 minutes
bash -c 'for i in {1..60}; do curl -k https://ide.kushnir.cloud/ -s -o /dev/null && echo "Request $i: OK" || echo "Request $i: FAIL"; sleep 5; done'
```

- [ ] **Test Execution**: Completes without hanging
- [ ] **Expected Result**: 60 requests, all successful
- [ ] **VPN Perspective**: Tests sustained throughput from VPN
- **Success Criteria**: >95% success rate (57/60 requests)

---

## Validation Execution Commands

### Command 1: Run Complete Validation Suite (Recommended)

```bash
# From your local machine (via VPN):
bash /scripts/phase-14-vpn-validation-runner.sh
```

**Output**: Comprehensive report to `/tmp/phase-14-vpn-validation-*.log`

### Command 2: Run Individual DNS Tests

```bash
# VPN-aware DNS validation only:
bash /scripts/phase-14-vpn-dns-validation.sh --test-dns
```

### Command 3: Run TLS Tests

```bash
# Certificate validation only:
bash /scripts/phase-14-vpn-dns-validation.sh --test-tls
```

### Command 4: Run HTTPS Response Tests

```bash
# HTTP response validation:
bash /scripts/phase-14-vpn-dns-validation.sh --test-https
```

---

## Success Criteria Summary

### Critical Path (Must Pass for Launch)

| Test | Success Criteria | Status |
|------|-----------------|--------|
| VPN Connectivity | Ping 192.168.168.31 <100ms | ⏳ |
| DNS Resolution | `dig ide.kushnir.cloud` → 192.168.168.31 | ⏳ |
| TLS Handshake | CN matches ide.kushnir.cloud | ⏳ |
| HTTPS Response | HTTP 2xx or 3xx status | ⏳ |
| Code-Server Access | Service accessible via HTTPS | ⏳ |
| All 6 Services Running | docker ps shows 6 Up services | ⏳ |

### Secondary Path (Should Pass for Full Confidence)

| Test | Success Criteria | Status |
|------|-----------------|--------|
| SSH Proxy | Port 2222 responds | ⏳ |
| Caddy Config | No errors in logs | ⏳ |
| Redis | PING returns PONG | ⏳ |
| Ollama | API responds with models | ⏳ |
| Load Test | 95%+ request success rate | ⏳ |

---

## Failure Handling & Troubleshooting

### If DNS Resolution Fails

1. **From VPN, verify resolver**:
   ```bash
   cat /etc/resolv.conf | grep nameserver
   ```

2. **Test with each resolver**:
   ```bash
   dig ide.kushnir.cloud @8.8.8.8
   dig ide.kushnir.cloud @1.1.1.1
   ```

3. **Check production host DNS server**:
   ```bash
   ssh akushnir@192.168.168.31 "cat /etc/resolv.conf"
   ```

4. **Escalation**: Contact infrastructure team to verify DNS propagation

### If TLS Certificate Fails

1. **Verify certificate exists on host**:
   ```bash
   ssh akushnir@192.168.168.31 "ls -l /home/akushnir/code-server-phase13/ssl/"
   ```

2. **Check Caddy certificate loading**:
   ```bash
   ssh akushnir@192.168.168.31 "docker logs caddy | grep -i certificate"
   ```

3. **Regenerate self-signed cert** (Temporary):
   ```bash
   ssh akushnir@192.168.168.31 "cd /home/akushnir/code-server-phase13 && \
     openssl req -x509 -newkey rsa:2048 -keyout ssl/cf_origin.key \
     -out ssl/cf_origin.crt -days 365 -nodes \
     -subj '/CN=ide.kushnir.cloud'"
   ```

4. **Escalation**: If persistent, contact security team

### If HTTPS Response Fails

1. **Verify Caddy is running**:
   ```bash
   ssh akushnir@192.168.168.31 "docker ps | grep caddy"
   ```

2. **Check Caddy logs**:
   ```bash
   ssh akushnir@192.168.168.31 "docker logs caddy | tail -50"
   ```

3. **Test internal connectivity**:
   ```bash
   ssh akushnir@192.168.168.31 "curl -I localhost:80/"
   ```

4. **Escalation**: Contact DevOps team

### If Service Health Fails

1. **Check all services**:
   ```bash
   ssh akushnir@192.168.168.31 "docker ps -a"
   ```

2. **Review service logs**:
   ```bash
   ssh akushnir@192.168.168.31 "docker logs <service_name>"
   ```

3. **Restart service stack**:
   ```bash
   ssh akushnir@192.168.168.31 "cd /home/akushnir/code-server-phase13 && \
     docker-compose restart"
   ```

4. **Escalation**: Contact DevOps team

---

## Post-Launch Actions

### Immediate (Same day as launch)

- [ ] Monitor error logs for 24 hours
- [ ] Verify user access via Slack channel
- [ ] Document any discovery/fixes in GitHub Issue #214

### Week 1 Post-Launch

- [ ] Implement Let's Encrypt auto-renewal (upgrade from self-signed)
- [ ] Enable AppArmor profiles gradually (start with audit mode)
- [ ] Establish baseline performance metrics

### Week 2-4 Post-Launch

- [ ] Full AppArmor enforcement
- [ ] Seccomp profile hardening
- [ ] Security audit of authentication flow

---

## Sign-Off and Approval

### Technical Review

- [ ] DevOps Lead: _________________ Date: _______
- [ ] Security Lead: _________________ Date: _______

### Management Approval

- [ ] Engineering Manager: _________________ Date: _______
- [ ] Project Stakeholder: _________________ Date: _______

### Production Launch Authorization

- [ ] All critical path tests PASSED
- [ ] All secondary path tests PASSED or documented
- [ ] Failure handling plan reviewed
- [ ] Post-launch actions scheduled
- [ ] GitHub Issue #214 ready for closure

**Launch Authorization**: ❌ NOT YET (TESTS PENDING)

---

## Appendix: VPN Testing Requirements Explanation

### Why VPN-Aware Testing?

1. **End-User Perspective**: Users access ide.kushnir.cloud through company VPN
2. **DNS Resolution**: VPN DNS servers may differ from public resolvers
3. **Routing**: VPN routes to 192.168.168.31 on internal network
4. **TLS Verification**: VPN routing must reach TLS endpoint without interference
5. **OAuth2 Flow**: Full auth flow must work through VPN proxy chains

### VPN Testing Checklist

- [ ] User is connected to production VPN before running tests
- [ ] VPN DNS servers are used (not public resolvers)
- [ ] Routing table shows VPN tunnel (tun/wg interface)
- [ ] Ping 192.168.168.31 succeeds with low latency
- [ ] All DNS tests use VPN DNS (automatic, or explicitly)
- [ ] TLS handshakes occur through VPN routing
- [ ] HTTPS responses travel through VPN proxy
- [ ] SSH sessions tunnel through VPN gateway

### VPN Testing Tools

```bash
# Check VPN status
ip link show | grep -E "tun|wg"
ip route | grep -E "tun|wg|vpn"
cat /etc/resolv.conf | grep -i nameserver

# Verify VPN DNS
nslookup ide.kushnir.cloud
dig ide.kushnir.cloud +trace  # Shows resolver chain
```

---

**Document Version**: 1.1
**File Location**: `/PHASE-14-VPN-VALIDATION-CHECKLIST.md`
**Last Updated**: April 13, 2026 - 21:30 UTC
**Git Commit**: [Pending - to be updated during Phase 14 validation execution]

---

*This checklist is a living document. Updates based on validation results will be committed to git with detailed messages.*
