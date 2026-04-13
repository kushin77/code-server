import * as os from 'os';
import axios, { AxiosError } from 'axios';
import pg from 'pg';
import redis from 'redis';

/**
 * Health status for a specific component
 */
export interface HealthStatus {
  component: string;
  status: 'healthy' | 'degraded' | 'unhealthy';
  latency: number;  // milliseconds
  details: Record<string, any>;
  lastChecked: Date;
}

/**
 * Overall system health snapshot
 */
export interface SystemHealth {
  overall: 'healthy' | 'degraded' | 'unhealthy';
  checkedAt: Date;
  components: HealthStatus[];
  systemMetrics: SystemMetrics;
}

/**
 * System-level performance metrics
 */
export interface SystemMetrics {
  cpuUsage: number;  // 0-100
  memoryUsage: number;  // 0-100
  diskUsage: number;  // 0-100
  uptime: number;  // seconds
}

/**
 * HealthMonitor - Continuous system health monitoring
 * Monitors database, cache, API, and system resources
 * Detects degradation and triggers alerts/failover
 */
export class HealthMonitor {
  private dbPool: pg.Pool;
  private redisClient: redis.RedisClient;
  private checkInterval: number;
  private healthHistory: HealthStatus[] = [];
  private maxHistorySize: number = 1440;  // 24 hours @ 1min intervals
  private isRunning: boolean = false;

  constructor(
    dbConfig: pg.PoolConfig,
    redisConfig: redis.ClientOpts,
    checkInterval: number = 10000
  ) {
    this.dbPool = new pg.Pool(dbConfig);
    this.redisClient = redis.createClient(redisConfig);
    this.checkInterval = checkInterval;
  }

  /**
   * Perform comprehensive health check across all components
   */
  async checkHealth(): Promise<SystemHealth> {
    const checks = await Promise.allSettled([
      this.checkDatabase(),
      this.checkCache(),
      this.checkAPI(),
      this.checkDiskSpace(),
    ]);

    const systemMetrics = this.getSystemMetrics();
    const components: HealthStatus[] = [];

    checks.forEach((result) => {
      if (result.status === 'fulfilled' && result.value !== null) {
        components.push(result.value);
      }
    });

    const overall = this.determineOverallHealth(components, systemMetrics);

    const health: SystemHealth = {
      overall,
      checkedAt: new Date(),
      components,
      systemMetrics,
    };

    // Maintain health history
    components.forEach((c) => this.healthHistory.push(c));
    if (this.healthHistory.length > this.maxHistorySize) {
      this.healthHistory = this.healthHistory.slice(-this.maxHistorySize);
    }

    return health;
  }

  /**
   * Monitor database connectivity, replication status, and performance
   */
  private async checkDatabase(): Promise<HealthStatus | null> {
    const startTime = Date.now();
    try {
      const client = await this.dbPool.connect();

      const result = await client.query(
        `SELECT 
          extract(epoch from (NOW() - pg_postmaster_start_time())) as uptime_seconds,
          (SELECT count(*) FROM pg_stat_activity) as active_connections,
          (SELECT count(*) FROM pg_stat_activity WHERE state = 'active') as active_queries,
          pg_is_in_recovery() as in_recovery,
          (SELECT 
            EXTRACT(EPOCH FROM MAX(pg_last_xact_replay_timestamp()))::int 
            FROM pg_stat_replication
          ) as max_replication_lag_seconds,
          (SELECT datsize FROM pg_database_size('code_server')) as database_size`
      );

      client.release();
      const latency = Date.now() - startTime;
      const row = result.rows[0];

      // Consider unhealthy if replication lag > 60 seconds
      const isHealthy = !row.max_replication_lag_seconds || row.max_replication_lag_seconds < 60;
      const isDegraded = !isHealthy && row.max_replication_lag_seconds < 120;

      return {
        component: 'database',
        status: isHealthy ? 'healthy' : isDegraded ? 'degraded' : 'unhealthy',
        latency,
        details: {
          uptime_seconds: Math.floor(row.uptime_seconds),
          active_connections: row.active_connections,
          active_queries: row.active_queries,
          in_recovery: row.in_recovery,
          replication_lag_seconds: row.max_replication_lag_seconds || 0,
          database_size_bytes: row.database_size,
        },
        lastChecked: new Date(),
      };
    } catch (error) {
      return {
        component: 'database',
        status: 'unhealthy',
        latency: Date.now() - startTime,
        details: { error: (error as Error).message },
        lastChecked: new Date(),
      };
    }
  }

  /**
   * Monitor Redis cache connectivity and cluster health
   */
  private async checkCache(): Promise<HealthStatus | null> {
    const startTime = Date.now();
    return new Promise((resolve) => {
      this.redisClient.ping((err, reply) => {
        const latency = Date.now() - startTime;

        if (err || reply !== 'PONG') {
          resolve({
            component: 'cache',
            status: 'unhealthy',
            latency,
            details: { error: err?.message || 'Invalid PONG response' },
            lastChecked: new Date(),
          });
          return;
        }

        // Get cache stats
        this.redisClient.info('stats', (infoErr, info) => {
          resolve({
            component: 'cache',
            status: latency < 50 ? 'healthy' : 'degraded',
            latency,
            details: {
              info: info || 'N/A',
              latency_ms: latency,
            },
            lastChecked: new Date(),
          });
        });
      });
    });
  }

  /**
   * Monitor API endpoint availability and response times
   */
  private async checkAPI(): Promise<HealthStatus | null> {
    const startTime = Date.now();
    try {
      const response = await axios.get('http://localhost:8080/healthz', {
        timeout: 5000,
        validateStatus: () => true,
      });

      const latency = Date.now() - startTime;
      const isHealthy = response.status === 200;

      return {
        component: 'api',
        status: isHealthy ? (latency < 500 ? 'healthy' : 'degraded') : 'unhealthy',
        latency,
        details: {
          statusCode: response.status,
          statusText: response.statusText,
          timestamp: new Date().toISOString(),
        },
        lastChecked: new Date(),
      };
    } catch (error) {
      const axiosError = error as AxiosError;
      return {
        component: 'api',
        status: 'unhealthy',
        latency: Date.now() - startTime,
        details: {
          error: axiosError.message || 'Unknown error',
          code: axiosError.code,
        },
        lastChecked: new Date(),
      };
    }
  }

  /**
   * Monitor disk space usage on main volume
   */
  private async checkDiskSpace(): Promise<HealthStatus | null> {
    try {
      const exec = require('util').promisify(require('child_process').exec);
      const { stdout } = await exec('df -h / | tail -1');
      const parts = stdout.trim().split(/\s+/);
      const usedPercent = parseInt(parts[4] || '0');

      return {
        component: 'disk',
        status:
          usedPercent < 80
            ? 'healthy'
            : usedPercent < 90
            ? 'degraded'
            : 'unhealthy',
        latency: 0,
        details: {
          usedPercent,
          filesystem: parts[0],
          size: parts[1],
          used: parts[2],
          available: parts[3],
        },
        lastChecked: new Date(),
      };
    } catch (error) {
      // Graceful degradation if disk check fails
      return null;
    }
  }

  /**
   * Get current system metrics (CPU, memory, uptime)
   */
  private getSystemMetrics(): SystemMetrics {
    const cpus = os.cpus();
    const totalMemory = os.totalmem();
    const freeMemory = os.freemem();

    // CPU usage based on load average
    const loadAverage = os.loadavg()[0];
    const cpuUsage = Math.min((loadAverage / cpus.length) * 100, 100);

    return {
      cpuUsage: Math.max(0, cpuUsage),
      memoryUsage: ((totalMemory - freeMemory) / totalMemory) * 100,
      diskUsage: 0,  // Set by checkDiskSpace
      uptime: os.uptime(),
    };
  }

  /**
   * Determine overall system health based on component status and metrics
   */
  private determineOverallHealth(
    components: HealthStatus[],
    metrics: SystemMetrics
  ): 'healthy' | 'degraded' | 'unhealthy' {
    const criticalComponents = ['database', 'api'];

    // Count unhealthy components
    const unhealthyCount = components.filter((c) => c.status === 'unhealthy').length;
    const unhealthyCritical = components.filter(
      (c) => c.status === 'unhealthy' && criticalComponents.includes(c.component)
    ).length;

    // Critical infrastructure down
    if (unhealthyCritical > 0) {
      return 'unhealthy';
    }

    // Resource exhaustion
    if (metrics.cpuUsage > 95 || metrics.memoryUsage > 95) {
      return 'unhealthy';
    }

    // Multiple components failing
    if (unhealthyCount > 1) {
      return 'degraded';
    }

    // Some components degraded
    const degradedCount = components.filter((c) => c.status === 'degraded').length;
    return degradedCount > 2 ? 'degraded' : 'healthy';
  }

  /**
   * Get health trend analysis over time window
   */
  getHealthTrend(timeWindowMinutes: number = 60): HealthStatus[] {
    const cutoff = new Date(Date.now() - timeWindowMinutes * 60000);
    return this.healthHistory.filter((h) => h.lastChecked > cutoff);
  }

  /**
   * Start continuous background health monitoring
   */
  startContinuousMonitoring(callback: (health: SystemHealth) => Promise<void>) {
    if (this.isRunning) {
      console.warn('Health monitoring already started');
      return;
    }

    this.isRunning = true;
    console.info(`Starting health monitoring every ${this.checkInterval}ms`);

    const monitor = async () => {
      try {
        const health = await this.checkHealth();
        await callback(health);
      } catch (error) {
        console.error('Error during health check:', error);
      }
    };

    setInterval(monitor, this.checkInterval);
    // Run immediately
    monitor().catch((error) => console.error('Initial health check failed:', error));
  }

  /**
   * Cleanup and shutdown monitoring
   */
  async shutdown(): Promise<void> {
    this.isRunning = false;
    await this.dbPool.end();
    return new Promise((resolve) => {
      this.redisClient.quit(() => resolve());
    });
  }
}
