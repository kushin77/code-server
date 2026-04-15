# P2: Database Optimization & Access Control - Implementation Guide

**Status**: 🏗️ IN PROGRESS  
**Phase**: P2 (Tier 2 Good Projects)  
**Timeline**: 17+ hours over 5-7 days  
**Priority**: P1/HIGH  

---

## Overview

P2 builds on the P1 performance baseline (14 hours) with:
- **Database Connection Pooling** - pgBouncer integration for 3-5x throughput
- **Git Proxy Implementation** (#184) - Access control + audit logging
- **Read-Only IDE Security** (#187) - 4-layer filesystem + terminal restrictions
- **Query Optimization** - Index creation + slow query analysis
- **Monitoring & Dashboards** - Real-time performance tracking

---

## Issues Covered

| Issue | Title | Est. | Status | Owner |
|-------|-------|------|--------|-------|
| #184 | Git Proxy (access + logging) | 4h | 🏗️ IN PROGRESS | Backend |
| #187 | Read-Only IDE (4-layer security) | 4h | 🏗️ IN PROGRESS | Security |
| #219 | P0-P3 Operations Stack | 5h | ⏳ QUEUED | Operations |
| - | Database Optimization | 4h | 🏗️ IN PROGRESS | Backend |

---

## Deliverables

### ✅ Completed

- [x] Git Proxy script (`scripts/git-proxy`)
- [x] Read-Only IDE initialization (`scripts/readonly-ide-init`)
- [x] Database optimization script (`scripts/database-optimize`)
- [x] 4-layer security model documentation

### 🏗️ In Progress

- [ ] Integration tests (git proxy + IDE access)
- [ ] Load testing (database pool impact)
- [ ] Monitoring dashboards (Prometheus + Grafana)
- [ ] Production deployment guide

### ⏳ Next (P3)

- [ ] Kubernetes infrastructure setup
- [ ] Multi-region replication
- [ ] Advanced caching layer

---

## Implementation Details

### 1. Git Proxy (#184) - 4 Hours

**Purpose**: Intercept and control git operations with audit logging

**Files**:
- `scripts/git-proxy` - Main proxy script

**Features**:
```bash
# Developer access check
$ git-proxy push git@github.com:org/repo.git
→ Validates developer status
→ Checks domain whitelist
→ Enforces rate limits
→ Logs to audit database

# Read-only operations allowed with less strict limits
$ git-proxy pull git@github.com:org/repo.git
→ Less strict rate limiting than push
```

**Database Integration**:
```
~/.code-server-developers/
├── developers.csv          # Developer access status
├── git-proxy-audit.csv     # All git operations logged
└── git-proxy.log           # Detailed audit log
```

**Rate Limiting**:
- **Push**: 10 per 60 seconds (strict - code modification)
- **Pull**: 30 per 60 seconds (lenient - read-only)

**Audit Fields**:
- timestamp, user, operation (push/pull/clone), repo, domain, status, reason

**Testing**:
```bash
# Test git proxy
git-proxy push git@github.com:kushin77/code-server.git
git-proxy pull git@github.com:kushin77/code-server.git
git-proxy clone https://github.com/kushin77/code-server.git

# Check audit log
tail -20 ~/.code-server-developers/git-proxy-audit.csv
```

---

### 2. Read-Only IDE (#187) - 4 Hours

**Purpose**: Enforce read-only access through 4 security layers

**Files**:
- `scripts/readonly-ide-init` - Initialization script
- `~/.code-server-readonly/` - Configuration directory

**4-Layer Security Model**:

#### Layer 1: Filesystem Permissions
```bash
# Workspace is mounted read-only (r-x permissions = 555)
/home/dev/code-server-workspace
├── .readonly (r-x)           # Read-only mount
├── .overlay/ (rwx)           # Session-specific temp layer
└── session-{uuid}/ (rwx)     # Per-session writable area
```

- **Read-only base**: No modifications possible
- **Overlay temp layer**: Safe temporary file area per session
- **Auto-cleanup**: Session temp dirs cleaned after disconnect

#### Layer 2: Terminal Command Restrictions
```bash
# Whitelist: 50+ allowed read-only commands
✓ cat, less, grep, awk, sed, find, locate
✓ git (pull/status/log, NOT push/commit)
✓ man, help, less, view

# Blacklist: 30+ forbidden commands
✗ rm, chmod, chown, usermod
✗ wget, curl, ftp (no external downloads)
✗ gcc, make (no compilation)
✗ bash (no script execution, only git/utils)
```

#### Layer 3: IDE Configuration
```json
{
  "editor.readOnlyIncludePattern": ["**"],
  "files.autoSave": "off",
  "editor.formatOnSave": false,
  "terminal.integrated.allowChords": false
}
```

- Editor configured for read-only mode
- No auto-save or format triggers
- Terminal restricted to safe commands

#### Layer 4: Audit & Monitoring
```csv
timestamp,session_id,user,command,status,reason
2026-04-15 10:30:45,sess-abc123,john.doe,cat README.md,allowed,
2026-04-15 10:31:02,sess-abc123,john.doe,rm test.txt,denied,Command in blacklist
```

- Every command logged with timestamp
- Monitoring metrics: commands/min, blocked commands, write attempts
- Alerts on suspicious patterns

**Testing**:
```bash
# Run initialization
scripts/readonly-ide-init

# Verify filesystem is read-only
cat /home/dev/code-server-workspace/test.txt    # OK
echo "test" > /home/dev/code-server-workspace/test.txt  # FAIL (Permission denied)

# Test allowed commands
ls -la /home/dev/code-server-workspace         # OK
git status /home/dev/code-server-workspace     # OK
cat /home/dev/code-server-workspace/code.py    # OK

# Test forbidden commands
rm /home/dev/code-server-workspace/test.txt    # BLOCKED
chmod 755 /home/dev/code-server-workspace     # BLOCKED
wget https://example.com/file.zip               # BLOCKED
```

---

### 3. Database Optimization - 4 Hours

**Purpose**: Improve query performance through connection pooling and indexing

**Files**:
- `scripts/database-optimize` - Optimization script
- `~/.code-server-db/` - Database configuration

**Phase 1: Connection Pooling (pgBouncer)**
```bash
# Transaction mode for web apps
pool_mode = transaction
max_client_conn = 200
default_pool_size = 20
reserve_pool_size = 3

# Expected improvement: 3-5x throughput
# Latency reduction: 10-20% (connection setup eliminated)
```

**Phase 2: Index Optimization**
```sql
-- 15+ essential indexes created:
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_audit_log_timestamp ON audit_log(timestamp DESC);
CREATE INDEX idx_audit_log_user_id ON audit_log(user_id, timestamp DESC);
CREATE INDEX idx_developers_expiry ON developers(expiry_date);
-- ... (see database-optimize script for full list)
```

Expected improvements:
- Sequential scan elimination: -90% full table scans
- Query latency: -50% improvement
- Index space: <50MB total

**Phase 3: Query Analysis**
```bash
# Run slow query analysis
scripts/database-optimize analyze

# Output includes:
# - Sequential scans (N+1 query indicators)
# - Unused indexes
# - Table bloat analysis
# - Cache hit ratio (target: >99%)
# - Long-running queries
```

**Phase 4: Configuration Tuning**
```bash
shared_buffers = 256MB          # 25% of RAM
effective_cache_size = 1GB      # 80% of RAM
work_mem = 4MB per operation
maintenance_work_mem = 64MB
effective_io_concurrency = 200  # SSD optimization
```

**Performance Targets**:
- P50 latency: <5ms per query
- P99 latency: <20ms per query
- Throughput: >1000 req/s
- Cache hit ratio: >98%

**Testing**:
```bash
# Run full optimization
scripts/database-optimize all

# Test connection pool
psql -h localhost -p 6432 -d code_server_db

# Verify indexes
SELECT * FROM pg_indexes WHERE schemaname = 'public';

# Check query performance (before/after)
EXPLAIN ANALYZE SELECT * FROM users WHERE email = 'test@example.com';
```

---

## Integration Points

### Git Proxy → Developer Lifecycle
```
developer-grant email 7 days
↓
~/.code-server-developers/developers.csv
↓
git-proxy checks status before push/pull
↓
Denies access if expired or revoked
```

### Read-Only IDE → Access Control
```
developer-grant (enables read-only access)
↓
scripts/readonly-ide-init (4-layer security)
↓
code-server mounts workspace read-only
↓
Terminal + editor enforce restrictions
```

### Database → Performance
```
pgBouncer (connection pooling)
↓ 3-5x throughput improvement
↓
Indexes (query optimization)
↓ 50% latency reduction
↓
Configuration (resource tuning)
↓ 99% cache hit ratio
```

---

## Production Deployment Checklist

### Pre-Deployment
- [ ] All tests passing (unit + integration)
- [ ] Load testing completed (baseline established)
- [ ] Monitoring dashboards configured
- [ ] Rollback procedures documented
- [ ] Security scan passing

### Deployment (Blue/Green)
1. **Blue Environment** (current production)
   - Continue serving 100% traffic
   - Monitor baseline metrics

2. **Green Environment** (new build)
   - Deploy all P2 changes
   - Run smoke tests
   - Verify all services healthy

3. **Traffic Shift** (5 stages)
   - Stage 1: Route 1% traffic to green
   - Stage 2: Route 10% traffic to green
   - Stage 3: Route 50% traffic to green
   - Stage 4: Route 90% traffic to green
   - Stage 5: Route 100% traffic to green

4. **Monitoring** (1 hour post-deploy)
   - Watch error rate (target: <0.1%)
   - Watch latency (target: no regression)
   - Watch resource utilization
   - Check logs for issues

### Rollback (if needed)
```bash
# 60-second rollback to previous version
git revert <commit_sha>
git push origin main
# CI/CD automatically deploys reverting commit
```

---

## Success Criteria

| Metric | Target | Status |
|--------|--------|--------|
| Git proxy: Audit logging | 100% of operations logged | ⏳ |
| Git proxy: Rate limiting | <1% false positives | ⏳ |
| Read-only IDE: Filesystem protection | 0% write violations | ⏳ |
| Read-only IDE: Terminal restrictions | 100% policy enforcement | ⏳ |
| Database pool: Throughput improvement | >3x (baseline to p50) | ⏳ |
| Database queries: Latency reduction | -50% improvement | ⏳ |
| Database indexes: Query performance | Full table scans -90% | ⏳ |

---

## Timeline

### Week 1 (This Week)
- [x] Git proxy script (4h)
- [x] Read-only IDE initialization (4h)
- [x] Database optimization script (4h)
- [ ] Integration testing (3h)
- [ ] Load test setup (2h)

### Week 2
- [ ] Monitoring dashboard implementation (3h)
- [ ] Production deployment guide (2h)
- [ ] Security hardening review (3h)
- [ ] Performance validation (4h)
- [ ] Team training (2h)

### Week 3
- [ ] Issue #219 - P0-P3 Operations Stack (5h)
- [ ] P3 planning - Kubernetes setup (8h)
- [ ] Documentation updates (4h)

---

## Files Modified

```
scripts/
├── git-proxy                      # NEW: Git access proxy
├── readonly-ide-init              # NEW: Read-only IDE initialization
├── database-optimize              # NEW: Database optimization
└── _common/config.sh              # UPDATED: Added P2 variables

~/.code-server-developers/         # NEW: Developer database
├── developers.csv                 # Developer access status
├── git-proxy-audit.csv            # Git operations audit
└── terminal-audit.csv             # Terminal commands audit

~/.code-server-readonly/           # NEW: Read-only configuration
├── terminal-whitelist.txt         # Allowed commands
├── terminal-blacklist.txt         # Forbidden commands
├── code-server-settings.json      # IDE configuration
├── monitoring-config.yaml         # Monitoring setup
└── terminal-wrapper.sh            # Command interceptor

~/.code-server-db/                 # NEW: Database configuration
├── optimization-report.txt        # Optimization results
├── indexes-pending.sql            # Pending indexes
└── pgbouncer.ini                  # Connection pool config
```

---

## Next Steps

1. **Code Review**
   - All P2 scripts must pass security review
   - Load testing must validate performance improvements
   - Integration tests must verify cross-component interaction

2. **Deployment**
   - Merge to main branch (with all tests passing)
   - Deploy to staging (48-hour validation)
   - Deploy to production (blue/green, 1-hour monitoring)

3. **P3 Preparation**
   - Review Kubernetes architecture (#191, #192, #193)
   - Prepare containerization strategy
   - Plan multi-region setup

---

## References

- **Issue #184**: [Git Proxy](https://github.com/kushin77/code-server/issues/184)
- **Issue #187**: [Read-Only IDE](https://github.com/kushin77/code-server/issues/187)
- **Issue #219**: [P0-P3 Operations](https://github.com/kushin77/code-server/issues/219)
- **REMOTE_ACCESS_IMPLEMENTATION_GUIDE.md**: Full architecture details
- **P1-P5-ACTIVATION-ROADMAP.md**: Overall execution strategy

---

**Last Updated**: April 15, 2026  
**Status**: P2 Implementation In Progress  
**Next Review**: When all scripts tested and ready for integration testing
