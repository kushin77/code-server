## Summary

Batch of medium and hygiene findings from the April 20, 2026 full codebase audit. Each finding is independently fixable. None is individually blocking production, but collectively they represent ongoing operational risk.

---

## M-01 — Jaeger uses in-memory trace storage — all traces lost on restart (docker-compose.yml:835)

```yaml
jaeger:
  environment:
    - SPAN_STORAGE_TYPE=memory
    - MEMORY_MAX_TRACES=50000
```

All distributed traces are lost when the Jaeger container restarts. Post-incident root cause analysis is impossible. The April 19 CSRF incident has no trace evidence.

**Fix**: Switch to `SPAN_STORAGE_TYPE=badger` with a persistent volume:
```yaml
environment:
  - SPAN_STORAGE_TYPE=badger
  - BADGER_EPHEMERAL=false
  - BADGER_DIRECTORY_VALUE=/badger/data
  - BADGER_DIRECTORY_KEY=/badger/key
volumes:
  - jaeger-data:/badger
```

---

## M-02 — `failover-promote.sh` has interactive `read -p` that blocks automation (scripts/ops/failover-promote.sh:48-53)

```bash
echo "Primary host appears healthy. This is unusual."
read -p "Continue anyway? (y/n): " -n 1 -r
```

When called from a CI job, VS Code task, or automated runbook, this hangs indefinitely.

**Fix**: The script already has `FORCE_FAILOVER=1`. Skip the prompt entirely when that variable is set:
```bash
if [[ "${FORCE_FAILOVER:-0}" != "1" ]]; then
  log_fatal "Primary is healthy — set FORCE_FAILOVER=1 to override"
fi
```
All ops scripts must be non-interactive by default.

---

## M-03 — `readonly DEPLOY_HOST` reassignment breaks bash strict mode (scripts/ops/redeploy.sh:17)

```bash
# scripts/_common/config.sh line ~33:
readonly DEPLOY_HOST="${DEPLOY_HOST:-192.168.168.31}"

# scripts/ops/redeploy.sh line ~17 (run AFTER init.sh sources config.sh):
DEPLOY_HOST="${DEPLOY_HOST:-192.168.168.31}"   # ← bash: DEPLOY_HOST: readonly variable
```

In strict mode (`set -euo pipefail`), this causes `redeploy.sh` to crash at startup.

**Fix**: Remove the redundant declaration from `redeploy.sh`. The env var override mechanism in `config.sh` is sufficient.

---

## M-04 — Credential scanner pattern list too narrow (scripts/ci/check-no-hardcoded-credentials.sh:14)

Current patterns only catch: `admin123`, `changeme`, `replication_user_pwd`, `CODE_SERVER_PASSWORD=`.

The Caddyfile `secret734` would NOT have been caught by this scanner. Neither would common patterns like `api_key=`, `token=`, `Bearer ey`, `private_key`.

**Fix**: Expand pattern list to include:
```bash
CREDENTIAL_PATTERNS=(
  "secret[_-]?key\s*[=:]\s*['\"]?[a-z0-9]"
  "api[_-]?key\s*[=:]\s*['\"]?[a-z0-9]"
  "lb_policy cookie [a-z_]+ [a-z0-9]+"   # catch future hardcoded LB secrets
  "Bearer [A-Za-z0-9-._~+/]"
  "private_key"
  "password\s*=\s*['\"][^$\{]"            # password = literal (not env var)
)
```
Or replace with `gitleaks` (already in the repo at `.gitleaks.toml`) as the pre-commit credential scanner.

---

## M-05 — `oauth2-proxy.cfg` is misleading — values differ from runtime (oauth2-proxy.cfg)

The file contains `cookie-samesite = "strict"` but runtime is `lax` (IDE) and `none` (portal). A comment notes it's not mounted, but this creates false security confidence during reviews.

**Fix**: Delete the file. It adds no runtime value. If a reference config is needed, add a `# REFERENCE ONLY — NOT MOUNTED` header to the first line and update all values to match actual docker-compose environment variables.

---

## M-06 — Duplicate service definitions in docker-compose.yml (docker-compose.yml)

Multiple services appear to have duplicate definition blocks (oauth2-proxy ~line 162 and ~line 513, session-broker ~line 309 and ~line 560, caddy ~line 362 and ~line 614).

YAML parsers use the **last** occurrence of duplicate keys. The first block is silently ignored. This creates confusion about what configuration is actually active.

**Fix**:
```bash
docker compose config 2>&1 | grep "duplicate key"
```
Then run `scripts/ci/detect-duplicate-compose-keys.sh` (if implemented) and remove all duplicate service entries. Only one definition per service name should exist.

---

## M-07 — `eval "$cmd"` in retry() is shell injection risk (scripts/_common/utils.sh:27)

```bash
retry() {
  local n=$1; shift
  local cmd="$*"
  ...
  if eval "$cmd"; then   # ← shell injection if $cmd contains user-controlled input
```

**Fix**: Pass command as positional args, execute directly:
```bash
retry() {
  local n=$1; shift
  for i in $(seq 1 $n); do
    if "$@"; then return 0; fi
    sleep $((i * 2))
  done
  return 1
}
```

---

## Definition of Done
- [ ] M-01: Jaeger uses persistent badger storage
- [ ] M-02: `failover-promote.sh` is non-interactive (no `read -p`)
- [ ] M-03: `redeploy.sh` redundant `DEPLOY_HOST` removed
- [ ] M-04: Credential scanner pattern list expanded (or replaced with gitleaks)
- [ ] M-05: `oauth2-proxy.cfg` deleted or clearly marked REFERENCE ONLY
- [ ] M-06: docker-compose.yml has zero duplicate service definitions
- [ ] M-07: `retry()` in utils.sh uses `"$@"` not `eval "$cmd"`
- [ ] Parent #967 updated with evidence

Fixes #967 (EPIC)
