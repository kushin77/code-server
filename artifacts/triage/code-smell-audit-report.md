# Code Smell Audit Report

- Timestamp (UTC): 2026-04-21T12:55:47Z
- Strict mode: 1
- Run ESLint checks: 1
- Run unused-export checks: 1
- Run complexity checks: 1
- Frontend complexity max threshold: 40
- Agent farm complexity max threshold: 10

## ESLint Strict Mode
- PASS: apps/frontend eslint strict check
- PASS: apps/extensions/agent-farm eslint strict check

## Unused Export Checks
- PASS: apps/frontend has zero ts-prune findings
- PASS: apps/extensions/agent-farm has zero ts-prune findings

## Complexity Checks
- PASS: apps/frontend complexity <= 40
- PASS: apps/extensions/agent-farm complexity <= 10

## Suppression Hygiene
- PASS: no unexplained eslint-disable/noqa markers

## TODO Hygiene
- PASS: TODO/FIXME/HACK markers are issue-linked or absent

## Summary
- eslint_fail: 0
- unused_export_fail: 0
- complexity_fail: 0
- suppress_fail: 0
- todo_fail: 0
- total_failure_flags: 0
