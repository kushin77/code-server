# Repo Rules SSOT

Purpose: unify governance rules used by humans, CI, and agents.

Status: ACTIVE
Lifecycle: active-production
Last Updated: 2026-04-18

## Core Rules

- Conventional commits only
- Issue-linked changes only
- One source of truth per function, config, and doc concept
- No secrets committed to git
- On-prem deploys executed from `192.168.168.31`

## IaC Rules

- Prefer immutable configuration changes over imperative hotfixes
- Ensure idempotent apply paths
- Pin versions for providers and critical images
- Validate before deploy and verify after deploy

## CI Enforcement Intent

- lint + validate on pull request
- root sprawl and duplicate content checks
- security scans with fail-on-critical
