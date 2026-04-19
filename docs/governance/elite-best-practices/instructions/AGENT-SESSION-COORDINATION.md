# Agent Session Coordination

Purpose: prevent collisions when multiple agents or terminals operate concurrently.

Status: ACTIVE
Lifecycle: active-production
Last Updated: 2026-04-18

## Coordination Rules

- Announce target files and intended scope before edits.
- Avoid editing files with active uncommitted user changes unless required.
- Prefer additive docs and isolated files for parallel work.
- Capture command evidence in issue comments or execution notes.

## Deployment Coordination

- Only one active redeploy actor per host at a time.
- Kill stale `docker-compose logs -f` sessions before new incident triage.
- Verify there is no active `terraform apply` before starting another deploy flow.

## Handoff Contract

Include:

- branch and commit
- files touched
- what was validated
- explicit next command to run
