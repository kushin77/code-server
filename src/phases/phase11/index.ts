/**
 * Phase 11: Advanced Resilience, HA/DR & Observability
 * 
 * This module provides enterprise-grade high availability and disaster recovery capabilities:
 * - Continuous health monitoring across all system components
 * - Automatic failover with customizable strategies
 * - Disaster recovery orchestration (backup, recovery, testing)
 * - Chaos engineering for resilience validation
 * - SLO tracking (RTO < 1h, RPO < 15min)
 */

export { HealthMonitor, type HealthStatus, type SystemHealth, type SystemMetrics } from './HealthMonitor';
export { FailoverManager, FailoverState, type FailoverStrategy } from './FailoverManager';
export { ResilienceOrchestrator, type DisasterRecoveryJob } from './ResilienceOrchestrator';
