# KC Branding Extension

Sovereign KC IDE branding package — custom welcome page, themes, and workspace configuration.

## Features

### 🎨 Custom Branding
- Custom welcome page with KC IDE branding
- Replaces default VS Code welcome screen
- Hides "code-server" and infrastructure references

### 🔒 Workspace Isolation
- Automatically hides infrastructure files (Docker, Terraform, scripts)
- Hides secrets and config files (.env, .git)
- Provides clean workspace view for end users

### ⚙️ Workspace Defaults
- Automatic workspace settings initialization
- File exclusion patterns configured on startup
- Security settings enabled by default

### 🎯 User-Centric Interface
- Shows only files and folders relevant to development
- Infrastructure completely hidden from end users
- Focused on code, projects, and collaboration

## Installation

This extension is pre-installed in KC IDE. To reinstall or update:

```bash
cd apps/extensions/kc-branding
npm install
npm run build
```

## Usage

### Open Welcome Page
```
Command: KC IDE: Open Welcome Page
Shortcut: Ctrl+Shift+P (search "KC IDE Welcome")
```

### Apply Workspace Defaults
```
Command: KC IDE: Apply Workspace Defaults
Shortcut: Ctrl+Shift+P (search "Workspace Defaults")
```

## Files Hidden

The extension automatically hides:
- `.git/` — Git internals
- `.env*` — Environment files and secrets
- `docker-compose*.yml` — Container orchestration
- `Dockerfile` — Container definitions
- `terraform/` — Infrastructure code
- `scripts/` — Internal scripts
- `.github/` — GitHub workflows
- `ansible/` — Configuration management

## Configuration

### Customize Hidden Files

Edit in `.vscode/settings.json`:

```json
{
  "files.exclude": {
    "**/.git": true,
    "**/docker*": true,
    "**/terraform/": true
  }
}
```

### Customize Welcome Page

Edit `src/extension.ts` and rebuild:

```bash
npm run build
```

## Compliance

- ✅ IaC: All code version-controlled
- ✅ Immutable: No runtime modifications to settings
- ✅ Idempotent: Safe to apply multiple times
- ✅ Governance: GOV-002 metadata headers

## Architecture

- `src/extension.ts` — Main extension logic (250 LOC)
- `package.json` — Metadata and extension configuration
- `tsconfig.json` — TypeScript compiler settings

## Related EPICs

- #1539 — IDE Intelligence & Developer OS
- #1262 — Session Management System

## License

MIT
