# Enterprise IDE Policy Pack

**Version:** 1.0.0  
**Date:** 2026-04-18  
**Scope:** All code-server users on kushnir.cloud  
**Owner:** Platform Engineering  

---

## Philosophy

> "Enterprise baseline, user customization respected"

All developers share a common ergonomic and security baseline. Within that baseline, users retain full control over personal preferences that do not affect repository hygiene, security, or team consistency.

---

## Policy Tiers

| Tier | Setting Type | Enforcement | User Can Override? | Example |
|------|-------------|-------------|-------------------|---------|
| **T1** | Safety-critical, governance, audit | Immutable at deploy; merged first | ❌ Hard enforcement | `editor.formatOnSave`, `files.exclude`, `telemetry.telemetryLevel` |
| **T2** | Best-practice recommendations | Merged additively; user keys win | ✅ Yes (discouraged) | `editor.minimap.enabled`, `workbench.colorTheme` |
| **T3** | Convenience, performance tuning | Seeded once; never overwritten | ✅ Yes (primary) | window chrome, font size |

---

## Merge Strategy

Settings are loaded via the entrypoint merge script:

```
Enterprise Defaults (config/code-server/settings.json)
         ↓
   [Additive Deep Merge — enterprise T1 keys always win]
         ↓
User Settings (~/.local/share/code-server/User/settings.json)
         ↓
Final Active Settings (T2/T3 user keys win on conflict)
```

---

## Change Log

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-04-18 | Platform Engineering | Initial enterprise policy pack |

---

## Key Policies

### Formatting (T1 — Immutable)
- `editor.formatOnSave: true` — formats every file on save
- `files.trimTrailingWhitespace: true` — eliminates whitespace noise in diffs
- `files.insertFinalNewline: true` — POSIX compliance, prevents diff churn
- `files.trimFinalNewlines: true` — prevents blank lines at EOF

### Security (T1 — Immutable)
- `telemetry.telemetryLevel: off` — no telemetry to Microsoft
- `extensions.autoUpdate: false` — extensions pinned per manifest
- `update.mode: none` — IDE version managed by IaC, not auto-update

### Git Hygiene (T1 — Immutable)
- `git.branchProtection: [main, master]` — prevents direct commits
- `git.branchProtectionPrompt: alwaysCommitToNewBranch` — guides issue workflow
- `git.allowForcePush: false` — protects history
- `git.enableSmartCommit: false` — prevents accidental multi-file commits

### File Visibility (T1 — Immutable)
Generated artifacts, caches, and build output are hidden from the file explorer and search to reduce noise. See the `files.exclude` and `search.exclude` blocks in `settings.json`.

---

## Extension Policy
See [`extensions/EXTENSIONS-POLICY.md`](extensions/EXTENSIONS-POLICY.md) for the full extension curation rationale.

---

## Related Issues
- #618 — Enterprise default VS Code policy pack
- #616 — Extension policy
- #615 — Git hygiene defaults
- #614 — Formatting defaults
- #617 — Copilot usage policy
- #624 — Issue-centric IDE defaults
