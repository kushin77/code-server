#!/usr/bin/env node
// README.md - SmartNotificationRoutingService

# SmartNotificationRoutingService

**Intelligent Multi-Channel Notification Routing with Context Awareness**

## Overview

`SmartNotificationRoutingService` intelligently routes notifications across multiple delivery channels (in-app, email, Slack, SMS, push) based on user context, readiness, preferences, and notification priority. It optimizes delivery timing, channel selection, and escalation policies to maximize notification effectiveness while respecting user preferences and availability.

## Purpose

Notifications are only effective when delivered through the right channel at the right time. This service:

- **Selects optimal delivery channels** based on user readiness and device availability
- **Respects user preferences** (do-not-disturb, quiet hours, focus time)
- **Escalates critical notifications** when unacknowledged
- **Batches compatible notifications** to reduce notification fatigue
- **Tracks delivery success** and adapts future routing decisions
- **Manages channel load** and prioritizes during capacity constraints

## Architecture

### Routing Decision Factors

The service considers multiple factors when routing notifications:

| Factor | Weight | Impact |
|--------|--------|--------|
| **Readiness Level** | 35% | available/busy/away/offline |
| **Notification Priority** | 30% | P0 (critical) → P3 (low) |
| **User Channel Preferences** | 20% | Preferred channels and priorities |
| **Time of Day** | 10% | Business hours vs. after-hours |
| **Device Availability** | 5% | Available clients and platforms |

### Routing Decision Algorithm

```
1. Evaluate notification context (priority, type, urgency)
2. Fetch user preferences and current readiness
3. Filter suppressed/unavailable channels
4. Score remaining channels (0-100)
5. Select primary route (highest score)
6. Determine escalation level
7. Calculate delivery delay
8. Record decision and emit event
```

### Delivery Channels

#### In-App (Primary)
- Synchronous delivery in web/IDE interface
- Immediate notification badge
- Full action support
- Best for: Collaborative updates, mentions, approvals
- Rate limit: 100/min
- Cost: Free

#### Email (Reliable)
- Asynchronous, searchable, archivable
- Works offline
- Best for: Summaries, approvals, non-urgent updates
- Rate limit: 10/min
- Cost: ~$0.001/message
- Batching: Up to 50 notifications

#### Slack (Synchronous)
- Instant delivery
- Integrated with daily workflow
- Rich formatting support
- Best for: Team updates, mentions, quick approvals
- Rate limit: 30/min
- Cost: Free (with business account)
- No batching

#### SMS (Critical)
- Direct to phone, guaranteed delivery
- No device required
- Best for: Critical alerts, time-sensitive approvals
- Rate limit: 5/min
- Cost: $0.05/message
- No batching
- Escalation only

#### Push (Mobile)
- Mobile app notification
- Works when offline
- Local device delivery
- Best for: Time-sensitive updates, mobile-specific alerts
- Rate limit: 50/min
- Cost: Free
- Batching: Up to 10 notifications

### Escalation Policies

Escalation triggers when a notification isn't acknowledged:

```
Level 1: Primary channels (in-app, email) - Immediate
  ↓ No acknowledgment for 5 minutes
Level 2: Secondary channels (Slack, email) - 5 min delay
  ↓ Still no acknowledgment for 15 minutes
Level 3: Tertiary channels (SMS, push) - 15 min delay
  ↓ Critical + still not acknowledged for 30 minutes
Level 4: SMS only - 30 min delay
  ↓ For P0 only, not acknowledged for 60 minutes
Level 5: Manager/team escalation - 2 hour delay
```

## Database Schema

### Tables

1. **routing_user_preferences**
   - User channel preferences
   - DND and quiet hours settings
   - Escalation policies
   - Indexed by `user_id`

2. **routing_decisions**
   - All routing decisions made
   - Selected channel and reasoning
   - Escalation level and confidence
   - For auditability and machine learning

3. **routing_delivery_acks**
   - Delivery confirmations
   - Read/action status
   - Timing metrics
   - For tracking notification effectiveness

4. **routing_escalations**
   - Active escalation tracking
   - Current and next level
   - Scheduled escalation times
   - For escalation orchestration

5. **routing_batch_windows**
   - Batched notification groups
   - Scheduled delivery times
   - Status tracking
   - For batch delivery coordination

## Usage

### Initialize Service

```typescript
import { Pool } from 'pg';
import { SmartNotificationRoutingService } from './smart-notification-routing-service';
import { AuditService } from '../audit/audit-service';

const pool = new Pool({ /* config */ });
const auditService = new AuditService(pool);

const routingService = new SmartNotificationRoutingService(pool, auditService);
await routingService.initialize();
```

### Make Routing Decision

```typescript
const context: RoutingContext = {
  userId: 'user-123',
  notificationId: 'notif-001',
  notificationType: 'mention',
  priority: 'P1',
  timestamp: new Date(),
  readinessLevel: 'available',
  isInFocusTime: false,
  isInMeeting: false,
  deviceAvailability: {
    hasDesktopClient: true,
    hasWebClient: true,
    hasMobileApp: false,
  },
  conversationContext: {
    threadId: 'thread-456',
    urgency: 'important',
    mentions: ['user-123'],
    requiresApproval: true,
  },
  userPreferences: {
    userId: 'user-123',
    preferredChannels: ['in-app', 'email', 'slack'],
    channelPriority: { 'in-app': 5, 'email': 3, 'slack': 4 },
    doNotDisturb: { enabled: false },
    focusTimeExclusion: false,
    meetingModeExclusion: false,
    channelOptOuts: [],
    escalationPolicy: {
      // ... escalation config
    },
  },
};

const decision = await routingService.makeRoutingDecision(context);

console.log(`Route: ${decision.selectedRoute}`);
console.log(`Escalation Level: ${decision.escalationPolicy}`);
console.log(`Delay: ${decision.deliveryDelay}ms`);
console.log(`Reason: ${decision.reason}`);
```

### Record Delivery Acknowledgment

```typescript
await routingService.recordDeliveryAck({
  notificationId: 'notif-001',
  userId: 'user-123',
  deliveryRoute: 'in-app',
  status: 'delivered',
  deliveredTime: new Date(),
  readTime: new Date(),
  actedUpon: true,
  actionTaken: 'approved',
});
```

### Get User Preferences

```typescript
const preferences = await routingService.getUserPreferences('user-123');

if (preferences) {
  console.log(`Preferred channels: ${preferences.preferredChannels.join(', ')}`);
  console.log(`DND enabled: ${preferences.doNotDisturb.enabled}`);
  console.log(`Max escalation level: ${preferences.escalationPolicy.maxEscalationLevel}`);
}
```

### Update Channel Status

```typescript
// Mark channel as degraded
await routingService.updateChannelStatus(
  'email',
  false, // available
  20, // 20% capacity
  'Email provider degradation'
);

// Restore channel
await routingService.updateChannelStatus('email', true, 100);
```

## Routing Decision Examples

### Example 1: Available User, P1 Message

**User Context**:
- Readiness: available (desktop active)
- Priority: P1 (important)
- In-app available: yes
- Recent activity: editing code

**Routing Decision**:
- Primary: in-app (highest score)
- Secondary: Slack (quick access)
- Delay: 0ms (immediate)
- Escalation: Level 2 (if no ack in 5 min)

### Example 2: Away User, P2 Update

**User Context**:
- Readiness: away (device inactive 30 min)
- Priority: P2 (medium)
- Email available: yes
- Focus time: disabled

**Routing Decision**:
- Primary: email (away users prefer async)
- Secondary: Slack (they might return)
- Delay: 5000ms (batch window)
- Escalation: Level 3 (max for P2)
- Batching: enabled

### Example 3: Offline User, P0 Alert

**User Context**:
- Readiness: offline (no activity 2 hours)
- Priority: P0 (critical)
- SMS available: yes
- Escalation enabled: yes

**Routing Decision**:
- Primary: SMS (mobile reachable)
- Secondary: Push (if device online)
- Delay: 0ms (immediate, critical)
- Escalation: Level 4 (escalate to SMS only)
- Re-attempt: Every 5 minutes until acknowledged

## Configuration

### User Preferences

Users can customize routing behavior:

```typescript
const preferences: ChannelPreference = {
  userId: 'user-123',
  preferredChannels: ['in-app', 'email', 'slack'],
  channelPriority: {
    'in-app': 5, // Prefer most
    'slack': 4,
    'email': 3,
    'sms': 1, // Use only for critical
    'push': 2,
  },
  doNotDisturb: {
    enabled: true,
    startTime: '22:00',
    endTime: '08:00',
    timezone: 'America/New_York',
  },
  quietHours: {
    enabled: true,
    startTime: '18:00',
    endTime: '09:00',
    timezone: 'America/New_York',
  },
  focusTimeExclusion: true, // Suppress during focus blocks
  meetingModeExclusion: false,
  channelOptOuts: ['sms'], // Never use SMS
  batchPreference: {
    enabled: true,
    windowMinutes: 5,
  },
  escalationPolicy: {
    levels: [1, 2, 3, 4, 5],
    levelRoutes: {
      1: ['in-app', 'email'],
      2: ['slack', 'email'],
      3: ['sms', 'push'],
      4: ['sms'],
      5: ['sms', 'email'], // Manager cc
    },
    levelDelays: {
      1: 0,
      2: 300000, // 5 min
      3: 900000, // 15 min
      4: 1800000, // 30 min
      5: 3600000, // 60 min
    },
    enableForPriority: ['P0', 'P1'],
    maxEscalationLevel: 5,
  },
};
```

## Performance Characteristics

| Operation | Typical Latency | Notes |
|-----------|-----------------|-------|
| Make routing decision | <15ms | In-memory scoring |
| Record delivery ack | <10ms | Fast write |
| Get user preferences | <5ms | Cached |
| Update channel status | <5ms | In-memory |

## Integration Points

### With ReadinessIndicatorService
Consumes readiness level (available/busy/away/offline) to inform channel selection.

### With NotificationPriorityEngineService
Consumes priority scores (P0-P3) to determine escalation policy.

### With External Services
- **Email Provider**: Send email notifications
- **Slack API**: Deliver Slack messages
- **SMS Provider**: Send SMS alerts
- **Push Service**: Deliver mobile push notifications

## Events

### `readinessChanged`
Emitted when routing decisions change due to user readiness change.

### `deliveryAck`
Emitted when delivery is acknowledged or acted upon.

```typescript
routingService.on('deliveryAck', (ack) => {
  console.log(`Notification ${ack.notificationId} acknowledged`);
  // Cancel escalation timers, update UI, etc.
});
```

## Monitoring & Observability

### Key Metrics

- `routing_decision_latency` — Time to make routing decision
- `delivery_success_rate` — Percentage of notifications delivered
- `escalation_rate` — Percentage requiring escalation
- `batch_savings` — Reduction from batching

### Audit Events

```
action: 'routing_decision_made'
details: {
  selectedRoute: 'in-app',
  escalationLevel: 2,
  priority: 'P1',
  readinessLevel: 'available',
}
```

## Testing

Comprehensive test suite with 25+ tests:

```bash
npm run test -- smart-notification-routing-service.test.ts
```

Test coverage:
- Routing decision algorithm
- Channel scoring
- Escalation logic
- User preference handling
- DND and focus time suppression
- Performance benchmarks

## Known Limitations

1. **Channel failures** require manual intervention (future: auto-failover)
2. **Batch window** timing is fixed (future: dynamic based on load)
3. **Escalation loops** limited to prevent spam (max 5 levels)
4. **SMS cost** not tracked (future: budget-aware routing)

## Future Enhancements

- [ ] Machine learning-based channel optimization
- [ ] Dynamic batch window sizing
- [ ] Cost-aware routing (optimize for SMS spend)
- [ ] A/B testing framework for routing policies
- [ ] User satisfaction feedback loop
- [ ] Webhook support for custom routing rules

## References

- [Types](./types.ts) — Complete type definitions
- [Test Suite](./\_\_tests\_\_/smart-notification-routing-service.test.ts) — Usage examples and test patterns
- [Service Integration](../index.ts) — Integration with service registry
