# Github Free Maximization Plan

**Purpose**: Github Free Maximization Plan reference document.

---
title: GitHub Free Maximization Plan
description: Inventory and optimization baseline for reducing paid GitHub Actions/API usage while preserving delivery quality.
owner: platform
last_review_date: 2026-04-20
status: active
related_issues:
  - 900
  - 891
---

# GitHub Free Maximization Plan

## Purpose

This plan keeps GitHub Free usage intentional: pin actions, limit artifact growth, reuse caches, and avoid unnecessary workflow churn.

## Baseline Inputs

- Workflow inventory report: [artifacts/triage/github-free-maximization-report.md](../../artifacts/triage/github-free-maximization-report.md)
- Run history baseline: [artifacts/metrics/gh-runs-raw.json](../../artifacts/metrics/gh-runs-raw.json)

## Current Guardrails

- External workflow actions are pinned to immutable SHAs.
- Artifact retention is capped at 90 days.
- Cache-backed installs are used where repeated dependency resolution would otherwise consume minutes.
- Workflow templates are already used for repeated validation surfaces.

## Approved Free-Tier Substitutions

1. Use pinned first-party actions and shared scripts instead of ad hoc shell fragments.
2. Use workflow caches for package installs instead of repeated clean fetches.
3. Keep triage/report artifacts short-lived and bounded by retention policy.
4. Prefer scheduled reporting jobs over manual replay runs for recurring inventory checks.

## Baseline Metrics to Track

- Total workflow run count.
- Success/failure/skip distribution.
- Ratio of scheduled workflows to PR-triggered workflows.
- Count of pinned external actions.
- Artifact retention ceiling.
- Cache usage in heavy validation jobs.

## Optimization Targets

- Keep unpinned external actions at zero.
- Keep artifact retention at or below 90 days.
- Keep workflow duplication under control by reusing shared scripts and templates.
- Watch the skip ratio on gating workflows so wasted runs do not drift upward.

## Validation Workflow

The inventory script runs in CI via [`.github/workflows/github-free-maximization.yml`](../../.github/workflows/github-free-maximization.yml).

That workflow produces a machine-readable report and a markdown baseline that can be used in issue updates, PR review, and monthly cost reviews.

## Review Cadence

- Weekly: inspect the generated report for drift.
- Monthly: compare run-history trend and workflow inventory counts.
- On workflow changes: verify new jobs are pinned, bounded, and justified.

## Closeout Criteria for #900

- Inventory and optimization plan published.
- Guard workflow and report generator committed.
- Baseline report generated from the current workflow set.
- Issue updated with evidence and no unresolved repo-side blockers.
