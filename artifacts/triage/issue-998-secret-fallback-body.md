## P1: Remove Hardcoded Fallback from IDE_SESSION_LB_SECRET in Caddyfile

### Problem

**File**: `Caddyfile`, line 106 (and others)

While #968 addresses the hardcoded `secret734`, the Caddyfile still has a **fallback to the compromised secret**:

```caddy
lb_policy cookie ide_session_lb {$IDE_SESSION_LB_SECRET:secret734}
```

### Impact

1. **If env var is unset**: Production uses the public hardcoded value
2. **Silent failure**: No warning if `IDE_SESSION_LB_SECRET` is missing
3. **Security debt**: Even after fixing #968, the fallback remains exploitable

### Current State

```caddy
# Caddyfile line 78:
lb_policy cookie ide_session_lb secret734  # ← Literal (covered by #968)

# Caddyfile line 106:
lb_policy cookie ide_session_lb {$IDE_SESSION_LB_SECRET:secret734}  # ← Fallback!
```

### Required Changes

#### Option A: Remove Fallback, Require Env Var

```diff
- lb_policy cookie ide_session_lb {$IDE_SESSION_LB_SECRET:secret734}
+ lb_policy cookie ide_session_lb {$IDE_SESSION_LB_SECRET}
```

This will cause Caddy to fail startup if `IDE_SESSION_LB_SECRET` is not set, which is **desired behavior** for a security-critical value.

#### Option B: Fail-Safe with Obvious Invalid Fallback

```diff
- lb_policy cookie ide_session_lb {$IDE_SESSION_LB_SECRET:secret734}
+ lb_policy cookie ide_session_lb {$IDE_SESSION_LB_SECRET:MISSING_SECRET_WILL_NOT_WORK}
```

This makes misconfiguration obvious but still allows startup (for debugging).

#### Recommended: Option A (Fail-Closed)

Per governance rules, security should fail closed. Missing secrets should prevent startup.

### Validation

```bash
# Test 1: Start without env var (should fail)
unset IDE_SESSION_LB_SECRET
docker-compose up caddy
# Expected: Caddy fails to start with config error

# Test 2: Start with env var (should succeed)
export IDE_SESSION_LB_SECRET=$(openssl rand -hex 16)
docker-compose up caddy
# Expected: Caddy starts successfully

# Test 3: Verify secret is not in config
docker-compose exec caddy caddy adapt --config /etc/caddy/Caddyfile | grep secret734
# Expected: No output (secret734 not present)
```

### CI Guard

Add to `.github/workflows/validate-config.yml`:

```yaml
- name: Check for hardcoded secrets in Caddyfile
  run: |
    if grep -q 'secret734' Caddyfile Caddyfile.tpl; then
      echo "ERROR: Hardcoded secret found in Caddyfile"
      exit 1
    fi
```

### Definition of Done

- [ ] All fallbacks to `secret734` removed from Caddyfile
- [ ] Caddy fails startup if `IDE_SESSION_LB_SECRET` is missing
- [ ] CI guard prevents reintroduction of hardcoded secrets
- [ ] Documentation updated with required env vars
- [ ] Both hosts (.31 and .42) have `IDE_SESSION_LB_SECRET` set

### Cross-References

- Extends: #968 (Hardcoded LB secret)
- Related: #967 (EPIC)
