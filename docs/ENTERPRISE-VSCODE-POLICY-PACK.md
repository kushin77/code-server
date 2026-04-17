# Enterprise VS Code Policy Pack

**Version**: 1.0 (April 17, 2026)  
**Status**: ACTIVE - Enforced at Startup  
**Owner**: Enterprise Platform  
**Last Updated**: April 17, 2026

---

## Overview

This policy pack defines enterprise-standard VS Code settings for all developers working with the code-server environment. Settings are organized into three tiers:

- **Tier 1 (Immutable)**: Core productivity & security rules that cannot be overridden
- **Tier 2 (Default + Override)**: Enterprise defaults with user override allowed
- **Tier 3 (User Choice)**: Recommendations only; users decide

The policy pack is merged additively at startup - user customizations are never overwritten.

---

## Tier System

### Tier 1: Immutable (Non-Override)

These settings are locked and cannot be modified by users. They enforce enterprise standards that are non-negotiable.

| Setting | Value | Reason | Category |
|---|---|---|---|
| `git.ignoreLimitWarning` | `true` | Suppress .gitignore warnings in large repos | Git Hygiene |
| `git.checkoutType` | `local` | Always check out local branches | Git Safety |
| `git.requireGitUserConfig` | `true` | Force git user.name/email config | Git Identity |
| `scm.defaultViewMode` | `list` | Show commits in list format | Developer UX |
| `editor.trimAutoWhitespace` | `true` | Auto-trim trailing whitespace on save | Code Hygiene |
| `editor.insertSpaces` | `true` | Use spaces instead of tabs | Code Standards |
| `editor.tabSize` | `2` | 2-space indentation | Code Standards |
| `files.trimTrailingWhitespace` | `true` | Trim trailing whitespace | Code Hygiene |
| `files.insertFinalNewline` | `true` | Ensure newline at EOF | Code Hygiene |
| `files.trimFinalNewlines` | `true` | Remove extra blank lines at EOF | Code Hygiene |
| `explorer.confirmDelete` | `true` | Confirm before deleting files | Safety |
| `explorer.confirmDragAndDrop` | `true` | Confirm before drag-drop operations | Safety |
| `security.workspace.trust.enabled` | `true` | Require workspace trust for auth | Security |
| `extensions.autoCheckUpdates` | `false` | Don't auto-check for updates | Stability |
| `telemetry.telemetryLevel` | `off` | Disable all telemetry | Privacy |
| `error.diagnose` | `false` | Disable diagnostic reporting | Privacy |
| `githubPullRequests.autoMerge` | `false` | Never auto-merge PRs | Safety |
| `git.showPushSuccessNotification` | `true` | Show push success confirmation | Developer UX |

### Tier 2: Default + Override (User Can Change)

These settings are pre-configured as enterprise defaults but users can modify them if needed.

| Setting | Default Value | Reason | Category |
|---|---|---|---|
| `editor.formatOnSave` | `true` | Auto-format on file save | Code Quality |
| `editor.formatOnPaste` | `true` | Auto-format on paste | Code Quality |
| `editor.codeActionsOnSave` | `{ "source.fixAll": "explicit" }` | Auto-fix linter issues | Code Quality |
| `editor.defaultFormatter` | `esbenp.prettier-vscode` | Use Prettier for formatting | Code Quality |
| `[markdown].editor.defaultFormatter` | `esbenp.prettier-vscode` | Markdown formatting | Code Quality |
| `[json].editor.defaultFormatter` | `esbenp.prettier-vscode` | JSON formatting | Code Quality |
| `editor.suggest.localityBonus` | `true` | Prefer close symbols in autocomplete | Developer UX |
| `editor.wordBasedSuggestions` | `true` | Include word-based suggestions | Developer UX |
| `editor.wordWrap` | `on` | Wrap long lines | Visual Preference |
| `editor.minimap.enabled` | `true` | Show minimap | Visual Preference |
| `editor.bracketPairColorization.enabled` | `true` | Color-code bracket pairs | Visual Preference |
| `editor.guides.bracketPairs` | `true` | Show bracket pair guides | Visual Preference |
| `workbench.editor.tabCloseButton` | `left` | Close button on left of tabs | Visual Preference |
| `workbench.sideBar.location` | `left` | Sidebar on left | Visual Preference |
| `explorer.excludeGitIgnore` | `true` | Hide .gitignore'd files from explorer | Visual Hygiene |
| `search.exclude` | `{ "**/node_modules": true, "**/.git": true }` | Exclude common dirs from search | Performance |
| `files.watcherExclude` | `{ "**/node_modules/**": true }` | Don't watch node_modules | Performance |
| `editor.fontLigatures` | `true` | Enable font ligatures | Visual Preference |
| `editor.scrollBeyondLastLine` | `false` | Don't scroll past EOF | Visual Preference |
| `git.confirmSync` | `true` | Confirm before sync | Safety |
| `git.pushTags` | `true` | Include tags in push | Git Standard |

### Tier 3: Recommendations (User Decides)

These are best-practice recommendations but users decide whether to adopt them.

| Setting | Recommended Value | Reason | Category |
|---|---|---|---|
| `editor.theme` | `Default Dark Modern` | Professional appearance | Aesthetic |
| `editor.fontSize` | `13` | Readable size for 1080p+ | Accessibility |
| `editor.lineHeight` | `1.6` | Comfortable line spacing | Accessibility |
| `editor.renderWhitespace` | `selection` | Show whitespace only in selection | Visual Aid |
| `extensions.ignoreRecommendations` | `false` | See extension recommendations | Developer UX |
| `files.autoSave` | `afterDelay` | Auto-save after 2s of inactivity | Developer Experience |
| `files.autoSaveDelay` | `2000` | Auto-save delay in ms | Developer Experience |
| `window.zoomLevel` | `0` | No zoom by default | Accessibility |
| `debug.inlineValues` | `auto` | Show variable values inline in debugger | Debugging |
| `github.copilot.enable` | `{ "*": true }` | Enable Copilot in all languages | AI Integration |

---

## Extension Policy

### Tier 1: Required Extensions (Auto-Installed)

These extensions are automatically installed and enabled. Users cannot disable them.

| Extension ID | Name | Reason |
|---|---|---|
| `ms-vscode.cpptools` | C++ Tools | Multi-language support |
| `esbenp.prettier-vscode` | Prettier | Code formatting standard |
| `dbaeumer.vscode-eslint` | ESLint | JavaScript linting |
| `rust-lang.rust-analyzer` | Rust Analyzer | Rust support |
| `golang.go` | Go | Go support |
| `ms-python.python` | Python | Python support |
| `hashicorp.terraform` | Terraform | IaC support |
| `ms-azuretools.vscode-docker` | Docker | Container support |
| `github.copilot` | GitHub Copilot | AI coding assistant |
| `github.github-vscode-theme` | GitHub Theme | Enterprise color scheme |
| `ms-vscode.remote-explorer` | Remote Explorer | Remote SSH support |
| `eamodio.gitlens` | GitLens | Enhanced Git capabilities |

### Tier 2: Recommended Extensions (Optional)

Users can choose to install these recommended extensions.

| Extension ID | Name | Category |
|---|---|---|
| `ms-vscode-remote.remote-ssh` | Remote - SSH | Remote Development |
| `ms-vscode-remote.vscode-remote-extensionpack` | Remote Development | Remote Development |
| `github.vscode-pull-request-github` | GitHub Pull Requests | Version Control |
| `ms-vscode.makefile-tools` | Makefile Tools | Build Tools |
| `ms-vscode.cmake-tools` | CMake Tools | Build Tools |

---

## Keybindings Policy

### Immutable Keybindings (Tier 1)

| Command | Keybinding | Reason |
|---|---|---|
| `git.commit` | `Ctrl+Shift+G C` | Standardized Git flow |
| `git.pull` | `Ctrl+Shift+G P` | Standardized Git flow |
| `git.push` | `Ctrl+Shift+G U` | Standardized Git flow |
| `editor.action.formatDocument` | `Shift+Alt+F` | Standard format shortcut |
| `editor.action.autoFix` | `Ctrl+.` | Quick fix standard |

---

## Implementation Checklist

### AC1: Tier System Definition
- [x] Tier 1 (18 immutable settings) documented
- [x] Tier 2 (20 default+override settings) documented
- [x] Tier 3 (10 recommendation settings) documented
- [x] Extension policy (12 required, 5 recommended) documented

### AC2: Policy Pack Structure
- [x] Created code-server policy pack structure
- [x] settings.json template for T1+T2 defaults
- [x] extensions-whitelist.json for allowed extensions
- [x] keybindings.json for standard keybindings
- [x] POLICY-PACK-README.md for user documentation

### AC3: Settings Documentation
- [x] Each setting includes: name, value, reason, category
- [x] Tier assignments clear (T1/T2/T3)
- [x] Override behavior documented (yes/no)
- [x] User guidance for T2 overrides

### AC4: Changelog & Versioning
- [x] Version 1.0 baseline established
- [x] Changelog structure created
- [x] Policy pack versioning scheme defined

### AC5: Conflict Detection
- [x] Duplicate setting checks documented
- [x] Conflicting extension combinations identified
- [x] Resolution strategy for user overrides

### AC6: CI Validation (Phase 2)
- [ ] CI check that policy JSON is valid
- [ ] CI check that settings don't conflict
- [ ] CI check that required extensions are available

### AC7: Migration Guide (Phase 2)
- [ ] User communication about policy merge
- [ ] Verification guide (check logs)
- [ ] FAQ for common questions

### AC8: Validation on 192.168.168.31 (Phase 2)
- [ ] Startup test without merge errors
- [ ] State preservation verification
- [ ] Settings merge validation in logs

---

## Policy Merge Behavior

### Startup Sequence

```
1. VS Code starts with clean code-server image
2. code-server-entrypoint.sh runs
3. Load enterprise defaults (Tier 1 + Tier 2):
   - Read /default-settings.json
   - Merge into user's settings.json (additive)
4. Load user customizations:
   - Read ~/.local/share/code-server/User/settings.json
   - Merge over defaults (user overrides T2, not T1)
5. Load installed extensions:
   - Verify required extensions installed
   - Log any skipped optional extensions
6. Initialize Git configuration:
   - Require git.user.name and git.user.email
7. Start VS Code server
```

### User Override Rules

| Tier | Override Allowed | Behavior |
|---|---|---|
| **T1 (Immutable)** | ❌ NO | Setting is ignored if user tries to change |
| **T2 (Default+Override)** | ✅ YES | User value takes precedence |
| **T3 (Recommendation)** | ✅ YES | User value taken as-is |

### Extension Merge Behavior

| Extension Type | Install | Disable | Reason |
|---|---|---|---|
| **Required (T1)** | ✅ Force | ❌ Cannot | Core functionality |
| **Recommended (T2)** | 💡 Suggest | ✅ Optional | Best practices |

---

## Governance & Updates

### Policy Review Cycle

- **Monthly**: Review policy violations and user feedback
- **Quarterly**: Evaluate new Tier 1/T2 candidates
- **Annually**: Full policy audit and versioning

### Amendment Process

1. **Propose** new setting via GitHub issue
2. **Discuss** tier assignment and rationale
3. **Vote** (infrastructure team: 3 of 5 required)
4. **Document** in CHANGELOG.md with version bump
5. **Release** in next code-server image build
6. **Communicate** to all users

### Deprecation Process

Settings can be deprecated with 90-day notice:
1. Document in CHANGELOG.md
2. Mark as `[DEPRECATED]` in settings.json
3. Announce in team documentation
4. Remove in next major release

---

## Migration Guide (Phase 2)

### For New Users

Policy pack applies automatically at first startup. No action needed.

### For Existing Users

When updating code-server:
1. Enterprise defaults are merged (non-destructive)
2. Your custom settings are preserved
3. Logs show `[entrypoint] Merged enterprise defaults` on startup
4. Verify by running: `code --list-extensions | wc -l`

### Testing Your Setup

```bash
# Verify policy pack applied
grep "Merged enterprise defaults" ~/.local/share/code-server/logs/*.log

# Check active settings
code --print-config | jq '.editor.formatOnSave'

# List all installed extensions
code --list-extensions
```

---

## Related Documentation

- [SCRIPT-WRITING-GUIDE.md](../docs/SCRIPT-WRITING-GUIDE.md) — How to update policy
- [DEDUPLICATION-POLICY.md](../docs/DEDUPLICATION-POLICY.md) — Avoid duplicate settings
- [README.md](../README.md) — Quick start guide

---

## FAQ

**Q: Can I change a Tier 1 setting?**  
A: No. Tier 1 settings are locked and required for enterprise compliance. If you have a specific use case, please file an issue.

**Q: Will my existing VS Code settings be lost?**  
A: No. The policy pack merges additively - your settings are preserved and take precedence over Tier 2 defaults.

**Q: How do I disable a recommended extension?**  
A: In Extensions view, click the extension and select "Disable". Your choice persists across restarts.

**Q: What if I need to override a Tier 1 setting?**  
A: File an issue explaining your use case. Infrastructure team reviews quarterly and may reclassify to Tier 2 if justified.

**Q: How often does the policy pack update?**  
A: Major updates quarterly (with 90-day deprecation notice), minor updates monthly.

---

**Last Updated**: April 17, 2026  
**Next Review**: May 17, 2026  
**Status**: ACTIVE in production
