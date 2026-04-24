#!/usr/bin/env node
// @file        apps/backend/src/services/session-broker/index.ts
// @module      session-broker
// @description Session broker public API exports

export { SessionBrokerService } from './session-broker-service'
export { ConsistentHashRing } from './consistent-hashing'
export type {
  BrokerInstance,
  SessionBrokerConfig,
  SessionRoutingContext,
  HashRingLookup,
  BrokerStats,
  InstanceHealthCheckResult,
} from './types'
