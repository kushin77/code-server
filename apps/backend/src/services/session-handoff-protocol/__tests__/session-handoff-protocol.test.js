import { describe, it, expect, beforeEach, vi } from 'vitest';
import { SessionHandoffProtocolService } from '../index';
vi.mock('../../../lib/logger', () => ({
    getLogger: () => ({
        info: vi.fn(),
        error: vi.fn(),
        debug: vi.fn(),
        warn: vi.fn()
    })
}));
describe('SessionHandoffProtocolService', () => {
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
        service = new SessionHandoffProtocolService(mockPool);
    });
    it('should initialize service and create tables', async () => {
        mockClient.query.mockResolvedValueOnce({});
        mockClient.query.mockResolvedValueOnce({});
        mockClient.query.mockResolvedValueOnce({});
        await service.initialize();
        expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('session_handoff_protocols'));
        expect(mockClient.release).toHaveBeenCalled();
    });
    it('should start a handoff', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'handoff-1',
                    session_id: 'session-1',
                    current_owner_id: 'user-1',
                    target_owner_id: 'user-2',
                    state: 'pending',
                    reason: 'transfer ownership',
                    expires_at: new Date(),
                    accepted_at: null,
                    rejected_at: null,
                    completed_at: null,
                    created_at: new Date(),
                    updated_at: new Date()
                }]
        });
        const handoff = await service.startHandoff({
            sessionId: 'session-1',
            currentOwnerId: 'user-1',
            targetOwnerId: 'user-2',
            reason: 'transfer ownership'
        });
        expect(handoff.id).toBe('handoff-1');
        expect(handoff.state).toBe('pending');
    });
    it('should accept a handoff', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'handoff-1',
                    session_id: 'session-1',
                    current_owner_id: 'user-2',
                    target_owner_id: 'user-2',
                    state: 'accepted',
                    reason: 'transfer ownership',
                    expires_at: new Date(),
                    accepted_at: new Date(),
                    rejected_at: null,
                    completed_at: null,
                    created_at: new Date(),
                    updated_at: new Date()
                }]
        });
        const handoff = await service.acceptHandoff('handoff-1', 'user-2');
        expect(handoff.state).toBe('accepted');
        expect(handoff.currentOwnerId).toBe('user-2');
    });
    it('should reject a handoff', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'handoff-1',
                    session_id: 'session-1',
                    current_owner_id: 'user-1',
                    target_owner_id: 'user-2',
                    state: 'rejected',
                    reason: 'transfer ownership',
                    expires_at: new Date(),
                    accepted_at: null,
                    rejected_at: new Date(),
                    completed_at: null,
                    created_at: new Date(),
                    updated_at: new Date()
                }]
        });
        const handoff = await service.rejectHandoff('handoff-1', 'user-2');
        expect(handoff.state).toBe('rejected');
    });
    it('should complete a handoff', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'handoff-1',
                    session_id: 'session-1',
                    current_owner_id: 'user-2',
                    target_owner_id: 'user-2',
                    state: 'completed',
                    reason: 'transfer ownership',
                    expires_at: new Date(),
                    accepted_at: new Date(),
                    rejected_at: null,
                    completed_at: new Date(),
                    created_at: new Date(),
                    updated_at: new Date()
                }]
        });
        const handoff = await service.completeHandoff('handoff-1');
        expect(handoff.state).toBe('completed');
    });
    it('should get a handoff by id', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'handoff-1',
                    session_id: 'session-1',
                    current_owner_id: 'user-1',
                    target_owner_id: 'user-2',
                    state: 'pending',
                    reason: 'transfer ownership',
                    expires_at: new Date(),
                    accepted_at: null,
                    rejected_at: null,
                    completed_at: null,
                    created_at: new Date(),
                    updated_at: new Date()
                }]
        });
        const handoff = await service.getHandoff('handoff-1');
        expect(handoff?.id).toBe('handoff-1');
    });
    it('should list handoffs', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'handoff-1',
                    session_id: 'session-1',
                    current_owner_id: 'user-1',
                    target_owner_id: 'user-2',
                    state: 'pending',
                    reason: 'transfer ownership',
                    expires_at: new Date(),
                    accepted_at: null,
                    rejected_at: null,
                    completed_at: null,
                    created_at: new Date(),
                    updated_at: new Date()
                }]
        });
        const handoffs = await service.listHandoffs('session-1');
        expect(handoffs).toHaveLength(1);
        expect(handoffs[0].sessionId).toBe('session-1');
    });
    it('should return null for missing handoff', async () => {
        mockClient.query.mockResolvedValueOnce({ rows: [] });
        const handoff = await service.getHandoff('missing');
        expect(handoff).toBeNull();
    });
    it('should expire stale handoffs', async () => {
        mockClient.query.mockResolvedValueOnce({ rowCount: 2 });
        const count = await service.expireStaleHandoffs();
        expect(count).toBe(2);
    });
    it('should emit handoff-started event', async () => {
        let emittedEvent;
        service.on('handoff-started', event => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'handoff-1',
                    session_id: 'session-1',
                    current_owner_id: 'user-1',
                    target_owner_id: 'user-2',
                    state: 'pending',
                    reason: 'transfer ownership',
                    expires_at: new Date(),
                    accepted_at: null,
                    rejected_at: null,
                    completed_at: null,
                    created_at: new Date(),
                    updated_at: new Date()
                }]
        });
        await service.startHandoff({
            sessionId: 'session-1',
            currentOwnerId: 'user-1',
            targetOwnerId: 'user-2'
        });
        expect(emittedEvent.id).toBe('handoff-1');
    });
    it('should emit handoff-accepted event', async () => {
        let emittedEvent;
        service.on('handoff-accepted', event => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'handoff-1',
                    session_id: 'session-1',
                    current_owner_id: 'user-2',
                    target_owner_id: 'user-2',
                    state: 'accepted',
                    reason: 'transfer ownership',
                    expires_at: new Date(),
                    accepted_at: new Date(),
                    rejected_at: null,
                    completed_at: null,
                    created_at: new Date(),
                    updated_at: new Date()
                }]
        });
        await service.acceptHandoff('handoff-1', 'user-2');
        expect(emittedEvent.state).toBe('accepted');
    });
    it('should emit handoff-rejected event', async () => {
        let emittedEvent;
        service.on('handoff-rejected', event => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'handoff-1',
                    session_id: 'session-1',
                    current_owner_id: 'user-1',
                    target_owner_id: 'user-2',
                    state: 'rejected',
                    reason: 'transfer ownership',
                    expires_at: new Date(),
                    accepted_at: null,
                    rejected_at: new Date(),
                    completed_at: null,
                    created_at: new Date(),
                    updated_at: new Date()
                }]
        });
        await service.rejectHandoff('handoff-1', 'user-2');
        expect(emittedEvent.state).toBe('rejected');
    });
    it('should emit handoff-completed event', async () => {
        let emittedEvent;
        service.on('handoff-completed', event => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'handoff-1',
                    session_id: 'session-1',
                    current_owner_id: 'user-2',
                    target_owner_id: 'user-2',
                    state: 'completed',
                    reason: 'transfer ownership',
                    expires_at: new Date(),
                    accepted_at: new Date(),
                    rejected_at: null,
                    completed_at: new Date(),
                    created_at: new Date(),
                    updated_at: new Date()
                }]
        });
        await service.completeHandoff('handoff-1');
        expect(emittedEvent.state).toBe('completed');
    });
});
//# sourceMappingURL=session-handoff-protocol.test.js.map