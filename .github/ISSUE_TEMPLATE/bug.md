---
name: Bug report
about: Something is broken in production
title: 'fix(<scope>): <short description>'
labels: bug
assignees: ''
---

## Duplicate Check (required before submitting)

- [ ] I searched [existing issues](https://github.com/kushin77/code-server/issues?q=is%3Aissue) for this problem
- [ ] No existing open issue covers this exact bug
<!-- If a duplicate exists, add a comment there instead of opening a new issue -->

## Describe the bug

<!-- A clear description of what is broken -->

## Steps to reproduce

1.
2.
3.

## Expected behaviour

## Actual behaviour

## Environment

- Host: 192.168.168.31 / 192.168.168.42 / local
- Service: <!-- caddy / code-server / oauth2-proxy / prometheus / grafana / redis / postgres -->
- Commit: <!-- git rev-parse HEAD -->

## Logs / evidence

```
paste relevant logs here
```

## Priority (select one)

- [ ] P0 — Outage / data loss / security breach (fix immediately)
- [ ] P1 — Major degradation, core broken (this sprint)
- [ ] P2 — Enhancement, non-critical (next sprint)
- [ ] P3 — Nice-to-have / docs / tech debt (backlog)
