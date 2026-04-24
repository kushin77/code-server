# Figma Design Embed Integration - Implementation Guide

## Overview

This document describes the implementation of the **Figma Design Embed** (Collab-9.4), which enables developers to view, comment on, and iterate on designs directly within the VS Code IDE.

## Features

- ✅ **Design Preview**: View Figma files and components in VS Code sidebar
- ✅ **Real-time Comments**: Add and view comments on designs
- ✅ **Component Browsing**: Navigate components and frames hierarchically
- ✅ **Export Assets**: Download designs as PNG or SVG
- ✅ **Version History**: Track and access design versions
- ✅ **Component Search**: Search design systems across teams
- ✅ **Usage Tracking**: See where components are used in codebase
- ✅ **Team Libraries**: Access shared component libraries
- ✅ **Performance**: Smart caching for faster access

## Architecture

### Components

```
┌──────────────────────────────────────┐
│     VS Code IDE                       │
├──────────────────────────────────────┤
│                                      │
│  ┌────────────────────────────────┐ │
│  │  Figma Embed Panel (React)      │ │
│  │  - File browser                 │ │
│  │  - Design preview               │ │
│  │  - Comment interface            │ │
│  │  - Export buttons               │ │
│  └────────────────────────────────┘ │
│            ↓                         │
│  ┌────────────────────────────────┐ │
│  │  Figma Extension Service        │ │
│  │  - Config management            │ │
│  │  - Event handling               │ │
│  └────────────────────────────────┘ │
│                                      │
└──────────────────────────────────────┘
         ↓                    ↓
┌──────────────────┐  ┌──────────────────┐
│  Backend API     │  │  Figma API       │
│  /api/figma/*    │  │  api.figma.com   │
└──────────────────┘  └──────────────────┘
         ↓
┌──────────────────────────────────────┐
│  FigmaClient Service                 │
│  - File fetching                     │
│  - Component management              │
│  - Export handling                   │
│  - Cache management                  │
└──────────────────────────────────────┘
```

### Data Flow

```
1. User opens VS Code
   ↓
2. Figma extension loads
   ↓
3. Reads Figma token from settings
   ↓
4. Initializes FigmaClient
   ↓
5. Fetches files from Figma API
   ↓
6. Renders file list in sidebar
   ↓
7. User clicks file
   ↓
8. Fetches file details (components, comments)
   ↓
9. Displays design preview and metadata
   ↓
10. User can comment, export, or open in browser
```

## Setup Instructions

### Step 1: Create Figma API Token

1. Go to Figma Settings → Account → Personal access tokens
2. Click "Create a new token"
3. Give it a name (e.g., "VS Code Integration")
4. Copy the token

### Step 2: Configure in VS Code

1. Open Settings (`Ctrl+,` or `Cmd+,`)
2. Search for "Figma"
3. Set:
   - **Token**: Paste your personal access token
   - **Team ID** (optional): For team library access
   - **Default File Key** (optional): Auto-open specific file

### Step 3: Enable Extension

```bash
# Install extension package
cd apps/frontend
npm install

# Enable in VS Code
# Extensions → Figma Design Embed → Enable
```

### Step 4: Configure Workspace (Optional)

Create `.vscode/settings.json`:

```json
{
  "figma.token": "${FIGMA_TOKEN}",
  "figma.teamId": "12345",
  "figma.showNotifications": true,
  "figma.autoPreview": true
}
```

## Usage

### Viewing Designs

1. Open **Figma Designs** panel in Explorer sidebar
2. Browse available files
3. Click file to view components and frames

### Adding Comments

1. Select component or frame
2. Type comment in text field
3. Click "Post Comment"
4. View all comments in list

### Exporting Assets

1. Select component
2. Click "Export as PNG" or "Export as SVG"
3. Choose scale (1x, 2x, etc.)
4. Download starts automatically

### Accessing Full Editor

- Click "Open in Figma" button
- Opens browser for detailed editing

## API Reference

### FigmaClient Methods

| Method | Description |
|--------|-------------|
| `getFile(fileKey)` | Get file metadata and structure |
| `listFiles(teamId)` | List all files in team |
| `getComponents(fileKey)` | Get components from file |
| `getComponentLibrary(teamId)` | Get team library components |
| `getComponentUsage(fileKey)` | Track component usage |
| `exportNode(fileKey, nodeId, scale)` | Export as PNG |
| `exportNodeSVG(fileKey, nodeId)` | Export as SVG |
| `getComments(fileKey)` | Get file comments |
| `postComment(fileKey, message, clientMeta)` | Add comment |
| `deleteComment(fileKey, commentId)` | Delete comment |
| `getVersionHistory(fileKey)` | Get version history |
| `getFileStats(fileKey)` | Get file statistics |
| `searchComponents(teamId, query)` | Search components |

### Configuration Schema

```json
{
  "figma.token": {
    "type": "string",
    "description": "Figma personal access token"
  },
  "figma.teamId": {
    "type": "string",
    "description": "Team ID for library access (optional)"
  },
  "figma.defaultFileKey": {
    "type": "string",
    "description": "File key to auto-open (optional)"
  },
  "figma.showNotifications": {
    "type": "boolean",
    "default": true,
    "description": "Show design update notifications"
  },
  "figma.autoPreview": {
    "type": "boolean",
    "default": false,
    "description": "Auto-preview when file selected"
  },
  "figma.cacheDuration": {
    "type": "number",
    "default": 300000,
    "description": "Cache duration in milliseconds"
  }
}
```

## Security

### Token Management

- **Storage**: VS Code workspace settings (encrypted locally)
- **Transmission**: HTTPS only to Figma API
- **Scope**: Limited to design file access
- **Best Practice**: Never commit token to git

### Data Privacy

- Files not cached to disk
- Comments not logged
- Export URLs are temporary
- Session data cleared on exit

## Performance

### Caching Strategy

1. **File List**: Cached for 5 minutes
2. **File Details**: Cached for 5 minutes
3. **Components**: Cached for 5 minutes
4. **Comments**: Cached for 2 minutes
5. **Cache Invalidation**: Auto on mutations

### Optimization

- Lazy load components on expansion
- Paginate large file lists
- Debounce search queries
- Compress thumbnails
- Stream large exports

## Troubleshooting

### Issue: "Invalid token"

**Solution**: Verify token:
1. Go to Figma → Account → Personal access tokens
2. Check token hasn't expired
3. Regenerate if needed
4. Update in VS Code settings

### Issue: "No files found"

**Solution**: Check:
1. You have access to the Figma workspace
2. Workspace has files/projects
3. Token has API access enabled
4. Try refreshing the file list

### Issue: "Export failed"

**Solution**:
1. Check component is visible
2. Try exporting in browser
3. Verify file permissions
4. Check disk space for download

### Issue: "Comments not loading"

**Solution**:
1. Refresh the file view
2. Check network connectivity
3. Verify token has comment access
4. Try posting a new comment

## Testing

### Manual Testing

```bash
# 1. Install extension
npm run build
code-server --install-extension figma-design-embed.vsix

# 2. Configure token
# Settings → Figma → Enter token

# 3. Open file
# Click file in Figma Designs panel

# 4. Test features
# - Browse components
# - Add comment
# - Export asset
# - View history
```

### Unit Tests

```bash
npm run test apps/backend/src/services/__tests__/figma-client.test.ts
```

## Integration with Development Workflow

### Design-to-Code

1. Designer creates component in Figma
2. Component added to design system library
3. Developer sees in VS Code sidebar
4. Developer references design spec while coding
5. Design and code stay in sync

### Collaboration

1. Developer adds design feedback via comment
2. Designer sees comment in Figma
3. Designer iterates on component
4. Developer sees updated version in VS Code
5. Feedback loop continuous

### Documentation

1. Figma file serves as source of truth for design
2. Comments document design decisions
3. Version history tracks evolution
4. Team has access to context without switching apps

## Future Enhancements

- [ ] Inline design preview in code
- [ ] One-click component generation (e.g., React)
- [ ] Design token sync to codebase
- [ ] Automatic asset export on design change
- [ ] Design-to-UI diff visualization
- [ ] AI-powered design analysis
- [ ] Slack notifications for design updates
- [ ] Analytics on design-code alignment

## Related Issues

- **#1164**: EPIC [Collab-9] GitHub Integration Hub
- **#1165**: [Collab-9.1] Ticket Linking
- **#1166**: [Collab-9.2] Slack Slash Command
- **#1167**: [Collab-9.3] CI/CD Status Sidebar
- **#1169**: [Collab-9.5] Sentry Error Notifications

---

**Implementation Status**: ✅ COMPLETE  
**Last Updated**: 2026-04-20  
**Owner**: Engineering Team
