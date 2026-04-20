## Severity: HIGH (production deploys silently not deploying)

---

## Finding 1 — deploy.yml `apply` job is truncated — no SSH deployment step (.github/workflows/deploy.yml:100)

### Evidence
The `apply` job in `deploy.yml` ends abruptly:
```yaml
apply:
  runs-on: ubuntu-latest
  needs: [validate, plan]
  steps:
    - uses: actions/checkout@v4
    # ← file ends here — no SSH step, no docker compose step
```

### Risk
**Merges to `main` do not trigger a production redeploy.** The workflow runs, shows green (checkout succeeds), and the deployment step never executes. Every merge since this was implemented has had **zero effect** on the running stack at 192.168.168.31.

This directly violates the "every merge to main MUST trigger production redeploy" non-negotiable.

### Fix — Add SSH deployment step
```yaml
    - name: Deploy to production host
      uses: appleboy/ssh-action@v1.0.3   # pinned version
      with:
        host: ${{ secrets.DEPLOY_HOST }}
        username: akushnir
        key: ${{ secrets.DEPLOY_SSH_KEY }}
        script: |
          set -euo pipefail
          cd ~/code-server-enterprise
          git pull --ff-only origin main
          source scripts/fetch-gsm-secrets.sh
          docker compose up -d --remove-orphans
          bash scripts/ci/healthcheck.sh || { echo "Health check failed"; exit 1; }

    - name: Post deployment verification
      uses: appleboy/ssh-action@v1.0.3
      with:
        host: ${{ secrets.DEPLOY_HOST }}
        username: akushnir
        key: ${{ secrets.DEPLOY_SSH_KEY }}
        script: |
          docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -v Exited
```

---

## Finding 2 — Snyk dependency scanning disabled (security.yml:46)

### Evidence
```yaml
- name: Snyk security scan
  continue-on-error: true   # ← bypasses all findings
  env:
    SNYK_TOKEN: ""           # empty — no authentication
```

### Risk
No dependency vulnerability scanning runs on PRs. The CI shows "passing" while shipping known-CVE packages. Finding J-02 (pip without hashes) and J-03 (no SBOM) compound this gap.

### Fix
Replace with `pnpm audit` which requires no external token:
```yaml
- name: Dependency vulnerability scan
  run: |
    pnpm audit --audit-level=critical --json > artifacts/audit.json || {
      echo "CRITICAL CVEs found in dependencies — failing build"
      cat artifacts/audit.json
      exit 1
    }
```
Remove `continue-on-error: true` from all security jobs.

---

## Finding 3 — No SBOM generation in CI pipeline (security.yml)

No Software Bill of Materials is generated on any build. When new CVEs are disclosed (e.g., log4j-style events), there is no artifact to query "are we affected?"

### Fix
```yaml
- name: Generate SBOM
  uses: anchore/sbom-action@v0.15.1
  with:
    image: ghcr.io/kushin77/session-broker:${{ github.sha }}
    format: cyclonedx-json
    output-file: artifacts/sbom.cyclonedx.json
  
- name: Upload SBOM
  uses: actions/upload-artifact@v4
  with:
    name: sbom-${{ github.sha }}
    path: artifacts/sbom.cyclonedx.json
    retention-days: 365
```

---

## Definition of Done
- [ ] `deploy.yml` apply job actually SSH-deploys to 192.168.168.31
- [ ] `git push` to main triggers visible `docker compose up -d` on the host (verified via `docker events`)
- [ ] Post-deploy health check fails the workflow if any core service is unhealthy
- [ ] Snyk stub replaced with `pnpm audit --audit-level=critical` (no token required)
- [ ] `continue-on-error` removed from all security workflow jobs
- [ ] SBOM generated and uploaded as artifact on every main-branch build
- [ ] Parent #967 updated with evidence

Fixes #967 (EPIC)
