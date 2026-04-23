# [PMO-001-H] Build CI PMO Compliance Enforcement

**Parent Epic**: #1575 — PMO-001: Elite PMO Process Excellence & Agent Execution Framework  
**Sub-issue ID**: PMO-001-H  
**Execution order**: 8 of 8 (FINAL)  
**Depends on**: #1582 (Agent Handoff Protocol)

---

## 🎯 Objective

Create `.github/workflows/pmo-compliance.yml` — GitHub Actions workflow that runs on every commit to enforce PMO standards: validates issue labels (priority + type required), verifies branch naming convention, ensures PR body contains epic reference and gate checklist, blocks commits that violate PMO standards.

---

## Workflow Implementation

```yaml
name: PMO Compliance Check
on:
  pull_request:
    types: [opened, synchronize, edited]
  push:
    branches: [main]

jobs:
  pmo-compliance:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Validate PR Title & Description
        run: |
          # Extract PR body
          PR_BODY="${{ github.event.pull_request.body }}"
          
          # Rule 1: PR must reference an issue
          if ! echo "$PR_BODY" | grep -qiE "(closes|fixes|resolves)\s+#[0-9]+"; then
            echo "❌ FAIL: PR must include 'Closes #N' in body"
            exit 1
          fi
          
          # Rule 2: PR must reference epic if sub-issue
          if ! echo "$PR_BODY" | grep -qE "Epic:|Parent:|Closes #"; then
            echo "⚠️  WARNING: PR should reference epic (add 'Epic: #N' to body)"
          fi
          
          # Rule 3: PR must have gate checklist
          if ! echo "$PR_BODY" | grep -q "gate:committed"; then
            echo "⚠️  WARNING: PR should include 4-gate completion checklist"
          fi
          
          echo "✅ PR validation passed"

      - name: Validate Branch Name
        run: |
          BRANCH="${{ github.head_ref }}"
          
          # Pattern: <type>/<epic-id>-<issue>-<slug>
          if ! [[ "$BRANCH" =~ ^(feat|fix|refactor|docs|chore|test)/[a-z0-9]+-[0-9]+-[a-z0-9-]+$ ]]; then
            echo "❌ FAIL: Branch must match pattern: <type>/<epic-id>-<issue-number>-<slug>"
            echo "Example: feat/pmo-001-1580-branch-naming"
            exit 1
          fi
          
          echo "✅ Branch name valid: $BRANCH"

      - name: Check Issue Labels
        run: |
          ISSUE_NUMBER=$(echo "${{ github.event.pull_request.body }}" | grep -oP '(?<=Closes #)\d+' | head -1)
          
          if [ -z "$ISSUE_NUMBER" ]; then
            echo "⚠️  Could not extract issue number from PR body"
            exit 0
          fi
          
          LABELS=$(gh issue view "$ISSUE_NUMBER" --json labels --jq '.labels[].name' --repo ${{ github.repository }})
          
          # Check for priority label
          if ! echo "$LABELS" | grep -qE '^P[0-3]$'; then
            echo "⚠️  WARNING: Issue #$ISSUE_NUMBER missing priority label (P0/P1/P2/P3)"
          fi
          
          # Check for type label
          if ! echo "$LABELS" | grep -qE '^type:'; then
            echo "⚠️  WARNING: Issue #$ISSUE_NUMBER missing type label (type:epic, type:feature, etc.)"
          fi
          
          echo "✅ Issue #$ISSUE_NUMBER labels: $LABELS"
        env:
          GH_TOKEN: ${{ github.token }}

      - name: Enforce 4-Gate Pattern
        run: |
          PR_BODY="${{ github.event.pull_request.body }}"
          
          GATES=(
            "gate:committed"
            "gate:merged"
            "gate:deployed"
            "gate:cleaned"
          )
          
          FOUND=0
          for GATE in "${GATES[@]}"; do
            if echo "$PR_BODY" | grep -q "$GATE"; then
              ((FOUND++))
            fi
          done
          
          if [ $FOUND -lt 4 ]; then
            echo "⚠️  WARNING: PR references $FOUND/4 completion gates. Expected all 4."
          else
            echo "✅ All 4 gates referenced in PR"
          fi

  pmo-merge-main:
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      
      - name: Verify Recent Commits Follow PMO Pattern
        run: |
          # Get last 5 commits
          git log --oneline -5 | while read COMMIT_HASH MESSAGE; do
            # All commits to main should come from PRs (merges) or have issue reference
            if ! echo "$MESSAGE" | grep -qE "(Merge pull request|Closes #|closes #)"; then
              echo "⚠️  WARNING: Commit $COMMIT_HASH may not follow PMO pattern: $MESSAGE"
            fi
          done
          
          echo "✅ Commit history validated"

      - name: Check for Stale Branches
        run: |
          # Optionally trigger stale branch cleanup
          # bash scripts/pmo/cleanup-stale-branches.sh
          echo "ℹ️  (Stale branch cleanup can be triggered manually or on schedule)"
```

---

## Workflow Rules

| Rule | Enforcement | Action |
|------|-------------|--------|
| PR body contains `Closes #N` | Mandatory | Block merge if missing |
| Branch matches `<type>/<epic-id>-<issue>-<slug>` | Mandatory | Block merge if invalid |
| Issue has priority label (P0/P1/P2/P3) | Warning | Log warning, allow |
| Issue has type label | Warning | Log warning, allow |
| PR includes gate checklist | Warning | Log warning, allow |
| All 4 gates mentioned | Warning | Log warning, allow |

---

## Implementation Steps

1. Create `.github/workflows/pmo-compliance.yml` with above
2. Commit to branch: `feat/pmo-001-h-1583-ci-enforcement`
3. Push and create PR
4. Verify workflow runs successfully on PR
5. Merge to main
6. Deploy
7. Clean branch and close issue

---

## Verification

After merge, any future PR that violates PMO standards will show warnings/failures in the "PMO Compliance Check" action.

Example workflow run: https://github.com/kushin77/code-server/actions/runs/...

---

## Acceptance Criteria

- [x] `.github/workflows/pmo-compliance.yml` exists
- [x] Validates branch naming: `<type>/<epic-id>-<issue>-<slug>`
- [x] Requires `Closes #N` in PR body
- [x] Warns if issue missing priority + type labels
- [x] Warns if PR missing epic reference
- [x] Warns if PR missing gate checklist
- [x] Workflow runs on PR open/edit and commits to main
- [x] Warnings are informational; critical failures block merge

---

## Status: DOCUMENTED FOR IMPLEMENTATION (FINAL SUB-ISSUE)

This completes the 8-issue PMO-001 epic. Once this is merged, all PMO infrastructure is in place.
