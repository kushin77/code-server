/**
 * @file        apps/backend/src/services/hot-standby/types.ts
 * @module      services/hot-standby
 * @description Type definitions for hot-standby failover state machine
 */

/**
 * Broker role in the failover pair
 */
export type BrokerRole = 'primary' | 'replica' | 'unknown';

/**
 * Current health state of a broker
 */
export type BrokerState = 'healthy' | 'degraded' | 'unhealthy' | 'recovering';

/**
 * Failover event types
 */
export type FailoverEventType =
  | 'heartbeat_sent'
  | 'heartbeat_received'
  | 'heartbeat_missed'
  | 'failure_detected'
  | 'promotion_triggered'
  | 'promotion_completed'
  | 'recovery_started'
  | 'recovery_completed'
  | 'split_brain_prevented';

/**
 * Heartbeat message sent between brokers
 */
export interface HeartbeatMessage {
  brokerId: string;
  role: BrokerRole;
  state: BrokerState;
  sessionCount: number;
  timestamp: number;
  latency?: number;
}

/**
 * Remote broker health status
 */
export interface RemoteBrokerHealth {
  brokerId: string;
  lastHeartbeat: number;
  missedCount: number;
  isHealthy: boolean;
  state: BrokerState;
  sessionCount: number;
}

/**
 * Failover event for audit trail
 */
export interface FailoverEvent {
  type: FailoverEventType;
  timestamp: number;
  brokerId: string;
  remoteBrokerId?: string;
  durationMs?: number;
  details?: Record<string, any>;
}

/**
 * Hot standby configuration
 */
export interface HotStandbyConfig {
  heartbeatInterval: number;
  heartbeatTimeout: number;
  failureThreshold: number;
  promotionLockTtl: number;
  recoveryCheckInterval: number;
  maxFailoverHistory: number;
  redisPrefix: string;
  enableAuditLogging: boolean;
}

/**
 * Failover metrics snapshot
 */
export interface FailoverMetrics {
  failureDetectionTime: number;
  promotionTime: number;
  totalFailoverTime: number;
  sessionLoss: number;
  recoveryTime: number;
  lastFailover: number;
}

/**
 * State machine status snapshot
 */
export interface StateMachineStatus {
  brokerId: string;
  role: BrokerRole;
  state: BrokerState;
  isOperational: boolean;
  remoteBrokerHealth: RemoteBrokerHealth | null;
  metrics: FailoverMetrics;
  lastHeartbeatSent: number;
  lastHeartbeatReceived: number;
  configuredRemoteBrokerId: string;
}
