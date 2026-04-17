# Enterprise VS Code Policy Pack - Phase 2 Implementation Plan

**Status**: Design & Specification (Awaiting Phase 1 PR Merge)  
**Target Issue**: #618  
**Timeline**: 2-3 weeks post Phase 1 merge  
**Owner**: @kushin77

---

## Executive Summary

Phase 1 established the tiered policy framework, canonical settings, extensions registry, and keybindings. Phase 2 integrates policy enforcement into the code-server entrypoint, validates policy compliance in CI, and implements policy merging logic for Tier 2/3 overrides.

**Phase 2 Scope**:
- ✅ Integrate policy enforcement into code-server startup
- ✅ Implement settings merge (Tier 1 immutable + Tier 2 user override)
- ✅ Extension auto-install validation
- ✅ CI policy compliance checks
- ✅ Policy version tracking and auditing

---

## Detailed Phase 2 Deliverables

### 1. Code-Server Entrypoint Integration

#### 1.1 Policy Enforcement Hook

**File**: `scripts/code-server-entrypoint.sh` (new function)

**Purpose**: Apply policy settings at code-server startup

**Execution Flow**:
```bash
# Load policy framework
source scripts/_common/policy-loader.sh
source config/code-server/ENTERPRISE-POLICY-PACK.sh

# Phase 1: Load Tier 1 (immutable)
apply_tier1_settings

# Phase 2: Merge Tier 2 (defaults with user override)
merge_tier2_settings

# Phase 3: Apply Tier 3 (recommendations)
apply_tier3_recommendations

# Phase 4: Validate extensions
validate_extension_manifest

# Phase 5: Install extensions (if needed)
auto_install_extensions

# Phase 6: Audit & log
log_policy_application
```

#### 1.2 Settings Merge Logic

**Tier 1 (Immutable)**:
```bash
# Write directly to user settings.json
# Skip user value if present
# Re-apply at every startup

declare -A TIER1_SETTINGS=(
  ["telemetry.enableTelemetry"]="false"
  ["security.workspace.trust.enabled"]="true"
  ["github.copilot.enable"]="true"
)

for key in "${!TIER1_SETTINGS[@]}"; do
  jq ".\"$key\" = ${TIER1_SETTINGS[$key]}" "$USER_SETTINGS" > "$USER_SETTINGS.tmp"
  mv "$USER_SETTINGS.tmp" "$USER_SETTINGS"
done
```

**Tier 2 (Default + Override)**:
```bash
# Check if user already set value
if jq -e ".\"$key\"" "$USER_SETTINGS" > /dev/null 2>&1; then
  # User override exists - use it (don't override)
  USER_VALUE=$(jq -r ".\"$key\"" "$USER_SETTINGS")
  log_info "Tier 2 override detected: $key = $USER_VALUE (user value preserved)"
else
  # No user value - apply default
  jq ".\"$key\" = ${TIER2_DEFAULT[$key]}" "$USER_SETTINGS" > "$USER_SETTINGS.tmp"
  mv "$USER_SETTINGS.tmp" "$USER_SETTINGS"
  log_info "Tier 2 default applied: $key = ${TIER2_DEFAULT[$key]}"
fi
```

**Tier 3 (Recommendations)**:
```bash
# Only suggest, never enforce
log_warn "RECOMMENDATION: $key = ${TIER3_RECOMMENDATION[$key]} (not enforced)"
```

#### 1.3 Audit Logging

**Log Entry Format**:
```bash
log_info "POLICY_APPLICATION | timestamp | user | $action | $key | $old_value → $new_value | tier"
```

**Log Storage**: 
- Stdout: `code-server` container logs
- File: `~/.code-server/logs/policy-audit.log`
- Retention: 7 days (rotated)

### 2. Extension Auto-Install & Validation

#### 2.1 Extension Manifest Processing

**File**: `config/code-server/extensions-manifest.json` (new)

**Structure**:
```json
{
  "tier": 1,
  "extensions": [
    {
      "id": "ms-python.python",
      "name": "Python",
      "tier": 1,
      "required": true,
      "version": "stable",
      "config": {
        "python.linting.enabled": true,
        "python.linting.pylintEnabled": true
      }
    },
    {
      "id": "eamodio.gitlens",
      "name": "GitLens",
      "tier": 2,
      "required": false,
      "version": "latest",
      "conflicts": ["ms-vscode.vscode-github"]
    }
  ]
}
```

#### 2.2 Auto-Install Script

**File**: `scripts/code-server-auto-install-extensions.sh`

**Process**:
```bash
1. Parse extensions-manifest.json
2. For each Tier 1 extension:
   - Check if installed: code-server --list-extensions | grep ID
   - If missing: code-server --install-extension ID@version
   - If wrong version: code-server --uninstall-extension ID && re-install
3. For each Tier 2 extension:
   - Optional: suggest via log message
4. Validate no conflicts (e.g., GitHub vs GitLens conflicts)
5. Log results: success/skip/error per extension
```

**Output Example**:
```
TIER 1 EXTENSIONS:
  ✅ ms-python.python@2024.4.1 (installed, correct version)
  ✅ ms-vscode.cpptools@1.18.5 (installed, correct version)
  ⬇️  ms-vscode.makefile-tools@0.6.0 (missing, installing...)
  ✅ ms-vscode.makefile-tools@0.6.0 (installed successfully)

TIER 2 EXTENSIONS (optional):
  💡 eamodio.gitlens@14.6.0 (recommended, not installed)

CONFLICTS: None detected ✅
```

### 3. CI Policy Compliance Checks

#### 3.1 CI Workflow

**File**: `.github/workflows/ci-vscode-policy-validation.yml`

**Jobs**:
1. **validate-policy-structure** - JSON schema validation
2. **validate-extensions-exist** - Verify extensions are real (query VS Code Marketplace)
3. **validate-no-conflicts** - Check for incompatible combinations
4. **validate-settings-applied** - Dry-run settings merge on test environment
5. **policy-coverage-report** - Compare coverage with previous month

#### 3.2 Policy Schema Validation

**Schema**: `config/code-server/policy-schema.json`

**Validates**:
```json
{
  "type": "object",
  "properties": {
    "tier": { "type": "number", "enum": [1, 2, 3] },
    "settings": {
      "type": "object",
      "additionalProperties": {
        "anyOf": [
          { "type": "string" },
          { "type": "number" },
          { "type": "boolean" }
        ]
      }
    },
    "extensions": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["id", "tier"],
        "properties": {
          "id": { "type": "string", "pattern": "^[^.]+\\.[^.]+$" },
          "tier": { "type": "number", "enum": [1, 2, 3] }
        }
      }
    }
  }
}
```

### 4. Policy Version Tracking & Auditing

#### 4.1 Policy Version File

**File**: `config/code-server/.policy-version`

**Content**:
```
POLICY_VERSION=1.0.0
POLICY_HASH=a1b2c3d4e5f6... (SHA256 of policy JSON)
LAST_UPDATED=2026-04-20T10:30:00Z
UPDATED_BY=@kushin77
CHANGE_LOG=Added Python tier 1, made debugger optional
```

#### 4.2 Audit Trail

**File**: `~/.code-server/logs/policy-changes.log`

**Entry Format**:
```
[2026-04-20T10:30:00Z] POLICY_UPDATED | version 1.0.0 | changes: +python.required, -terminal.required | applied_by: entrypoint | affected_settings: 3 | affected_extensions: 1
```

#### 4.3 Policy Compliance Report

**Generated**: Monthly (by `scripts/governance-reports/policy-compliance-report.sh`)

**Contents**:
- Policies applied (success rate)
- Conflicts resolved
- Extension installation success rate
- User overrides (Tier 2) frequency
- Deviation documentation (if any)

### 5. Conflict Detection & Resolution

#### 5.1 Conflict Definition

**Conflict Types**:
1. **Extension Incompatibility**: Two extensions can't coexist (e.g., GitHub vs GitLens)
2. **Setting Incompatibility**: Two settings conflict (e.g., two formatters)
3. **Version Incompatibility**: Extension version incompatible with VS Code version

#### 5.2 Conflict Detection

**File**: `scripts/validate-policy-conflicts.sh`

**Logic**:
```bash
# Load conflict matrix from policy
CONFLICTS=(
  "ms-vscode.vscode-github:eamodio.gitlens:GitHub extension conflicts with GitLens"
  "esbenp.prettier-vscode:ms-python.python:Prettier conflicts with Python formatter"
)

# Check for conflicts in user's installed extensions
for conflict in "${CONFLICTS[@]}"; do
  ext1=$(echo "$conflict" | cut -d: -f1)
  ext2=$(echo "$conflict" | cut -d: -f2)
  reason=$(echo "$conflict" | cut -d: -f3)
  
  if [[ $(check_installed "$ext1") && $(check_installed "$ext2") ]]; then
    log_error "CONFLICT DETECTED: $reason. Removing: $ext2"
    code-server --uninstall-extension "$ext2"
  fi
done
```

---

## Implementation Sequence

### Week 1: Entrypoint Integration & Settings Merge
- [ ] Create policy loader functions
- [ ] Implement Tier 1/2/3 merge logic
- [ ] Add audit logging
- [ ] Test on 5 sample environments

### Week 2: Extension Management
- [ ] Create extensions manifest and schema
- [ ] Create auto-install script
- [ ] Implement conflict detection
- [ ] Test extension installation and conflicts

### Week 3: CI Validation & Auditing
- [ ] Create CI policy validation workflow
- [ ] Create version tracking system
- [ ] Create audit trail logging
- [ ] First compliance report generation

### Week 4: Integration & Hardening
- [ ] Full end-to-end test (fresh code-server → policy applied)
- [ ] Performance testing (startup time impact)
- [ ] Documentation updates
- [ ] Team training & rollout

---

## Technical Details

### Settings Merge Algorithm

```bash
function merge_policy_settings() {
  local tier=$1
  local settings_file=$2
  
  # Read policy settings for tier
  local policy_settings=$(jq ".tiers[$tier].settings" "$POLICY_FILE")
  
  # For each setting in policy
  while IFS='=' read -r key value; do
    if [[ -z "$key" ]]; then continue; fi
    
    # Check user override (Tier 2 only)
    if [[ $tier -eq 2 ]]; then
      if has_user_override "$settings_file" "$key"; then
        log_info "Tier 2 override: $key (user value preserved)"
        continue
      fi
    fi
    
    # Apply setting
    apply_setting "$settings_file" "$key" "$value"
  done < <(echo "$policy_settings" | jq -r 'to_entries[] | "\(.key)=\(.value)"')
}
```

### Extension Installation Logic

```bash
function install_required_extensions() {
  local manifest=$1
  
  # Parse manifest and get Tier 1 extensions
  local extensions=$(jq -r '.extensions[] | select(.tier == 1) | .id' "$manifest")
  
  for ext_id in $extensions; do
    local version=$(jq -r ".extensions[] | select(.id == \"$ext_id\") | .version" "$manifest")
    
    # Check if already installed
    if code-server --list-extensions | grep -q "^${ext_id}@"; then
      log_info "Extension already installed: $ext_id"
      continue
    fi
    
    # Install extension
    log_info "Installing extension: $ext_id@$version"
    code-server --install-extension "$ext_id@$version"
    
    if [[ $? -eq 0 ]]; then
      log_info "✅ Successfully installed: $ext_id"
    else
      log_error "❌ Failed to install: $ext_id"
    fi
  done
}
```

---

## Integration with Phase 3-5

### Phase 3: Compliance Monitoring
- Build dashboard (Grafana): Extension coverage, setting compliance
- Real-time policy deviation alerts
- Auto-generate compliance reports

### Phase 4: Advanced Enforcement
- Team/organization policy profiles
- Per-user override permissions
- Automated rollback of unauthorized changes

### Phase 5: Governance Maturity
- Policy as code (Rego/CUE)
- Integration with SIEM/audit systems
- ML-based anomaly detection

---

## Success Criteria

**Phase 2 Completion Definition**:
- [ ] Policy enforcement working at startup (tested on 10+ instances)
- [ ] Settings merge logic correct (Tier 1 immutable, Tier 2 override, Tier 3 info)
- [ ] Extensions auto-install working (all Tier 1 extensions installed)
- [ ] Conflict detection preventing incompatible extension combos
- [ ] CI validation workflow integrated and passing
- [ ] Audit logging complete and searchable
- [ ] Team trained on policy system
- [ ] Documentation complete

**Quality Gates**:
- [ ] Startup time overhead < 500ms
- [ ] Zero policy enforcement failures
- [ ] 100% Tier 1 extension installation success rate
- [ ] Conflict detection accuracy 100%
- [ ] Audit log searchable and complete

---

## Known Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Startup delay | Poor UX | Cache policy state, parallelize installs |
| Extension install failure | Incomplete policy | Retry logic, manual intervention guide |
| Settings merge bugs | Incorrect configuration | Test merge on sample configs, UAT |
| Policy conflicts not detected | Silent failures | Comprehensive conflict matrix, CI validation |
| Audit log grows too large | Disk space issues | Implement rotation, compression |
| User frustration with immutable settings | Policy rejection | Clear tier 1 justification, communication |

---

## Testing Strategy

### Unit Tests
- Test settings merge (Tier 1/2/3)
- Test conflict detection
- Test extension validation
- Test audit logging

### Integration Tests
- Fresh code-server → policy applied
- Policy update → settings re-applied
- Extension install → conflict resolution
- Audit trail → searchable logs

### UAT (Team)
- Real environment with full policy stack
- User overrides (Tier 2) verification
- Extension conflicts (intentional test)
- Policy update workflow

---

## Handoff Criteria (Phase 3 Ready)

Phase 2 is complete when:
1. ✅ Policy enforcement working on main branch
2. ✅ 50+ users processed through new policy system
3. ✅ Zero policy-related production incidents
4. ✅ Monthly compliance reports stable
5. ✅ Team trained and comfortable with policy system
6. ✅ All known bugs fixed and tested

---

**Next Session**: Implement Phase 2 upon PR #649 merge
