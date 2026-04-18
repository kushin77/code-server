# Works On My Computer Elimination

Purpose: remove environment drift from redeploy and validation flows.

Status: ACTIVE
Lifecycle: active-production
Last Updated: 2026-04-18

## Execution Contract

- All production redeploy actions are validated against host 192.168.168.31.
- Local shells must not be the hidden source of deploy behavior.
- Preflight must run in deterministic mode:
  - mode ssh with explicit key path, or
  - mode local-on-host on the target host.

## Standard Command Set

```bash
# Deterministic remote mode
bash scripts/operations/redeploy/preflight/onprem/redeploy-preflight.sh \
  --mode ssh \
  --ssh-key ~/.ssh/akushnir-31 \
  --fix-stale-logs

# Deterministic host-local mode
bash scripts/operations/redeploy/preflight/onprem/redeploy-preflight.sh \
  --mode local-on-host \
  --fix-stale-logs

# Windows to on-prem one-shot execution with line-ending normalization
powershell -Command "
  $script = Get-Content scripts/operations/redeploy/preflight/onprem/redeploy-preflight.sh -Raw;
  $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($script));
  ssh akushnir@192.168.168.31 \"echo $b64 | base64 -d > /tmp/redeploy-preflight.sh && tr -d '\\r' < /tmp/redeploy-preflight.sh > /tmp/redeploy-preflight.lf.sh && cd ~/code-server-enterprise && bash /tmp/redeploy-preflight.lf.sh --mode local-on-host --fix-stale-logs\"
"
```

## Anti-Pattern Controls

- Avoid ambiguous auth from ambient ssh-agent state.
- Avoid local-only terraform or docker assumptions for production.
- Capture branch, commit, and compose status in issue evidence before apply.

## Evidence Checklist

- branch and commit hash
- dirty-tree summary
- compose render result
- compose service table
- stale-session cleanup output

## Related Runbook

- Deploy SSH identity bootstrap: [DEPLOY-SSH-IDENTITY-BOOTSTRAP.md](DEPLOY-SSH-IDENTITY-BOOTSTRAP.md)
