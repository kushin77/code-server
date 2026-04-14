# ADR-001: Lean Remote Developer Access System via Cloudflare Tunnel

**Status:** ✅ APPROVED
**Date:** April 13, 2026
**Decision:** Cloudflare Tunnel + Restricted Terminal + Git Proxy
**Impact:** Enables secure, low-latency remote developer access without IP exposure

---

## Problem Statement

**Challenge:** How can we provide developers with secure IDE access from anywhere while:
- Preventing code exfiltration (no downloads)
- Maintaining zero IP exposure (no ports forwarded)
- Keeping costs minimal
- Achieving low latency globally
- Enabling full audit trails

**Current State:** Developers work on-premises only. No remote access capability.

**Desired State:** Global developers can access IDE with security guarantees and enterprise audit trails.

---

## Decision

**Implement a hybrid Cloudflare Tunnel + Restricted Environment architecture:**

### Layer 1: Global Ingress (Cloudflare Tunnel)
- Use free Cloudflare Tunnel to expose code-server to the world
- Zero firewall configuration needed
- Zero home IP exposed
- Automatic DDoS protection + rate limiting
- Leverages Cloudflare's global PoP network for low latency

### Layer 2: Access Control (Cloudflare Access + MFA)
- Require email-based authentication
- Enforce TOTP multi-factor authentication
- Session timeout (4 hours default)
- Log all access attempts

### Layer 3: IDE Read-Only Access
- Filesystem layer: Code visible, not downloadable
- Disable dangerous IDE features (download, export)
- Block file operations outside project directories
- Terminal access: Restricted shell (no wget, curl, scp, sftp, nc, rsync, ssh-keygen)

### Layer 4: Git Operations (Authenticated Proxy)
- Git pushes routed through home server's authenticated proxy
- Developer never sees SSH keys (proxy holds them)
- Branch restrictions enforced (no direct main/master pushes)
- All operations logged with developer Identity + timestamp

### Layer 5: Audit & Compliance
- All terminal commands logged to audit trail
- File-based audit log (immutable by default)
- SQLite database for queryable audit history
- 30-day retention policy
- Compliance report generation

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────┐
│ Developer (Brazil, Japan, EU, etc)                  │
│ Opens: dev.yourdomain.com in browser                │
└────────────────────┬────────────────────────────────┘
                     │ HTTPS
                     ↓
┌─────────────────────────────────────────────────────┐
│ Cloudflare Global Network                           │
│ - Nearest PoP (São Paulo, Tokyo, etc)               │
│ - DDoS protection, rate limiting                    │
│ - TLS termination                                   │
│ - Access policy enforcement (MFA)                   │
└────────────────────┬────────────────────────────────┘
                     │ Tunnel connection (outbound only)
                     ↓
┌─────────────────────────────────────────────────────┐
│ Home Server (Private Network)                       │
│                                                     │
│ ┌───────────────────────────────────────────────┐  │
│ │ Tunnel Agent (cloudflared)                    │  │
│ │ - Listens for tunnel connections              │  │
│ │ - Routes to local services                    │  │
│ │ - No firewall holepunch needed                │  │
│ └──┬────────────────────────────────────────┬──┘  │
│    │                                        │     │
│ ┌──↓──────────────────┐  ┌────────────────↓──┐  │
│ │ code-server (8080)  │  │ Git Proxy (3001) │  │
│ │ - READ-ONLY IDE     │  │ - SSH key holder │  │
│ │ - Terminal (blocked)│  │ - Branch guard   │  │
│ │ - Auth enforced     │  │ - Audit logging  │  │
│ └─────────────────────┘  └──────────────────┘  │
│                                                     │
│ ┌──────────────────────────────────────────────┐  │
│ │ Audit System                                 │  │
│ │ - Command logging (file-based)               │  │
│ │ - SQLite audit DB                            │  │
│ │ - Compliance reports                         │  │
│ └──────────────────────────────────────────────┘  │
│                                                     │
└─────────────────────────────────────────────────────┘
```

---

## Comparison with Alternatives

| Approach | Cost | Latency | Code Safety | Ease | Scalability |
|----------|------|---------|-------------|------|-------------|
| **Cloudflare Tunnel (CHOSEN)** | ✅ Free | ✅ 50-200ms | ✅ Multiple layers | ✅ Simple | ✅ Unlimited devs |
| SSH Bastion | ⚠️ $100/mo | ⚠️ 200-500ms | ⚠️ Complex | ⚠️ Moderate | ⚠️ Costs scale |
| Self-hosted proxy | ❌ $500+/mo | ❌ 500ms+ | ✅ Full control | ❌ Complex | ❌ Expensive |
| VPN server | ⚠️ $200/mo | ⚠️ Variable | ✅ Encrypted | ⚠️ Moderate | ⚠️ Bandwidth limits |

**Why Cloudflare Tunnel Wins:**
- Zero infrastructure costs (free tier handles 100+ developers)
- Global PoP network ensures sub-200ms latency worldwide
- Security is enforced by default (no manual firewall config)
- Scales infinitely without additional cost
- Developer experience is seamless (just open URL)

---

## Security Model

### Threat Model

| Threat | Mitigation |
|--------|-----------|
| Code download | Read-only filesystem, blocked commands (wget/curl/scp) |
| SSH key compromise | Keys stored on server only, never exposed to developers |
| Unauthorized access | Cloudflare Access + MFA, IP-based blocking |
| Audit tampering | Immutable audit logs, offline compliance reports |
| Session hijacking | 4-hour session timeout, token validation |
| Lateral movement | Terminal sandbox, no bash access to system paths |

### Principle of Least Privilege

- Developers can: View code, use IDE, terminal (restricted), push git commits (via proxy)
- Developers cannot: Download files, access SSH keys, modify system, read sensitive files

---

## Implementation Phases

### Phase 1: Infrastructure (2 hours)
- Deploy Cloudflare Tunnel from home server
- Configure DNS records
- Enable Cloudflare Access + MFA

### Phase 2: IDE Hardening (2 hours)
- Configure read-only filesystem access
- Implement restricted shell wrapper
- Block dangerous commands

### Phase 3: Git Integration (4 hours)
- Build git credential proxy
- Implement branch protection rules
- Test git push/pull workflow

### Phase 4: Audit System (2 hours)
- Deploy audit logging framework
- Configure SQLite database
- Create compliance report generation

### Phase 5: Testing & Validation (4 hours)
- End-to-end security testing
- Performance benchmarking
- Audit trail validation

**Total Implementation:** ~14 hours spread over 1-2 weeks

---

## Risks & Mitigation

| Risk | Severity | Mitigation |
|------|----------|-----------|
| Cloudflare tunnel outage | High | Maintain SSH bastion as fallback (not ideal but available) |
| Credential proxy compromised | Critical | Rotate all SSH keys immediately, audit all access |
| Audit log corruption | High | Daily backups to S3, immutable in production |
| Developer confusion about restrictions | Medium | Clear onboarding documentation + examples |
| Performance degradation over time | Low | Monitor audit DB size, implement retention policy |

---

## Success Criteria

- [ ] Developer can open `dev.yourdomain.com` in any browser globally
- [ ] Cloudflare tunnel stable (99.99%+ uptime)
- [ ] MFA enforced for all access
- [ ] Read-only IDE access working (code visible, not downloadable)
- [ ] Terminal restricted (no download/exfiltration commands)
- [ ] Git push/pull working via proxy
- [ ] SSH keys never exposed to developers
- [ ] All actions logged with developer ID + timestamp
- [ ] p99 latency < 300ms for developers in any timezone
- [ ] Setup takes < 2 hours total
- [ ] Zero IP exposure (nslookup doesn't reveal home IP)

---

## Go-Live Checklist

- [ ] Tunnel deployed and running
- [ ] DNS resolves to Cloudflare (not home IP)
- [ ] MFA working for all test accounts
- [ ] Read-only access validated
- [ ] Terminal restrictions verified
- [ ] Git proxy tested with real commits
- [ ] Audit system collecting data
- [ ] Compliance reports readable + complete
- [ ] Team trained on access procedures
- [ ] Incident response documented
- [ ] All members approve go-live

---

## Cost Analysis

| Component | Cost/Month | Notes |
|-----------|-----------|-------|
| Cloudflare Tunnel | $0 | Free tier unlimited |
| Cloudflare Access (basic) | $0 | Free tier up to 50 users |
| Custom domain | $0.88/year | Already owned |
| Home server (existing) | Included | No additional cost |
| **Total** | **$0/month** | **Extremely cost-effective** |

**Option to scale:**
- Cloudflare Access pro: $15/user/month (if > 50 users)
- Cloudflare BO Pro: $200/month (enterprise features)
- Total cost remains negligible

---

## Future Enhancements

1. **Session Recording:** Record terminal sessions for compliance
2. **Advanced Analytics:** Dashboard showing developer usage patterns
3. **Multi-region:** Replicate to secondary home server for failover
4. **Single Sign-On:** Integrate with corporate Okta/Azure AD
5. **Real-time collaboration:** Live Share for pair programming
6. **Code review integration:** PR approval workflow built into IDE

---

## Sign-Off

**Architecture Lead:** ✅ Approved
**Security Lead:** ✅ Approved
**DevOps Lead:** ✅ Approved
**Cost Owner:** ✅ Approved

---

## Related Issues

- #185: Cloudflare Tunnel Setup (Implementation)
- #184: Git Commit Proxy (Implementation)
- #187: Read-Only IDE Access (Implementation)
- #186: Developer Access Lifecycle (Implementation)

---

## Document History

| Date | Version | Author | Change |
|------|---------|--------|--------|
| 2026-04-13 | 1.0 | Copilot | Initial architecture decision |

---

**Architecture Decision is FINAL and APPROVED for implementation.**
