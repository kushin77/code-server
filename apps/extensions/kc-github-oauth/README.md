# KC GitHub OAuth Integration

User-scoped GitHub OAuth2 authentication for KC IDE. Each user authenticates with their own GitHub account for personalized access to repositories, issues, and pull requests.

## Features

### 🔐 OAuth2 Authentication
- **User-Scoped**: Each user's own GitHub account (not shared)
- **Secure Storage**: Tokens stored in VS Code SecretStorage
- **Session Management**: Auto-refresh and expiration handling
- **Multi-User**: Supports multiple concurrent users on shared infrastructure

### 🔗 GitHub Integration
- **Repository Access**: Clone and open user's repositories
- **Issue Tracking**: View and manage user's GitHub issues
- **Pull Requests**: Review and manage user's PRs
- **GitHub API**: Full API access via user's own token
- **Gist Integration**: Create and manage GitHub Gists

### 👤 User Session
- **Status Bar**: Shows authenticated user
- **Session Info Panel**: View user details, expiration, logout
- **Auto-Session Restore**: Session persists across IDE restarts
- **Session Expiration**: 90-day validity with auto-refresh

## Installation

This extension is pre-installed in KC IDE. Manual installation:

```bash
cd apps/extensions/kc-github-oauth
npm install
npm run build
```

## Usage

### First-Time Authentication

```
Command: KC GitHub: Authenticate
Shortcut: Ctrl+Shift+P (search "GitHub Authenticate")
```

This opens GitHub's authorization page. Approve access and you'll receive a token to paste back into the IDE.

### View Session Status

```
Command: KC GitHub: Show Current Session
```

Opens a panel showing:
- Your GitHub username
- User ID
- Session expiration date
- Status (Active/Expired)
- Logout button

### Open Your Repositories

```
Command: KC GitHub: Open My Repositories
```

Lists and allows cloning of your GitHub repositories.

### Logout

```
Command: KC GitHub: Logout
```

Clears your session from the IDE.

## Configuration

### Environment Variables

Set these for OAuth flow:

```bash
GITHUB_OAUTH_CLIENT_ID=your_github_app_client_id
GITHUB_OAUTH_CLIENT_SECRET=your_github_app_client_secret
GITHUB_OAUTH_REDIRECT_URI=http://localhost:8080/oauth/callback
```

### Scopes

Requested GitHub scopes:
- `repo` — Full repo access
- `user` — User profile data
- `gist` — Gist management
- `workflow` — GitHub Actions workflows

## Security

### Token Storage
- Tokens stored in VS Code **SecretStorage** (OS-level keyring)
- Never logged or exposed in output
- Automatically cleared on logout
- Session-scoped (not shared between users)

### Session Isolation
- Each user's token is completely isolated
- No cross-user access
- Per-user workspace (/home/${USER}/...)
- Secure SSH transport between replicas

### HTTPS Only
- OAuth callback requires HTTPS (production)
- No token transmission over unencrypted channels
- PKCE flow (planned) for enhanced security

## Architecture

- `src/extension.ts` (430 LOC) — Main extension logic
  - OAuth2 flow handling
  - Session management
  - GitHub API integration
  - Status bar UI

- `package.json` — Extension metadata
- `tsconfig.json` — TypeScript config
- `README.md` — Documentation

## Integration Points

### With Phase 1 (KC Branding)
- Status bar shows GitHub session
- Integrates seamlessly with branding
- User isolation preserved

### With Phase 2 (Extension Pack)
- Works with GitHub Copilot, GitHub PRs
- Shares OAuth session across extensions
- Unified GitHub auth

### With docker-compose
```yaml
environment:
  - GITHUB_OAUTH_CLIENT_ID=...
  - GITHUB_OAUTH_CLIENT_SECRET=...
  - GITHUB_OAUTH_REDIRECT_URI=...
```

## Governance

- ✅ IaC: All code version-controlled
- ✅ Immutable: Configuration via env vars
- ✅ Idempotent: Session can be re-established safely
- ✅ GOV-002: Metadata headers present
- ✅ No hardcodes: All OAuth secrets via env vars
- ✅ Linux-native: No Windows/PowerShell artifacts

## Related

- **Phase 1**: KC Branding Extension (complete)
- **Phase 2**: Extension Pack (complete)
- **Phase 3**: GitHub OAuth (current)
- **EPIC**: #1539 (IDE Intelligence & Developer OS)

## License

MIT
