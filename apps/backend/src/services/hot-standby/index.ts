/**
 * @file        apps/backend/src/services/hot-standby/index.ts
 * @module      services/hot-standby
 * @description Exports for hot-standby failover service
 */

export { HotStandbyStateMachine } from './state-machine';
export type {
  BrokerRole,
  BrokerState,
  HeartbeatMessage,
  RemoteBrokerHealth,
  FailoverEvent,
  FailoverEventType,
  HotStandbyConfig,
  FailoverMetrics,
  StateMachineStatus,
} from './types';
