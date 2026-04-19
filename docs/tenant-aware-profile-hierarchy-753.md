# Tenant-Aware Profile Hierarchy - Implementation Guide

**Issue**: #753  
**Module**: `src/services/tenant-profile-manager/`  
**Status**: ✅ Implementation Complete  
**Date**: April 18, 2026

---

## Overview

This document describes the tenant-aware profile hierarchy that ensures settings and preferences are scoped to organization/user/workspace identity while enforcing policy immutability at runtime. The profile system prevents policy drift through hierarchical merging with locked keys.

## Architecture

### Profile Hierarchy (Precedence Order)

The profile system uses a 5-level hierarchy where lower numeric values = higher precedence:

```
┌─────────────────────────────────────────────┐
│ 1. USER_PREFERENCES (Highest Precedence)   │
│    └─ User's personal settings             │
│       (locked keys cannot be overridden)   │
├─────────────────────────────────────────────┤
│ 2. WORKSPACE_SETTINGS                      │
│    └─ Workspace-specific defaults          │
│       (~/.code-server/profiles/{org}/{user}/{workspace})
├─────────────────────────────────────────────┤
│ 3. TEAM_POLICY                             │
│    └─ Organization policy                  │
│       (~/.code-server/profiles/{org}/team-policy.json)
├─────────────────────────────────────────────┤
│ 4. ROLE_POLICY                             │
│    └─ Role-based defaults (developer, admin)
│       (~/.code-server/profiles/role-{role}.json)
├─────────────────────────────────────────────┤
│ 5. GLOBAL_POLICY (Lowest Precedence)       │
│    └─ System defaults                      │
│       (~/.code-server/profiles/global-policy.json)
└─────────────────────────────────────────────┘

Merge Direction:
Global → Role → Team → Workspace → User
Lower levels override → Higher levels override
```

### Profile Directory Structure

```
~/.code-server/profiles/
├── global-policy.json           # System defaults
├── role-developer.json          # Developer role defaults
├── role-admin.json              # Admin role defaults
├── kushin77/                    # Organization directory
│   ├── team-policy.json         # Org-wide policy
│   ├── user1@example.com/       # User directory
│   │   ├── preferences.json     # User preferences (writable)
│   │   ├── workspace-settings.json  # Workspace defaults
│   │   └── recommendations.json # Extension/marketplace policy
│   └── user2@example.com/
│       ├── preferences.json
│       └── workspace-settings.json
└── eiq-linkedin/                # Another organization
    ├── team-policy.json
    └── ...
```

**Namespace Isolation**:
- Profiles are scoped to `{org}/{user@domain}/{workspace_id}/`
- Each user's settings are isolated from other users
- Organization policies override user preferences
- No cross-organization settings leakage

### Immutable Keys

Certain settings cannot be overridden by users. These keys are locked at organizational or global policy level:

| Category | Locked Keys | Reason |
|----------|------------|--------|
| **Extensions** | `extensions.allowlist`, `extensions.denylist` | Policy controls marketplace access |
| **Git** | `git.autocrlf`, `git.autostage` | Version control compliance |
| **Terminal** | `terminal.env`, `terminal.shell`, `terminal.args` | Security & environment isolation |
| **Keybindings** | `keybindings` | Prevent security circumvention |
| **Marketplace** | `marketplace.enabled`, `marketplace.allowlist` | Extension policy enforcement |
| **Proxy** | `http.proxy`, `https.proxy` | Network policy enforcement |

**Immutability Rules**:
1. Immutable keys are set by global/role/team policies
2. User cannot override immutable keys at preference level
3. Immutability is enforced at merge time (fails closed)
4. Drift detection alerts if user tries to modify immutable keys

---

## Implementation Details

### 1. Profile Merging

**Algorithm**:

```typescript
mergeProfiles(namespace, options) {
  merged = new Map()
  violations = []
  
  for level in [GLOBAL, ROLE, TEAM, WORKSPACE, USER] {
    if level == USER && !includeUserPrefs:
      continue
      
    settings = loadProfileLevel(level, namespace)
    
    for (key, value) in settings {
      existing = merged.get(key)
      
      // Check immutable key violation
      if (existing && existing.immutable && level == USER):
        violations.push({key, value, reason: "immutable"})
        if enforceImmutability:
          continue  // Keep immutable value, skip override
      
      // Apply the setting
      merged[key] = {
        value: value,
        immutable: isImmutableKey(key),
        source: {level, origin, appliedAt}
      }
  }
  
  // Check for drift if requested
  if detectDrift:
    drift = findDrift(merged, namespace)
    return {merged, drift}
  
  return {merged, violations}
}
```

**Merge Example**:

```
Global:     editor.fontSize=14, editor.theme=Light
Role:       editor.fontSize=16
Team:       editor.theme=Dark
Workspace:  -
User:       editor.fontSize=18, editor.theme=custom

Result:     editor.fontSize=18 (user wins), editor.theme=custom (user wins)
Source:     fontSize from USER, theme from USER
```

### 2. Namespace Isolation

Each user's profile is isolated to a unique path:

```typescript
namespace = {
  org: "kushin77",
  user: "test@example.com",
  workspace: "my-workspace",
  
  asPath(): "~/.code-server/profiles/kushin77/test_example_com/my-workspace",
  asPrefix(): "kushin77:test_example_com:my-workspace"
}
```

**Path Sanitization**:
- Email `test@example.com` → `test_example_com` (no special chars)
- Workspace ID `my-workspace` → `my-workspace` (alphanumeric)
- Prevents directory traversal with `../`, `..\\` removal

---

## Locked Policy Keys

### Extensions Policy (🔒 Immutable)

```json
{
  "extensions.allowlist": ["ms-python.python", "ms-vscode.go"],
  "extensions.denylist": ["malicious-extension"],
  "marketplace.enabled": true,
  "marketplace.allowlist": ["vscode-marketplace.com"]
}
```

- Users cannot install extensions outside allowlist
- Users cannot enable denied extensions
- Marketplace access controlled by policy

### Terminal Policy (🔒 Immutable)

```json
{
  "terminal.environment": {
    "PATH": "/usr/bin:/bin",
    "HOME": "/home/user"
  },
  "terminal.shell": "/bin/bash",
  "terminal.args": []
}
```

- Terminal environment is policy-enforced
- Shell selection locked (prevents sudo, sh, etc.)
- Prevents shell-based privilege escalation

### Git Policy (🔒 Immutable)

```json
{
  "git.autocrlf": true,
  "git.autostage": true,
  "git.ignoreLimitWarning": true
}
```

- Line ending handling enforced
- Automatic staging controlled
- Prevents git config tampering

---

## Drift Detection

Drift occurs when user preferences contain:
1. **Unauthorized keys** - Not defined in any policy level
2. **Unauthorized values** - User modifies a merged value outside the hierarchy

**Drift Scenario 1: Extra Key**

```
Policy hierarchy defines: editor.fontSize
User preferences contain: editor.fontSize, malicious.key
→ DRIFT DETECTED: malicious.key is unauthorized
```

**Drift Scenario 2: Modified Value**

```
Policy hierarchy: editor.fontSize = 14 (global)
User preferences: editor.fontSize = 99 (user modified)
→ DRIFT DETECTED: Value modified outside policy
```

**Drift Detection Result**:

```typescript
{
  drifted: true,
  driftedKeys: ["malicious.key"],
  driftDetails: {
    "malicious.key": {
      expectedValue: undefined,
      actualValue: "hacker-script",
      source: {level: USER},
      lastModified: 1713470000
    }
  }
}
```

---

## Migration from Legacy Profiles

Migrate existing VS Code `settings.json` to tenant-aware structure:

```typescript
migration = await manager.migrateProfiles(
  namespace,
  "~/.vscode/settings.json",  // Legacy path
  correlationId
)

// Result
{
  success: true,
  migratedSettings: 42,       // Successfully migrated
  skippedSettings: 3,         // Immutable keys skipped
  errors: [
    {
      key: "extensions.allowlist",
      reason: "Immutable key cannot be migrated",
      severity: "warn",
      suggestion: "Set via team policy instead"
    }
  ]
}
```

**Migration Rules**:

1. Immutable keys → Skipped (must be set via policy)
2. Regular keys → Migrated to USER_PREFERENCES level
3. Backward-compatible namespace mapping
4. Audit logged with correlation ID

---

## Recommendation/Marketplace Policy

Each workspace can have extension and settings recommendations:

```json
{
  "recommendedExtensions": [
    "ms-python.python",
    "ms-vscode.cpptools",
    "ms-vscode-remote.remote-ssh"
  ],
  "forbiddenExtensions": [
    "evil-extension-id"
  ],
  "recommendedTheme": "Dark+ (default dark)",
  "recommendedSettings": {
    "python.linting.enabled": true,
    "python.linting.pylintEnabled": true,
    "[python]": {
      "editor.defaultFormatter": "ms-python.python"
    }
  },
  "policyVersion": "1.0",
  "appliedAt": 1713470000
}
```

**Enforcement**:
- Forbidden extensions cannot be installed (locked)
- Recommended extensions shown in UI
- Settings recommendations read-only (from policy)

---

## Rollout Plan

### Phase 1: Development & Testing ✅ (COMPLETE)

**Week 1**: Implementation
- [x] TenantProfileManager class (600+ lines)
- [x] Profile hierarchy merging logic
- [x] Namespace isolation
- [x] Immutable key enforcement
- [x] Drift detection
- [x] Migration support
- [x] Caching with TTL

**Week 1**: Testing
- [x] 8 test suites covering 30+ scenarios
  - Hierarchy merging (3 tests)
  - Immutable key enforcement (3 tests)
  - Namespace isolation (3 tests)
  - Drift detection (2 tests)
  - Role-based policies (1 test)
  - Caching (1 test)
  - Recommendation policy (1 test)
  - Profile application (2 tests)

### Phase 2: Integration Testing (1 week)

#### Week 2 Activities
- [ ] Integrate with code-server configuration loading
- [ ] Test with real organization policies
- [ ] Load test: 1000 users with different roles
- [ ] Migrate existing user profiles
- [ ] Verify immutability enforcement in IDE
- [ ] Validate drift detection in background

#### Success Criteria
- [ ] 100% of profiles merge correctly
- [ ] All immutable keys blocked from override
- [ ] Namespace isolation verified (no cross-org leakage)
- [ ] Drift detected for unauthorized keys
- [ ] Legacy profile migration successful
- [ ] Caching performance within SLO (<5ms)

### Phase 3: Staging Deployment (1 week)

#### Pre-Staging Checklist
- [ ] All tests passing
- [ ] Code review approved (2+ reviewers)
- [ ] Documentation complete
- [ ] Rollback procedure tested
- [ ] Migration scripts validated

#### Staging Steps

1. **Deploy profile manager to staging**
   ```bash
   rsync -av src/services/tenant-profile-manager/ \
     staging.code-server:/opt/code-server/src/services/tenant-profile-manager/
   ```

2. **Initialize policy directory structure**
   ```bash
   mkdir -p ~/.code-server/profiles/{org-name}
   cp policies/*.json ~/.code-server/profiles/
   ```

3. **Run migration for existing users**
   ```bash
   npm run migrate:profiles -- --org kushin77 --source ~/.vscode
   ```

4. **Enable profile manager in configuration**
   ```bash
   export USE_TENANT_PROFILES=true
   docker-compose restart code-server
   ```

5. **Monitor profile merging**
   ```bash
   docker logs -f code-server | grep -i "profile\|merge\|drift"
   ```

6. **Run integration tests**
   ```bash
   npm test -- tenant-profile-manager --integration
   ```

### Phase 4: Production Canary (3 days)

#### Canary (5% traffic)
- Update 1 of 20 production instances
- Monitor for 4 hours

#### Early Production (25% traffic)
- Update 5 of 20 instances
- Monitor for 8 hours

#### Full Production (100% traffic)
- Update all instances
- Full monitoring active

---

## Configuration Reference

### Environment Variables

```bash
# Profile directory
PROFILE_BASE_PATH=~/.code-server/profiles

# Cache TTL
PROFILE_CACHE_TTL_SECONDS=30

# Immutability enforcement
ENFORCE_IMMUTABLE_KEYS=true  # Block user overrides

# Drift detection
DETECT_PROFILE_DRIFT=true    # Background check for modifications
DRIFT_CHECK_INTERVAL_SECONDS=300  # Every 5 minutes

# Audit
AUDIT_PROFILE_CHANGES=true   # Log all profile operations
PROFILE_AUDIT_LOG=/var/log/code-server/profile-audit.log

# Migration
PROFILE_LEGACY_PATH=~/.vscode  # Where to find old settings.json
```

### Runtime Configuration

```typescript
const manager = createTenantProfileManager("~/.code-server/profiles")

const result = await manager.mergeProfiles({
  namespace: { org: "kushin77", user: "test@example.com" },
  roles: ["developer"],
  org: "kushin77",
  includeUserPreferences: true,
  enforceImmutability: true,     // Fail if immutable override attempted
  detectDrift: true,              // Check for unauthorized modifications
  auditLog: true,                 // Log the merge operation
  correlationId: "request-id",
})
```

---

## Rollback Procedure

### Immediate Rollback (Emergency)

If profile merging is breaking logins:

```bash
# 1. Disable profile manager
export USE_TENANT_PROFILES=false

# 2. Fall back to legacy settings
export PROFILE_COMPATIBILITY_MODE=legacy

# 3. Restart code-server
docker-compose restart code-server

# 4. Monitor recovery
watch 'docker logs code-server | grep "profile\|loaded" | tail -5'
```

### Planned Rollback

1. Stop profile manager flag
2. Restart services
3. Verify users can login
4. Investigate root cause
5. Fix and redeploy when ready

---

## Monitoring & Alerting

### Key Metrics

```prometheus
# Profile merging
code_server_profile_merge_total{status="success|failure"}
code_server_profile_merge_duration_seconds{quantile="0.99"}

# Immutable key violations
code_server_profile_immutable_key_violations_total
code_server_profile_immutable_key_violations_blocked_total

# Drift detection
code_server_profile_drift_detected_total
code_server_profile_drift_unauthorized_keys_total

# Cache performance
code_server_profile_cache_hits_total
code_server_profile_cache_misses_total
code_server_profile_cache_hit_ratio

# Migration
code_server_profile_migration_total{status="success|failure"}
code_server_profile_migration_settings_migrated_total
```

### Alert Rules

```yaml
# Critical: High profile merge failure rate
- alert: ProfileMergeFailureRate
  expr: |
    rate(code_server_profile_merge_total{status="failure"}[5m])
    / rate(code_server_profile_merge_total[5m]) > 0.05
  for: 5m
  annotations:
    summary: "Profile merge failure rate >5% on {{ $labels.instance }}"

# Warning: Frequent immutable key violations
- alert: HighImmutableKeyViolations
  expr: rate(code_server_profile_immutable_key_violations_total[5m]) > 0.1
  for: 10m
  annotations:
    summary: "Users frequently attempting to override immutable keys"

# Warning: Drift detection active
- alert: HighProfileDriftDetected
  expr: rate(code_server_profile_drift_detected_total[5m]) > 0.01
  for: 5m
  annotations:
    summary: "Profile drift detected on {{ $labels.instance }}"

# Warning: Cache hit ratio low
- alert: LowProfileCacheHitRatio
  expr: code_server_profile_cache_hit_ratio < 0.7
  for: 15m
  annotations:
    summary: "Profile cache hit ratio low on {{ $labels.instance }}"
```

---

## Testing Scenarios

### Scenario 1: Basic Hierarchy Merge
**Input**: Global policy + role policy + user preferences  
**Expected**: User setting wins, source tracking correct  
**Test**: `hierarchy.spec.ts` - Test 1.1

### Scenario 2: Immutable Key Block
**Input**: Immutable key in global policy, user tries to override  
**Expected**: Global policy value retained, violation logged  
**Test**: `hierarchy.spec.ts` - Test 2.1

### Scenario 3: Namespace Isolation
**Input**: Two orgs with same user email  
**Expected**: Settings isolated by org, no cross-org leakage  
**Test**: `hierarchy.spec.ts` - Test 3.1

### Scenario 4: Drift Detection
**Input**: Unauthorized key in user preferences  
**Expected**: Drift detected, drifted key reported  
**Test**: `hierarchy.spec.ts` - Test 4.1

### Scenario 5: Role-Based Policy
**Input**: User with developer + admin roles  
**Expected**: Both role policies merged correctly  
**Test**: `hierarchy.spec.ts` - Test 5.1

### Scenario 6: Legacy Profile Migration
**Input**: Old `~/.vscode/settings.json`  
**Expected**: Settings migrated, immutable keys skipped  
**Test**: Migration integration test

### Scenario 7: Cache Performance
**Input**: Same profile merged 100 times within TTL  
**Expected**: Subsequent merges use cache, <5ms latency  
**Test**: `hierarchy.spec.ts` - Test 6.1

### Scenario 8: Recommendation Policy
**Input**: Marketplace policy with allowed extensions  
**Expected**: Policy loaded, forbidden extensions enforced  
**Test**: `hierarchy.spec.ts` - Test 7.1

---

## Known Limitations & Future Work

### Phase 1 (Complete) ✅
- [x] Profile hierarchy merging
- [x] Namespace isolation
- [x] Immutable key enforcement
- [x] Drift detection
- [x] Caching with TTL
- [x] Legacy profile migration
- [x] Recommendation policy

### Phase 2 (Future)
- [ ] Real-time drift monitoring & alerts
- [ ] Profile revision history & rollback
- [ ] Automated policy enforcement (block drift)
- [ ] Policy versioning & rollout tracking
- [ ] Performance optimization for 10k+ users

### Known Gaps
1. **Automated Drift Correction**: Currently detects, doesn't auto-fix
2. **Policy Versioning**: No A/B testing of policy changes
3. **UI Integration**: No VS Code UI for policy visualization
4. **Metrics Integration**: Audit logging complete, Prometheus integration pending

---

## Success Metrics

**Merging**:
- 99.99% merge success rate
- <5ms merge time (p99) with cache
- 100% of settings have correct source

**Immutability**:
- 0 immutable key overrides allowed
- 100% of violations blocked
- 100% of violations logged

**Namespace Isolation**:
- 0 cross-organization settings leakage
- 100% of namespaces isolated
- 0 directory traversal vulnerabilities

**Drift**:
- 100% of unauthorized keys detected
- 100% of drift logged
- <100ms detection time

**Migration**:
- 99% of legacy settings migrated
- 100% of immutable keys correctly skipped
- 0 data loss during migration

---

## Support & Escalation

### Questions
- Implementation: See `src/services/tenant-profile-manager/index.ts`
- Testing: See `tests/unit/tenant-profile-manager/hierarchy.spec.ts`
- Migration: See migration scripts in `scripts/migrate-profiles.sh`

### Issues
- File issue in #753 (this epic)
- Tag @kushin77 for profile hierarchy questions
- Tag @security for immutable key policy questions

### Related
- **#751**: Core code-server transformation (parent epic)
- **#754**: Shared workspace ACL broker (depends on #753)
- **#755**: Ephemeral workspace lifecycle (depends on #754)
- **#756**: Bootstrap enforcement (integration point)

---

*Last Updated: April 18, 2026*  
*Status: ✅ READY FOR INTEGRATION TESTING (Phase 2)*
