# CI/CD Status Sidebar - Implementation Guide

## Overview

This document describes the implementation of the **CI/CD Status Sidebar** (Collab-9.3), which provides live pipeline visualization directly in VS Code with support for GitHub Actions, GitLab CI, CircleCI, and Buildkite.

## Features

- ✅ **Multi-Provider Support**: GitHub, GitLab, CircleCI, Buildkite
- ✅ **Real-time Status**: Auto-refresh (configurable interval)
- ✅ **Pipeline Hierarchy**: Pipelines → Stages → Jobs
- ✅ **Status Icons**: Visual indicators (✅ ❌ ⏳ ⏱️ 🚫 ⊘)
- ✅ **One-Click Access**: Open pipelines in browser
- ✅ **Branch Tracking**: Auto-detect and filter by current Git branch
- ✅ **Configuration UI**: Built-in settings panel
- ✅ **Error Handling**: Graceful degradation on API failures
- ✅ **Notifications**: Optional notifications for pipeline status changes

## Architecture

### Component Hierarchy

```
┌─────────────────────────────────────────────────────────────────┐
│                    VS Code Sidebar                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  CI/CD Status [↻] [⚙]                                           │
│  ├─ ✅ Build Main (pushed by alice)                             │
│  │  ├─ Build Stage (✅ success)                                 │
│  │  │  ├─ Run tests (✅ 45s)                                    │
│  │  │  └─ Build image (✅ 120s)                                 │
│  │  ├─ Deploy Stage (⏳ running)                                │
│  │  │  ├─ Deploy to staging (⏳ 2m)                             │
│  │  │  └─ Smoke tests (⏱️ pending)                              │
│  │  └─ Metrics (✅ 10s)                                         │
│  │                                                              │
│  ├─ ⏳ Build Develop (pushed by bob)                            │
│  │  └─ Build Stage (⏳ running)                                 │
│  │     └─ Run tests (⏳ 30s)                                    │
│  │                                                              │
│  └─ ✅ Build Feature/auth-flow (3h ago)                         │
│     └─ Build Stage (✅ success)                                 │
│        └─ Run tests (✅ 42s)                                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Request Flow

```
┌──────────────────────────────────┐
│   VS Code Extension Starts        │
├──────────────────────────────────┤
│ 1. Load CICD config from settings │
│ 2. Initialize API client          │
│ 3. Register tree view             │
│ 4. Setup auto-refresh interval    │
│ 5. Watch Git branch changes       │
└──────────────────────────────────┘
         ↓
┌──────────────────────────────────┐
│   Render Tree View                │
├──────────────────────────────────┤
│ 1. Call fetchPipelines()          │
│ 2. Map to tree items              │
│ 3. Sort by creation time          │
│ 4. Display with status icons      │
└──────────────────────────────────┘
         ↓
┌──────────────────────────────────┐
│   User Interaction                │
├──────────────────────────────────┤
│ - Click "Refresh" → fetchPipelines│
│ - Click pipeline → Open in browser│
│ - View details → JSON editor      │
│ - Settings → Config panel         │
└──────────────────────────────────┘
```

### Provider Integration

Each provider uses its native API:

**GitHub Actions API**:
```
GET /repos/{owner}/{repo}/actions/runs?branch=main&per_page=10
```

**GitLab CI API**:
```
GET /projects/{id}/pipelines?ref=main&per_page=10
```

**CircleCI API**:
```
GET /project/github/{owner}/{repo}/pipeline?branch=main
```

**Buildkite API**:
```
GET /organizations/{org}/pipelines/{repo}/builds?branch=main&per_page=10
```

## Setup Instructions

### Step 1: Install the Extension

```bash
# Clone or download the extension
cd apps/frontend

# Build extension
npm run build

# Package as .vsix
npm run package

# Install in code-server
code-server --install-extension cicd-status-sidebar-1.0.0.vsix
```

### Step 2: Configure Provider

#### GitHub

1. Generate Personal Access Token:
   - Go to GitHub Settings → Developer settings → Personal access tokens
   - Create token with `repo` and `read:org` scopes
   - Copy token

2. Configure in VS Code:
   - Open Settings (`Ctrl+,` or `Cmd+,`)
   - Search for "CI/CD"
   - Set:
     - **Provider**: `github`
     - **Token**: `ghp_your_token_here`
     - **Owner**: `kushin77`
     - **Repo**: `code-server`

#### GitLab

1. Generate Personal Access Token:
   - Go to GitLab Settings → Access Tokens
   - Create token with `api` and `read_user` scopes
   - Copy token

2. Configure in VS Code:
   - Set:
     - **Provider**: `gitlab`
     - **Token**: `glpat_your_token_here`
     - **Owner**: `your-org-or-user`
     - **Repo**: `your-project`

#### CircleCI

1. Generate API Token:
   - Go to CircleCI Settings → Personal API Tokens
   - Create new token
   - Copy token

2. Configure in VS Code:
   - Set:
     - **Provider**: `circleci`
     - **Token**: `your-circleci-token`
     - **Owner**: `github-org`
     - **Repo**: `your-project`

#### Buildkite

1. Generate API Token:
   - Go to Buildkite Settings → API Access Tokens
   - Create token with `read_pipelines` scope
   - Copy token

2. Configure in VS Code:
   - Set:
     - **Provider**: `buildkite`
     - **Token**: `your-buildkite-token`
     - **Owner**: `your-organization`
     - **Repo**: `your-pipeline-slug`

### Step 3: Configure Refresh Behavior

In Settings:

```json
{
  "cicd.refreshInterval": 30000,
  "cicd.showNotifications": true,
  "cicd.failureNotificationLevel": "warning",
  "cicd.autoOpenLogs": false
}
```

## Usage

### Viewing Pipelines

1. Open the **Explorer** sidebar in VS Code
2. Look for **CI/CD Status** section
3. Expand to see pipelines for current branch
4. Expand pipelines to see stages and jobs

### Refreshing Status

- Click the **Refresh** button (↻) in the sidebar header
- Or run command: `CI/CD: Refresh CI/CD Status`

### Opening Pipeline Details

- Click on any pipeline to open in browser
- Right-click → "View Pipeline Details" to see JSON

### Configuring Provider

- Click the **Settings** button (⚙) in the sidebar
- Select provider and enter credentials

### Filtering by Branch

- Sidebar automatically filters pipelines for current Git branch
- Switch branches → sidebar updates automatically

## Commands

| Command | Description |
|---------|-------------|
| `cicdStatus.refresh` | Refresh pipeline list |
| `cicdStatus.openPipeline` | Open pipeline in browser |
| `cicdStatus.viewDetails` | View pipeline JSON |
| `cicdStatus.configure` | Open settings |

## Configuration Reference

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `cicd.provider` | string | `github` | CI/CD provider |
| `cicd.token` | string | - | API token (store in workspace settings) |
| `cicd.owner` | string | - | Repository owner/organization |
| `cicd.repo` | string | - | Repository name |
| `cicd.baseUrl` | string | - | Custom API URL (for self-hosted) |
| `cicd.refreshInterval` | number | 30000 | Auto-refresh interval (ms) |
| `cicd.showNotifications` | boolean | true | Show status notifications |
| `cicd.failureNotificationLevel` | string | `warning` | Notification level for failures |
| `cicd.autoOpenLogs` | boolean | false | Auto-open logs for failed jobs |

## Status Icons

| Icon | Meaning |
|------|---------|
| ✅ | Success |
| ❌ | Failed |
| ⏳ | Running |
| ⏱️ | Pending |
| 🚫 | Canceled |
| ⊘ | Skipped |
| ❓ | Unknown |

## API Reference

### CICDStatusSidebarProvider

Main tree data provider for the sidebar.

**Methods**:
- `getTreeItem(element)` - Get VS Code tree item
- `getChildren(element)` - Get child items
- `refresh()` - Refresh tree
- `dispose()` - Cleanup

**Events**:
- `onDidChangeTreeData` - Emitted when tree changes

### Pipeline Interface

```typescript
interface Pipeline {
  id: string;
  name: string;
  status: 'success' | 'failed' | 'running' | 'pending' | 'canceled';
  branch: string;
  commit: string;
  author: string;
  createdAt: number;
  updatedAt: number;
  webUrl: string;
  stages: Stage[];
}
```

### Stage Interface

```typescript
interface Stage {
  id: string;
  name: string;
  status: 'success' | 'failed' | 'running' | 'pending' | 'skipped';
  duration: number;
  startedAt: number;
  finishedAt?: number;
  jobs: Job[];
}
```

### Job Interface

```typescript
interface Job {
  id: string;
  name: string;
  status: 'success' | 'failed' | 'running' | 'pending' | 'skipped';
  duration: number;
  logs?: string;
}
```

## Security Considerations

### Token Storage

- **DO**: Store tokens in workspace settings (`.vscode/settings.json` ignored in `.gitignore`)
- **DON'T**: Commit tokens to version control
- **BEST PRACTICE**: Use environment variables for CI/CD deployments

### API Authentication

- All requests use Bearer token authentication
- Tokens are passed in `Authorization` header
- Never logged or exposed in debug output

### Data Privacy

- Logs are not cached locally
- Session data cleared on extension deactivation
- No telemetry collection

## Troubleshooting

### Issue: "CI/CD Status: Configure CICD_TOKEN in settings"

**Solution**: Add token to workspace settings:
```json
{
  "cicd.token": "your-token-here",
  "cicd.owner": "kushin77",
  "cicd.repo": "code-server"
}
```

### Issue: "Failed to fetch CI/CD pipelines: Request timeout"

**Solution**: Check if:
1. Provider URL is correct: `cicd.baseUrl`
2. Network connectivity is available
3. Token has required scopes
4. API rate limits not exceeded

**Increase timeout** (if needed):
- Edit extension source and rebuild
- Default timeout: 5000ms

### Issue: No pipelines showing

**Solution**: Verify:
1. Repository has pipelines configured
2. Current Git branch has pipelines
3. Token has sufficient permissions
4. Owner/repo are correct

**Debug**:
```bash
# Test GitHub API manually
curl -H "Authorization: token YOUR_TOKEN" \
  https://api.github.com/repos/kushin77/code-server/actions/runs?branch=main
```

### Issue: Icons show as weird characters

**Solution**: VS Code may need font update
- Check terminal font supports Unicode
- Try Noto Sans Mono or Fira Code

### Issue: Auto-refresh not working

**Solution**: Check settings:
```json
{
  "cicd.refreshInterval": 30000
}
```

Minimum value: 10000ms (10 seconds)

## Testing

### Manual Testing

```bash
# 1. Install extension in code-server
code-server --install-extension cicd-status-sidebar-1.0.0.vsix

# 2. Open code-server and configure provider
# Settings → CI/CD → Enter token and repo info

# 3. View CI/CD Status sidebar
# Should show pipelines for current branch

# 4. Test refresh
# Click refresh button → pipelines update

# 5. Test browser link
# Click on pipeline → opens in browser
```

### Unit Tests

```bash
npm run test
```

Coverage:
- ✅ Configuration loading
- ✅ Provider API mapping
- ✅ Tree data rendering
- ✅ Status normalization
- ✅ Auto-refresh mechanism
- ✅ Branch tracking
- ✅ Command execution
- ✅ Error handling

## Performance

### Optimization Techniques

1. **Caching**: Recent pipelines cached for 30s
2. **Pagination**: Fetch only 10 latest pipelines
3. **Debouncing**: Auto-refresh debounced at 30s intervals
4. **Filtering**: Filter by branch to reduce API calls
5. **Lazy Loading**: Stages/jobs loaded on expansion

### Metrics

- **API Response Time**: ~200-500ms per request
- **Tree Render Time**: ~50-100ms
- **Memory Usage**: ~5-10MB per provider connection
- **Network**: ~100KB per refresh cycle

## Rollout Plan

### Phase 1: Alpha (Week 1)
- Internal testing with team
- GitHub provider validation
- Configuration flow review

### Phase 2: Beta (Week 2)
- Multi-provider support (GitLab, CircleCI, Buildkite)
- Notification system testing
- Performance optimization

### Phase 3: GA (Week 3)
- All features complete
- Documentation finalized
- Available in extension marketplace

## Future Enhancements

- [ ] Log streaming panel
- [ ] Pipeline templates
- [ ] Webhook integration for real-time updates
- [ ] Analytics dashboard
- [ ] Custom status filters
- [ ] Slack integration for notifications
- [ ] Historical pipeline trends
- [ ] Performance metrics tracking

## Related Issues

- **#1164**: EPIC [Collab-9] GitHub Integration Hub
- **#1165**: [Collab-9.1] Ticket Linking (COMPLETED)
- **#1166**: [Collab-9.2] Slack Slash Command (COMPLETED)
- **#1168**: [Collab-9.4] Figma Design Integration
- **#1169**: [Collab-9.5] Sentry Error Notifications

---

**Implementation Status**: ✅ COMPLETE  
**Last Updated**: 2026-04-20  
**Owner**: Engineering Team
