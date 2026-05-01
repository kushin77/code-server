# Daily Standup Template

Tracks: GitHub issue [#2415](https://github.com/kushin77/code-server/issues/2415).

## When & where
- **Cadence**: weekday, 09:30 local, 15 minutes max
- **Channel**: #eng-standup (Slack/Teams) — async-first; sync optional
- **Facilitator**: rotating weekly (alphabetical by handle)

## Format

Each engineer answers, in writing, three questions:

1. **Yesterday** — what shipped (PR/commit/issue links).
2. **Today** — what you're working on (issue link).
3. **Blockers** — what is in your way; tag the unblocker.

```
:sun_with_face: Standup — <date>

*Yesterday*
- (#NNNN) <one-line outcome> — <PR or commit>

*Today*
- (#NNNN) <one-line plan>

*Blockers*
- <none | @handle on #NNNN>
```

## Rules

- One message per person, posted before 09:45.
- No status questions in-thread; use the issue.
- Blockers older than 24h escalate automatically to the facilitator.
- Facilitator posts a daily roll-up (count of PRs merged, issues closed, blockers).

## Escalation matrix

| Blocker age | Action |
|---|---|
| < 24h | Note in standup |
| 24–48h | Facilitator pings owner + assigns helper |
| > 48h | Engineering manager notified, blocker becomes a P1 issue |

## Roll-up template (facilitator)

```
:bar_chart: Standup roll-up — <date>

- Attendees: X/Y
- PRs merged (24h): N
- Issues closed (24h): N
- Active blockers: N (>24h: M)
- Highlights: <2-3 lines>
- Risks: <if any>
```

## Definition of done for this template

- [x] Cadence and channel defined
- [x] Per-engineer message format
- [x] Roll-up format
- [x] Blocker escalation matrix
