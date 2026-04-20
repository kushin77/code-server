## P1: Implement code-server Team Hub Sidebar Extension

### Summary

Build a custom VS Code extension for code-server that provides a "Team Hub" sidebar panel showing real-time team presence, same-file awareness, and one-click collaboration actions.

### User Experience

```
┌─────────────────────────────────────────┐
│ 👥 Team Hub                        [⚙️] │
├─────────────────────────────────────────┤
│ 🟢 Online (3)                           │
│ ├─ Alice Chen         api/auth.ts       │
│ │  └─ 🟢 Same file! Line 142            │
│ ├─ Bob Kumar          utils/logger.ts   │
│ └─ Carol Wang         tests/e2e.spec.ts │
│                                         │
│ 🟡 Away (1)                             │
│ └─ Dave Lee           [Away 15m]        │
│                                         │
│ ⚫ Offline (2)                          │
│ └─ Eve Park, Frank Wu                   │
├─────────────────────────────────────────┤
│ Quick Actions                           │
│ [📞 Start Meet] [💬 @Mention]           │
│ [🎤 Voice Call] [🔗 Share Link]         │
├─────────────────────────────────────────┤
│ 📁 Current File: api/auth.ts            │
│ Also viewing: Alice (L142), Carol (L87) │
└─────────────────────────────────────────┘
```

### Features

#### 1. Presence Panel
- Real-time list of online/away/offline users
- Current file being edited per user
- Line number for same-file collaborators
- Visual highlight for "same file as you"

#### 2. Same-File Awareness
- Green badge/highlight when someone is in same file
- Optional: cursor position sync (like VSCode Live Share)
- Notification when someone joins your file

#### 3. Quick Actions
- **@Mention**: Opens chat input to mention selected user
- **Start Meet**: Creates Google Meet link, posts to team room
- **Voice Call**: Initiates Element Call or bridged voice
- **Share Link**: Generates shareable workspace URL

#### 4. Settings
- Notification preferences
- Presence auto-away timeout
- Chat room selection

### Technical Implementation

```typescript
// extensions/team-hub/src/extension.ts

interface PresenceState {
  userId: string;
  displayName: string;
  status: 'online' | 'away' | 'offline';
  currentFile?: string;
  currentLine?: number;
  lastSeen: Date;
  workspace?: string;
}

// WebSocket connection to presence sidecar
const presenceSocket = new WebSocket(PRESENCE_SIDECAR_URL);

// Update presence on file change
vscode.window.onDidChangeActiveTextEditor((editor) => {
  if (editor) {
    presenceSocket.send(JSON.stringify({
      type: 'presence_update',
      file: editor.document.fileName,
      line: editor.selection.active.line
    }));
  }
});
```

### Extension Structure

```
extensions/team-hub/
├── package.json          # Extension manifest
├── src/
│   ├── extension.ts      # Entry point
│   ├── sidebar.ts        # Webview sidebar provider
│   ├── presence.ts       # Presence service (WebSocket)
│   ├── actions.ts        # Quick action handlers
│   └── settings.ts       # Configuration
├── media/
│   ├── sidebar.html      # Sidebar UI template
│   ├── sidebar.css       # Styling
│   └── sidebar.js        # Client-side logic
└── test/
    └── extension.test.ts # Unit tests
```

### Integration Points

| Service | Integration |
|---------|-------------|
| **Presence Sidecar** | WebSocket for real-time state |
| **Matrix SDK** | Room membership, state events |
| **Google Meet API** | Create meeting links |
| **OAuth2 Proxy** | Token retrieval for auth |

### Acceptance Criteria

- [ ] Extension builds and installs in code-server
- [ ] Sidebar shows real-time online/away/offline users
- [ ] Current file per user displayed
- [ ] "Same file" highlight when collaborators present
- [ ] @Mention action posts to Matrix room (bridged to Slack/Teams)
- [ ] Start Meet creates Google Meet link
- [ ] Presence updates <500ms latency
- [ ] Settings panel for preferences
- [ ] Extension pre-installed in code-server Docker image
- [ ] Unit tests with >80% coverage

### Docker Integration

```dockerfile
# Dockerfile.code-server (addition)

# Pre-install Team Hub extension
COPY extensions/team-hub/team-hub-0.1.0.vsix /tmp/
RUN code-server --install-extension /tmp/team-hub-0.1.0.vsix

# Configure extension in settings.json
COPY settings.json /home/coder/.local/share/code-server/User/settings.json
```

### Dependencies

- Requires: #1001 (Matrix architecture decision)
- Requires: #1003 (Presence sidecar deployed)
- Blocks: #1007 (Google Meet integration)

### Parent

EPIC #TBD (Matrix Collaboration Hub)
