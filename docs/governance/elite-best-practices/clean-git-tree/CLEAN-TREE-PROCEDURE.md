# Clean Git Tree Procedure

Purpose: define clean-tree standards before and after redeploy activity.

Status: ACTIVE
Lifecycle: active-production
Last Updated: 2026-04-18

## Pre-Deploy Gate

1. `git status --short --branch`
2. Confirm no accidental generated artifacts are staged.
3. Confirm branch naming and issue linkage are valid.
4. Record current commit hash in issue.

## During Deploy

- Keep runtime artifacts ephemeral and outside tracked source.
- Avoid ad-hoc edits directly on production host repo during incident handling.

## Post-Deploy Gate

1. Re-check tree state.
2. Capture `docker-compose ps` and key health outputs.
3. Update issue with evidence.
4. Close issue only after acceptance criteria are met.
