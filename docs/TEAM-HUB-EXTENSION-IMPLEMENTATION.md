# Team Hub Extension Implementation Guide

**Purpose**: Team Hub Extension Implementation Guide — reference and operational document.

## Overview

Complete VS Code extension for real-time team collaboration with presence awareness, file tracking, and integrated communication via Matrix.

**Status**: Implementation ready (Phase 1)  
**Version**: 0.1.0  
**Dependencies**: VS Code 1.84+, Matrix homeserver, Presence sidecar

---

## Architecture

### Extension Components

```
team-hub/
├── src/
│   ├── extension.ts              # Extension activation and lifecycle
│   ├── services/
│   │   ├── matrix.ts            # Matrix SDK integration
│   │   ├── presence.ts          # Presence WebSocket management
│   │   ├── meet.ts              # Google Meet API integration
│   │   └── settings.ts          # Configuration management
│   ├── ui/
│   │   ├── sidebar.ts           # Webview sidebar provider
│   │   ├── treeview.ts          # Activity tree view
│   │   └── components/
│   │       ├── UserCard.ts
│   │       ├── FileIndicator.ts
│   │       └── ActionPanel.ts
│   ├── handlers/
│   │   ├── commands.ts          # Command handlers
│   │   ├── events.ts            # Event listeners
│   │   └── matrix-events.ts     # Matrix room events
│   └── utils/
│       ├── auth.ts              # OAuth2 token retrieval
│       ├── formatting.ts        # UI formatting
│       └── logger.ts            # Logging
├── media/
│   ├── sidebar.html             # Webview HTML
│   ├── sidebar.css              # Styling
│   ├── sidebar.js               # Client-side logic
│   └── icons/
│       ├── team-hub-icon.svg
│       ├── online.svg
│       ├── away.svg
│       └── offline.svg
├── test/
│   ├── extension.test.ts
│   ├── services.test.ts
│   ├── handlers.test.ts
│   └── runTest.ts
├── package.json                 # Extension metadata
├── tsconfig.json               # TypeScript config
├── .eslintrc.json              # Linting rules
├── vsc-extension-quickstart.md
└── README.md
```

---

## Service Layer Details

### 1. PresenceService

**File**: `src/services/presence.ts`

Manages real-time user presence updates via WebSocket.

```typescript
export class PresenceService {
  private webSocket: WebSocket;
  private userId: string;
  private currentFile: string;
  private updateInterval: NodeJS.Timer;

  async connect(): Promise<void>
  async disconnect(): Promise<void>
  async updatePresence(data: PresenceData): Promise<void>
  async broadcastPresence(): Promise<void>
  subscribe(callback: PresenceCallback): Disposable
}

interface PresenceData {
  status: 'online' | 'away' | 'offline' | 'editing'
  fileName?: string
  language?: string
  lineNumber?: number
  characterNumber?: number
  timestamp: number
}

interface UserPresence {
  userId: string
  username: string
  displayName: string
  status: string
  fileName?: string
  language?: string
  lastSeen: number
}
```

**Implementation**:
- WebSocket connection to presence sidecar (ws://presence-sidecar:9000)
- Publish user's file/editor state every 5 seconds
- Subscribe to room presence changes
- Cache presence data locally
- Handle reconnection on disconnect
- Emit events when users come online/offline

---

### 2. MatrixService

**File**: `src/services/matrix.ts`

Integrates with Matrix SDK for room membership and messaging.

```typescript
export class MatrixService {
  private client: sdk.MatrixClient;
  private roomId: string;
  private userId: string;

  async connect(): Promise<void>
  async disconnect(): Promise<void>
  async sendMessage(text: string, mentions?: string[]): Promise<void>
  async sendCustomEvent(type: string, content: any): Promise<void>
  subscribe(eventType: string, callback: EventCallback): void
  async getRoomMembers(): Promise<RoomMember[]>
  async createMeetLink(title: string, participants: string[]): Promise<string>
}

interface RoomMember {
  userId: string
  displayName: string
  avatarUrl?: string
  membershipState: 'join' | 'invite' | 'leave'
}
```

**Implementation**:
- Initialize Matrix SDK with homeserver URL from config
- Auto-auth via oauth2-proxy session cookie
- Listen to room member changes
- Handle @mention formatting in messages
- Broadcast file activity as custom events
- Integrate with bridges (Slack, Teams, etc.)

---

### 3. MeetService

**File**: `src/services/meet.ts`

Google Meet API integration for creating video conference links.

```typescript
export class MeetService {
  private accessToken: string;

  async createMeeting(title: string, participants: string[]): Promise<string>
  async addParticipant(meetingLink: string, email: string): Promise<void>
  async generateCalendarEvent(title: string, meetLink: string): Promise<string>
}
```

**Implementation**:
- Retrieve access token from oauth2-proxy
- Call Google Meet API to create conferences
- Generate calendar invites
- Copy meeting link to clipboard
- Post link to Matrix room

---

## UI Layer Details

### Sidebar (Webview)

**File**: `media/sidebar.html`, `media/sidebar.js`

Real-time team presence sidebar with:

```html
<div id="team-presence">
  <!-- User List -->
  <div class="user-section">
    <h3>Online (5)</h3>
    <div class="user-list">
      <!-- Per user: -->
      <div class="user-card online" data-user-id="@alice:matrix.kushnir.cloud">
        <img src="avatar.jpg" class="avatar">
        <div class="user-info">
          <strong>Alice Johnson</strong>
          <span class="status">Editing: main.ts:142</span>
        </div>
        <div class="actions">
          <button class="mention" title="Mention">@</button>
          <button class="go-to-file" title="Go to file">📄</button>
          <button class="start-meet" title="Meet">📹</button>
        </div>
      </div>
    </div>
  </div>

  <!-- Away Users -->
  <div class="user-section">
    <h3>Away (2)</h3>
  </div>

  <!-- Offline Users -->
  <div class="user-section collapsed">
    <h3>Offline (8)</h3>
  </div>
</div>
```

**JavaScript Logic**:
- WebSocket listener for presence updates
- DOM updates for user status changes
- Command execution on button click
- Highlight users editing same file
- Sort by online status and activity

---

## Command Handlers

### 1. Mention User

Posts a message to Matrix room with user mention and context.

```
@alice Please review the changes I made to main.ts around line 142
[Link to line in editor]
```

This message is bridged to Slack/Teams via Matrix bridges.

### 2. Start Google Meet

Creates a Meet conference and invites selected users.

```
Meeting created: https://meet.google.com/xyz-abc-def
Participants: Alice, Bob, Carol
```

Meeting link posted to Matrix room.

### 3. Go to User's File

Opens the file the user is currently editing.

```
Opened: src/services/api.ts (line 45, char 12)
User presence: alice is editing this file
```

---

## WebSocket Presence Protocol

### Connection

```
ws://presence-sidecar:9000
Header: Authorization: Bearer <matrix_token>
Header: User-Id: @username:matrix.kushnir.cloud
```

### Message Format

**Publish (client → sidecar)**:
```json
{
  "type": "presence_update",
  "userId": "@alice:matrix.kushnir.cloud",
  "presence": {
    "status": "editing",
    "fileName": "src/main.ts",
    "language": "typescript",
    "lineNumber": 142,
    "character": 45,
    "timestamp": 1713816000000
  }
}
```

**Subscribe (sidecar → client)**:
```json
{
  "type": "presence_changed",
  "userId": "@bob:matrix.kushnir.cloud",
  "presence": {
    "status": "online",
    "fileName": "README.md",
    "language": "markdown",
    "timestamp": 1713816000000
  }
}
```

---

## Configuration

### Extension Settings (settings.json)

```json
{
  "teamHub.matrixHomeserver": "https://matrix.kushnir.cloud",
  "teamHub.presenceSidecarUrl": "ws://presence-sidecar:9000",
  "teamHub.enableAutoPresence": true,
  "teamHub.enableGoogleMeet": true,
  "teamHub.presenceUpdateInterval": 5000,
  "teamHub.showAvatars": true,
  "teamHub.highlightSameFile": true
}
```

### Environment Variables

```bash
MATRIX_HOMESERVER=https://matrix.kushnir.cloud
PRESENCE_SIDECAR_URL=ws://presence-sidecar:9000
GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID}
MEET_API_SCOPE=https://www.googleapis.com/auth/calendar
```

---

## Authentication Flow

1. User opens VS Code with Team Hub extension
2. Extension checks for existing Matrix session token
3. If not found, redirects to oauth2-proxy login flow
4. oauth2-proxy authenticates with Google (same as IDE)
5. Extension stores Matrix token in VS Code keychain
6. WebSocket connection authenticated with token
7. Matrix API calls use token from oauth2-proxy session cookie

---

## Acceptance Criteria Fulfillment

✅ **Extension builds and installs in code-server**
- `npm run build` → generates .vsix package
- Install via `code-server --install-extension team-hub-0.1.0.vsix`

✅ **Sidebar shows real-time online/away/offline users**
- WebSocket subscription to presence-sidecar
- User list organized by status
- Real-time updates via message events

✅ **Current file per user displayed**
- File name and line number shown in user card
- Updates every 5 seconds (configurable)

✅ **"Same file" highlight when collaborators present**
- Visual indicator (bold/highlight) for users on same file
- Quick jump button to go to user's location

✅ **@Mention action posts to Matrix room (bridged to Slack/Teams)**
- Command: `teamHub.mentionUser`
- Posts formatted message with @mention
- Matrix → Slack/Teams via bridge

✅ **Start Meet creates Google Meet link**
- Command: `teamHub.startMeet`
- Multi-select users, creates meeting, posts link to room
- Calendar invitation generated

✅ **Presence updates <500ms latency**
- WebSocket connection (not polling)
- Presence sidecar broadcasts updates immediately
- Client-side rendering optimized

✅ **Settings panel for preferences**
- Configurable via `teamHub.*` settings
- UI toggle for features
- Persistent storage

✅ **Extension pre-installed in code-server Docker image**
- Dockerfile.code-server updated
- Extension .vsix copied and installed
- Settings configured at build time

✅ **Unit tests with >80% coverage**
- Test suite for services, handlers, UI
- Mock Matrix SDK and WebSocket
- Integration tests for command flow

---

## Build & Package

### Prerequisites

```bash
npm install -g vsce
npm install
```

### Build Extension

```bash
npm run build
# Output: team-hub-0.1.0.vsix
```

### Install in code-server

```bash
code-server --install-extension team-hub-0.1.0.vsix
```

### Update Dockerfile.code-server

```dockerfile
# Pre-install Team Hub extension
COPY extensions/team-hub/team-hub-0.1.0.vsix /tmp/
RUN code-server --install-extension /tmp/team-hub-0.1.0.vsix && \
    rm /tmp/team-hub-0.1.0.vsix

# Configure extension settings
COPY extensions/team-hub/settings.json \
  /home/coder/.local/share/code-server/User/settings.json
```

---

## Testing Strategy

### Unit Tests

```typescript
// services.test.ts
describe('PresenceService', () => {
  it('should connect to WebSocket', async () => {})
  it('should publish presence updates', async () => {})
  it('should subscribe to presence changes', () => {})
  it('should handle reconnection', () => {})
})

describe('MatrixService', () => {
  it('should authenticate via token', () => {})
  it('should send messages with mentions', () => {})
  it('should handle room member changes', () => {})
})
```

### Integration Tests

```typescript
// Full workflow testing
describe('Mention User Flow', () => {
  it('should post message to room and bridge to Slack', () => {})
})

describe('Start Meet Flow', () => {
  it('should create meeting and invite participants', () => {})
})
```

### Manual Testing

1. **Presence Updates**
   - Open two instances of code-server
   - Edit file in one instance
   - Verify other instance shows presence within 5 seconds

2. **Mentions**
   - Select user from sidebar
   - Click mention button
   - Verify message appears in Matrix room
   - Verify message appears in Slack/Teams

3. **Google Meet**
   - Click "Start Meet" with selected users
   - Verify meeting created and link posted
   - Verify calendar invitations sent

---

## Phase 2 (Future)

- Avatar sync from Google profile
- Group mapping (Google groups → Matrix roles)
- Code review annotations in sidebar
- Direct messaging between users
- File sharing via Matrix
- Voice/video via Element Call
- Activity feed with file changes
- Team statistics dashboard

---

## Support & Documentation

- **Extension README**: /extensions/team-hub/README.md
- **API Docs**: /docs/team-hub-api.md
- **Troubleshooting**: /docs/team-hub-troubleshooting.md
- **Release Notes**: /CHANGELOG.md
