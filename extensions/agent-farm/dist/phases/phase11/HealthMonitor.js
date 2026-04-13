"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.HealthMonitor = void 0;
const os = __importStar(require("os"));
/**
 * HealthMonitor - Continuous system health monitoring
 * Monitors database, cache, API, and system resources
 * Detects degradation and triggers alerts/failover
 */
class HealthMonitor {
    constructor(config, checkInterval = 10000) {
        this.config = config;
        this.healthHistory = [];
        this.maxHistorySize = 1440; // 24 hours @ 1min intervals
        this.isRunning = false;
        this.checkInterval = checkInterval;
    }
    /**
     * Perform comprehensive health check across all components
     */
    async checkHealth() {
        const checks = await Promise.allSettled([
            this.checkDatabase(),
            this.checkCache(),
            this.checkAPI(),
            this.checkDiskSpace(),
        ]);
        const systemMetrics = this.getSystemMetrics();
        const components = [];
        checks.forEach((result) => {
            if (result.status === 'fulfilled' && result.value !== null) {
                components.push(result.value);
            }
        });
        const overall = this.determineOverallHealth(components, systemMetrics);
        const health = {
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
    async checkDatabase() {
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
        }
        catch (error) {
            return {
                component: 'database',
                status: 'unhealthy',
                latency: Date.now() - startTime,
                details: { error: error.message },
                lastChecked: new Date(),
            };
        }
    }
    /**
     * Monitor Redis cache connectivity
     */
    async checkCache() {
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
            }
            catch (error) {
                resolve({
                    component: 'cache',
                    status: 'unhealthy',
                    latency: Date.now() - startTime,
                    details: { error: error.message },
                    lastChecked: new Date(),
                });
            }
        });
    }
    /**
     * Monitor API endpoint availability
     */
    async checkAPI() {
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
        }
        catch (error) {
            return {
                component: 'api',
                status: 'unhealthy',
                latency: Date.now() - startTime,
                details: {
                    error: error.message,
                },
                lastChecked: new Date(),
            };
        }
    }
    /**
     * Monitor disk space usage
     */
    async checkDiskSpace() {
        try {
            // Simulate disk check
            const usedPercent = 65;
            return {
                component: 'disk',
                status: usedPercent < 80
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
        }
        catch (error) {
            return null;
        }
    }
    /**
     * Get current system metrics
     */
    getSystemMetrics() {
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
    determineOverallHealth(components, metrics) {
        const criticalComponents = ['database', 'api'];
        const unhealthyCount = components.filter((c) => c.status === 'unhealthy').length;
        const unhealthyCritical = components.filter((c) => c.status === 'unhealthy' && criticalComponents.includes(c.component)).length;
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
    getHealthTrend(timeWindowMinutes = 60) {
        const cutoff = new Date(Date.now() - timeWindowMinutes * 60000);
        return this.healthHistory.filter((h) => h.lastChecked > cutoff);
    }
    /**
     * Start continuous background monitoring
     */
    startContinuousMonitoring(callback) {
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
            }
            catch (error) {
                console.error('Error during health check:', error);
            }
        };
        setInterval(monitor, this.checkInterval);
        monitor().catch((error) => console.error('Initial health check failed:', error));
    }
    /**
     * Shutdown monitoring
     */
    async shutdown() {
        this.isRunning = false;
    }
}
exports.HealthMonitor = HealthMonitor;
//# sourceMappingURL=HealthMonitor.js.map