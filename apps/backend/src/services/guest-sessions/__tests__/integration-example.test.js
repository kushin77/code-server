// @file        apps/backend/src/services/guest-sessions/__tests__/integration-example.test.ts
// @module      collaboration/guest-sessions
// @description Tests for guest-session runtime bootstrap wiring
// @owner       collab-5.5
// @status      active
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { initializeGuestSessionRuntime } from '../integration-example';
vi.mock('../../../lib/logger', () => ({
    getLogger: vi.fn(() => ({
        info: vi.fn(),
        error: vi.fn(),
        warn: vi.fn(),
        debug: vi.fn(),
    })),
}));
describe('initializeGuestSessionRuntime', () => {
    let mockClient;
    let mockPool;
    let mockCache;
    let mockApp;
    beforeEach(() => {
        mockClient = {
            query: vi.fn(),
            release: vi.fn(),
        };
        mockPool = {
            connect: vi.fn(async () => mockClient),
        };
        mockCache = {
            revokeSessionCredentials: vi.fn(async () => 1),
        };
        mockApp = {
            use: vi.fn(),
        };
        mockClient.query.mockResolvedValue({});
    });
    afterEach(() => {
        vi.clearAllMocks();
    });
    it('mounts the guest session routes and revokes credentials on session end', async () => {
        const { service } = await initializeGuestSessionRuntime(mockApp, {
            pool: mockPool,
            cache: mockCache,
        });
        expect(mockApp.use).toHaveBeenCalled();
        mockClient.query.mockResolvedValueOnce({});
        await service.revokeSession('session-123');
        expect(mockCache.revokeSessionCredentials).toHaveBeenCalledWith('session-123');
    });
    it('revokes credentials when expired sessions are cleaned up', async () => {
        const { service } = await initializeGuestSessionRuntime(mockApp, {
            pool: mockPool,
            cache: mockCache,
        });
        mockClient.query.mockResolvedValueOnce({ rows: [{ id: 'session-456' }] });
        await service.cleanupExpiredSessions();
        expect(mockCache.revokeSessionCredentials).toHaveBeenCalledWith('session-456');
    });
});
//# sourceMappingURL=integration-example.test.js.map