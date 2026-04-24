# GitHub Issue Management Guide

## Issue Types

### 🐛 Bug
System not working as expected. Regression or broken functionality.
- **Template**: Minimal repro steps, expected behavior, actual behavior
- **Labels**: `bug`, priority level, component
- **SLA**: Critical (30 min), High (2h), Medium (8h), Low (1 week)

### 🚀 Enhancement
Improve existing feature or add new capability.
- **Template**: Motivation, proposed solution, alternatives considered
- **Labels**: `enhancement`, priority level, component
- **Effort**: XS (< 2h), S (2-4h), M (1 day), L (2-3 days), XL (1+ weeks)

### 📋 Task
Non-code work: docs, planning, testing, ops.
- **Template**: What, Why, Success criteria
- **Labels**: `task`, component, effort
- **Blocking**: Link to dependent issues

### 🎯 Goal/Milestone
High-level objective spanning multiple issues.
- **Template**: Product vision, key results, dependencies
- **Labels**: `goal`, phase number, priority
- **Related**: Link all supporting issues

### ❓ Question
Need clarification or design input.
- **Template**: Context, what's unclear, decision needed
- **Labels**: `question`, `needs-triage`
- **Response Time**: 24 hours

---

## Label Categories

### Priority (Mandatory)
- `P0-critical`: Blocking production, immediate escalation
- `P1-high`: Major feature/bug, needed for release
- `P2-medium`: Nice to have, non-blocking
- `P3-low`: Backlog, discussion item

### Status (Mandatory)
- `status/ready`: Designed, ready to start
- `status/in-progress`: Someone actively working
- `status/blocked`: Waiting on dependency or decision
- `status/review`: PR/design review needed
- `status/done`: Completed and merged

### Effort (For tasks/enhancements)
- `effort/xs`: < 2 hours
- `effort/s`: 2-4 hours
- `effort/m`: 1 day
- `effort/l`: 2-3 days
- `effort/xl`: 1+ weeks

### Component
- `component/gpu`: GPU/CUDA/driver work
- `component/kubernetes`: k3s/Kubernetes
- `component/ci-cd`: Dagger/ArgoCD pipeline
- `component/monitoring`: Prometheus/Loki/Jaeger
- `component/security`: Vault/OPA/policies
- `component/dev-tools`: IDE/dashboard/onboarding
- `component/infrastructure`: Networking/storage
- `component/testing`: Tests/benchmarks/chaos

### Phase
- `phase/1`: Architecture & Planning
- `phase/2-5`: Foundation work
- `phase/6-8`: Core features
- `phase/9-11`: CI/CD & Operations
- `phase/12-13`: Multi-region & Edge

### Type-Specific
- `bug`: Something broken
- `enhancement`: Improvement or new feature
- `task`: Non-code work
- `goal`: High-level milestone
- `question`: Needs discussion
- `needs-triage`: Haven't reviewed yet
- `needs-design`: Requires architecture decision
- `needs-test`: Needs test coverage
- `needs-docs`: Needs documentation

### Special
- `breaking-change`: Backwards incompatible
- `security`: Security implications
- `performance`: Performance optimization
- `technical-debt`: Refactoring/cleanup

---

## Issue Structure (Standard Template)

```markdown
## 🎯 Goal
[1-2 sentence summary of what we're solving]

## 📝 Description
[Why this matters, context, motivation]

## ✅ Acceptance Criteria
- [ ] Specific testable outcome 1
- [ ] Specific testable outcome 2
- [ ] Documentation complete
- [ ] Tests added
- [ ] Ready for production

## 🔗 Dependencies
- Parent: #123 (blocking this)
- Blocked by: #456 (we block this)
- Related: #789 (good to know)

## 📊 Effort & Priority
- **Priority**: P1-high
- **Effort**: M (1 day)
- **Component**: kubernetes
- **Phase**: phase/9

## 🏗️ Implementation Notes
[Technical approach, considerations, known issues]

## 📚 References
- Design doc link
- Related discussions
```

---

## Issue Lifecycle

### 1. **Triage** (24 hours)
- Review: accurate title/description?
- Assign: labels, priority, effort
- Categorize: type + component
- Decide: accept, close as duplicate, or postpone

### 2. **Ready** (design completed)
- Acceptance criteria defined
- Dependencies mapped
- Design doc linked
- Owner assigned
- Status: `status/ready`

### 3. **In Progress** (work started)
- Branch created
- PR linked
- Status: `status/in-progress`
- Add comment when stuck

### 4. **Review** (PR needs review)
- Code review requested
- Tests added
- Documentation complete
- Status: `status/review`

### 5. **Done** (merged to main)
- PR merged
- Close issue
- Status: `status/done`
- Celebrate! 🎉

---

## Milestone Structure

### Monthly Milestones
- **1 month out**: High-level planning (40% of issues)
- **2-3 weeks out**: Detailed planning (60% of issues)
- **Current month**: Execution (80% assigned)
- **Next 3 months**: Roadmap/backlog (lower priority)

### Milestone Conventions
- `M-2026-04`: April 2026
- `Sprint-N`: 2-week sprints
- `Phase-12`: Project phase milestone

---

## Best Practices

### ✅ Good Issue
- [x] Clear, specific title
- [x] Motivation in description
- [x] Acceptance criteria listed
- [x] Effort estimated
- [x] Dependencies mapped
- [x] Relevant labels applied
- [x] Owner assigned (if ready)

### ❌ Bad Issue
- [ ] Vague title ("Fix things")
- [ ] No context or motivation
- [ ] Unclear acceptance criteria
- [ ] No effort estimate
- [ ] No labels
- [ ] Orphaned (no owner)
- [ ] Blocked but not marked

### 💡 Creating Issues
1. Use template (choose type: bug/enhancement/task/goal)
2. Be specific and testable
3. Link dependencies
4. Add preliminary label estimate
5. Request triage if unsure

### 🔍 Reviewing Issues
1. Check title clarity
2. Verify acceptance criteria are testable
3. Ensure dependencies are linked
4. Estimate effort if missing
5. Apply appropriate labels
6. Assign to milestone

### 🎯 Query Examples

**What's ready to work on?**
```
is:open status/ready -has:assignee label:effort/s
```

**What's blocking the current sprint?**
```
is:open status/blocked label:P1-high
```

**What needs triage?**
```
is:open label:needs-triage
```

**What's in progress?**
```
is:open status/in-progress
```

**What's been reviewed?**
```
is:open status/review
```

---

## Rules for Different Teams

### Developers
- Assign yourself when you start work
- Add `status/in-progress` label
- Link your PR
- Comment when blocked
- Update status when reviewing or done

### Reviewers
- Review within SLA (P0: 1h, P1: 4h, P2: 24h)
- Request changes or approve
- Update issue with decision

### Product/PM
- Triage new issues within 24h
- Set priority + effort
- Create goals/milestones
- Write acceptance criteria

### DevOps/Ops
- Flag if ops impact detected
- Link to runbooks
- Ensure monitoring planned

---

## Automation

### GitHub Actions
- Auto-add milestone based on branch
- Auto-move to "In Progress" when PR created
- Auto-close if PR merged
- Warn if no milestone (P0-P1)
- Warn if blocked but no status marker

### Bots
- Link duplicate issues
- Ping maintainers for stalled review
- Archive old backlog issues
- Generate weekly status

---

## Reporting & Analytics

### Weekly Dashboard
- Open issues by priority
- In-progress completion rate
- Blocked issues (need unblocking)
- PR review cycle time
- Closure rate

### Monthly Report
- Issues created vs closed
- Average resolution time
- Component breakdown
- Phase progress
- Risk assessment

---

## Escalation Path

**If stuck:**
1. Add `status/blocked` + comment why
2. @ mention blocking person/team
3. If no response in 4 hours: escalate to lead

**If urgent:**
1. Label as `P0-critical`
2. Post in Slack #code-server-urgent
3. Schedule sync with team lead

**If design needed:**
1. Add `needs-design` label
2. Create discussion/ADR
3. Link to issue
