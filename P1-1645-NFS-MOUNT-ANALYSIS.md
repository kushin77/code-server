# P1 #1645 NFS Mount Issue - Remediation Analysis

**Issue**: P1 SSH connectivity blocker (root cause: NFS mount failure)  
**Affected System**: Replica 2 (192.168.168.42)  
**Impact**: Services degraded, blocks production parity  
**Status**: Actively investigating  

---

## Problem Summary

Replica 2 docker-compose deployment is failing on NFS volume mount for appsmith:

```
Error: failed to populate volume /export/appsmith
Path doesn't exist: mount :/export/appsmith
```

### Root Causes Identified

1. **Missing NAS Directories**
   - NAS (192.168.168.56) exports `/export` but not `/export/appsmith` subdirectory
   - Required for appsmith service volume mount
   - Replica 1 doesn't have this issue (working differently or has directory)

2. **Passwordless Sudo Missing**
   - Cannot create directories with `sudo` on Replica 2
   - akushnir user lacks passwordless sudo configuration
   - Blocks automated remediation

3. **Git Drift on Replica 2**
   - Was 2 commits behind main (69fe25e1 vs 0c050374)
   - Already corrected via git fetch/reset
   - Services still failing due to NFS issue

---

## Investigation Path

### ✅ Verified Working
- Network connectivity: Replica 2 ↔ NAS working
- SSH chain access: Replica 1 → Replica 2 working
- Git operations: Fixed and current

### ❌ Verified Broken
- NFS subdirectory: `/export/appsmith` does NOT exist
- Docker-compose deployment: Fails on volume population
- Service startup: appsmith and caddy not running

### ⏳ Unknown
- Why Replica 1 doesn't have same NFS issue
- Why passwordless sudo unavailable on Replica 2
- Whether Appsmith service is critical or optional

---

## Remediation Options

### Option 1: Create NAS Directory (Preferred)
**Requirements**: SSH access to NAS or admin privileges
```bash
# On NAS (192.168.168.56) as admin:
mkdir -p /export/appsmith
chmod 755 /export/appsmith
chown nobody:nogroup /export/appsmith  # NFS default user

# Verify from Replica 2:
ls -ld /export/appsmith  # Should show mount point
```

**Pros**: Fixes root cause permanently  
**Cons**: Requires NAS admin access  

### Option 2: Update docker-compose.yml
**Change appsmith volume config**:
```yaml
# From:
volumes:
  - type: nfs
    o: addr=192.168.168.56,vers=4,soft,timeo=180,bg
    device: ":/export/appsmith"
    target: /appsmith

# To: Skip NFS, use local volume
volumes:
  - type: volume
    source: appsmith_local
    target: /appsmith

volumes:
  appsmith_local:
    driver: local
```

**Pros**: Works without NAS access  
**Cons**: Data not shared between replicas  

### Option 3: Disable Appsmith Service
**In docker-compose.yml**:
```yaml
services:
  appsmith:
    profiles: []  # Remove from default profiles
    # Service disabled
```

**Pros**: Simplest fix  
**Cons**: Loses Appsmith functionality  

---

## Recommended Path Forward

1. **IMMEDIATE**: Determine if Appsmith is critical
   - Check production architecture (KUBECONFIG, deployment docs)
   - Is Appsmith required for KC IDE functionality?
   - If optional → Disable and move forward

2. **SHORT TERM**: Create NAS directory
   - Requires NAS admin access
   - Once done, deployment will proceed normally
   - Maintains full feature parity

3. **MEDIUM TERM**: Review passwordless sudo
   - Why is it missing on Replica 2?
   - Should it be configured identically on both?
   - Add to infrastructure as code?

---

## Docker-Compose Volume Analysis

**Current Config** (docker-compose.yml):
```yaml
volumes:
  - type: nfs
    o: addr=192.168.168.56,vers=4,soft,timeo=180,bg
    device: ":/export/appsmith"
    target: /appsmith

  - type: nfs
    o: addr=192.168.168.56,vers=4,soft,timeo=180,bg
    device: ":/export/code-server-enterprise"
    target: /code-server-enterprise-shared
```

**Working on Replica 1**: `/export/code-server-enterprise` exists  
**Broken on Replica 2**: `/export/appsmith` does NOT exist

**Hypothesis**: Appsmith directory was created on NAS only for Replica 1, or was inadvertently deleted.

---

## Investigation Commands

To run on Replica 2 (via chain SSH):
```bash
ssh -o ProxyCommand="ssh akushnir@192.168.168.31 'nc -X connect -x %h:%p 192.168.168.42'" \
    akushnir@192.168.168.42 << 'EOF'

# Check NFS connectivity
showmount -e 192.168.168.56
# Expected output:
# /export           (everyone)
# /export/appsmith  (everyone)  ← Should appear

# Check current mounts
df -h | grep export
# Expected: See mounted volumes

# Check docker-compose config
cat docker-compose.yml | grep -A 5 "device.*export"

# Try manual mount test
mkdir -p /tmp/test-mount
sudo mount -t nfs 192.168.168.56:/export/appsmith /tmp/test-mount
ls /tmp/test-mount  # Should show appsmith data or be empty
sudo umount /tmp/test-mount

EOF
```

---

## Resolution Steps

### Step 1: Verify Appsmith Criticality
Check KC infrastructure docs to determine if Appsmith is required:
- [ ] Is it used by KC IDE?
- [ ] Is it part of core service stack?
- [ ] Can it be disabled temporarily?

### Step 2: Choose Remediation Path
Based on Step 1 results:
- **If critical**: Create NAS directory (needs admin)
- **If optional**: Disable in docker-compose.yml
- **If uncertain**: Disable, deploy, then add later

### Step 3: Deploy Chosen Solution
Update docker-compose.yml or NAS accordingly

### Step 4: Redeploy Replica 2
```bash
ssh akushnir@192.168.168.42 'cd ~/code-server-enterprise && docker compose up -d'
```

### Step 5: Verify Services
```bash
ssh akushnir@192.168.168.42 'docker compose ps'
# All services should show "Up"
```

---

## Decision Matrix

| Solution | Time | Admin Access | Impact | Reversible |
|----------|------|--------------|--------|-----------|
| Create NAS dir | 5 min | Yes (NAS) | ✅ Full features | Yes |
| Disable Appsmith | 5 min | No | ⚠️ Loses feature | Yes |
| Local volume | 10 min | No | ⚠️ No data share | Yes |

**Recommendation**: Start with **Option 3 (Disable Appsmith)** to unblock deployment, then investigate Option 1 in parallel.

---

## Files to Update for Option 3 (Disable Appsmith)

**File**: docker-compose.yml  
**Change**: Remove appsmith from default profile

**Before**:
```yaml
services:
  appsmith:
    image: appsmith/appsmith:...
    profiles: [default, appsmith-dev]
```

**After**:
```yaml
services:
  appsmith:
    image: appsmith/appsmith:...
    profiles: [appsmith-dev]  # Remove 'default'
```

This allows deployment to proceed without appsmith, but service can be enabled later if needed.

---

**Status**: Ready for decision on remediation path  
**Next**: Determine Appsmith criticality from KC docs
