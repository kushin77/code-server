# PMO Branch Naming Convention

**Standard**: All work branches must follow the canonical PMO naming pattern to enable automation and tracking.

## Pattern

```
<type>/<epic-id>-<issue-number>-<short-slug>
```

## Examples

| Type | Epic | Issue | Slug | Full Branch |
|------|------|-------|------|-------------|
| feat | pmo-001 | 1576 | label-taxonomy | `feat/pmo-001-1576-label-taxonomy` |
| fix | pmo-001 | 1577 | template-config | `fix/pmo-001-1577-template-config` |
| refactor | oidc-auth | 1234 | session-validation | `refactor/oidc-auth-1234-session-validation` |
| docs | resilience | 5678 | failover-runbook | `docs/resilience-5678-failover-runbook` |
| chore | infra | 9012 | ci-update | `chore/infra-9012-ci-update` |

## Components

### Type
Branch classification that appears first:
- **feat** — New feature or enhancement
- **fix** — Bug fix or defect resolution
- **refactor** — Code quality, structure, or performance improvements
- **chore** — Maintenance, tooling, process improvements
- **docs** — Documentation, guides, runbooks
- **infra** — Infrastructure-as-Code, deployment, operations

### Epic ID
Short identifier linking to the strategic epic:
- `pmo-001` — PMO Process Excellence Framework
- `pmo-002` — Future PMO epic
- `oidc-auth` — OIDC Authentication & Identity
- `resilience` — Infrastructure Resilience
- `observability` — Monitoring & Alerting
- `security-hardening` — Security Hardening
- `kushnir-cloud` — Kushnir.cloud Platform
- etc.

### Issue Number
The GitHub issue number (without `#`):
- Example: `1576`, `1577`, `1234`

### Short Slug
Brief description of the change (lowercase, hyphens, max 30 chars):
- `label-taxonomy` — Describes provisioning labels
- `session-validation` — Describes session auth changes
- `failover-runbook` — Describes failover documentation

**Good slugs:**
- ✅ `label-taxonomy`
- ✅ `session-validation`
- ✅ `ci-github-actions-migration`

**Bad slugs:**
- ❌ `fix-the-thing` (too vague)
- ❌ `UPPERCASE_UNDERSCORE` (must be lowercase with hyphens)
- ❌ `feature-for-epic-pmo-001-to-add-better-label-provisioning-with-idempotency` (too long)

## Enforcement

### CI Rules
- Branch naming is validated on every push via `.github/workflows/pmo-compliance.yml`
- PRs with non-compliant branch names will fail CI check
- Error message: `BRANCH_NAME_INVALID: Expected format <type>/<epic-id>-<issue-number>-<slug>`

### Git Hooks (Optional - for local validation)
```bash
# In .git/hooks/pre-push
#!/bin/bash
branch=$(git rev-parse --abbrev-ref HEAD)
if [[ ! $branch =~ ^(feat|fix|refactor|chore|docs|infra)/[a-z0-9]+-[0-9]+-[a-z0-9-]+$ ]]; then
    echo "ERROR: Branch '$branch' does not match PMO pattern"
    exit 1
fi
```

## Creation Workflow

1. **Create branch following pattern:**
   ```bash
   git checkout -b feat/pmo-001-1576-label-taxonomy
   ```

2. **Work on your changes**

3. **Commit with Conventional Commit format:**
   ```bash
   git commit -m "feat: implement label provisioning for PMO framework (#1576)"
   ```

4. **Push branch:**
   ```bash
   git push -u origin feat/pmo-001-1576-label-taxonomy
   ```

5. **Create PR** with:
   - Title: `[FEAT] pmo-001-1576: Implement label provisioning`
   - Body includes: `Closes #1576` and `Epic: pmo-001`

6. **After merge**, cleanup is automatic via PMO completion gates

## Cleanup & Deletion

### Automatic (via `complete-issue.sh`)
```bash
bash scripts/pmo/complete-issue.sh kushin77/code-server 1576
```
- Deletes local branch: `feat/pmo-001-1576-label-taxonomy`
- Deletes remote branch via: `git push origin --delete feat/pmo-001-1576-label-taxonomy`

### Manual (if needed)
```bash
# Delete local
git branch -d feat/pmo-001-1576-label-taxonomy

# Delete remote
git push origin --delete feat/pmo-001-1576-label-taxonomy
```

### Cleanup Audit (see stale branches)
```bash
bash scripts/pmo/cleanup-stale-branches.sh --dry-run
```

## Q&A

**Q: What if my epic ID has multiple words?**  
A: Use hyphens: `epic-name-123-4567-slug` (but keep epic IDs short — 1-2 words)

**Q: Can I use underscores?**  
A: No — only hyphens for readability and consistency

**Q: What's the max branch name length?**  
A: Git supports up to 255 characters; aim for <80 for readability

**Q: Do I need to delete my branch?**  
A: Yes — `complete-issue.sh` does it automatically, or use the manual commands above. Stale branches should not accumulate.

---

**Version**: 1.0  
**Last Updated**: April 23, 2026  
**Governance**: Rule 5 (Script Writing Guide) + PMO-001 Framework
