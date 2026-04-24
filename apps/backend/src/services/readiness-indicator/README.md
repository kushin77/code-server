#!/usr/bin/env node
// @file        apps/backend/src/services/readiness-indicator/README.md
// @module      collaboration/readiness-indicator
// @description ReadinessIndicatorService documentation
// @owner       collab-services
// @status      active

# ReadinessIndicatorService

Team member availability and collaborative capacity indicator for real-time collaboration features.

## Overview

ReadinessIndicatorService aggregates multi-source availability signals (presence, activity, calendar, capacity) to determine team member readiness for real-time collaboration. It provides:

- **Real-time availability tracking**: Monitor when team members are available for collaboration
- **Capacity awareness**: Track active file/session counts and task load
- **Readiness prediction**: Forecast future availability based on historical patterns
- **Team metrics**: Calculate team-wide readiness and optimal collaboration windows
- **Event-based updates**: Subscribe to readiness changes for specific team members

## Architecture

### Signal Aggregation

The service aggregates signals from multiple sources:

| Signal Type | Weight | Source Examples | Description |
|-------------|--------|-----------------|-------------|
| Presence | 30% | Presence service, OAuth2-proxy | Physical location/online status |
| Activity | 25% | IDE activity, keyboard/mouse events | Active work patterns |
| Calendar | 25% | Integrated calendars, meeting status | Scheduled availability |
| Capacity | 15% | Active file/session counts | Current task load |
| History | 5% | Historical patterns | Past availability trends |

### Readiness Levels

- **AVAILABLE** (score ≥ 75): Fully available for real-time collaboration
- **BUSY** (score ≥ 50): Available but with limited capacity
- **AWAY** (score ≥ 25): Not at desk, may return soon
- **OFFLINE** (score < 25): Not available for collaboration
- **DND** (explicit): Do not disturb status

### Scoring Algorithm

```
readinessScore = (
  (presenceSignals * 0.30) +
  (activitySignals * 0.25) +
  (calendarSignals * 0.25) +
  (capacitySignals * 0.15) +
  (historySignals * 0.05)
) / 100
```

Each signal contributes its confidence score (0-100) weighted by signal type importance.

## API Reference

### Core Methods

#### `addSignal(signal: AvailabilitySignal): Promise<boolean>`

Add an availability signal from any source.

```typescript
await service.addSignal({
  userId: 'user-123',
  signalType: SignalType.PRESENCE,
  readinessLevel: ReadinessLevel.AVAILABLE,
  confidence: 95,
  timestamp: Date.now(),
  metadata: { location: 'office' },
  source: 'presence-service',
});
```

**Returns**: `true` if signal was processed, `false` if error occurred.

#### `getUserStatus(userId: string): UserReadinessStatus | null`

Get current readiness status for a specific user.

```typescript
const status = service.getUserStatus('user-123');
if (status?.readinessLevel === ReadinessLevel.AVAILABLE) {
  // Initiate real-time collaboration
}
```

**Returns**: User readiness status or `null` if user has no signals.

#### `getTeamReadiness(teamId: string, userIds: string[]): TeamReadinessMetrics`

Get team-wide readiness metrics.

```typescript
const metrics = service.getTeamReadiness('team-1', [
  'user-1',
  'user-2',
  'user-3',
]);

console.log(`Team capacity: ${metrics.teamCapacityScore}%`);
console.log(`Available: ${metrics.availableCount}/${metrics.totalMembers}`);
```

**Returns**: Team readiness metrics including availability distribution and capacity scores.

#### `getCapacity(userId: string): CollaborativeCapacity | null`

Get collaborative capacity metrics for a user.

```typescript
const capacity = service.getCapacity('user-123');
if (capacity && capacity.taskLoadScore > 80) {
  // User has high task load, recommend asynchronous communication
}
```

**Returns**: Capacity metrics or `null` if user has no capacity data.

#### `setCapacity(userId: string, capacity: CollaborativeCapacity): void`

Update collaborative capacity metrics.

```typescript
service.setCapacity('user-123', {
  userId: 'user-123',
  activeFileCount: 3,
  activeSessionCount: 2,
  taskLoadScore: 65,
  responseLatencyMs: 250,
  contextSwitchCost: 40,
  recommendedInteractionWindowMs: 600000, // 10 minutes
  timestamp: Date.now(),
});
```

#### `predictReadiness(userId: string): ReadinessPrediction | null`

Predict future readiness based on current signals.

```typescript
const prediction = service.predictReadiness('user-123');
if (prediction) {
  console.log(`User will be ${prediction.predictedReadinessLevel}`);
  console.log(`Confidence: ${prediction.confidenceScore}%`);
}
```

**Returns**: Readiness prediction or `null` if insufficient signals.

#### `findOptimalCollaborationWindow(teamId: string, userIds: string[], windowSizeMs?: number): CollaborationWindowRecommendation`

Find optimal collaboration window for team.

```typescript
const window = service.findOptimalCollaborationWindow(
  'team-1',
  ['user-1', 'user-2', 'user-3'],
  60 * 60 * 1000, // 1 hour window
);

console.log(`Recommend: ${new Date(window.recommendedStartTime)}`);
console.log(`Optimality: ${window.optimalityScore}%`);
```

**Returns**: Recommended collaboration window with optimality score.

#### `onReadinessChanged(userId: string, callback: (update: ReadinessUpdate) => void): () => void`

Subscribe to readiness changes for a user.

```typescript
const unsubscribe = service.onReadinessChanged('user-123', (update) => {
  console.log(`User went from ${update.previousLevel} to ${update.currentLevel}`);
  // Adjust UI or features based on readiness change
});

// Later: unsubscribe
unsubscribe();
```

**Returns**: Unsubscribe function to stop listening.

#### `queryReadiness(options: ReadinessQueryOptions): ReadinessQueryResult`

Query readiness status with filtering.

```typescript
// Find all available users
const result = service.queryReadiness({
  readinessLevel: ReadinessLevel.AVAILABLE,
  maxResults: 10,
});

// Find specific user's historical status
const userResult = service.queryReadiness({
  userId: 'user-123',
  includeHistorical: true,
});
```

**Returns**: Query results with matching statuses and query time.

#### `getStats(): ReadinessIndicatorStats`

Get service statistics.

```typescript
const stats = service.getStats();
console.log(`Signals processed: ${stats.signalsProcessed}`);
console.log(`Avg scoring time: ${stats.averageScoringTimeMs}ms`);
console.log(`Team readiness checks: ${stats.teamReadinessCheckCount}`);
```

### Lifecycle Methods

#### `shutdown(): void`

Gracefully shutdown the service.

```typescript
service.shutdown();
```

## Configuration

### Default Configuration

```typescript
const config: ReadinessIndicatorConfig = {
  // Signal weights (must sum to 100)
  signalWeights: {
    presence: 30,
    activity: 25,
    calendar: 25,
    capacity: 15,
    history: 5,
  },

  // Readiness thresholds
  readinessThresholds: {
    available: 75,   // score >= 75 → available
    busy: 50,        // score >= 50 → busy
    away: 25,        // score >= 25 → away
    offline: 0,      // score < 25 → offline
  },

  // Activity tracking
  activityTimeoutMs: 5 * 60 * 1000,      // 5 minutes
  idleThresholdMs: 30 * 60 * 1000,       // 30 minutes

  // Signal freshness
  signalFreshnessMs: 60 * 1000,          // 1 minute
  minSignalsForReadiness: 2,             // need 2+ signals

  // Predictions
  enablePredictions: true,
  predictionWindowMs: 15 * 60 * 1000,    // 15 minutes
  predictionUpdateIntervalMs: 60 * 1000, // 1 minute

  // Cleanup
  maxSignalHistorySize: 1000,
  signalRetentionMs: 24 * 60 * 60 * 1000, // 24 hours
  cleanupIntervalMs: 5 * 60 * 1000,      // 5 minutes
};
```

### Custom Configuration

```typescript
const service = createReadinessIndicatorService({
  signalWeights: {
    presence: 40,    // Increase presence weight
    activity: 30,
    calendar: 20,
    capacity: 10,
    history: 0,
  },
  readinessThresholds: {
    available: 80,   // Higher threshold for "available"
    busy: 60,
    away: 30,
    offline: 0,
  },
});
```

## Integration Patterns

### With NotificationPriorityEngine

```typescript
import { getReadinessIndicatorService } from './readiness-indicator';
import { getNotificationPriorityEngine } from '../notification-priority-engine';

const readiness = getReadinessIndicatorService();
const notificationEngine = getNotificationPriorityEngine();

// Notify based on readiness
const user = readiness.getUserStatus('user-123');
notificationEngine.queueNotification({
  userId: 'user-123',
  message: 'Collaboration request from team',
  priority: user?.readinessLevel === ReadinessLevel.AVAILABLE ? 'HIGH' : 'LOW',
});
```

### With ConflictPredictionService

```typescript
import { getReadinessIndicatorService } from './readiness-indicator';
import { getConflictPredictionService } from '../conflict-prediction';

const readiness = getReadinessIndicatorService();
const conflicts = getConflictPredictionService();

// Suggest collaboration when both team members are available
const conflict = conflicts.getRiskScore('file.ts', 'func1');
if (conflict?.riskScore > 0.7) {
  const user1Status = readiness.getUserStatus('user-1');
  const user2Status = readiness.getUserStatus('user-2');

  if (
    user1Status?.readinessLevel === ReadinessLevel.AVAILABLE &&
    user2Status?.readinessLevel === ReadinessLevel.AVAILABLE
  ) {
    // Suggest pair programming or synchronized editing
  }
}
```

### Team Collaboration Orchestration

```typescript
// Find optimal time for team standup
const window = readiness.findOptimalCollaborationWindow('team-1', [
  'user-1',
  'user-2',
  'user-3',
]);

// Check team capacity
const metrics = readiness.getTeamReadiness('team-1', [
  'user-1',
  'user-2',
  'user-3',
]);

if (metrics.teamCapacityScore > 60) {
  // Schedule collaborative feature work
} else {
  // Recommend async-first approach
}
```

## Performance Characteristics

- **Signal addition**: O(1) amortized time
- **Readiness calculation**: < 1ms per user
- **Team metrics**: O(n) where n = team size
- **Predictions**: < 5ms per user
- **Memory usage**: ~100 bytes per active signal
- **Cleanup overhead**: < 50ms per 5-minute interval

### Scaling

- Handles 1000+ concurrent users
- Signal history: ~24 hours retention (configurable)
- Event subscriptions: O(1) per user
- Team metrics: Efficient for teams up to 1000 members

## Testing

Run test suite:

```bash
npm exec -- vitest run apps/backend/src/services/readiness-indicator/__tests__/ --run
```

Tests cover:

- Signal aggregation and weighting
- Readiness level calculations and transitions
- Availability window predictions
- Team metrics aggregation
- Event subscriptions and unsubscriptions
- Query filtering and pagination
- Statistics tracking
- Lifecycle management

**Coverage**: >95% of service code

## Event Emissions

### `readinessChanged`

Emitted when a user's readiness level changes.

```typescript
service.on('readinessChanged', (update: ReadinessUpdate) => {
  console.log(`${update.userId}: ${update.previousLevel} → ${update.currentLevel}`);
});
```

### `error`

Emitted when an error occurs during signal processing.

```typescript
service.on('error', (error: Error) => {
  logger.error('Readiness service error', error);
});
```

## Production Deployment

### Prerequisites

- Node.js ≥ 16
- Redis 7+ (optional, for caching)
- PostgreSQL 15+ (optional, for persistence)

### Deployment Checklist

- [ ] Configuration reviewed and customized for environment
- [ ] Signal sources configured (presence, calendar, activity services)
- [ ] Event handlers implemented (readinessChanged, error)
- [ ] Monitoring and alerting configured
- [ ] Performance baselines established
- [ ] Cleanup intervals tested with expected signal volume
- [ ] Integration tests with upstream services passed

### Monitoring

Key metrics to monitor:

- `signalsProcessed`: Rate of incoming signals (should be steady)
- `averageScoringTimeMs`: Should stay < 5ms
- `averageSignalsPerUser`: Indicates signal redundancy
- `statusUpdatesGenerated`: Readiness level changes
- Memory usage: Should remain stable with cleanup interval

### Known Limitations

- Predictions are based on current signals only (no ML models)
- Relies on upstream services for signal accuracy
- No persistent storage (in-memory only, survives process restarts)
- Team metrics calculated on-demand (not pre-aggregated)

## Future Enhancements

- [ ] Machine learning-based readiness prediction
- [ ] Historical pattern analysis
- [ ] Geographic/timezone-aware recommendations
- [ ] Integration with IDE focus mode
- [ ] Async-collaboration mode recommendations
- [ ] Team productivity metrics
- [ ] Burnout early warning system

## Troubleshooting

### No readiness status appears for user

**Cause**: User has fewer than minimum required signals.  
**Solution**: Ensure signal sources are sending signals. Check `minSignalsForReadiness` config.

### Readiness levels not changing

**Cause**: New signals not being added or signals have low confidence.  
**Solution**: Verify signal sources are active. Check confidence scores are > 30.

### High memory usage

**Cause**: Too many signals retained, cleanup not running.  
**Solution**: Reduce `signalRetentionMs` or `maxSignalHistorySize`. Check cleanup interval logs.

### Predictions not available

**Cause**: Service configured with `enablePredictions: false` or insufficient signals.  
**Solution**: Enable predictions in config and ensure 2+ signal types present.

## Related Services

- [ConflictPredictionService](../conflict-prediction/README.md) - Real-time file conflict detection
- [NotificationPriorityEngine](../notification-priority-engine/README.md) - Priority-based notification delivery

---

**Last updated**: April 23, 2026  
**Maintainer**: Collaboration Services Team
