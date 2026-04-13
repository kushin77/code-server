import axios from 'axios';
import { SystemHealth } from './HealthMonitor';
import { execSync, spawn } from 'child_process';

/**
 * Failover states during HA/DR operations
 */
export enum FailoverState {
  HEALTHY = 'healthy',
  DEGRADED = 'degraded',
  FAILOVER_IN_PROGRESS = 'failover_in_progress',
  FAILOVER_COMPLETE = 'failover_complete',
}

/**
 * Pluggable failover strategy interface
 */
export interface FailoverStrategy {
  name: string;
  priority: number;
  condition: (health: SystemHealth) => boolean;
  execute: () => Promise<void>;
}

/**
 * FailoverManager - Orchestrates automatic failover operations
 * Detects failures and executes recovery strategies
 */
export class FailoverManager {
  private state: FailoverState = FailoverState.HEALTHY;
  private strategies: FailoverStrategy[] = [];
  private failoverInProgress: boolean = false;
  private lastFailoverTime: Date | null = null;
  private failoverAttempts: number = 0;
  private readonly maxFailoverAttempts: number = 3;
  private readonly failoverCooldown: number = 300000;  // 5 minutes

  constructor() {
    this.registerDefaultStrategies();
  }

  /**
   * Register built-in failover strategies
   */
  private registerDefaultStrategies(): void {
    // Strategy 1: Database failover (highest priority)
    this.registerStrategy({
      name: 'database-failover',
      priority: 1,
      condition: (health: SystemHealth) => {
        const dbStatus = health.components.find((c) => c.component === 'database');
        return (
          dbStatus?.status === 'unhealthy' &&
          health.overall === 'unhealthy'
        );
      },
      execute: async () => {
        await this.promoteStandbyDatabase();
      },
    });

    // Strategy 2: Cache cluster failover
    this.registerStrategy({
      name: 'cache-failover',
      priority: 2,
      condition: (health: SystemHealth) => {
        const cacheStatus = health.components.find((c) => c.component === 'cache');
        return cacheStatus?.status === 'unhealthy';
      },
      execute: async () => {
        await this.failoverCache();
      },
    });

    // Strategy 3: Load balancer reconfiguration
    this.registerStrategy({
      name: 'api-failover',
      priority: 3,
      condition: (health: SystemHealth) => {
        const apiStatus = health.components.find((c) => c.component === 'api');
        return apiStatus?.status === 'unhealthy';
      },
      execute: async () => {
        await this.reconfigureLoadBalancer();
      },
    });
  }

  /**
   * Register custom failover strategy
   */
  registerStrategy(strategy: FailoverStrategy): void {
    this.strategies.push(strategy);
    // Sort by priority (lower number = higher priority)
    this.strategies.sort((a, b) => a.priority - b.priority);
    console.info(`Registered failover strategy: ${strategy.name}`);
  }

  /**
   * Trigger automatic failover based on system health
   */
  async triggerFailover(health: SystemHealth): Promise<void> {
    if (this.failoverInProgress) {
      console.warn('Failover already in progress, skipping...');
      return;
    }

    // Enforce cooldown period to avoid failover storms
    if (
      this.lastFailoverTime &&
      Date.now() - this.lastFailoverTime.getTime() < this.failoverCooldown
    ) {
      console.warn(`Failover cooldown active (${this.failoverCooldown}ms), skipping...`);
      return;
    }

    this.state = FailoverState.FAILOVER_IN_PROGRESS;
    this.failoverInProgress = true;
    this.failoverAttempts = 0;

    try {
      // Find applicable strategies
      const applicableStrategies = this.strategies.filter((s) => s.condition(health));

      if (applicableStrategies.length === 0) {
        console.info('No applicable failover strategies for current health state');
        return;
      }

      const strategyNames = applicableStrategies.map((s) => s.name).join(', ');
      console.warn(`Triggering failover with strategies: ${strategyNames}`);

      // Execute strategies in priority order
      for (const strategy of applicableStrategies) {
        try {
          console.info(`Executing failover strategy: ${strategy.name}`);
          await strategy.execute();
          console.info(`✓ Successfully executed: ${strategy.name}`);
        } catch (error) {
          console.error(`✗ Failed to execute strategy ${strategy.name}:`, error);
          this.failoverAttempts++;

          if (this.failoverAttempts >= this.maxFailoverAttempts) {
            throw new Error(`Max failover attempts exceeded (${this.maxFailoverAttempts})`);
          }
        }
      }

      this.state = FailoverState.FAILOVER_COMPLETE;
      this.lastFailoverTime = new Date();

      // Notify operations
      await this.notifyOpsTeam('WARNING', `Failover completed successfully via: ${strategyNames}`);
    } catch (error) {
      console.error('Failover failed:', error);
      // Alert operations team with critical severity
      await this.notifyOpsTeam(
        'CRITICAL',
        `Failover FAILED: ${(error as Error).message}`
      );
    } finally {
      this.failoverInProgress = false;

      // Reset state after delay
      if (this.state === FailoverState.FAILOVER_COMPLETE) {
        setTimeout(() => {
          this.state = FailoverState.HEALTHY;
        }, 30000);  // 30 second grace period
      }
    }
  }

  /**
   * Promote PostgreSQL standby database to primary
   */
  private async promoteStandbyDatabase(): Promise<void> {
    try {
      console.info('Promoting standby database to primary...');

      // Execute promotion command on standby
      const result = execSync(
        'psql -h standby.example.com -U postgres -c "SELECT pg_promote();"',
        { encoding: 'utf-8' }
      );
      console.info('Database promoted successfully:', result);

      // Wait for promotion to complete
      await new Promise((resolve) => setTimeout(resolve, 5000));

      // Verify promotion
      const verifyResult = execSync(
        'psql -h standby.example.com -U postgres -c "SELECT pg_is_in_recovery();"',
        { encoding: 'utf-8' }
      );

      if (verifyResult.includes('f')) {
        console.info('✓ Standby promotion verified (not in recovery)');
      } else {
        throw new Error('Promotion verification failed: still in recovery mode');
      }

      // Update connection strings for all services
      await this.updateServiceConnections('primary');
    } catch (error) {
      throw new Error(`Database promotion failed: ${(error as Error).message}`);
    }
  }

  /**
   * Failover Redis cache cluster
   */
  private async failoverCache(): Promise<void> {
    try {
      console.info('Initiating Redis cache failover...');

      // Trigger Redis cluster failover
      const result = execSync(
        'redis-cli -h redis-cluster -p 7000 CLUSTER FAILOVER',
        { encoding: 'utf-8' }
      );
      console.info('Cache failover initiated:', result);

      // Wait for failover
      await new Promise((resolve) => setTimeout(resolve, 10000));

      // Verify cluster health
      const healthCheck = execSync(
        'redis-cli -h redis-cluster -p 7000 CLUSTER INFO',
        { encoding: 'utf-8' }
      );

      if (healthCheck.includes('cluster_state:ok')) {
        console.info('✓ Redis cluster failover completed successfully');
      } else {
        console.warn('Redis cluster in degraded state, monitoring...');
      }
    } catch (error) {
      throw new Error(`Cache failover failed: ${(error as Error).message}`);
    }
  }

  /**
   * Reconfigure load balancer to exclude failed backend
   */
  private async reconfigureLoadBalancer(): Promise<void> {
    try {
      console.info('Reconfiguring load balancer...');

      // Reload HAProxy with new configuration
      const result = execSync('systemctl reload haproxy', { encoding: 'utf-8' });
      console.info('Load balancer reconfigured:', result);

      // Verify HAProxy is healthy
      const stats = execSync(
        'curl -s http://localhost:8404/stats | grep "Healthy"',
        { encoding: 'utf-8' }
      );
      console.info('Load balancer health verified');
    } catch (error) {
      throw new Error(`Load balancer update failed: ${(error as Error).message}`);
    }
  }

  /**
   * Update service discovery with new database connection
   */
  private async updateServiceConnections(node: string): Promise<void> {
    try {
      console.info(`Updating service discovery to point to ${node}...`);

      // Register new service endpoint with Consul
      execSync(
        `consul services register -id code-server-${node} -name code-server`,
        { encoding: 'utf-8' }
      );

      console.info(`✓ Service discovery updated to ${node}`);
    } catch (error) {
      throw new Error(`Service discovery update failed: ${(error as Error).message}`);
    }
  }

  /**
   * Notify operations team via Slack and PagerDuty
   */
  private async notifyOpsTeam(severity: string, message: string): Promise<void> {
    try {
      // Send to Slack
      const slackWebhook = process.env.SLACK_WEBHOOK_URL;
      if (slackWebhook) {
        await axios.post(slackWebhook, {
          text: `*[${severity}] Failover Alert*\n${message}`,
          color: severity === 'CRITICAL' ? 'danger' : 'warning',
        });
      }

      // Send to PagerDuty for critical events
      if (severity === 'CRITICAL') {
        const pagerdutyKey = process.env.PAGERDUTY_KEY;
        if (pagerdutyKey) {
          await axios.post('https://events.pagerduty.com/v2/enqueue', {
            routing_key: pagerdutyKey,
            event_action: 'trigger',
            dedup_key: `failover-${Date.now()}`,
            payload: {
              summary: message,
              severity: 'critical',
              source: 'HA/DR System - Failover Manager',
              timestamp: new Date().toISOString(),
            },
          });
        }
      }
    } catch (error) {
      console.error('Failed to send notification:', error);
    }
  }

  /**
   * Get current failover state
   */
  getState(): FailoverState {
    return this.state;
  }

  /**
   * Get failover statistics
   */
  getFailoverStats(): {
    state: FailoverState;
    lastFailoverTime: Date | null;
    failoverAttempts: number;
  } {
    return {
      state: this.state,
      lastFailoverTime: this.lastFailoverTime,
      failoverAttempts: this.failoverAttempts,
    };
  }
}
