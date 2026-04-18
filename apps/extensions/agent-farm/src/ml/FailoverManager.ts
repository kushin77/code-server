/**
 * Failover Manager
 * Manages failover between replicas and data centers
 */

export type FailoverStrategy = 'active-active' | 'active-passive' | 'active-backup';
export type FailoverTrigger = 'health-check' | 'manual' | 'automatic';

export interface ReplicaHealth {
  replicaId: string;
  isHealthy: boolean;
  lastHeartbeat: number;
  consecutiveFailures: number;
  latency: number;
  capacity: number;
}

export interface FailoverEvent {
  timestamp: number;
  trigger: FailoverTrigger;
  fromReplica: string;
  toReplica: string;
  reason?: string;
  dataLoss?: number; // bytes of potential data loss
}

export interface FailoverConfig {
  strategy: FailoverStrategy;
  healthCheckInterval: number; // milliseconds
  failureThreshold: number; // consecutive failures before failover
  replicationDelay: number; // max acceptable delay in milliseconds
  autoFailover: boolean;
}

export class FailoverManager {
  private config: FailoverConfig;
  private replicas: Map<string, ReplicaHealth> = new Map();
  private primaryReplica?: string;
  private failoverHistory: FailoverEvent[] = [];
  private healthCheckInterval?: NodeJS.Timeout;

  constructor(config: FailoverConfig, primaryReplicaId: string) {
    this.config = config;
    this.primaryReplica = primaryReplicaId;
  }

  /**
   * Register a replica
   */
  registerReplica(replicaId: string, initialHealthy: boolean = true): void {
    this.replicas.set(replicaId, {
      replicaId,
      isHealthy: initialHealthy,
      lastHeartbeat: Date.now(),
      consecutiveFailures: 0,
      latency: 0,
      capacity: 100,
    });
  }

  /**
   * Update replica health
   */
  updateReplicaHealth(
    replicaId: string,
    isHealthy: boolean,
    latency: number,
    capacity: number
  ): void {
    const replica = this.replicas.get(replicaId);
    if (!replica) return;

    replica.lastHeartbeat = Date.now();
    replica.latency = latency;
    replica.capacity = capacity;

    if (isHealthy) {
      replica.consecutiveFailures = 0;
      replica.isHealthy = true;
    } else {
      replica.consecutiveFailures++;
      if (replica.consecutiveFailures >= this.config.failureThreshold) {
        replica.isHealthy = false;
        this.handleReplicaFailure(replicaId);
      }
    }
  }

  /**
   * Handle replica failure
   */
  private handleReplicaFailure(replicaId: string): void {
    if (replicaId === this.primaryReplica && this.config.autoFailover) {
      this.executePrimaryFailover();
    }
  }

  /**
   * Execute primary failover to next healthy replica
   */
  private executePrimaryFailover(): void {
    const healthyReplicas = Array.from(this.replicas.values())
      .filter((r) => r.isHealthy && r.replicaId !== this.primaryReplica)
      .sort((a, b) => a.latency - b.latency);

    if (healthyReplicas.length === 0) {
      // No healthy replicas available
      return;
    }

    const newPrimary = healthyReplicas[0];
    const oldPrimary = this.primaryReplica;

    this.primaryReplica = newPrimary.replicaId;

    this.failoverHistory.push({
      timestamp: Date.now(),
      trigger: 'automatic',
      fromReplica: oldPrimary || '',
      toReplica: newPrimary.replicaId,
      reason: 'Primary replica failure detected',
      dataLoss: 0,
    });
  }

  /**
   * Manual failover
   */
  manualFailover(targetReplicaId: string, reason?: string): boolean {
    const targetReplica = this.replicas.get(targetReplicaId);
    if (!targetReplica || !targetReplica.isHealthy) {
      return false;
    }

    const oldPrimary = this.primaryReplica;
    this.primaryReplica = targetReplicaId;

    this.failoverHistory.push({
      timestamp: Date.now(),
      trigger: 'manual',
      fromReplica: oldPrimary || '',
      toReplica: targetReplicaId,
      reason: reason || 'Manual failover triggered',
      dataLoss: 0,
    });

    return true;
  }

  /**
   * Get primary replica
   */
  getPrimaryReplica(): string | undefined {
    return this.primaryReplica;
  }

  /**
   * Get all healthy replicas
   */
  getHealthyReplicas(): ReplicaHealth[] {
    return Array.from(this.replicas.values()).filter((r) => r.isHealthy);
  }

  /**
   * Get replica health status
   */
  getReplicaHealth(replicaId: string): ReplicaHealth | undefined {
    return this.replicas.get(replicaId);
  }

  /**
   * Get failover history
   */
  getFailoverHistory(limit: number = 50): FailoverEvent[] {
    return this.failoverHistory.slice(-limit);
  }

  /**
   * Start health monitoring
   */
  startHealthMonitoring(): void {
    if (this.healthCheckInterval) return;

    this.healthCheckInterval = setInterval(() => {
      // In real implementation, would perform actual health checks
      for (const replica of this.replicas.values()) {
        const timeSinceHeartbeat = Date.now() - replica.lastHeartbeat;
        if (timeSinceHeartbeat > this.config.healthCheckInterval * 2) {
          // Heartbeat timeout
          this.updateReplicaHealth(replica.replicaId, false, 0, 0);
        }
      }
    }, this.config.healthCheckInterval);
  }

  /**
   * Stop health monitoring
   */
  stopHealthMonitoring(): void {
    if (this.healthCheckInterval) {
      clearInterval(this.healthCheckInterval);
      this.healthCheckInterval = undefined;
    }
  }

  /**
   * Destroy and cleanup
   */
  destroy(): void {
    this.stopHealthMonitoring();
  }
}
