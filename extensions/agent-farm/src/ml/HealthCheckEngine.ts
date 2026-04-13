/**
 * Phase 8: Advanced Kubernetes & Microservices
 * Health Check Engine - Comprehensive service health monitoring
 */

export interface HealthCheckConfig {
  type: 'http' | 'tcp' | 'exec' | 'grpc';
  endpoint: string;
  initialDelaySeconds: number;
  periodSeconds: number;
  timeoutSeconds: number;
  successThreshold: number;
  failureThreshold: number;
}

export interface HealthStatus {
  serviceName: string;
  status: 'healthy' | 'unhealthy' | 'unknown';
  lastCheck: number;
  checks: Array<{
    type: string;
    status: boolean;
    latency: number;
    error?: string;
  }>;
  consecutiveFailures: number;
  consecutiveSuccesses: number;
  uptime: number; // percentage
}

export interface ServiceHealth {
  serviceName: string;
  httpStatus: HealthStatus | null;
  tcpStatus: HealthStatus | null;
  grpcStatus: HealthStatus | null;
  dependencies: Array<{ service: string; healthy: boolean }>;
  overall: 'healthy' | 'degraded' | 'unhealthy';
}

/**
 * Health Check Engine
 */
export class HealthCheckEngine {
  private healthStatuses: Map<string, ServiceHealth>;
  private configs: Map<string, HealthCheckConfig>;
  private checkIntervals: Map<string, NodeJS.Timeout>;
  private history: Map<string, Array<{ timestamp: number; status: 'healthy' | 'unhealthy' }>>;

  constructor() {
    this.healthStatuses = new Map();
    this.configs = new Map();
    this.checkIntervals = new Map();
    this.history = new Map();
  }

  /**
   * Register health check configuration
   */
  registerHealthCheck(serviceName: string, config: HealthCheckConfig): void {
    this.configs.set(`${serviceName}-${config.type}`, config);
  }

  /**
   * Start health checks for service
   */
  startHealthChecks(serviceName: string): void {
    const configs = Array.from(this.configs.entries())
      .filter(([key]) => key.startsWith(serviceName))
      .map(([, config]) => config);

    if (configs.length === 0) return;

    const checkInterval = setInterval(async () => {
      await this.performHealthChecks(serviceName);
    }, configs[0].periodSeconds * 1000);

    this.checkIntervals.set(serviceName, checkInterval);
  }

  /**
   * Stop health checks for service
   */
  stopHealthChecks(serviceName: string): void {
    const interval = this.checkIntervals.get(serviceName);
    if (interval) {
      clearInterval(interval);
      this.checkIntervals.delete(serviceName);
    }
  }

  /**
   * Perform health checks
   */
  private async performHealthChecks(serviceName: string): Promise<void> {
    const health: ServiceHealth = {
      serviceName,
      httpStatus: null,
      tcpStatus: null,
      grpcStatus: null,
      dependencies: [],
      overall: 'healthy',
    };

    // Perform checks
    const httpConfig = this.configs.get(`${serviceName}-http`);
    if (httpConfig) {
      health.httpStatus = await this.performHTTPCheck(serviceName, httpConfig);
    }

    const tcpConfig = this.configs.get(`${serviceName}-tcp`);
    if (tcpConfig) {
      health.tcpStatus = await this.performTCPCheck(serviceName, tcpConfig);
    }

    const grpcConfig = this.configs.get(`${serviceName}-grpc`);
    if (grpcConfig) {
      health.grpcStatus = await this.performGRPCCheck(serviceName, grpcConfig);
    }

    // Determine overall health
    const statuses = [health.httpStatus, health.tcpStatus, health.grpcStatus].filter((s) => s !== null);
    const unhealthy = statuses.filter((s) => s!.status === 'unhealthy').length;

    if (unhealthy === 0) {
      health.overall = 'healthy';
    } else if (unhealthy < statuses.length) {
      health.overall = 'degraded';
    } else {
      health.overall = 'unhealthy';
    }

    // Record history
    const history = this.history.get(serviceName) || [];
    history.push({
      timestamp: Date.now(),
      status: health.overall === 'healthy' ? 'healthy' : 'unhealthy',
    });

    // Keep only last 100 entries
    if (history.length > 100) {
      history.shift();
    }

    this.history.set(serviceName, history);
    this.healthStatuses.set(serviceName, health);
  }

  /**
   * Perform HTTP health check
   */
  private async performHTTPCheck(serviceName: string, config: HealthCheckConfig): Promise<HealthStatus> {
    const startTime = performance.now();
    let status: 'healthy' | 'unhealthy' | 'unknown' = 'unknown';
    let error: string | undefined;

    try {
      const response = await fetch(config.endpoint, { timeout: config.timeoutSeconds * 1000 }).catch(
        () => null
      );
      const latency = performance.now() - startTime;

      if (response && response.status >= 200 && response.status < 300) {
        status = 'healthy';
      } else {
        status = 'unhealthy';
        error = `HTTP ${response?.status || 'timeout'}`;
      }

      const existing = this.healthStatuses.get(serviceName)?.httpStatus;
      const consecutiveFailures = status === 'unhealthy' ? (existing?.consecutiveFailures || 0) + 1 : 0;
      const consecutiveSuccesses = status === 'healthy' ? (existing?.consecutiveSuccesses || 0) + 1 : 0;

      return {
        serviceName,
        status,
        lastCheck: Date.now(),
        checks: [
          {
            type: 'http',
            status: status === 'healthy',
            latency,
            error,
          },
        ],
        consecutiveFailures,
        consecutiveSuccesses,
        uptime: this.calculateUptime(serviceName),
      };
    } catch (err) {
      return {
        serviceName,
        status: 'unhealthy',
        lastCheck: Date.now(),
        checks: [
          {
            type: 'http',
            status: false,
            latency: performance.now() - startTime,
            error: err instanceof Error ? err.message : 'Unknown error',
          },
        ],
        consecutiveFailures: 1,
        consecutiveSuccesses: 0,
        uptime: this.calculateUptime(serviceName),
      };
    }
  }

  /**
   * Perform TCP health check
   */
  private async performTCPCheck(serviceName: string, config: HealthCheckConfig): Promise<HealthStatus> {
    const startTime = performance.now();
    // Simplified TCP check simulation
    const latency = Math.random() * 50;
    const status = Math.random() > 0.1 ? 'healthy' : 'unhealthy';

    return {
      serviceName,
      status: status as any,
      lastCheck: Date.now(),
      checks: [{ type: 'tcp', status: status === 'healthy', latency }],
      consecutiveFailures: 0,
      consecutiveSuccesses: 0,
      uptime: this.calculateUptime(serviceName),
    };
  }

  /**
   * Perform gRPC health check
   */
  private async performGRPCCheck(serviceName: string, config: HealthCheckConfig): Promise<HealthStatus> {
    const startTime = performance.now();
    // Simplified gRPC check simulation
    const latency = Math.random() * 100;
    const status = Math.random() > 0.05 ? 'healthy' : 'unhealthy';

    return {
      serviceName,
      status: status as any,
      lastCheck: Date.now(),
      checks: [{ type: 'grpc', status: status === 'healthy', latency }],
      consecutiveFailures: 0,
      consecutiveSuccesses: 0,
      uptime: this.calculateUptime(serviceName),
    };
  }

  /**
   * Calculate uptime percentage
   */
  private calculateUptime(serviceName: string): number {
    const history = this.history.get(serviceName) || [];
    if (history.length === 0) return 100;

    const healthy = history.filter((h) => h.status === 'healthy').length;
    return (healthy / history.length) * 100;
  }

  /**
   * Get service health status
   */
  getServiceHealth(serviceName: string): ServiceHealth | null {
    return this.healthStatuses.get(serviceName) || null;
  }

  /**
   * Get health of all services
   */
  getAllHealth(): Map<string, ServiceHealth> {
    return this.healthStatuses;
  }

  /**
   * Get health statistics
   */
  getHealthStats(): {
    totalServices: number;
    healthyServices: number;
    degradedServices: number;
    unhealthyServices: number;
    averageUptime: number;
  } {
    let healthy = 0;
    let degraded = 0;
    let unhealthy = 0;
    let totalUptime = 0;

    this.healthStatuses.forEach((health) => {
      if (health.overall === 'healthy') healthy++;
      if (health.overall === 'degraded') degraded++;
      if (health.overall === 'unhealthy') unhealthy++;
      totalUptime +=
        (health.httpStatus?.uptime || 0) + (health.tcpStatus?.uptime || 0) + (health.grpcStatus?.uptime || 0);
    });

    const totalServices = this.healthStatuses.size;
    const checkCount = Array.from(this.healthStatuses.values()).reduce(
      (sum, h) => sum + (h.httpStatus ? 1 : 0) + (h.tcpStatus ? 1 : 0) + (h.grpcStatus ? 1 : 0),
      0
    );

    return {
      totalServices,
      healthyServices: healthy,
      degradedServices: degraded,
      unhealthyServices: unhealthy,
      averageUptime: checkCount > 0 ? totalUptime / checkCount : 100,
    };
  }
}

export default HealthCheckEngine;
