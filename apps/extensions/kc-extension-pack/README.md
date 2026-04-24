# KC IDE Extension Pack

Essential VS Code extensions bundled for KC IDE development and collaboration.

## Features

### 📦 What's Included

**18+ Pre-Selected Extensions**:

#### Version Control & Git (3)
- **GitLens** — Advanced Git integration
- **GitHub Pull Requests** — Issue/PR management
- **GitHub Theme** — Official GitHub branding

#### AI & Copilot (2)
- **GitHub Copilot** — AI-powered code completion
- **Copilot Chat** — Conversational AI assistance

#### Remote Development (5)
- **Remote SSH** — Connect to remote machines
- **Remote SSH: Editing Config Files** — SSH config support
- **Live Share** — Real-time code collaboration
- **Live Share Audio** — Voice chat during collaboration
- **Live Share Extension Pack** — Enhanced collaboration features

#### Code Quality (2)
- **Prettier** — Code formatter
- **ESLint** — JavaScript/TypeScript linter

#### Infrastructure (3)
- **Docker** — Container management
- **Terraform** — Infrastructure as Code
- **Makefile Tools** — Build automation

#### Data & Utilities (3+)
- **JSON Editor** — Advanced JSON support
- **Even Better TOML** — TOML language
- **Object Viewer** — Visual inspection tools
- **Serial Port Monitor** — Serial communication

## Installation

This extension pack is automatically installed in KC IDE. Manual installation:

```bash
cd apps/extensions/kc-extension-pack
npm install
npm run build
```

## Usage

### First Time Setup
- Extension pack activates automatically on startup
- Welcome message shows confirmation
- Click "Learn More" to view documentation

### Access Documentation
```
Command: KC IDE: Open Extension Pack Documentation
Shortcut: Ctrl+Shift+P (search "Extension Pack")
```

### Managing Individual Extensions

View all installed extensions:
```
Shortcut: Ctrl+Shift+X
```

Disable/enable extensions as needed for your workflow.

## Configuration

### GitHub Copilot
Requires GitHub account sign-in:
1. Open Extensions (Ctrl+Shift+X)
2. Find GitHub Copilot
3. Click "Sign In"

### ESLint & Prettier
Configure via `.vscode/settings.json`:

```json
{
  "eslint.enable": true,
  "eslint.validate": ["javascript", "typescript"],
  "editor.defaultFormatter": "esbenp.prettier-vscode",
  "editor.formatOnSave": true
}
```

### Remote SSH
Configure SSH hosts in `~/.ssh/config`:

```
Host my-server
  HostName 192.168.168.31
  User akushnir
  IdentityFile ~/.ssh/id_rsa
```

Then connect via:
```
Remote-SSH: Connect to Host (Ctrl+Shift+P)
```

### Live Share
Enable collaboration:

```
Live Share: Start Collaboration Session (Ctrl+Shift+P)
```

Share the session link with teammates to collaborate.

## Customization

### Adding More Extensions

Edit `package.json` `extensionPack` array:

```json
{
  "extensionPack": [
    "publisher.extension-id",
    "..." 
  ]
}
```

Rebuild and redeploy.

### Removing Extensions

Remove from `extensionPack` array in `package.json` and rebuild.

## Architecture

- `src/extension.ts` — Onboarding and documentation (240 LOC)
- `package.json` — Extension metadata with 18+ dependencies
- `tsconfig.json` — TypeScript configuration

## Governance

- ✅ IaC: All code version-controlled
- ✅ Immutable: Extension list immutable via package.json
- ✅ Idempotent: Safe to reinstall
- ✅ GOV-002: Metadata headers present
- ✅ No hardcodes: All configuration via package.json

## Related

- **Phase 1**: KC Branding Extension (complete)
- **Phase 2**: This extension pack (current)
- **Phase 3**: GitHub OAuth integration (upcoming)
- **EPIC**: #1539 (IDE Intelligence & Developer OS)

## License

MIT
