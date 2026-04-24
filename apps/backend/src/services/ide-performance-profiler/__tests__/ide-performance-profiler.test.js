import { describe, it, expect, beforeEach, vi } from 'vitest';
import { IDEPerformanceProfilerService } from '../index';
vi.mock('../../../lib/logger', () => ({
    getLogger: () => ({
        info: vi.fn(),
        error: vi.fn(),
        debug: vi.fn(),
        warn: vi.fn()
    })
}));
describe('IDEPerformanceProfilerService', () => {
    let service;
    let mockPool;
    let mockClient;
    beforeEach(() => {
        mockClient = {
            query: vi.fn(),
            release: vi.fn()
        };
        mockPool = {
            connect: vi.fn().mockResolvedValue(mockClient)
        };
        service = new IDEPerformanceProfilerService(mockPool);
    });
    it('should initialize service and create tables', async () => {
        mockClient.query.mockResolvedValueOnce({});
        mockClient.query.mockResolvedValueOnce({});
        mockClient.query.mockResolvedValueOnce({});
        mockClient.query.mockResolvedValueOnce({});
        mockClient.query.mockResolvedValueOnce({});
        mockClient.query.mockResolvedValueOnce({});
        await service.initialize();
        expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('extension_metrics'));
        expect(mockClient.release).toHaveBeenCalled();
    });
    it('should record extension metrics', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'metric-1',
                    extension_id: 'ext-1',
                    extension_name: 'Test Extension',
                    startup_time_ms: 100,
                    activation_time_ms: 50,
                    latency_ms: 30,
                    health_score: 80,
                    is_disabled: false,
                    disable_reason: null,
                    measured_at: new Date('2025-04-21T10:00:00')
                }]
        });
        const metrics = await service.recordExtensionMetrics('ext-1', 'Test Extension', 100, 50, 30);
        expect(metrics.extensionId).toBe('ext-1');
        expect(metrics.healthScore).toBeGreaterThan(0);
        expect(metrics.startupTime).toBe(100);
    });
    it('should get extension metrics history', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [
                { extension_id: 'ext-1', extension_name: 'Test', startup_time_ms: 100, activation_time_ms: 50, latency_ms: 30, health_score: 80, is_disabled: false, disable_reason: null, measured_at: new Date() },
                { extension_id: 'ext-1', extension_name: 'Test', startup_time_ms: 110, activation_time_ms: 55, latency_ms: 35, health_score: 75, is_disabled: false, disable_reason: null, measured_at: new Date() }
            ]
        });
        const metrics = await service.getExtensionMetrics('ext-1');
        expect(metrics.length).toBe(2);
        expect(metrics[0].extensionId).toBe('ext-1');
    });
    it('should get performance profile for session', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'session-1',
                    session_id: 'sess-1',
                    overall_health_score: 75,
                    slow_extension_count: 2,
                    recorded_at: new Date('2025-04-21T10:00:00')
                }]
        });
        mockClient.query.mockResolvedValueOnce({
            rows: [
                { extension_id: 'ext-1', extension_name: 'Slow Ext 1', startup_time_ms: 200, activation_time_ms: 100, latency_ms: 50, health_score: 40, is_disabled: false, disable_reason: null, measured_at: new Date() },
                { extension_id: 'ext-2', extension_name: 'Fast Ext', startup_time_ms: 50, activation_time_ms: 20, latency_ms: 10, health_score: 90, is_disabled: false, disable_reason: null, measured_at: new Date() }
            ]
        });
        const profile = await service.getPerformanceProfile('sess-1');
        expect(profile).not.toBeNull();
        expect(profile?.extensions.length).toBe(2);
        expect(profile?.slowExtensions.length).toBe(1);
    });
    it('should disable extension when health score is poor', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'metric-1',
                    extension_id: 'bad-ext',
                    extension_name: 'Bad Extension',
                    startup_time_ms: 500,
                    activation_time_ms: 400,
                    latency_ms: 300,
                    health_score: 15,
                    is_disabled: false,
                    disable_reason: null,
                    measured_at: new Date()
                }]
        });
        mockClient.query.mockResolvedValueOnce({});
        mockClient.query.mockResolvedValueOnce({});
        const metrics = await service.recordExtensionMetrics('bad-ext', 'Bad Extension', 500, 400, 300);
        expect(metrics.healthScore).toBeLessThan(20);
    });
    it('should manually disable extension', async () => {
        mockClient.query.mockResolvedValueOnce({});
        mockClient.query.mockResolvedValueOnce({});
        await service.disableExtension('ext-slow', 'Performance degradation');
        expect(mockClient.query).toHaveBeenCalled();
    });
    it('should enable extension', async () => {
        mockClient.query.mockResolvedValueOnce({});
        mockClient.query.mockResolvedValueOnce({});
        await service.enableExtension('ext-slow');
        expect(mockClient.query).toHaveBeenCalled();
    });
    it('should get slow extensions', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [
                { extension_id: 'ext-slow-1', extension_name: 'Slow 1', startup_time_ms: 300, activation_time_ms: 200, latency_ms: 100, health_score: 30, is_disabled: false, disable_reason: null, measured_at: new Date() },
                { extension_id: 'ext-slow-2', extension_name: 'Slow 2', startup_time_ms: 250, activation_time_ms: 180, latency_ms: 90, health_score: 35, is_disabled: false, disable_reason: null, measured_at: new Date() }
            ]
        });
        const slowExts = await service.getSlowExtensions(50);
        expect(slowExts.length).toBe(2);
        expect(slowExts[0].healthScore).toBeLessThan(50);
    });
    it('should cleanup old metrics', async () => {
        mockClient.query.mockResolvedValueOnce({
            rowCount: 1000
        });
        const count = await service.cleanupOldMetrics(30);
        expect(count).toBe(1000);
    });
    it('should return null for non-existent profile', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: []
        });
        const profile = await service.getPerformanceProfile('non-existent');
        expect(profile).toBeNull();
    });
    it('should emit metrics-recorded event', async () => {
        let emittedEvent;
        service.on('metrics-recorded', (event) => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'metric-1',
                    extension_id: 'ext-1',
                    extension_name: 'Test',
                    startup_time_ms: 100,
                    activation_time_ms: 50,
                    latency_ms: 30,
                    health_score: 80,
                    is_disabled: false,
                    disable_reason: null,
                    measured_at: new Date()
                }]
        });
        await service.recordExtensionMetrics('ext-1', 'Test', 100, 50, 30);
        expect(emittedEvent).toBeDefined();
        expect(emittedEvent.extensionId).toBe('ext-1');
    });
    it('should emit extension-disabled event', async () => {
        let emittedEvent;
        service.on('extension-disabled', (event) => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({});
        mockClient.query.mockResolvedValueOnce({});
        await service.disableExtension('ext-slow', 'Too slow');
        expect(emittedEvent).toBeDefined();
        expect(emittedEvent.reason).toBe('Too slow');
    });
    it('should emit extension-enabled event', async () => {
        let emittedEvent;
        service.on('extension-enabled', (event) => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({});
        mockClient.query.mockResolvedValueOnce({});
        await service.enableExtension('ext-slow');
        expect(emittedEvent).toBeDefined();
        expect(emittedEvent.extensionId).toBe('ext-slow');
    });
    it('should emit metrics-cleaned event', async () => {
        let emittedEvent;
        service.on('metrics-cleaned', (event) => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({
            rowCount: 500
        });
        await service.cleanupOldMetrics(30);
        expect(emittedEvent).toBeDefined();
        expect(emittedEvent.count).toBe(500);
    });
    it('should calculate health score correctly', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'metric-1',
                    extension_id: 'ext-1',
                    extension_name: 'Fast Ext',
                    startup_time_ms: 10,
                    activation_time_ms: 5,
                    latency_ms: 2,
                    health_score: 97,
                    is_disabled: false,
                    disable_reason: null,
                    measured_at: new Date()
                }]
        });
        const metrics = await service.recordExtensionMetrics('ext-1', 'Fast Ext', 10, 5, 2);
        expect(metrics.healthScore).toBeGreaterThan(90);
    });
    it('should handle performance profile with mixed extension speeds', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'session-1',
                    session_id: 'sess-1',
                    overall_health_score: 70,
                    slow_extension_count: 1,
                    recorded_at: new Date()
                }]
        });
        mockClient.query.mockResolvedValueOnce({
            rows: [
                { extension_id: 'ext-1', extension_name: 'Slow', startup_time_ms: 300, activation_time_ms: 200, latency_ms: 100, health_score: 45, is_disabled: false, disable_reason: null, measured_at: new Date() },
                { extension_id: 'ext-2', extension_name: 'Fast', startup_time_ms: 20, activation_time_ms: 10, latency_ms: 5, health_score: 95, is_disabled: false, disable_reason: null, measured_at: new Date() },
                { extension_id: 'ext-3', extension_name: 'Medium', startup_time_ms: 100, activation_time_ms: 50, latency_ms: 30, health_score: 75, is_disabled: false, disable_reason: null, measured_at: new Date() }
            ]
        });
        const profile = await service.getPerformanceProfile('sess-1');
        expect(profile?.extensions.length).toBe(3);
        expect(profile?.slowExtensions.length).toBe(1);
    });
    it('should retrieve extension metrics with limit', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [
                { extension_id: 'ext-1', extension_name: 'Test', startup_time_ms: 100, activation_time_ms: 50, latency_ms: 30, health_score: 80, is_disabled: false, disable_reason: null, measured_at: new Date() }
            ]
        });
        const metrics = await service.getExtensionMetrics('ext-1', 5);
        expect(metrics.length).toBeLessThanOrEqual(5);
    });
});
//# sourceMappingURL=ide-performance-profiler.test.js.map