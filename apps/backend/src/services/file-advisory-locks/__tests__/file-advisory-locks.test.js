import { describe, it, expect, beforeEach, vi } from 'vitest';
import { FileAdvisoryLockService } from '../index';
vi.mock('../../../lib/logger', () => ({
    getLogger: () => ({
        info: vi.fn(),
        error: vi.fn(),
        debug: vi.fn(),
        warn: vi.fn()
    })
}));
describe('FileAdvisoryLockService', () => {
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
        service = new FileAdvisoryLockService(mockPool);
    });
    it('should initialize service and create tables', async () => {
        mockClient.query.mockResolvedValueOnce({});
        mockClient.query.mockResolvedValueOnce({});
        mockClient.query.mockResolvedValueOnce({});
        await service.initialize();
        expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('file_advisory_locks'));
        expect(mockClient.release).toHaveBeenCalled();
    });
    it('should acquire a lock', async () => {
        mockClient.query.mockResolvedValueOnce({ rows: [] });
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'lock-1',
                    asset_path: '/assets/binary.dat',
                    user_id: 'user-1',
                    reason: 'editing',
                    is_active: true,
                    expires_at: new Date(),
                    released_at: null,
                    created_at: new Date(),
                    updated_at: new Date()
                }]
        });
        const lock = await service.acquireLock({
            assetPath: '/assets/binary.dat',
            userId: 'user-1',
            reason: 'editing',
            ttlMinutes: 30
        });
        expect(lock.id).toBe('lock-1');
        expect(lock.assetPath).toBe('/assets/binary.dat');
    });
    it('should refuse a lock held by another user', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'lock-1',
                    asset_path: '/assets/binary.dat',
                    user_id: 'user-2',
                    reason: 'editing',
                    is_active: true,
                    expires_at: new Date(Date.now() + 30000),
                    released_at: null,
                    created_at: new Date(),
                    updated_at: new Date()
                }]
        });
        await expect(service.acquireLock({ assetPath: '/assets/binary.dat', userId: 'user-1' })).rejects.toThrow(/already locked/);
    });
    it('should return existing lock for same user', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'lock-1',
                    asset_path: '/assets/binary.dat',
                    user_id: 'user-1',
                    reason: 'editing',
                    is_active: true,
                    expires_at: new Date(Date.now() + 30000),
                    released_at: null,
                    created_at: new Date(),
                    updated_at: new Date()
                }]
        });
        const lock = await service.acquireLock({ assetPath: '/assets/binary.dat', userId: 'user-1' });
        expect(lock.id).toBe('lock-1');
    });
    it('should release a lock', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'lock-1',
                    asset_path: '/assets/binary.dat',
                    user_id: 'user-1',
                    reason: 'editing',
                    is_active: false,
                    expires_at: new Date(),
                    released_at: new Date(),
                    created_at: new Date(),
                    updated_at: new Date()
                }]
        });
        const lock = await service.releaseLock('lock-1', 'user-1');
        expect(lock.isActive).toBe(false);
        expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('UPDATE file_advisory_locks'), expect.any(Array));
    });
    it('should renew a lock', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'lock-1',
                    asset_path: '/assets/binary.dat',
                    user_id: 'user-1',
                    reason: 'editing',
                    is_active: true,
                    expires_at: new Date(Date.now() + 120000),
                    released_at: null,
                    created_at: new Date(),
                    updated_at: new Date()
                }]
        });
        const lock = await service.renewLock('lock-1', 'user-1', 60);
        expect(lock.isActive).toBe(true);
        expect(lock.userId).toBe('user-1');
    });
    it('should get a lock by asset path', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'lock-1',
                    asset_path: '/assets/binary.dat',
                    user_id: 'user-1',
                    reason: 'editing',
                    is_active: true,
                    expires_at: new Date(),
                    released_at: null,
                    created_at: new Date(),
                    updated_at: new Date()
                }]
        });
        const lock = await service.getLock('/assets/binary.dat');
        expect(lock?.id).toBe('lock-1');
    });
    it('should list locks', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [
                {
                    id: 'lock-1',
                    asset_path: '/assets/binary.dat',
                    user_id: 'user-1',
                    reason: 'editing',
                    is_active: true,
                    expires_at: new Date(),
                    released_at: null,
                    created_at: new Date(),
                    updated_at: new Date()
                }
            ]
        });
        const locks = await service.listLocks({ includeExpired: true });
        expect(locks).toHaveLength(1);
        expect(locks[0].assetPath).toBe('/assets/binary.dat');
    });
    it('should cleanup expired locks', async () => {
        mockClient.query.mockResolvedValueOnce({ rowCount: 2 });
        const count = await service.cleanupExpiredLocks();
        expect(count).toBe(2);
    });
    it('should emit lock-acquired event', async () => {
        let emittedEvent;
        service.on('lock-acquired', (event) => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({ rows: [] });
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'lock-1',
                    asset_path: '/assets/binary.dat',
                    user_id: 'user-1',
                    reason: 'editing',
                    is_active: true,
                    expires_at: new Date(),
                    released_at: null,
                    created_at: new Date(),
                    updated_at: new Date()
                }]
        });
        await service.acquireLock({ assetPath: '/assets/binary.dat', userId: 'user-1' });
        expect(emittedEvent.id).toBe('lock-1');
    });
    it('should emit lock-released event', async () => {
        let emittedEvent;
        service.on('lock-released', (event) => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'lock-1',
                    asset_path: '/assets/binary.dat',
                    user_id: 'user-1',
                    reason: 'editing',
                    is_active: false,
                    expires_at: new Date(),
                    released_at: new Date(),
                    created_at: new Date(),
                    updated_at: new Date()
                }]
        });
        await service.releaseLock('lock-1', 'user-1');
        expect(emittedEvent.id).toBe('lock-1');
    });
    it('should emit lock-renewed event', async () => {
        let emittedEvent;
        service.on('lock-renewed', (event) => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'lock-1',
                    asset_path: '/assets/binary.dat',
                    user_id: 'user-1',
                    reason: 'editing',
                    is_active: true,
                    expires_at: new Date(Date.now() + 120000),
                    released_at: null,
                    created_at: new Date(),
                    updated_at: new Date()
                }]
        });
        await service.renewLock('lock-1', 'user-1', 60);
        expect(emittedEvent.id).toBe('lock-1');
    });
});
//# sourceMappingURL=file-advisory-locks.test.js.map