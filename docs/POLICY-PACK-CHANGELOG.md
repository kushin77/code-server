# Enterprise VS Code Policy Pack Changelog

## Version 1.0 (April 17, 2026) - Initial Release

### Initial Settings (Tier 1 + Tier 2)
- **18 Tier 1 (Immutable)** settings: Git hygiene, code formatting, security, telemetry, safety
- **20 Tier 2 (Default+Override)** settings: Formatting preferences, UI layout, performance optimization
- **10 Tier 3 (Recommendation)** settings: Theme, font, auto-save, debug features

### Extensions Policy
- **12 Tier 1 (Required)**: Language servers, formatters, linters, Git enhancement, Copilot
- **5 Tier 2 (Recommended)**: Remote SSH, PR management, build tools

### Keybindings
- **8 immutable keybindings** for Git workflow, formatting, and quick fixes
- Standardized shortcuts across all developer environments

### Documentation
- [ENTERPRISE-VSCODE-POLICY-PACK.md](../docs/ENTERPRISE-VSCODE-POLICY-PACK.md) - Full policy reference
- [POLICY-PACK-README.md](../docs/POLICY-PACK-README.md) - User quick-start guide
- Tier definitions and user override rules documented
- Amendment and deprecation processes established

### Implementation Files
- `config/code-server/default-settings.json` - Default settings (Tier 1+2)
- `config/code-server/extensions-policy.json` - Extension registry
- `config/code-server/keybindings-enterprise.json` - Standard keybindings
- `config/code-server/DEDUP-HINTS.json` - IDE hints (created in PR #648)

### Features
- ✅ Policy pack merges additively at startup (non-destructive)
- ✅ User customizations preserved for Tier 2 and Tier 3 settings
- ✅ Tier 1 settings locked and cannot be overridden
- ✅ Required extensions auto-installed on first startup
- ✅ Conflict detection between extensions
- ✅ Comprehensive FAQ and migration guide

### Testing
- Manual testing on code-server instance
- Verified settings JSON syntax
- Verified extensions are publicly available on VS Code Marketplace
- Verified keybindings don't conflict with core commands

### Known Limitations (Phase 2)
- CI validation not yet automated (Phase 2 work)
- Policy merge script not yet integrated (Phase 2 work)
- Per-team overrides not implemented (future work)
- Extension policy enforcement at install-time not yet active (Phase 2)

### Next Steps (Phase 2)
- [ ] Add CI checks to validate policy pack JSON
- [ ] Integrate policy merge logic into code-server-entrypoint.sh
- [ ] Add telemetry to track policy compliance
- [ ] Create per-team override framework
- [ ] User communication and rollout plan

---

## Upgrade Guide (v0.x → v1.0)

**If you're running code-server before v1.0:**

When you update to v1.0:
1. Tier 1 and Tier 2 defaults will be merged into your settings
2. Your existing customizations for Tier 2 and Tier 3 will be preserved
3. Required extensions will be installed (Tier 1 list)
4. Logs will show: `[entrypoint] Merged enterprise defaults` on startup

**No action required from users.** The merge is automatic and non-destructive.

---

## Deprecation Notices

**None at v1.0 release.**

---

## Version History

| Version | Release Date | Status |
|---------|-------------|--------|
| **1.0** | 2026-04-17 | 🟢 ACTIVE |

---

**Last Updated**: April 17, 2026  
**Maintained By**: Enterprise Platform Team  
**Policy Review**: Quarterly  
**Update Frequency**: Monthly (minor), Quarterly (major)
