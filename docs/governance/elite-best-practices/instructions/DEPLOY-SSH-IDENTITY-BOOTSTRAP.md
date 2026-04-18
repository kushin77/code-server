# Deploy SSH Identity Bootstrap

Purpose: standardize non-interactive SSH authentication for deterministic on-prem redeploy execution.

Status: ACTIVE
Lifecycle: active-production
Last Updated: 2026-04-18

## Scope

- Primary host: 192.168.168.31
- User: akushnir
- Applies to local operator shell, self-hosted runners, and host-local execution

## Principles

- Use explicit identity material instead of ambient shell state.
- Keep key material ephemeral in CI workspaces and remove after run.
- Fail fast when SSH auth is missing; never continue with partial execution.

## Local Operator Shell

```bash
# Validate key file and remote auth directly
ssh -i ~/.ssh/akushnir-31 -o BatchMode=yes akushnir@192.168.168.31 "echo OK"

# Deterministic preflight using explicit key
bash scripts/operations/redeploy/preflight/onprem/redeploy-preflight.sh \
  --mode ssh \
  --ssh-key ~/.ssh/akushnir-31 \
  --fix-stale-logs

# Deterministic redeploy wrapper using explicit key
bash scripts/operations/redeploy/onprem/redeploy-remote-execute.sh \
  --mode ssh \
  --ssh-key ~/.ssh/akushnir-31

# Full-stack convergence only when intentional
bash scripts/operations/redeploy/onprem/redeploy-remote-execute.sh \
  --mode ssh \
  --ssh-key ~/.ssh/akushnir-31 \
  --all-services
```

## Self-Hosted Runner Pattern

```bash
# Write deploy key from secret to ephemeral workspace path
install -m 700 -d "$RUNNER_TEMP/.ssh"
printf '%s' "$DEPLOY_SSH_KEY" > "$RUNNER_TEMP/.ssh/deploy.key"
chmod 600 "$RUNNER_TEMP/.ssh/deploy.key"

# Strict non-interactive test
ssh -i "$RUNNER_TEMP/.ssh/deploy.key" -o BatchMode=yes akushnir@192.168.168.31 "echo OK"

# Execute preflight and redeploy with explicit key
bash scripts/operations/redeploy/preflight/onprem/redeploy-preflight.sh \
  --mode ssh \
  --ssh-key "$RUNNER_TEMP/.ssh/deploy.key" \
  --fix-stale-logs

bash scripts/operations/redeploy/onprem/redeploy-remote-execute.sh \
  --mode ssh \
  --ssh-key "$RUNNER_TEMP/.ssh/deploy.key"

# Ephemeral cleanup
shred -u "$RUNNER_TEMP/.ssh/deploy.key" || rm -f "$RUNNER_TEMP/.ssh/deploy.key"
```

## Host-Local Execution Pattern

```bash
ssh akushnir@192.168.168.31 "cd ~/code-server-enterprise && bash scripts/operations/redeploy/preflight/onprem/redeploy-preflight.sh --mode local-on-host --fix-stale-logs"
ssh akushnir@192.168.168.31 "cd ~/code-server-enterprise && bash scripts/operations/redeploy/onprem/redeploy-remote-execute.sh --mode local-on-host"
```

## Verification Checklist

- SSH non-interactive auth succeeds with explicit identity.
- Preflight prints branch, commit, dirty summary, and compose render result.
- Redeploy command completes without image pull errors.
- Compose service table is captured in issue evidence.
