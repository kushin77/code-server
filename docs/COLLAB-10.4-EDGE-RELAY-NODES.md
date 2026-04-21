# Collab-10.4 Edge Relay Nodes

## Overview

This change introduces a dedicated edge-relay selection layer for globally distributed collaboration traffic.

The goal is to keep interactive sessions under a 50 ms relay target when possible, while preserving session affinity and enabling seamless migration when a relay becomes unhealthy or overloaded.

## What It Adds

- Edge relay registration with region, endpoint, capacity, and health state
- Session-aware relay selection
- Affinity-based reuse of the current relay for follow-up requests
- Relay migration for failover or draining
- Latency sampling and p95 tracking
- Relay health and session migration metrics

## How It Works

1. A session is routed to the best available relay.
2. The manager prefers healthy relays with the lowest measured latency.
3. If the current relay is still healthy, the session stays pinned to it.
4. If a relay is drained or unhealthy, active sessions are migrated to another relay.

## Configuration

```ts
const relayManager = new EdgeRelayManager({
  regions: ['us-east-1', 'eu-west-1', 'ap-south-1'],
  targetLatencyMs: 50,
  affinityTimeoutMs: 300000,
  healthStalenessMs: 30000,
  maxSessionsPerRelay: 100,
});
```

## Runtime Operations

### Register a Relay

```ts
relayManager.registerRelay({
  relayId: 'relay-us-east-1-a',
  regionId: 'us-east-1',
  endpoint: 'wss://relay-us-east-1-a.example.com',
  healthy: true,
  latencyMs: 28,
  capacity: 100,
});
```

### Select a Relay for a Session

```ts
const decision = relayManager.selectRelay({
  sessionId: 'session-123',
  preferredRegions: ['us-east-1'],
});
```

### Migrate a Session

```ts
relayManager.migrateSession('session-123', 'relay-eu-west-1-a', 'relay failure');
```

## Metrics

The manager exposes:

- total relays
- healthy relays
- average relay latency
- affinity size
- total selections
- total migrations

## Tests

The new test suite validates:

- target-latency selection
- session affinity retention
- migration on relay failure
- relay draining behavior
- metrics reporting

## Related Routing Stack

This feature complements the existing routing primitives in:

- [src/services/routing/GeoRouter.ts](../src/services/routing/GeoRouter.ts)
- [src/services/routing/LoadBalancer.ts](../src/services/routing/LoadBalancer.ts)
- [src/services/routing/FailoverManager.ts](../src/services/routing/FailoverManager.ts)

## Status

Implemented for Collab-10.4.