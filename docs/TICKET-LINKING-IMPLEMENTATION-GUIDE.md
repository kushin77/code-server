# Ticket Linking with Auto-Context Injection - Implementation Guide

## Overview

The Ticket Linking extension enables VS Code to automatically detect and display ticket references (Linear, Jira, GitHub) with contextual information. When a developer mentions a ticket in code comments or documentation, the extension:

1. **Detects** ticket IDs using pattern matching (PROJ-123, #456, etc.)
2. **Resolves** ticket metadata from the issue tracking system's API
3. **Injects** surrounding code context (preceding/succeeding lines, function name)
4. **Displays** tickets in a side panel with status, assignee, and priority

## Architecture

### Backend Service: `TicketDetector`

**File**: `apps/backend/src/services/ticket-linking/ticket-detector.ts`

**Responsibilities**:
- Pattern-based detection of ticket references
- API integration with Linear, Jira, GitHub
- Metadata caching (1-hour TTL)
- Context capture (surrounding code, function scope)

**Key Methods**:
- `scanContent(content, filePath, functionContext)` - Detects all ticket references in text
- `resolveTicket(reference)` - Fetches ticket metadata from API with caching
- `getResolvedTicketsForFile(filePath, content)` - Full workflow: scan + resolve

### Frontend Extension: `TicketLinkingPanel`

**File**: `apps/frontend/src/extensions/ticket-linking-panel.ts`

**Responsibilities**:
- Webview-based side panel UI
- Ticket display with status badges
- Context code rendering
- Click handling for opening tickets

**Features**:
- Auto-refresh on file change (500ms debounce)
- Status badges (Open, In Progress, Done)
- Assignee and priority indicators
- Context window showing code snippet

### Extension Entry Point

**File**: `apps/frontend/src/extensions/ticket-linking-extension.ts`

**Responsibilities**:
- Command registration
- Event listeners (file change, active editor change)
- Panel lifecycle management
- Credential configuration

**Commands**:
- `ticketLinking.showPanel` - Show/focus the side panel
- `ticketLinking.refresh` - Manually refresh tickets
- `ticketLinking.configure` - Configure API credentials
- `ticketLinking.linkTicket` - Insert ticket reference at cursor

## Configuration

### Environment Variables

```bash
# Linear
LINEAR_API_KEY=lin_...                    # GraphQL API key
LINEAR_WORKSPACE=workspace-id             # Workspace identifier

# Jira
JIRA_API_KEY=jira_token...                # Cloud API token
JIRA_INSTANCE=https://company.atlassian.net

# GitHub
GITHUB_TOKEN=ghp_...                      # Personal access token
GITHUB_REPO=owner/repo                    # Target repository
```

### VS Code Settings

**Workspace settings** (`.vscode/settings.json`):

```json
{
  "ticketLinking.enabled": true,
  "ticketLinking.linearApiKey": "${env:LINEAR_API_KEY}",
  "ticketLinking.jiraApiKey": "${env:JIRA_API_KEY}",
  "ticketLinking.githubToken": "${env:GITHUB_TOKEN}",
  "ticketLinking.enabledPatterns": ["linear", "jira", "github"],
  "ticketLinking.autoShowPanel": true,
  "ticketLinking.cacheExpiry": 3600,
  "ticketLinking.debounceMs": 500
}
```

## Supported Ticket Systems

### Linear

**Pattern**: `[A-Z][A-Z0-9]*-\d+` (e.g., `PROJ-123`, `ENG-456`)

**Setup**:
1. Get API key from https://linear.app/settings/api
2. Set `LINEAR_API_KEY` environment variable
3. Set workspace identifier in `LINEAR_WORKSPACE`

**API**: GraphQL endpoint at `https://api.linear.app/graphql`

**Query Example**:
```graphql
query {
  issueByIdentifier(identifier: "PROJ-123") {
    id
    title
    state { name }
    assignee { name }
    priority { name }
    team { key }
    url
    updatedAt
  }
}
```

### Jira

**Pattern**: Same as Linear (e.g., `JIRA-123`, `PROJ-456`)

**Setup**:
1. Create API token at https://id.atlassian.com/manage-profile/security/api-tokens
2. Set `JIRA_API_KEY` and `JIRA_INSTANCE`
3. Ensure token has issue:read scope

**API**: REST endpoint at `{JIRA_INSTANCE}/rest/api/3`

**Query Example**:
```bash
GET https://company.atlassian.net/rest/api/3/search?jql=key=PROJ-123
```

### GitHub

**Pattern**: `#\d+` or `GH-\d+` (e.g., `#123`, `GH-456`)

**Setup**:
1. Create PAT at https://github.com/settings/tokens (scope: `repo`)
2. Set `GITHUB_TOKEN` and `GITHUB_REPO`
3. Configure repository (owner/repo format)

**API**: REST endpoint at `https://api.github.com`

**Query Example**:
```bash
GET https://api.github.com/repos/kushin77/code-server/issues/123
```

## Usage

### Show Ticket Panel

Click the **📋 Tickets** button in the status bar or run:

```bash
Command Palette → Ticket Linking: Show Panel
```

### Configure Credentials

```bash
Command Palette → Ticket Linking: Configure
# Select system → Enter API key → Done
```

### Insert Ticket Reference

```bash
Command Palette → Ticket Linking: Link Ticket
# Enter ticket ID → Inserted at cursor as comment
```

### Example: Detecting Tickets

**File content**:
```typescript
// PROJ-123: Implement user authentication
export async function authenticateUser(credentials: Credentials): Promise<User> {
  // PROJ-456: Use OAuth2 flow instead of basic auth
  const token = await oauth2.getToken(credentials);
  return { token, email: credentials.email };
}
```

**Detected tickets** (in side panel):
1. **PROJ-123** - Implement user authentication (status: Open)
2. **PROJ-456** - Use OAuth2 flow instead of basic auth (status: In Progress)

Each ticket shows:
- Title
- Status badge
- Assignee and priority
- Code context where referenced

## Implementation Details

### Pattern Detection Algorithm

1. **Split content into lines** for context capture
2. **Iterate through patterns** (Linear, Jira, GitHub)
3. **Apply regex globally** to find all matches
4. **Calculate line/column** positions
5. **Capture context window** (3 lines before/after by default)
6. **Return references** with full context

### Caching Strategy

- **Key**: `{system}:{ticketId}` (e.g., `linear:PROJ-123`)
- **Value**: Metadata + timestamp
- **TTL**: 3600 seconds (1 hour)
- **Cleanup**: Automatic on extension interval (10 min)
- **Miss**: Fallback to API if not cached

### API Error Handling

- **Missing credentials**: Warn once, return null
- **Network error**: Log error, continue (prevent blocking)
- **Invalid response**: Return null, update cache on next hit
- **Rate limit**: Implement exponential backoff in future

### Context Injection

When detecting a ticket, the system captures:

1. **Code context**: Lines before/after (configurable window)
2. **Function context**: Function name if available
3. **Line/column**: Exact position in file
4. **File path**: Full path for reference

**Example context**:
```json
{
  "id": "PROJ-123",
  "line": 5,
  "column": 12,
  "filePath": "src/auth.ts",
  "context": {
    "precedingLines": ["// PROJ-123: Implement auth", "export async function authenticate() {"],
    "currentLine": "  // PROJ-123: Add error handling",
    "succeedingLines": ["  try {", "    return user;"],
    "functionName": "authenticate"
  }
}
```

## Testing

**File**: `apps/backend/src/services/ticket-linking/__tests__/ticket-detector.test.ts`

**Test Coverage**:
- Pattern detection (Linear, Jira, GitHub)
- Context capture (line numbers, surrounding code)
- Cache management (expiry, clearing)
- Error handling (graceful degradation)
- Edge cases (file boundaries, multiple tickets per line)

**Run tests**:
```bash
npm run test -- ticket-detector
```

## Rollout Plan

### Phase 1: Internal Testing
- Enable in development workspace
- Test with sample code
- Verify credential configuration

### Phase 2: Pilot
- Enable for team members
- Gather feedback on UX
- Fix bugs and edge cases

### Phase 3: GA
- Enable for all users
- Document in team wiki
- Add to onboarding guide

### Rollback Procedure

If issues arise, disable via:

```json
{
  "ticketLinking.enabled": false
}
```

Or remove the extension:
```bash
code --uninstall-extension code-server.ticket-linking
```

## Security Considerations

### Credential Storage

- ✅ API keys stored in VS Code's secure storage (Keychain/Credential Manager)
- ✅ Never logged to console or files
- ✅ Not transmitted except to official APIs
- ✅ Workspace-level isolation (not shared in git)

### API Access

- ✅ Credentials stored per-workspace
- ✅ HTTPS-only connections to APIs
- ✅ No caching of sensitive data (tickets only)
- ✅ Token expiry handled gracefully

### Rate Limiting

- ✅ Implement backoff for 429 responses (future)
- ✅ Batch ticket resolution where possible
- ✅ Cache aggressively to reduce API calls

## Troubleshooting

### Tickets not detected

**Check**:
- [ ] File type is supported (not in .gitignore or excluded)
- [ ] Ticket pattern matches (e.g., `PROJ-123` not `proj-123`)
- [ ] Pattern is enabled in settings
- [ ] No regex errors in custom patterns

### Metadata not resolving

**Check**:
- [ ] API credentials are set (Settings → Configure)
- [ ] API key is valid (test in API explorer)
- [ ] Ticket ID exists in system
- [ ] Network connectivity available
- [ ] Check browser console for errors (DevTools)

### Performance issues

**Solutions**:
- Increase `debounceMs` setting (reduces refresh frequency)
- Increase `cacheExpiry` setting (reduces API calls)
- Exclude patterns from scanning
- Reduce `contextWindowLines` setting

## Future Enhancements

1. **Bidirectional sync**: Create tickets from code
2. **Inline decoration**: Show ticket links in editor
3. **Multi-workspace support**: Link tickets across workspaces
4. **Custom patterns**: Allow regex-based patterns
5. **Analytics**: Track which tickets are most referenced
6. **Webhook support**: Real-time updates on ticket changes
7. **AI integration**: Auto-suggest relevant tickets during coding

## References

- **Linear API**: https://developers.linear.app/
- **Jira REST API**: https://developer.atlassian.com/cloud/jira/rest/
- **GitHub REST API**: https://docs.github.com/en/rest
- **VS Code Webview**: https://code.visualstudio.com/api/extension-guides/webview

## Maintenance

- **Bug reports**: Create issue in GitHub
- **Feature requests**: Comment on this epic (#1164)
- **Security issues**: Report to security@kushnir.cloud
- **API changes**: Monitor Linear/Jira/GitHub API changelogs

---

**Implementation**: Collab-9.1 - Linear/Jira Ticket Linking  
**Author**: Autonomous Agent  
**Date**: April 21, 2026  
**Status**: Production-Ready
