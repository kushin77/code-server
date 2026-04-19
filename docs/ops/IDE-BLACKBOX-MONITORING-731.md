# IDE-BLACKBOX-MONITORING-731

Purpose:
- Define the blackbox probe location, signal interpretation, and operational usage for issue #731.

Issue:
- #731 P1: Add blackbox monitoring for ide.kushnir.cloud failover path

Probe Location:
- Script: `scripts/ops/ide-blackbox-monitor.sh`
- Workflow: `.github/workflows/ide-blackbox-monitor.yml`
- Trigger mode:
  - Scheduled every 10 minutes
  - Manual `workflow_dispatch`

What Is Probed:
1. `https://ide.kushnir.cloud/`
- Accepted statuses: `200`, `302`, `303`, `401`, `403`
- This endpoint is expected to challenge unauthenticated users, so `403` is healthy.

2. `https://ide.kushnir.cloud/oauth2/start?rd=/`
- Accepted statuses: `302`, `303`
- Confirms OAuth start path remains responsive.

3. Sticky routing cookie
- Requires `Set-Cookie: ide_lb_shared` in response headers.
- Confirms active sticky LB behavior is observable from user path probes.

SLO Interpretation:
- Availability SLI:
  - Successful probe run where all checks pass.
- Availability SLO:
  - Target: >= 99.9% successful probe runs in rolling 30 days.
- Degradation signal:
  - Consecutive workflow failures indicate user-path impairment or auth-flow regression.

Game-Day Usage:
1. Trigger manual run before failover event.
2. Trigger manual run during failover window.
3. Trigger manual run after failback.
4. Attach run URLs and pass/fail evidence to issue #714 drill notes.

Operator Commands:
- Manual local probe:
```bash
bash scripts/ops/ide-blackbox-monitor.sh
```

- Manual GitHub run:
```bash
gh workflow run ide-blackbox-monitor.yml
```

- View latest run:
```bash
gh run list --workflow ide-blackbox-monitor.yml --limit 1
```