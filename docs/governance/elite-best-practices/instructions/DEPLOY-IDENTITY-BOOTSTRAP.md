# Deploy Identity Bootstrap (On-Prem)

Purpose: standardize non-interactive deploy identity setup to eliminate environment-specific redeploy failures.

Status: ACTIVE
Lifecycle: active-production
Owner: platform engineering
Last Updated: 2026-04-18

## Scope

- Target host: `192.168.168.31`
- Target user: `akushnir`
- Canonical repo path: `~/code-server-enterprise`

## Approved Execution Modes

1. `local-on-host`: run scripts directly on `192.168.168.31`.
2. `ssh` or `auto`: run from external shell with non-interactive SSH identity.

## Bootstrap Procedure (External Shell)

1. Confirm key path exists and is restricted:
   - `ls -l ~/.ssh/<deploy-key>`
2. Export deterministic identity variables:
   - `export TARGET_HOST=192.168.168.31`
   - `export TARGET_USER=akushnir`
   - `export SSH_KEY_PATH=~/.ssh/<deploy-key>`
3. Validate preflight without mutation:
   - `bash scripts/operations/redeploy/preflight/onprem/redeploy-preflight.sh --mode ssh --ssh-key "$SSH_KEY_PATH"`
4. Execute deterministic redeploy:
   - `bash scripts/operations/redeploy/onprem/redeploy-remote-execute.sh --mode ssh --ssh-key "$SSH_KEY_PATH" --fix-stale-logs`

If running from WSL and key permissions/agent forwarding fail, use Windows SSH client:

- `bash scripts/operations/redeploy/preflight/onprem/redeploy-preflight.sh --mode ssh --ssh-bin ssh.exe --fix-stale-logs`
- `bash scripts/operations/redeploy/onprem/redeploy-remote-execute.sh --mode ssh --ssh-bin ssh.exe --fix-stale-logs`

## Bootstrap Procedure (On Host)

Run directly on `192.168.168.31` after SSH login:

```bash
cd ~/code-server-enterprise
bash scripts/operations/redeploy/preflight/onprem/redeploy-preflight.sh --mode local-on-host --fix-stale-logs
bash scripts/operations/redeploy/onprem/redeploy-remote-execute.sh --mode local-on-host --fix-stale-logs
```

## Failure Remediation

- If SSH fails with `Permission denied (publickey,password)`, provide `--ssh-key` explicitly or run in `local-on-host` mode.
- If compose validation fails, stop and fix tracked source; do not apply in-container hotfixes.
- If preflight reports `Docker daemon is not reachable in execution environment`, treat this as a hard block and move execution to `192.168.168.31` or enable Docker Desktop WSL integration before retrying.

## Evidence Requirements

Attach to issues/PRs:

- branch and short commit
- preflight output summary
- compose render and service health summary
- redirect verification result

Note: avoid posting full oauth2-proxy token validation payloads in issue comments; summarize status and redact tokens.
