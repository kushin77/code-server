## P0 CRITICAL: Caddyfile `primary_host` is Literal String - Dual-Upstream Failover Broken

### Severity: CRITICAL

### Evidence

**File**: `Caddyfile`, lines 40, 99, 143, 173, 247, 276

The Caddyfile uses `primary_host:5000` as a **literal hostname string**, while `{$REPLICA_HOST:replica-host}` uses proper env var syntax:

```caddy
# Line 40-43 (and similar patterns throughout):
upstreams {
    primary_host:5000   # ← LITERAL STRING, not {$PRIMARY_HOST:...}
}

# Line 99-102:
upstreams {
    {$REPLICA_HOST:replica-host}:5000  # ← CORRECT env var syntax
}
```

### Impact

1. **DNS resolution fails**: `primary_host` is not a valid hostname - Caddy cannot resolve it
2. **All traffic to primary upstream fails**: Requests intended for primary host (.31) fail immediately
3. **Dual-host failover is broken**: The entire HA architecture relies on Caddy routing between primary/replica
4. **Production is running on accident**: Traffic only works because it falls back to replica or single-host mode

### Related Gap: Missing `PRIMARY_HOST` in `.env.template`

**File**: `.env.template` lines 12-15

```bash
# Current state:
DEPLOY_HOST=192.168.168.31
REPLICA_HOST=192.168.168.42
# Missing: PRIMARY_HOST=192.168.168.31
```

Without `PRIMARY_HOST` defined, even fixing the Caddyfile won't work.

### Required Changes

#### 1. Fix Caddyfile (all occurrences)

```diff
- upstreams {
-     primary_host:5000
- }
+ upstreams {
+     {$PRIMARY_HOST:192.168.168.31}:5000
+ }
```

#### 2. Update `.env.template` and `.env.schema.json`

```bash
# .env.template:
PRIMARY_HOST=192.168.168.31
REPLICA_HOST=192.168.168.42
```

```json
// .env.schema.json:
{
  "PRIMARY_HOST": {
    "description": "Primary host IP for Caddy dual-upstream failover",
    "required": true,
    "default": "192.168.168.31"
  }
}
```

#### 3. Update docker-compose.tpl

Ensure `PRIMARY_HOST` is passed to Caddy container:

```yaml
caddy:
  environment:
    PRIMARY_HOST: ${PRIMARY_HOST}
    REPLICA_HOST: ${REPLICA_HOST}
```

### Validation Commands

```bash
# 1. Verify env var is set
docker-compose exec caddy printenv | grep PRIMARY_HOST

# 2. Check Caddy config parsing
docker-compose exec caddy caddy adapt --config /etc/caddy/Caddyfile

# 3. Test upstream routing
curl -v https://ide.kushnir.cloud/health
# Should route to primary, fail over to replica on error
```

### Definition of Done

- [ ] All `primary_host` literals in Caddyfile replaced with `{$PRIMARY_HOST:...}`
- [ ] `PRIMARY_HOST` added to `.env.template`
- [ ] `PRIMARY_HOST` added to `.env.schema.json`
- [ ] docker-compose.tpl passes `PRIMARY_HOST` to Caddy
- [ ] Both hosts (.31 and .42) have correct `PRIMARY_HOST` value
- [ ] Caddy restart succeeds with new config
- [ ] Failover test: stop session-broker on .31, verify traffic routes to .42

### Cross-References

- Related: #958 (Dual-host Caddy upstream)
- Related: #967 (EPIC: Full codebase audit)
- This is a **blocker** for any HA testing

### Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Production outage | HIGH (if tested) | CRITICAL | Test in staging first |
| DNS resolution failure | CURRENT | CRITICAL | This is happening now |
| Rollback needed | LOW | LOW | Keep backup Caddyfile |
