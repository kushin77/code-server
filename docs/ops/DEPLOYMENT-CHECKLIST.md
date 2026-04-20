# Deployment Checklist

Purpose: canonical pre-deploy, deploy, and rollback checklist for on-prem production changes.

## Scope

- Primary production host: `192.168.168.31`
- Replica host: `192.168.168.42`
- Applies to non-trivial changes that touch runtime, infrastructure, or auth paths

## Pre-Deploy

- Confirm the change is linked to a GitHub issue and has acceptance criteria.
- Confirm the working tree is clean and the target branch is current with `main`.
- Run the repo validation commands relevant to the change (`terraform fmt`, `terraform validate`, compose config checks, unit tests, or script linting as applicable).
- Verify required secrets are present in GSM or Vault and are not committed to the repository.
- Capture a rollback target: last known-good commit, image tag, or compose revision.
- Confirm backups or restore points exist for any data-bearing service changes.
- Review current health and alerts before applying the change.

## Deploy

- SSH to the primary host: `ssh akushnir@192.168.168.31`.
- Pull the reviewed commit or merge result on the host.
- Run the preflight task or equivalent validation before touching production services.
- Apply the smallest safe rollout first: target the affected service or module before broad redeploys.
- Verify service health, endpoint behavior, and logs immediately after deployment.
- Record the validation evidence in the linked issue.

## Rollback

- Revert the last change or redeploy the last known-good commit if health checks fail.
- Prefer targeted rollback for a single service over a full stack rollback when possible.
- Re-run health checks after rollback and confirm the original failure mode is gone.
- If rollback touches data-bearing services, validate restore points and data integrity before re-enabling traffic.

## Sign-Off

- Update the linked issue with the commands run, the validation result, and any rollback evidence.
- Close the issue only after the fix is merged, deployed, and verified in the target environment.
- If the change is documentation-only, still record where the canonical doc now lives.

## Related Ops Docs

- [OPERATIONS-INDEX.md](OPERATIONS-INDEX.md)
- [INCIDENT-RESPONSE-PLAYBOOK.md](INCIDENT-RESPONSE-PLAYBOOK.md)
- [DISASTER-RECOVERY-PLAN.md](DISASTER-RECOVERY-PLAN.md)
- [OPS-COMPLIANCE-CHECKLIST.md](OPS-COMPLIANCE-CHECKLIST.md)