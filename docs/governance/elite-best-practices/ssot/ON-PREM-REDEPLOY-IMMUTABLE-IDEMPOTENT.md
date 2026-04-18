# On-Prem Redeploy SSOT

Purpose: deterministic redeploy runbook that is immutable, idempotent, and operationally safe.

Status: ACTIVE
Lifecycle: active-production
Last Updated: 2026-04-18

## Deployment Invariants

- Host: `192.168.168.31`
- Operator: `akushnir`
- Repo path: `~/code-server-enterprise`
- Deploy command family: `docker compose` or `docker-compose` as installed on host

## Preflight

1. SSH to host and verify identity.
2. Enter repo and print branch and commit.
3. Validate tree state before deploy:
   - no accidental local-only patch files
   - no unresolved merges
4. Validate config syntax without apply:
   - `docker-compose config`
5. Validate secret source non-interactively where required.

Recommended automation command from an authenticated operator environment:

```bash
bash scripts/operations/redeploy/preflight/onprem/redeploy-preflight.sh --fix-stale-logs
```

Canonical wrapper command (preflight + redeploy sequence):

```bash
bash scripts/operations/redeploy/onprem/redeploy-remote-execute.sh \
   --mode ssh \
   --ssh-key ~/.ssh/akushnir-31 \
   --fix-stale-logs
```

Default wrapper behavior redeploys a safe core subset to avoid destructive prompts:

- `code-server oauth2-proxy caddy postgres redis pgbouncer`

Optional flags:

- `--services "svc1 svc2"` for explicit service list
- `--all-services` when full stack convergence is intentionally required

Deterministic connection options:

```bash
# From operator laptop with explicit key (no ambient shell dependency)
bash scripts/operations/redeploy/preflight/onprem/redeploy-preflight.sh \
   --mode ssh \
   --ssh-key ~/.ssh/akushnir-31 \
   --fix-stale-logs

# From deployment host itself (no SSH hop, eliminates local-machine drift)
bash scripts/operations/redeploy/preflight/onprem/redeploy-preflight.sh \
   --mode local-on-host \
   --fix-stale-logs
```

If SSH keys are not available in the local shell context, run from the on-prem host or from a shell that has the deployment SSH identity loaded.

## Immutable And Idempotent Rules

- Immutable: deployment artifacts are generated from tracked source only.
- Idempotent: repeated deploy command yields same target state.
- Ephemeral: temporary files may exist only during job execution and are removed after completion.
- Never mutate running container filesystem as source of truth.

## Canonical Redeploy Sequence

```bash
ssh akushnir@192.168.168.31
cd ~/code-server-enterprise

git rev-parse --abbrev-ref HEAD
git rev-parse --short HEAD
git status --short

docker-compose config >/tmp/compose.rendered.yaml
docker-compose up -d

docker-compose ps
docker-compose logs --tail=100 code-server oauth2-proxy caddy
```

## Health Gates

- `code-server`, `oauth2-proxy`, `caddy`, `postgres`, and `redis` are up
- Auth redirect works for apex and IDE routes
- Monitoring stack is healthy if monitoring profile enabled

## Rollback

1. Revert commit or switch to known-good tag.
2. Re-run `docker-compose up -d`.
3. Confirm service health and auth flow.

## Evidence Requirements

Capture and attach to issue/PR:

- branch + commit
- deploy command output summary
- container health table
- auth redirect verification result
