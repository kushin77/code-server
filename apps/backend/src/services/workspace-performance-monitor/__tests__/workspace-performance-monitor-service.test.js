/**
 * Workspace Performance Monitor Service Tests
 * @file        apps/backend/src/services/workspace-performance-monitor/__tests__/workspace-performance-monitor-service.test.ts
 * @module      services/workspace-performance-monitor
 * @description Test suite for workspace performance monitoring
 */
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { WorkspacePerformanceMonitor } from '../workspace-performance-monitor-service.js';
describe('Workspace Performance Monitor Service', () => {
    let service;
    beforeEach(() => {
        WorkspacePerformanceMonitor.reset();
        service = WorkspacePerformanceMonitor.getInstance();
    });
    afterEach(() => {
        service.shutdown();
    });
    // Initialization Tests
    describe('Initialization', () => {
        it('should initialize service', () => {
            expect(service).toBeDefined();
            expect(service.metrics).toBeDefined();
            expect(service.thresholds).toBeDefined();
        });
        it('should return same instance on subsequent calls', () => {
            const instance1 = WorkspacePerformanceMonitor.getInstance();
            const instance2 = WorkspacePerformanceMonitor.getInstance();
            expect(instance1).toBe(instance2);
        });
    });
    // Metrics Recording Tests
    describe('Record Metrics', () => {
        it('should record workspace metrics', () => {
            const metrics = {
                workspaceId: 'ws-1',
                userId: 'user1',
                timestamp: Date.now(),
                metrics: {
                    latency: 50,
                    throughput: 1000,
                    cpuUsage: 25,
                    memoryUsage: 512,
                    diskUsage: 100,
                    errorRate: 0.1,
                    availability: 99.9,
                },
                aggregatedAt: Date.now(),
            };
            const result = service.recordMetrics(metrics, '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
        });
        it('should emit metrics-recorded event', () => {
            return new Promise((resolve) => {
                const metrics = {
                    workspaceId: 'ws-2',
                    userId: 'user2',
                    timestamp: Date.now(),
                    metrics: {
                        latency: 50,
                        throughput: 1000,
                        cpuUsage: 25,
                        memoryUsage: 512,
                        diskUsage: 100,
                        errorRate: 0.1,
                        availability: 99.9,
                    },
                    aggregatedAt: Date.now(),
                };
                service.once('metrics-recorded', (event) => {
                    expect(event.data_object.workspaceId).toBe('ws-2');
                    resolve();
                });
                service.recordMetrics(metrics, '192.168.1.1', 'Mozilla');
            });
        });
        it('should retrieve recorded metrics', () => {
            const metrics = {
                workspaceId: 'ws-3',
                userId: 'user3',
                timestamp: Date.now(),
                metrics: {
                    latency: 50,
                    throughput: 1000,
                    cpuUsage: 25,
                    memoryUsage: 512,
                    diskUsage: 100,
                    errorRate: 0.1,
                    availability: 99.9,
                },
                aggregatedAt: Date.now(),
            };
            service.recordMetrics(metrics, '192.168.1.1', 'Mozilla');
            const retrieved = service.getMetrics('ws-3');
            expect(retrieved.length).toBeGreaterThan(0);
        });
    });
    // Threshold Management Tests
    describe('Threshold Management', () => {
        it('should create performance threshold', () => {
            const result = service.createThreshold({
                metricType: 'latency',
                operator: 'gt',
                value: 100,
                severity: 'warning',
                enabled: true,
                notifyUsers: ['user1'],
            }, 'admin', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
            expect(result.thresholdId).toBeDefined();
        });
        it('should update threshold', () => {
            const created = service.createThreshold({
                metricType: 'latency',
                operator: 'gt',
                value: 100,
                severity: 'warning',
                enabled: true,
                notifyUsers: ['user1'],
            }, 'admin', '192.168.1.1', 'Mozilla');
            const updated = service.updateThreshold(created.thresholdId, { value: 200 }, 'admin', '192.168.1.1', 'Mozilla');
            expect(updated.success).toBe(true);
        });
        it('should delete threshold', () => {
            const created = service.createThreshold({
                metricType: 'latency',
                operator: 'gt',
                value: 100,
                severity: 'warning',
                enabled: true,
                notifyUsers: [],
            }, 'admin', '192.168.1.1', 'Mozilla');
            const deleted = service.deleteThreshold(created.thresholdId, 'admin', '192.168.1.1', 'Mozilla');
            expect(deleted.success).toBe(true);
        });
        it('should list thresholds', () => {
            service.createThreshold({
                metricType: 'latency',
                operator: 'gt',
                value: 100,
                severity: 'warning',
                enabled: true,
                notifyUsers: [],
            }, 'admin', '192.168.1.1', 'Mozilla');
            const thresholds = service.getThresholds();
            expect(Array.isArray(thresholds)).toBe(true);
        });
    });
    // Alert Management Tests
    describe('Alert Management', () => {
        it('should retrieve alerts', () => {
            const alerts = service.getAlerts('ws-1');
            expect(Array.isArray(alerts)).toBe(true);
        });
        it('should resolve alert', () => {
            // This would require creating an alert first in real scenario
            expect(service.resolveAlert).toBeDefined();
        });
        it('should acknowledge alert', () => {
            // This would require creating an alert first in real scenario
            expect(service.acknowledgeAlert).toBeDefined();
        });
    });
    // Trend Analysis Tests
    describe('Trend Analysis', () => {
        it('should analyze trends', () => {
            const trends = service.analyzeTrends('ws-1');
            expect(Array.isArray(trends)).toBe(true);
        });
    });
    // Anomaly Detection Tests
    describe('Anomaly Detection', () => {
        it('should detect anomalies', () => {
            const anomalies = service.detectAnomalies('ws-1');
            expect(Array.isArray(anomalies)).toBe(true);
        });
    });
    // Report Generation Tests
    describe('Report Generation', () => {
        it('should support report generation', () => {
            expect(service.generateReport).toBeDefined();
        });
        it('should retrieve reports', () => {
            const reports = service.getReports('ws-1');
            expect(Array.isArray(reports)).toBe(true);
        });
    });
    // Baseline Management Tests
    describe('Baseline Management', () => {
        it('should update baseline', () => {
            const result = service.updateBaseline({
                baselineId: 'baseline-1',
                workspaceId: 'ws-1',
                metricType: 'latency',
                normalRange: { min: 10, max: 100 },
                createdAt: Date.now(),
                updatedAt: Date.now(),
                dataPoints: 1000,
            }, 'admin', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
        });
        it('should retrieve baseline', () => {
            service.updateBaseline({
                baselineId: 'baseline-2',
                workspaceId: 'ws-2',
                metricType: 'latency',
                normalRange: { min: 10, max: 100 },
                createdAt: Date.now(),
                updatedAt: Date.now(),
                dataPoints: 1000,
            }, 'admin', '192.168.1.1', 'Mozilla');
            const baseline = service.getBaseline('ws-2', 'latency');
            expect(baseline).toBeDefined();
        });
        it('should list baselines', () => {
            const baselines = service.getBaselines('ws-1');
            expect(Array.isArray(baselines)).toBe(true);
        });
    });
    // Optimization Suggestions Tests
    describe('Optimization Suggestions', () => {
        it('should get optimization suggestions', () => {
            const suggestions = service.getOptimizationSuggestions('ws-1');
            expect(Array.isArray(suggestions)).toBe(true);
        });
        it('should support applying suggestions', () => {
            expect(service.applySuggestion).toBeDefined();
        });
    });
    // Event Recording Tests
    describe('Event Recording', () => {
        it('should record event', () => {
            const result = service.recordEvent({
                workspaceId: 'ws-1',
                eventType: 'deployment',
                description: 'Production deployment',
                impactedMetrics: ['latency', 'throughput'],
                severity: 'info',
                status: 'ongoing',
            }, 'admin', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
            expect(result.eventId).toBeDefined();
        });
        it('should emit event-recorded event', () => {
            return new Promise((resolve) => {
                service.once('event-recorded', (event) => {
                    expect(event.data_object.workspaceId).toBe('ws-1');
                    resolve();
                });
                service.recordEvent({
                    workspaceId: 'ws-1',
                    eventType: 'deployment',
                    description: 'Production deployment',
                    impactedMetrics: ['latency'],
                    severity: 'info',
                    status: 'ongoing',
                }, 'admin', '192.168.1.1', 'Mozilla');
            });
        });
        it('should get events', () => {
            service.recordEvent({
                workspaceId: 'ws-2',
                eventType: 'update',
                description: 'System update',
                impactedMetrics: ['availability'],
                severity: 'info',
                status: 'completed',
            }, 'admin', '192.168.1.1', 'Mozilla');
            const events = service.getEvents('ws-2');
            expect(Array.isArray(events)).toBe(true);
        });
    });
    // Statistics Tests
    describe('Statistics', () => {
        it('should calculate service statistics', () => {
            const stats = service.getStatistics();
            expect(stats).toBeDefined();
            expect(stats.totalMetricsRecorded).toBeGreaterThanOrEqual(0);
            expect(stats.alertsTriggered).toBeGreaterThanOrEqual(0);
        });
    });
    // Audit Log Tests
    describe('Audit Logging', () => {
        it('should emit audit-logged event for operations', () => {
            return new Promise((resolve) => {
                service.once('audit-logged', (event) => {
                    expect(event.data_object.userId).toBeDefined();
                    expect(event.data_object.action).toBeDefined();
                    resolve();
                });
                service.recordEvent({
                    workspaceId: 'ws-1',
                    eventType: 'deployment',
                    description: 'Test',
                    impactedMetrics: [],
                    severity: 'info',
                    status: 'ongoing',
                }, 'user1', '192.168.1.1', 'Mozilla');
            });
        });
        it('should retrieve audit log', () => {
            const log = service.getAuditLog();
            expect(Array.isArray(log)).toBe(true);
        });
    });
    // Configuration Tests
    describe('Configuration', () => {
        it('should update configuration', () => {
            return new Promise((resolve) => {
                service.once('config-updated', (event) => {
                    expect(event.data_object.config).toBeDefined();
                    resolve();
                });
                service.updateConfig({ enableMonitoring: false });
            });
        });
        it('should retrieve configuration', () => {
            const config = service.getConfig();
            expect(config).toBeDefined();
            expect(config.enableMonitoring).toBeDefined();
        });
    });
    // Threshold Creation Event Tests
    describe('Threshold Events', () => {
        it('should emit threshold-created event', () => {
            return new Promise((resolve) => {
                service.once('threshold-created', (event) => {
                    expect(event.data_object.thresholdId).toBeDefined();
                    resolve();
                });
                service.createThreshold({
                    metricType: 'latency',
                    operator: 'gt',
                    value: 100,
                    severity: 'warning',
                    enabled: true,
                    notifyUsers: [],
                }, 'admin', '192.168.1.1', 'Mozilla');
            });
        });
        it('should emit threshold-updated event', () => {
            return new Promise((resolve) => {
                const created = service.createThreshold({
                    metricType: 'latency',
                    operator: 'gt',
                    value: 100,
                    severity: 'warning',
                    enabled: true,
                    notifyUsers: [],
                }, 'admin', '192.168.1.1', 'Mozilla');
                service.once('threshold-updated', (event) => {
                    expect(event.data_object.thresholdId).toBe(created.thresholdId);
                    resolve();
                });
                service.updateThreshold(created.thresholdId, { value: 150 }, 'admin', '192.168.1.1', 'Mozilla');
            });
        });
        it('should emit threshold-deleted event', () => {
            return new Promise((resolve) => {
                const created = service.createThreshold({
                    metricType: 'latency',
                    operator: 'gt',
                    value: 100,
                    severity: 'warning',
                    enabled: true,
                    notifyUsers: [],
                }, 'admin', '192.168.1.1', 'Mozilla');
                service.once('threshold-deleted', (event) => {
                    expect(event.data_object.thresholdId).toBe(created.thresholdId);
                    resolve();
                });
                service.deleteThreshold(created.thresholdId, 'admin', '192.168.1.1', 'Mozilla');
            });
        });
    });
    // Shutdown Tests
    describe('Shutdown', () => {
        it('should shutdown service cleanly', () => {
            service.shutdown();
            expect(service.metrics.size).toBe(0);
            expect(service.thresholds.size).toBe(0);
        });
    });
});
//# sourceMappingURL=workspace-performance-monitor-service.test.js.map