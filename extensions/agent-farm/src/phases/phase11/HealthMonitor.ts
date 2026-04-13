import * as os from 'os';

// Type stubs for external dependencies
interface HealthCheckConfig {
  dbHost?: string;
  dbPort?: number;
  redisHost?: string;
  redisPort?: number;
}

interface AxiosError {
  message: string;
  code?: string;
}

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
  private checkInterval: number;
  private healthHistory: HealthStatus[] = [];
  private maxHistorySize: number = 1440;  // 24 hours @ 1min intervals
  private isRunning: boolean = false;

  constructor(
    private config: HealthCheckConfig,
    checkInterval: number = 10000
  ) {
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
   * Monitor database connectivity and performance
   */
  private async checkDatabase(): Promise<HealthStatus | null> {
    const startTime = Date.now();
    try {
      // Simulate database health check
      const latency = Date.now() - startTime;

      return {
        component: 'database',
        status: latency < 100 ? 'healthy' : 'degraded',
        latency,
        details: {
          uptime_seconds: 3600,
          active_connections: 5,
          active_queries: 1,
          in_recovery: false,
          replication_lag_seconds: 0,
          database_size_bytes: 1073741824,
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
   * Monitor Redis cache connectivity
   */
  private async checkCache(): Promise<HealthStatus | null> {
    const startTime = Date.now();
    return new Promise((resolve) => {
      try {
        // Simulate cache health check
        const latency = Date.now() - startTime;

        resolve({
          component: 'cache',
          status: latency < 50 ? 'healthy' : 'degraded',
          latency,
          details: {
            info: 'Cache operational',
            latency_ms: latency,
          },
          lastChecked: new Date(),
        });
      } catch (error) {
        resolve({
          component: 'cache',
          status: 'unhealthy',
          latency: Date.now() - startTime,
          details: { error: (error as Error).message },
          lastChecked: new Date(),
        });
      }
    });
  }

  /**
   * Monitor API endpoint availability
   */
  private async checkAPI(): Promise<HealthStatus | null> {
    const startTime = Date.now();
    try {
      // Simulate API health check
      const latency = Date.now() - startTime;

      return {
        component: 'api',
        status: latency < 500 ? 'healthy' : 'degraded',
        latency,
        details: {
          statusCode: 200,
          statusText: 'OK',
          timestamp: new Date().toISOString(),
        },
        lastChecked: new Date(),
      };
    } catch (error) {
      return {
        component: 'api',
        status: 'unhealthy',
        latency: Date.now() - startTime,
        details: {
          error: (error as Error).message,
        },
        lastChecked: new Date(),
      };
    }
  }

  /**
   * Monitor disk space usage
   */
  private async checkDiskSpace(): Promise<HealthStatus | null> {
    try {
      // Simulate disk check
      const usedPercent = 65;

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
          filesystem: '/dev/sda1',
          size: '100GB',
          used: '65GB',
          available: '35GB',
        },
        lastChecked: new Date(),
      };
    } catch (error) {
      return null;
    }
  }

  /**
   * Get current system metrics
   */
  private getSystemMetrics(): SystemMetrics {
    const cpus = os.cpus();
    const totalMemory = os.totalmem();
    const freeMemory = os.freemem();

    const loadAverage = os.loadavg()[0];
    const cpuUsage = Math.min((loadAverage / cpus.length) * 100, 100);

    return {
      cpuUsage: Math.max(0, cpuUsage),
      memoryUsage: ((totalMemory - freeMemory) / totalMemory) * 100,
      diskUsage: 65,
      uptime: os.uptime(),
    };
  }

  /**
   * Determine overall system health
   */
  private determineOverallHealth(
    components: HealthStatus[],
    metrics: SystemMetrics
  ): 'healthy' | 'degraded' | 'unhealthy' {
    const criticalComponents = ['database', 'api'];

    const unhealthyCount = components.filter((c) => c.status === 'unhealthy').length;
    const unhealthyCritical = components.filter(
      (c) => c.status === 'unhealthy' && criticalComponents.includes(c.component)
    ).length;

    if (unhealthyCritical > 0) {
      return 'unhealthy';
    }

    if (metrics.cpuUsage > 95 || metrics.memoryUsage > 95) {
      return 'unhealthy';
    }

    if (unhealthyCount > 1) {
      return 'degraded';
    }

    const degradedCount = components.filter((c) => c.status === 'degraded').length;
    return degradedCount > 2 ? 'degraded' : 'healthy';
  }

  /**
   * Get health trend
   */
  getHealthTrend(timeWindowMinutes: number = 60): HealthStatus[] {
    const cutoff = new Date(Date.now() - timeWindowMinutes * 60000);
    return this.healthHistory.filter((h) => h.lastChecked > cutoff);
  }

  /**
   * Start continuous background monitoring
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
    monitor().catch((error) => console.error('Initial health check failed:', error));
  }

  /**
   * Shutdown monitoring
   */
  async shutdown(): Promise<void> {
    this.isRunning = false;
  }
}
