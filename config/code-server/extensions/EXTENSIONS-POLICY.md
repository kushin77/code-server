# Enterprise Extension Policy

**Version:** 1.0.0  
**Date:** 2026-04-18  
**Scope:** All code-server users on kushnir.cloud  

---

## Extension Tiers

| Tier | Description | Pre-Installed | User Can Uninstall |
|------|-------------|---------------|-------------------|
| **T1-Core** | Governance-critical; required for formatting/AI policy | ✅ Yes | ❌ No |
| **T2-Recommended** | Best-practice; improves developer experience | ❌ No | ✅ Yes |
| **T3-Optional** | User preference; no enterprise opinion | ❌ No | ✅ Yes |
| **Blocked** | Conflicts with architecture, security, or org policy | ❌ No | N/A — install prevented |

---

## Approved Extensions

See [`extensions-approved.json`](extensions-approved.json) for the full versioned allowlist.

### T1-Core (Required)
- **GitHub Copilot** (`GitHub.copilot`) — AI completion, enterprise licensed
- **GitHub Copilot Chat** (`GitHub.copilot-chat`) — AI chat, enterprise licensed
- **Python** (`ms-python.python`) — Python language support
- **Black Formatter** (`ms-python.black-formatter`) — Python T1 formatting
- **Prettier** (`esbenp.prettier-vscode`) — JS/TS/JSON/YAML T1 formatting
- **YAML** (`redhat.vscode-yaml`) — YAML schema validation

### T2-Recommended
- **Terraform** (`hashicorp.terraform`) — IaC editing
- **ShellCheck** (`timonwong.shellcheck`) — Bash linting inline
- **Docker** (`ms-azuretools.vscode-docker`) — Compose/Dockerfile editing
- **GitLens** (`eamodio.gitlens`) — Git history and blame
- **GitHub Actions** (`github.vscode-github-actions`) — Workflow editing

---

## Blocked Extensions

See [`extensions-blocked.json`](extensions-blocked.json) for patterns and alternatives.

**Blocked categories:**
- Remote Development extensions (incompatible with code-server)  
- Duplicate AI completions (conflict with Copilot, upload code externally)
- Cloud provider toolkits not approved for on-prem use

---

## Requesting New Extensions

1. Open a GitHub Issue with label `extension-request`
2. Include: purpose, tier, security review, alternative considered
3. Platform Engineering reviews within 1 sprint
4. Approved extensions added to `extensions-approved.json` via PR

---

## Version Pinning Policy

- T1-Core extensions are version-pinned in `Dockerfile.code-server` and cached at build time
- `extensions.autoUpdate: false` is enforced by T1 `settings.json` policy
- Version bumps require a PR touching `extensions-approved.json` + `Dockerfile.code-server`

---

## Related Issues
- #616 — Extension policy ship
- #618 — Enterprise VS Code policy pack
