# Security Hardening - Post-Launch Remediation

**Status**: Post-launch priority  
**Date**: April 13, 2026  
**Current Risk Level**: MODERATE (temporary workarounds only)

---

## Executive Summary

Phase 14 production launch uses **temporary** security workarounds to bypass host-level kernel restrictions. These must be replaced with proper security profiles post-launch.

### Current State (NOT PRODUCTION-READY)
- ✅ Services running and functional
- ❌ AppArmor disabled (`apparmor=unconfined`)
- ❌ Seccomp disabled (`seccomp=unconfined`)
- ❌ TLS using self-signed certificate
- ⏳ Audit logging in progress, needs validation

### Post-Launch Requirements (Must Complete Before Full Prod)
1. **AppArmor Profile Development** (HIGH PRIORITY)
2. **Seccomp Filter Hardening** (HIGH PRIORITY)
3. **CA-Signed TLS Certificate** (MEDIUM PRIORITY)
4. **Audit Logging Validation** (MEDIUM PRIORITY)
5. **Security Scanning Integration** (MEDIUM PRIORITY)

---

## 1. AppArmor Profile Development (CRITICAL)

### Current Status
```yaml
# TEMPORARY - Not secure for production
security_opt:
  - apparmor=unconfined  # ❌ Disables all AppArmor restrictions
```

### Required Solution
Create custom AppArmor profile `/etc/apparmor.d/code-server-containers` allowing:
- Binary execution from /usr/bin, /usr/local/bin, /bin
- Network access on required ports only (8080, 2222, 3222, 11434, 6379)
- File system access limited to container mounts
- Deny: Device access, raw sockets, admin operations

### Implementation Steps
1. **Profile Development** (Infrastructure/Security team)
   - Use AppArmor learning mode to detect required capabilities
   - Generate profile from container behavior logs
   - Test with audit mode before enforcement

2. **Profile Testing** (QA/Validation)
   - Verify code-server IDE functions with profile enabled
   - Verify no spurious "permission denied" errors
   - Load test to ensure no performance impact

3. **Deployment**
   - Update docker-compose.yml security_opt:
     ```yaml
     security_opt:
       - apparmor=code-server-containers  # ✅ Custom profile
     ```
   - Rollout to production infrastructure

### Success Criteria
- All services start without AppArmor denials
- No "audit" mode messages in logs
- Load test SLOs still met
- Zero false-positive permission denials from legitimate operations

---

## 2. Seccomp Filter Hardening (CRITICAL)

### Current Status
```yaml
# TEMPORARY - No syscall restrictions
security_opt:
  - seccomp=unconfined  # ❌ Allows all syscalls
```

### Required Solution
Create custom seccomp filter `/etc/docker/seccomp-code-server.json` allowing only:
- Process management: execve, fork, clone, wait4, exit
- File I/O: open, read, write, close, stat, lstat, fstat
- Network: socket, connect, bind, listen, accept, send, recv
- Memory: mmap, brk, mprotect
- Signals: rt_sigaction, rt_sigprocmask
- Deny: All others (ptrace, chroot, mount, reboot, etc.)

### Implementation Steps
1. **Filter Development** (Infrastructure/Security)
   - Generate from seccomp-tools or bpftrace container behavior recording
   - Validate against known CVEs prevented by seccomp restrictions
   - Test in audit mode first

2. **Validation** (QA)
   - Full integration test suite
   - Load test with expected workloads
   - Security scanning for exploitable syscalls

3. **Deployment**
   - Update docker-compose.yml:
     ```yaml
     security_opt:
       - seccomp=/etc/docker/seccomp-code-server.json  # ✅ Custom filter
     ```

### Success Criteria
- Zero container startup failures
- SLO targets maintained during load test
- All functionality preserved
- Audit mode shows no false-positive denials

---

## 3. TLS Certificate Replacement (MEDIUM PRIORITY)

### Current Status
```
Self-signed certificate valid for ide.kushnir.cloud
- Generated at deployment time
- Valid for 365 days (until April 13, 2027)
- Browser shows security warning (expected, but not ideal)
```

### Required Solution
Obtain CA-signed certificate from:
- **Option A**: CloudFlare Origin Certificate (recommended)
  - Free with CloudFlare account
  - Valid for *.elevatediq.ai domains only (won't work for .kushnir.cloud)
  
- **Option B**: GoDaddy SSL Certificate
  - Purchase standard SSL cert for ide.kushnir.cloud
  - ~$50-100/year, 1-year renewal
  - Requires domain ownership verification

- **Option C**: Let's Encrypt (Free)
  - Free automated certificate renewal
  - Requires Caddy to request via ACME (currently disabled)
  - Easiest for long-term maintenance

### Implementation Steps
1. **Certificate Procurement**
   - Recommend: Let's Encrypt (free, automated)
   - Enable ACME in Caddyfile: `tls /etc/caddy/ssl/letsencrypt {}`

2. **Caddyfile Update**
   - Replace self-signed reference with automatic ACME
   - Enable auto_https (currently disabled)
   - Test certificate renewal process

3. **Validation**
   - Browser shows green lock icon
   - Certificate chain valid
   - No manual renewal needed (ACME handles it)

### Success Criteria
- Zero TLS warnings in browser
- Certificate chain shows only trusted CAs
- Auto-renewal functional
- No service disruption during renewal

---

## 4. Audit Logging Validation (MEDIUM)

### Current Status
- ✅ SSH proxy audit logging configured
- ✅ JSON log output to `/var/log/code-server-audit.log`
- ✅ SQLite database at `/var/lib/code-server/audit.db`
- ⏳ Validation not yet complete

### Required Validation
1. **Audit Log Capture**
   - [ ] All SSH connections logged with user, IP, timestamp
   - [ ] Commands captured with full arguments
   - [ ] Session duration recorded
   - [ ] Connection termination logged
   - [ ] Failed auth attempts logged

2. **Database Searchability**
   - [ ] Query recent sessions: `SELECT * FROM ssh_sessions ORDER BY start_time DESC LIMIT 10`
   - [ ] Search by user: `SELECT * FROM ssh_sessions WHERE username='akushnir'`
   - [ ] Search by IP: `SELECT * FROM ssh_sessions WHERE remote_ip='192.168.1.100'`

3. **Compliance Verification**
   - [ ] Log retention policy: 90+ days minimum
   - [ ] Immutable storage (logs can't be modified after write)
   - [ ] Central syslog forwarding configured
   - [ ] PII redaction applied where required

### Implementation
1. Query audit logs post-Phase-14-launch
2. Validate schema matches expected format
3. Test compliance queries
4. Set up automated backups
5. Configure syslog forwarding to central log aggregation

---

## 5. Security Scanning Integration (MEDIUM)

### Current Status
- ❌ No automated security scanning in CI/CD
- ❌ Container images not scanned for vulnerabilities

### Required Scanning Tools
1. **Image Scanning** (Trivy / Snyk)
   - Scan all container images pre-build
   - Generate SBOM (Software Bill of Materials)
   - Fail build if critical/high vulnerabilities found

2. **Configuration Scanning** (OPA / kube-mgmt)
   - Validate docker-compose.yml follows security best practices
   - Check for insecure defaults
   - Enforce AppArmor/seccomp usage

3. **Dependency Scanning** (OWASP Dependency Check)
   - Scan npm packages in code-server extensions
   - Scan Python packages in Ollama
   - Generate security advisories

### Implementation Steps
1. Add Trivy scanning to GitHub Actions
2. Add OPA policy enforcement
3. Create security dashboards
4. Set up weekly vulnerability reports

---

## Implementation Priority & Timeline

| Item | Priority | Owner | Timeline |
|------|----------|-------|----------|
| **AppArmor Profile** | CRITICAL | Infra/Security | Week 1-2 Post-Launch |
| **Seccomp Filter** | CRITICAL | Infra/Security | Week 1-2 Post-Launch |
| **TLS Certificate** | MEDIUM | DevOps | Week 2-3 Post-Launch |
| **Audit Log Validation** | MEDIUM | Ops/Compliance | Week 1 Post-Launch |
| **Security Scanning** | MEDIUM | DevOps/Security | Week 3-4 Post-Launch |

---

## Risk Assessment

### Current Risk (With Workarounds)
**Level**: MODERATE

**Risks**:
- 🔴 Container escape via kernel exploit (AppArmor disabled)
- 🔴 Malicious syscalls not restricted (seccomp disabled)
- 🟡 TLS certificate not CA-verified (browser warning, MITM risk)
- 🟡 Audit logs not validated for compliance

**Mitigations**:
- Only trusted developers can access (OAuth2 gate)
- Network isolation within data center
- Code review + testing catches malicious changes
- Temporary nature documented and tracked

### Post-Hardening Risk
**Level**: LOW

**After security hardening**:
- 🟢 AppArmor + seccomp limit container capabilities
- 🟢 TLS verified by trusted CA
- 🟢 Audit logs validated and compliant
- 🟢 Security scanning prevents known CVEs

---

## Approval & Signoff

**Current Approval**: CONDITIONAL (temporary workarounds only)  
- ✅ Approved for Phase 14 launch (development/testing)
- ❌ NOT approved for unrestricted production access
- ⏳ Final production approval pending security hardening

**Final Signoff Requirements**:
1. ✅ AppArmor profile deployed and tested
2. ✅ Seccomp filter deployed and tested
3. ✅ TLS certificate replaced with CA-signed
4. ✅ Audit logging validated
5. ✅ Security scanning integrated
6. ✅ Zero P0/P1 vulnerabilities

---

## References

- [NIST Container Security Guide](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-190.pdf)
- [CIS Docker Benchmark](https://www.cisecurity.org/cis-benchmarks/)
- [AppArmor Documentation](https://gitlab.com/apparmor/apparmor/-/wikis/home)
- [Seccomp Filtering](https://man7.org/linux/man-pages/man2/seccomp.2.html)
- [Docker Security Best Practices](https://docs.docker.com/engine/security/)

---

## Checklist (Post-Launch)

### Week 1 Post-Launch
- [ ] Schedule security hardening planning meeting
- [ ] Assign AppArmor profile development
- [ ] Assign seccomp filter development
- [ ] Start audit log validation

### Week 2 Post-Launch
- [ ] Complete AppArmor profile (dev + testing)
- [ ] Complete seccomp filter (dev + testing)
- [ ] Validate audit logs
- [ ] Procure CA certificate (or configure Let's Encrypt)

### Week 3 Post-Launch
- [ ] Deploy AppArmor profile to production
- [ ] Deploy seccomp filter to production
- [ ] Replace TLS certificate
- [ ] Complete security scanning setup

### Week 4 Post-Launch
- [ ] Final security validation
- [ ] Penetration testing (optional but recommended)
- [ ] Security hardening sign-off
- [ ] Final production approval

---

**Document Status**: APPROVED AS FINAL POST-LAUNCH PLAN  
**Approval Date**: April 13, 2026  
**Next Review**: After Phase 14 Production Launch  
**Owner**: Security & Infrastructure Teams
