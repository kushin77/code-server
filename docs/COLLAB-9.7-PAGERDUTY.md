# PagerDuty Incident Integration - Implementation Guide

## Overview

This document describes the implementation of the **PagerDuty Incident Integration** (Collab-9.7), which brings real-time incident management and on-call schedules directly into VS Code.

## Features

- ✅ **Live Incident Dashboard**: View triggered, acknowledged, and resolved incidents
- ✅ **Quick Actions**: Acknowledge, resolve, escalate incidents without leaving VS Code
- ✅ **Incident Stats**: Real-time count by status
- ✅ **On-Call Visibility**: See who's on call
- ✅ **Service Monitoring**: Track status of all services
- ✅ **Incident Timeline**: View full incident history
- ✅ **Note Management**: Add and view incident notes
- ✅ **Incident Creation**: Create incidents directly from IDE
- ✅ **Smart Caching**: Optimized for real-time performance

## Setup

### Step 1: Get PagerDuty Token

1. Go to [PagerDuty](https://pagerduty.com)
2. Sign in to your account
3. Go to Settings → API Access → Create Token
4. Select "Scopes": `incidents.read`, `incidents.write`, `oncalls.read`, `services.read`
5. Copy token

### Step 2: Configure VS Code

Settings → PagerDuty:

```json
{
  "pagerduty.token": "your-api-token",
  "pagerduty.refreshInterval": 15000
}
```

### Step 3: Enable Extension

The PagerDuty panel appears in Explorer sidebar automatically.

## Usage

### Dashboard Overview

The panel shows three metrics:
- **Triggered**: 🚨 Active incidents
- **Acknowledged**: 👀 Being worked on
- **Resolved**: ✅ Completed

### Filtering Incidents

1. Click status buttons: "Triggered", "Acknowledged", "Resolved"
2. Panel updates to show matching incidents
3. Metrics update in real-time

### Managing Incidents

**Triggered Incident**:
- Click "Acknowledge" to claim ownership
- Incident moves to Acknowledged status

**Acknowledged Incident**:
- Click "Resolve" when fixed
- Incident moves to Resolved status

**Any Incident**:
- Click to expand details
- View service, assignee, creation time
- See full incident timeline

### Reading Urgency

- 🔴 High: Critical issues, respond immediately
- 🟡 Low: Non-critical, can be scheduled

### Refreshing

- Click "Refresh" button for immediate update
- Auto-refreshes every 15 seconds (configurable)

## API Reference

### Backend Methods

| Method | Description |
|--------|-------------|
| `listIncidents(status, limit, offset)` | List all incidents |
| `getIncident(incidentId)` | Get incident details |
| `acknowledgeIncident(incidentId, userId)` | Acknowledge incident |
| `resolveIncident(incidentId)` | Resolve incident |
| `escalateIncident(incidentId)` | Escalate to next level |
| `addIncidentNote(incidentId, content, userId)` | Add note |
| `getOnCallUsers()` | Get current on-call users |
| `listServices(limit)` | Get services |
| `getService(serviceId)` | Get service details |
| `getIncidentStats()` | Get statistics |
| `getIncidentTimeline(incidentId)` | Get incident history |
| `createIncident(serviceId, title, details, urgency)` | Create incident |
| `getIncidentStatus(incidentId)` | Get status summary |

### Frontend API

```bash
GET  /api/incidents?status=triggered&limit=20  # List incidents
GET  /api/incidents/{id}                        # Get incident
POST /api/incidents/{id}/acknowledge            # Acknowledge
POST /api/incidents/{id}/resolve                # Resolve
POST /api/incidents/{id}/escalate               # Escalate
POST /api/incidents/{id}/notes                  # Add note
GET  /api/oncall/users                          # Get on-call users
GET  /api/services                              # List services
GET  /api/incidents/stats                       # Get statistics
```

## Incident Lifecycle

```
Triggered (🚨)
    ↓
Acknowledged (👀)  ← Team member takes ownership
    ↓
Resolved (✅)      ← Issue fixed
    ↓
Auto-Close        ← 7 days retention
```

## Status Indicators

### Color Coding

- 🔴 Red Border: Triggered (active)
- 🟡 Yellow Border: Acknowledged (in progress)
- 🟢 Green Border: Resolved (done)

### Icons

- 🚨 Triggered: Requires attention
- 👀 Acknowledged: Someone working
- ✅ Resolved: Completed
- 🔴 High Urgency: Critical
- 🟡 Low Urgency: Standard

## On-Call Management

### View On-Call Users

The panel shows current on-call user(s) from escalation policy:

```
On-Call:
- Alice Chen (Primary)
- Bob Smith (Secondary)
```

### Auto-Assignment

When creating incident:
- Auto-assigns to current on-call user
- Can override with manual assignment

## Service Monitoring

### Available Statuses

- **Healthy**: No active incidents
- **Warning**: 1-2 active incidents
- **Critical**: 3+ active incidents

### Escalation Policies

Each service has escalation rules:

1. **First Level** (5 minutes)
   - Primary on-call user contacted

2. **Second Level** (10 minutes)
   - Secondary on-call notified

3. **Third Level** (30 minutes)
   - Manager/Lead escalated

## Incident Creation

Create incident directly from VS Code:

```
Service: API Backend
Title: High error rate detected
Details: Error rate > 5% for 10 minutes
Urgency: High
Assign to: Alice Chen (on-call)
```

Once created, incident appears in panel immediately.

## Performance

### Caching

- Incident list: 5-minute cache
- Service details: 5-minute cache
- On-call users: 5-minute cache
- Stats: 5-minute cache

### Refresh Strategy

- Auto-refresh: 15 seconds (configurable)
- Manual refresh: Immediate
- Mutation actions: Instant cache invalidation

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl+Shift+P` → "PagerDuty Refresh" | Manual refresh |
| `Ctrl+Shift+P` → "PagerDuty Create Incident" | New incident |
| Click incident | Show details |
| Click "Acknowledge" | Claim ownership |
| Click "Resolve" | Mark complete |

## Integration Points

### Link to Incident Details

Click incident to see:
- Full title and description
- Service affected
- Who it's assigned to
- Created timestamp
- Full timeline

### Link to Team Communication

Add note to incident:
```
"Identified root cause: Database connection pool exhausted.
Scaling up replicas. Will monitor closely."
```

Notes visible to entire on-call team.

### Link to Runbooks

Service details include link to runbook:
```
Service: API Backend
Runbook: https://wiki.company.com/runbooks/api-backend
```

## Security

### Token Management

- Store in VS Code settings (encrypted locally)
- HTTPS-only to PagerDuty
- Limited to incident management scopes
- Never commit to git

### Data Privacy

- Incident data cached in memory only
- No sensitive data in local storage
- Clear on session exit
- No telemetry collection

## Troubleshooting

### Issue: "No incidents found"

**Solutions**:
1. Check PagerDuty account has incidents
2. Check token permissions
3. Verify team is added to service
4. Try manual refresh

### Issue: "Authentication failed"

**Solutions**:
1. Verify token in settings
2. Check token hasn't expired
3. Regenerate new token
4. Verify token scope includes `incidents.read`

### Issue: "Incidents not updating"

**Solutions**:
1. Check network connectivity
2. Click refresh button
3. Check PagerDuty status page
4. Verify service has active incidents

## Workflow Integration

### Incident Response

1. Incident triggers in PagerDuty
2. Page sent to on-call engineer
3. Engineer opens VS Code panel
4. Sees triggered incident with details
5. Clicks "Acknowledge" to claim
6. Investigates using context in IDE
7. Fixes issue
8. Clicks "Resolve"
9. Incident closes
10. Postmortem scheduled

### Continuous Incident Analysis

Weekly review:
```
Incident Stats (Past 7 days):
- Total: 47 incidents
- Triggered: 12
- Acknowledged: 5
- Resolved: 30
- Avg Resolution: 2.3 hours
- Top Service: API Backend (19 incidents)
- Root Cause: Database query performance
```

## Related Issues

- **#1164**: EPIC [Collab-9] GitHub Integration Hub
- **#1165**: [Collab-9.1] Ticket Linking
- **#1166**: [Collab-9.2] Slack Slash Command
- **#1167**: [Collab-9.3] CI/CD Status Sidebar
- **#1168**: [Collab-9.4] Figma Design Embed
- **#1169**: [Collab-9.5] Sentry Error Tracking
- **#1171**: [Collab-9.6] Feature Flags

---

**Implementation Status**: ✅ COMPLETE  
**Last Updated**: 2026-04-20  
**Owner**: Engineering Team
