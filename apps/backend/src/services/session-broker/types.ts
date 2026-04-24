#!/usr/bin/env node
// @file        apps/backend/src/services/session-broker/types.ts
// @module      session-broker
// @description Type definitions for session-broker horizontal scaling

/**
 * Represents a single instance in the broker pool
 */
export interface BrokerInstance {
  id: string
  host: string
  port: number
  weight?: number // For weighted consistent hashing
  status: 'healthy' | 'unhealthy' | 'draining'
  lastHealthCheck?: number
}

/**
 * Configuration for session broker
 */
export interface SessionBrokerConfig {
  instances: BrokerInstance[]
  replicationFactor?: number // Number of replicas for hash ring
  virtualNodes?: number // Virtual nodes per instance for better distribution
  healthCheckInterval?: number // ms between health checks
  healthCheckTimeout?: number // ms timeout for each check
}

/**
 * Result of hash ring lookup
 */
export interface HashRingLookup {
  instance: BrokerInstance
  replicas: BrokerInstance[] // Ordered list of replica instances
}

/**
 * Session routing context
 */
export interface SessionRoutingContext {
  sessionId: string
  userId: string
  workspaceId: string
}

/**
 * Broker statistics
 */
export interface BrokerStats {
  instanceId: string
  requestCount: number
  errorCount: number
  latencyP50: number
  latencyP95: number
  latencyP99: number
  lastUpdated: number
}

/**
 * Health check response
 */
export interface InstanceHealthCheckResult {
  instanceId: string
  healthy: boolean
  responseTime: number
  error?: string
}
