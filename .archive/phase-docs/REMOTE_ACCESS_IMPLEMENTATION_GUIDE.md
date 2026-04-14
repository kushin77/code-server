# Lean On-Premises Remote Developer Access System
## Complete Implementation Guide

**Status**: Architecture defined in GitHub issues #181-#189
**Cost**: $0.88/year (domain only, Cloudflare free tier)
**Implementation Timeline**: 6 weeks (phased)
**Target**: Cost-effective, secure, low-latency global access to on-premises code-server

---

## Quick Reference

### Your Workflow (After Implementation)
```bash
# Grant contractor access for 2 weeks
make grant-access EMAIL=contractor@example.com DAYS=14

# They access IDE at https://dev.yourdomain.com
# All actions logged for audit
# Auto-revokes on day 15

# Or manually revoke immediately
make revoke-access EMAIL=contractor@example.com
```

### System Properties
- **Cost**: $0.88/year (domain only)
- **Latency**: <150ms same-continent, <350ms cross-continent
- **Security**: Read-only IDE, restricted terminal, git proxy, full audit
- **Code Protection**: Code never downloads, zero SSH key exposure
- **Scaling**: Same cost for 1-100+ developers

---

## Architecture Overview

### Three Security Layers

#### Layer 1: Network Ingress (Cloudflare Tunnel)
- Route all traffic through Cloudflare global edge
- No home IP exposure (Tunnel bridges encrypted connection)
- Free tier, includes DDoS protection
- Sub-50ms latency to nearest PoP

#### Layer 2: Access Control (Cloudflare Access + Time Bounds)
- Zero-trust authentication (MFA required)
- Time-bounded sessions (4 hour default, expires per schedule)
- Domain-level protection
- Session logging in Cloudflare dashboard

#### Layer 3: Code Protection (Multi-layer)
- **IDE**: Read-only filesystem, no downloads
- **Terminal**: Command filtering (blocks wget, scp, nc, rsync, etc.)
- **Git**: Credential proxy (SSH keys on server only)
- **Audit**: Complete activity trail (file access, commands, git ops)

### Data Flow

```
Developer (Brazil)
  │
  └─→ https://dev.yourdomain.com
      │
      └─→ Cloudflare São Paulo PoP (50ms)
          │
          └─→ Cloudflare Tunnel (encrypted)
              │
              └─→ Home Server (180ms)
                  │
                  ├─→ code-server (IDE, read-only)
                  ├─→ restricted-shell (terminal, filtered)
                  ├─→ git-proxy (git operations)
                  └─→ audit-system (logging)

Total latency: ~330ms (acceptable, further optimizable)
```

---

## Implementation Phases

### Phase 1: Infrastructure (Week 1)
**GitHub Issue**: [#181 ARCH](https://github.com/kushin77/code-server/issues/181), [#185 IMPL](https://github.com/kushin77/code-server/issues/185)

**Tasks**:
1. Install Cloudflare tunnel on home server
2. Authenticate with Cloudflare account
3. Create tunnel "home-dev"
4. Configure routing to code-server (port 8080)
5. Set up DNS records (dev.yourdomain.com)
6. Configure Cloudflare Access (MFA, email whitelist)
7. Test: IDE loads at custom domain, home IP not exposed

**Estimated Time**: 2-4 hours
**Key Files**: `~/.cloudflared/config.yml`

---

### Phase 2: Access Control (Week 2)
**GitHub Issue**: [#187 IMPL](https://github.com/kushin77/code-server/issues/187)

**Tasks**:
1. Configure code-server read-only mode
2. Build restricted shell wrapper (`/usr/local/bin/restricted-shell`)
3. Implement command filtering (block wget, scp, nc, rsync, etc.)
4. Hide sensitive files (.env, .ssh keys)
5. Test: Developers can view code, cannot download

**Estimated Time**: 3-5 hours
**Key Files**:
- `.config/code-server/config.yaml`
- `/usr/local/bin/restricted-shell`
- `/etc/profile.d/developer-restrictions.sh`

---

### Phase 3: Git Operations (Week 3)
**GitHub Issue**: [#184 IMPL](https://github.com/kushin77/code-server/issues/184)

**Tasks**:
1. Build git credential proxy server (FastAPI)
2. Configure git credential helper on developers' sessions
3. Set up branch protections in proxy (no main/master push)
4. Implement SSH key management (keys on server only)
5. Test: `git push origin feature-branch` works, but main is protected

**Estimated Time**: 4-6 hours
**Key Files**:
- `/home/user/git-proxy/server.py`
- `/usr/local/bin/git-credential-cloudflare-proxy`
- `/etc/systemd/system/git-proxy.service`

---

### Phase 4: Developer Lifecycle (Week 4)
**GitHub Issue**: [#186 IMPL](https://github.com/kushin77/code-server/issues/186)

**Tasks**:
1. Create `developer-grant` script (one-command provisioning)
2. Create `developer-revoke` script (one-command revocation)
3. Set up developer database (CSV: email, expiry, status)
4. Implement Cloudflare API integration
5. Configure auto-revocation cron job
6. Test: `make grant-access EMAIL=test@example.com DAYS=1` works

**Estimated Time**: 3-4 hours
**Key Files**:
- `~/.code-server-developers/developers.csv`
- `/usr/local/bin/developer-grant`
- `/usr/local/bin/developer-revoke`
- `/usr/local/bin/developer-auto-revoke-cron`

---

### Phase 5: Audit & Compliance (Week 5)
**GitHub Issue**: [#183 IMPL](https://github.com/kushin77/code-server/issues/183)

**Tasks**:
1. Build central audit logger (Python)
2. Hook IDE for file access logging
3. Hook terminal for command logging
4. Hook git-proxy for git operation logging
5. Create audit query tools (`audit-query`, `audit-compliance-report`)
6. Test: All actions logged and queryable

**Estimated Time**: 4-5 hours
**Key Files**:
- `/home/user/audit-system/log-collector.py`
- `/home/user/audit-system/logging-functions.sh`
- `/usr/local/bin/audit-query`
- `~/.code-server-developers/logs/audit.jsonl`

---

### Phase 6: Performance & Operations (Week 6)
**GitHub Issue**: [#182 IMPL](https://github.com/kushin77/code-server/issues/182), [#188 IMPL](https://github.com/kushin77/code-server/issues/188)

**Tasks**:
1. Enable WebSocket compression in tunnel config
2. Implement terminal output batching
3. Set up latency monitoring
4. Create Makefile with standard commands
5. Write quick-start guide
6. Test: Full system works end-to-end

**Estimated Time**: 3-4 hours
**Key Files**:
- `Makefile.remote-access`
- `/home/user/latency-monitor/monitor.py`
- `setup-remote-access.sh`
- `quick-reference.txt`

---

## Critical Success Factors

### Security (Non-Negotiable)
- ✅ Home server IP never exposed (verify with `curl -I https://dev.yourdomain.com` shows Cloudflare, not home IP)
- ✅ SSH keys never visible to developers (proxy holds keys)
- ✅ Code cannot be downloaded (IDE read-only + terminal filtering)
- ✅ All actions logged (100% audit trail)
- ✅ Time-bounded access (no lingering access)

### Performance (Target)
- ✅ IDE loads in <500ms
- ✅ Terminal keystroke echo <100ms
- ✅ Same-continent latency <150ms
- ✅ Cross-continent latency <350ms

### Operations (Ease of Use)
- ✅ One-command grant: `make grant-access EMAIL=dev@example.com DAYS=7`
- ✅ One-command revoke: `make revoke-access EMAIL=dev@example.com`
- ✅ One-command health check: `make health-check`
- ✅ Auto-revocation (no manual intervention needed)

---

## Cost Breakdown

### Setup Costs
| Item | Cost | Notes |
|------|------|-------|
| Domain (.com/.net bulk) | $0.88/year | One-time (~$0.07/month amortized) |
| Cloudflare account | FREE | Free tier |
| Time (6 weeks × 40 hrs) | 240 hours | Your labor (amortized) |
| **Total Ongoing** | **$0.88/year** | Just domain |

### vs Alternatives
| Solution | Setup | Monthly | Annual |
|----------|-------|---------|--------|
| Your system (Cloudflare) | 6 weeks | $0.07 | $0.88 |
| AWS EC2 small (us-east-1) | 2 hours | $12 | $144 |
| DigitalOcean VPS | 2 hours | $6 | $72 |
| Heroku Dyno | 1 hour | $15 | $180 |
| Self-hosted proxy | 4 weeks | $20-50 | $240-600 |

**Your system is 100-600x cheaper than alternatives** with better security (zero IP exposure).

---

## Getting Started Checklist

### Pre-Implementation
- [ ] Confirm Cloudflare account & API token available
- [ ] Identify desired domain (dev.yourdomain.com)
- [ ] Verify code-server running on home network
- [ ] Read all 9 GitHub issues (#181-#189)
- [ ] Choose implementation timeline (parallel phases vs sequential)

### Week 1 Setup
- [ ] Install cloudflared on home server
- [ ] Authenticate with Cloudflare
- [ ] Create tunnel "home-dev"
- [ ] Configure DNS records
- [ ] Set up Cloudflare Access MFA
- [ ] Verify IDE loads at custom domain

### Post-Implementation
- [ ] Test grant/revoke workflows
- [ ] Verify audit logging
- [ ] Monitor latency metrics
- [ ] Document team procedures
- [ ] Set up monitoring/alerting

---

## Key Files & Directories

```
System Structure After Implementation:

~/.code-server-developers/
├── developers.csv                 # Developer database
├── revocation.log                 # Admin action log
└── logs/
    ├── audit.jsonl               # Master audit log
    └── YYYY-MM-DD.log            # Date-partitioned logs

/usr/local/bin/
├── developer-grant               # Provision access
├── developer-revoke              # Revoke access
├── developer-list                # List developers
├── audit-query                   # Search audit logs
└── audit-compliance-report       # Generate reports

~/.cloudflared/
└── config.yml                    # Tunnel routing

/home/user/git-proxy/
├── server.py                     # FastAPI proxy
└── logging.py                    # Git operation logging

/home/user/audit-system/
├── log-collector.py              # Central logger
├── logging-functions.sh          # Bash integration
└── ide-monitor.py                # IDE hooking

/home/user/terminal-proxy/
└── optimizer.py                  # Terminal batching

/home/user/latency-monitor/
└── monitor.py                    # Metrics collection
```

---

## Typical Usage Examples

### Granting Access
```bash
# Grant 2-week access to contractor
$ make grant-access EMAIL=jane@contractor.com DAYS=14
✅ Access granted to jane@contractor.com until 2026-04-27

# Developer receives email with:
# - IDE URL: https://dev.yourdomain.com
# - Duration: 14 days (auto-revokes 2026-04-28)
# - Restrictions listed
# - Session timeout: 4 hours
```

### Developer Using System
```bash
# 1. Opens IDE
https://dev.yourdomain.com

# 2. Logs in with email (Cloudflare Access MFA)
Email: jane@contractor.com
Code: [sent to email]

# 3. IDE loads - code is visible, read-only
Can read all project files
Can use search, go-to-def, syntax highlighting
Cannot download files
Cannot edit (read-only)

# 4. Terminal available for work
$ git status
On branch develop
Your branch is up to date...

$ git commit -am "feat: add feature X"
[develop abc1234] feat: add feature X

$ git push origin develop
Pushing code through proxy (SSH key never exposed)
✓ Success

# Attempted dangerous command:
$ wget https://external-site.com/archive.tar.gz
Error: Command 'wget' is restricted for security
```

### Automatic Revocation
```bash
# 2026-04-27 23:59:59 UTC
# Cron job triggers:

- Cloudflare Access policy expires
- jane@contractor.com automatically logged out
- All active sessions terminated
- Git proxy revokes credentials
- Audit log: "Developer session ended: jane@contractor.com (expired)"

# jane tries to access IDE:
# Error 403: Access denied (policy expired)
```

### Manual Revocation
```bash
# If contractor ends early:
$ make revoke-access EMAIL=jane@contractor.com
✅ Access revoked for jane@contractor.com

# Immediate effects:
- jane@contractor.com logged out (if active)
- Git operations blocked
- All access terminated
- Audit log updated
```

---

## Monitoring & Maintenance

### Daily Checks
```bash
make health-check
# Shows: Cloudflared status, code-server status, tunnel connectivity
```

### Weekly Review
```bash
# List active developers
make list-developers

# Check for violations
audit-query --date $(date +%Y-%m-%d) | grep VIOLATION
```

### Monthly Audit
```bash
# Generate compliance report
audit-compliance-report

# Review: access grants, revokes, violations
```

### Quarterly Review
```bash
# Analyze latency trends
# Review audit retention
# Update security policies if needed
```

---

## Troubleshooting

### IDE Not Accessible
```bash
# Check tunnel status
systemctl status cloudflared

# Check tunnel logs
journalctl -u cloudflared -f

# Verify DNS resolution
nslookup dev.yourdomain.com

# Check home server connectivity
ping home-server-ip
```

### Developer Cannot Access
```bash
# Verify in database
grep developer@example.com ~/.code-server-developers/developers.csv

# Check expiry date
# Verify Cloudflare Access policy is active
# Check session timeout (default 4 hours)
```

### Git Operations Failing
```bash
# Check git-proxy status
systemctl status git-proxy

# View git-proxy logs
journalctl -u git-proxy -f

# Test git manually
git status
```

---

## Next Steps

1. **Read the Architecture** (Issue #181)
   - Understand the design decisions
   - Review comparison with alternatives

2. **Start Phase 1** (Issue #185)
   - Install Cloudflare tunnel
   - Configure routing
   - Verify connectivity

3. **Follow Phases 2-6** (Issues #187, #184, #186, #183, #182, #188)
   - Implement incrementally
   - Test each phase
   - Move to next phase when complete

4. **Deploy to Production**
   - Run full end-to-end test
   - Grant access to first developer
   - Monitor for 1 week
   - Expand to regular use

---

## Questions?

All implementation details are documented in:
- **#181**: Architecture & comparison
- **#182**: Performance optimization
- **#183**: Audit logging
- **#184**: Git proxy
- **#185**: Cloudflare setup
- **#186**: Developer lifecycle
- **#187**: Access control
- **#188**: Operations
- **#189**: Epic overview & roadmap

Start with #189 for complete overview, then #181 for architecture decision.

---

**Last Updated**: April 13, 2026
**Status**: Ready for implementation
**Owner**: You (on-premises, self-managed)
