## Severity: CRITICAL

## Evidence

**File**: `scripts/ops/secret-rotation.sh`, lines 28–65

```bash
# Even in non-dry-run mode (DRY_RUN=0), the entire implementation is:
log_info "✅ Secrets fetched from GSM"    # No actual gcloud secrets access
log_info "✅ All secrets validated"        # No actual validation logic
log_info "✅ .env file updated"            # No actual file write
log_info "✅ Restarted oauth2-proxy"       # No actual docker restart
log_info "✅ Restarted code-server"        # No actual docker restart
```

The script logs success messages unconditionally while performing zero actual operations.

## Risk

**This is a false safety guarantee during a key-compromise incident.**

An operator who runs `DRY_RUN=0 bash scripts/ops/secret-rotation.sh` during an incident will:
1. See "✅ Secrets rotated successfully" output
2. Believe rotation has occurred
3. Not actually have rotated any secrets
4. Continue operating with compromised credentials

The April 20, 2026 audit confirms this script has never successfully rotated any secret in any environment. Finding A-01 (hardcoded `secret734`) cannot be remediated without a working rotation script.

## Required Implementation

Replace the stub implementation with actual steps:

```bash
# 1. Fetch new secret versions from GSM
for secret in OAUTH2_PROXY_COOKIE_SECRET REDIS_PASSWORD IDE_SESSION_LB_SECRET; do
  value=$(gcloud secrets versions access latest --secret="$secret" --project="${GCP_PROJECT_ID}")
  declare "NEW_${secret}=${value}"
done

# 2. Validate secret formats
validate_secret_length "OAUTH2_PROXY_COOKIE_SECRET" "${NEW_OAUTH2_PROXY_COOKIE_SECRET}" 32
validate_hex_secret    "REDIS_PASSWORD" "${NEW_REDIS_PASSWORD}"

# 3. Write new .env atomically (write to .env.new, then mv)
write_env_atomic

# 4. Restart affected services with health checks
for service in oauth2-proxy oauth2-proxy-portal session-broker; do
  docker compose restart "$service"
  wait_for_healthy "$service" 60
done

# 5. Verify sessions still work after rotation
verify_auth_path_health
```

Key requirements:
- Each step must assert its postcondition before proceeding
- Rotation must be atomic (partial rotation leaves system broken)
- Failed rotation must roll back the `.env` file
- Audit log entry must be written to `artifacts/incidents/rotation-$(date +%Y%m%d%H%M%S).log`

## Definition of Done
- [ ] Script actually fetches secrets from GSM (test: `gcloud secrets versions access latest --secret=...` executes)
- [ ] Script actually writes updated `.env` (test: `diff` before/after shows changed values)
- [ ] Script actually restarts services (test: `docker events` shows restart events)
- [ ] Script verifies services are healthy after restart
- [ ] Failed rotation rolls back `.env` to pre-rotation state
- [ ] Dry-run mode shows what WOULD happen without executing
- [ ] Audit trail written for every rotation attempt
- [ ] Parent #967 updated with evidence

Fixes #967 (EPIC)
