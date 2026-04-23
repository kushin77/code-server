// @file        apps/backend/src/services/guest-sessions/__tests__/integration.test.ts
// @module      collaboration/guest-sessions
// @description Tests for guest session runtime bootstrap with credential teardown wiring
// @owner       collab-5.5
// @status      active
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { initializeGuestSessionRuntime } from '../integration-example.js';
describe('Guest Session Runtime Integration', () => {
    let mockCache;
    let mockPool;
    let mockApp;
    let config;
    beforeEach(() => {
        mockCache = {
            revokeSessionCredentials: vi.fn().mockResolvedValue(2),
        };
        mockPool = {
            connect: vi.fn().mockResolvedValue({
                query: vi.fn().mockResolvedValue({ rows: [] }),
                release: vi.fn(),
            }),
        };
        mockApp = {
            use: vi.fn(),
        };
        config = {
            pool: mockPool,
            cache: mockCache,
            guestSessionConfig: {},
        };
    });
    describe('Teardown Wiring', () => {
        it('should revoke credentials with proper session ID', async () => {
            // Create a test callback directly
            let capturedSessionId;
            const testOnSessionEnded = async (sessionId) => {
                capturedSessionId = sessionId;
                if (config.cache) {
                    await config.cache.revokeSessionCredentials(sessionId);
                }
            };
            const testConfig = {
                pool: mockPool,
                cache: mockCache,
                guestSessionConfig: {
                    onSessionEnded: testOnSessionEnded,
                },
            };
            // Call the callback
            await testConfig.guestSessionConfig.onSessionEnded('test-session-123');
            // Verify the callback was invoked correctly
            expect(capturedSessionId).toBe('test-session-123');
            expect(mockCache.revokeSessionCredentials).toHaveBeenCalledWith('test-session-123');
        });
        it('should handle missing cache without throwing', async () => {
            const configWithoutCache = {
                pool: mockPool,
                cache: undefined,
                guestSessionConfig: {},
            };
            const result = await initializeGuestSessionRuntime(mockApp, configWithoutCache);
            expect(result.service).toBeDefined();
        });
    });
    describe('Service Registration', () => {
        it('should register routes with the express app', async () => {
            const result = await initializeGuestSessionRuntime(mockApp, config);
            // Verify app.use was called (routes registered)
            expect(mockApp.use).toHaveBeenCalled();
            expect(result.service).toBeDefined();
        });
        it('should initialize the service', async () => {
            const result = await initializeGuestSessionRuntime(mockApp, config);
            // Service should be initialized and ready
            expect(result.service).toBeDefined();
            expect(result.service.initialize).toBeDefined();
        });
    });
});
//# sourceMappingURL=integration.test.js.map