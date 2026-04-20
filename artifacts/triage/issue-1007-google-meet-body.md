## P1: Integrate Google Meet One-Click Creation

### Summary

Enable one-click Google Meet creation from the Team Hub sidebar extension. When clicked, create a Meet link and post it to the Matrix room (which bridges to Slack/Teams/Google Chat).

### User Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ code-server IDE - Team Hub Sidebar                              │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ Quick Actions                                               │ │
│ │ [📞 Start Meet] ← User clicks                               │ │
│ └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│ 1. Create Google Meet via Calendar API                          │
│    POST /calendar/v3/calendars/primary/events                   │
│    { conferenceDataVersion: 1, ... }                            │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. Extract Meet link: https://meet.google.com/abc-defg-hij      │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. Post to Matrix room with bridge to Slack/Teams/Chat         │
│    "@here - Join the standup: https://meet.google.com/..."     │
└─────────────────────────────────────────────────────────────────┘
                               │
           ┌───────────────────┼───────────────────┐
           ▼                   ▼                   ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│ Slack Channel   │  │ Teams Channel   │  │ Google Chat     │
│ Link appears    │  │ Link appears    │  │ Link appears    │
└─────────────────┘  └─────────────────┘  └─────────────────┘
```

### Implementation

```typescript
// extensions/team-hub/src/meet.ts

import { google } from 'googleapis';

const calendar = google.calendar({ version: 'v3', auth: oauthClient });

export async function createInstantMeet(
  title: string = 'Quick Meeting',
  invitees: string[] = []
): Promise<string> {
  const event = await calendar.events.insert({
    calendarId: 'primary',
    conferenceDataVersion: 1,
    requestBody: {
      summary: title,
      start: { dateTime: new Date().toISOString() },
      end: { dateTime: new Date(Date.now() + 60 * 60 * 1000).toISOString() },
      attendees: invitees.map(email => ({ email })),
      conferenceData: {
        createRequest: {
          requestId: crypto.randomUUID(),
          conferenceSolutionKey: { type: 'hangoutsMeet' }
        }
      }
    }
  });

  return event.data.conferenceData?.entryPoints?.[0]?.uri || '';
}

// Post to Matrix room
async function postMeetLinkToRoom(meetUrl: string, roomId: string) {
  await matrixClient.sendMessage(roomId, {
    msgtype: 'm.text',
    body: `📞 Join the meeting: ${meetUrl}`,
    format: 'org.matrix.custom.html',
    formatted_body: `<p>📞 Join the meeting: <a href="${meetUrl}">${meetUrl}</a></p>`
  });
}
```

### Google Cloud Setup

1. **Enable APIs**:
   - Google Calendar API
   - Google Meet REST API (optional, for advanced features)

2. **OAuth Scopes**:
   - `https://www.googleapis.com/auth/calendar.events`
   - `https://www.googleapis.com/auth/calendar.events.owned`

3. **OAuth Consent Screen**:
   - Internal (Google Workspace) or External
   - Add required scopes

### OAuth Flow in Extension

```typescript
// extensions/team-hub/src/auth.ts

// Use existing oauth2-proxy session to get Google tokens
async function getGoogleAccessToken(): Promise<string> {
  // Option 1: Token relay via oauth2-proxy
  const response = await fetch('/oauth2/userinfo', {
    headers: { 'X-Forwarded-Access-Token': 'true' }
  });
  return response.json().access_token;

  // Option 2: Service account impersonation
  // (for domain-wide delegation)
}
```

### Docker/Environment Configuration

```yaml
# docker-compose.yml environment additions for code-server

code-server:
  environment:
    GOOGLE_MEET_ENABLED: "true"
    GOOGLE_CLIENT_ID: ${GOOGLE_CLIENT_ID}
    # Access token retrieved via oauth2-proxy session
```

### Terraform Configuration

```hcl
# terraform/modules/google-meet/main.tf

resource "google_project_service" "calendar_api" {
  project = var.project_id
  service = "calendar-json.googleapis.com"
}

# OAuth client for Meet integration
resource "google_identity_platform_oauth_client" "meet_client" {
  display_name = "code-server Meet Integration"
  # ... OAuth configuration
}
```

### Acceptance Criteria

- [ ] Google Calendar API enabled
- [ ] OAuth scopes configured for Meet creation
- [ ] "Start Meet" button in Team Hub extension
- [ ] Meet link created on click
- [ ] Link posted to Matrix room automatically
- [ ] Link appears in bridged Slack/Teams/Chat channels
- [ ] Works with existing oauth2-proxy SSO flow
- [ ] Error handling for API failures
- [ ] Telemetry: Meet creation events logged

### Advanced Features (Future)

- [ ] Select attendees before creating Meet
- [ ] Schedule Meet for future time
- [ ] Recurring standup Meet links
- [ ] In-meeting presence in sidebar ("3 people in standup call")

### Dependencies

- Requires: #1002 (Team Hub extension)
- Requires: #1004 or #1005 or #1006 (at least one bridge)
- Requires: Google Workspace OAuth integration

### Parent

EPIC #TBD (Matrix Collaboration Hub)
