import { describe, it, expect, beforeEach, vi } from 'vitest';
import { FlowStateDetectionService } from '../index';
vi.mock('../../../lib/logger', () => ({
    getLogger: () => ({
        info: vi.fn(),
        error: vi.fn(),
        debug: vi.fn(),
        warn: vi.fn()
    })
}));
describe('FlowStateDetectionService', () => {
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
        service = new FlowStateDetectionService(mockPool);
    });
    it('initializes flow state tables', async () => {
        for (let i = 0; i < 8; i++) {
            mockClient.query.mockResolvedValueOnce({});
        }
        await service.initialize();
        expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('flow_activity_log'));
        expect(mockClient.release).toHaveBeenCalled();
    });
    it('records flow activity and detects flow state', async () => {
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        const record = await service.recordActivity('user-1', 55, 0, 8, 'editor');
        expect(record.userId).toBe('user-1');
        expect(record.wordsPerMinute).toBe(55);
    });
    it('records distracted activity', async () => {
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        const record = await service.recordActivity('user-1', 20, 4, 3, 'browser');
        expect(record.appName).toBe('browser');
    });
    it('detects flow state from recent activity', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    avg_wpm: 52,
                    avg_switches: 0,
                    avg_duration: 7
                }]
        });
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    user_id: 'user-1',
                    state: 'flow',
                    confidence: 95,
                    reason: 'High typing speed, no context switches, sustained focus',
                    updated_at: new Date()
                }]
        });
        const snapshot = await service.detectFlowState('user-1');
        expect(snapshot.state).toBe('flow');
        expect(snapshot.confidence).toBe(95);
    });
    it('queues a ping', async () => {
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        const ping = await service.queuePing('user-1', 'Standup starts soon', 'high');
        expect(ping.message).toBe('Standup starts soon');
        expect(ping.priority).toBe('high');
    });
    it('gets queued pings', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [
                {
                    user_id: 'user-1',
                    message: 'Ping 1',
                    priority: 'normal',
                    queued_at: new Date(),
                    delivered_at: null
                }
            ]
        });
        const pings = await service.getQueuedPings('user-1');
        expect(pings).toHaveLength(1);
        expect(pings[0].message).toBe('Ping 1');
    });
    it('completes a flow session and delivers pings', async () => {
        mockClient.query.mockResolvedValueOnce({ rows: [{ id: 'ping-1' }, { id: 'ping-2' }] });
        mockClient.query.mockResolvedValueOnce({ rowCount: 2 });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        const result = await service.completeFlowSession('user-1');
        expect(result.delivered).toBe(2);
        expect(result.state).toBe('available');
    });
    it('gets current flow state', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [
                {
                    user_id: 'user-1',
                    state: 'flow',
                    confidence: 90,
                    reason: 'Sustained focus',
                    updated_at: new Date()
                }
            ]
        });
        const snapshot = await service.getFlowState('user-1');
        expect(snapshot?.state).toBe('flow');
    });
    it('returns null for missing flow state', async () => {
        mockClient.query.mockResolvedValueOnce({ rows: [] });
        const snapshot = await service.getFlowState('missing');
        expect(snapshot).toBeNull();
    });
    it('returns flow history', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [
                {
                    user_id: 'user-1',
                    words_per_minute: 55,
                    switch_count: 0,
                    duration_minutes: 8,
                    app_name: 'editor',
                    recorded_at: new Date()
                }
            ]
        });
        const history = await service.getFlowHistory('user-1', 20);
        expect(history).toHaveLength(1);
        expect(history[0].wordsPerMinute).toBe(55);
    });
    it('emits activity-recorded event', async () => {
        let emittedEvent;
        service.on('activity-recorded', event => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        await service.recordActivity('user-1', 55, 0, 8, 'editor');
        expect(emittedEvent.userId).toBe('user-1');
    });
    it('emits flow-state-detected event on detect', async () => {
        let emittedEvent;
        service.on('flow-state-detected', event => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({
            rows: [{ avg_wpm: 52, avg_switches: 0, avg_duration: 7 }]
        });
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    user_id: 'user-1',
                    state: 'flow',
                    confidence: 95,
                    reason: 'High typing speed, no context switches, sustained focus',
                    updated_at: new Date()
                }]
        });
        await service.detectFlowState('user-1');
        expect(emittedEvent.userId).toBe('user-1');
    });
    it('emits ping-queued event', async () => {
        let emittedEvent;
        service.on('ping-queued', event => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        await service.queuePing('user-1', 'Ping later', 'normal');
        expect(emittedEvent.message).toBe('Ping later');
    });
    it('emits flow-session-completed event', async () => {
        let emittedEvent;
        service.on('flow-session-completed', event => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({ rows: [{ id: 'ping-1' }] });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        await service.completeFlowSession('user-1');
        expect(emittedEvent.userId).toBe('user-1');
    });
    it('detects available state below flow threshold', async () => {
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        await service.recordActivity('user-1', 25, 1, 4, 'editor');
        expect(mockClient.query).toHaveBeenCalledTimes(2);
    });
    it('supports custom activity app names', async () => {
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        const record = await service.recordActivity('user-1', 45, 0, 6, 'notes');
        expect(record.appName).toBe('notes');
    });
});
//# sourceMappingURL=flow-state-detection.test.js.map