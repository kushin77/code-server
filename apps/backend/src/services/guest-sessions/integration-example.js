// @file        apps/backend/src/services/guest-sessions/integration-example.ts
// @module      collaboration/guest-sessions
// @description Runtime bootstrap helper for guest sessions with credential teardown wiring
// @owner       collab-5.5
// @status      active
import { initializeGuestSessionRoutes } from '../../routes/guest-sessions.js';
import { GuestSessionService } from './index.js';
export async function initializeGuestSessionRuntime(app, config) {
    const service = new GuestSessionService(config.pool, {
        ...config.guestSessionConfig,
        onSessionEnded: async (guestSessionId) => {
            if (!config.cache) {
                return;
            }
            // Revoke all session credentials when guest session ends
            // This ensures ephemeral credentials are cleaned up
            const revokedCount = await config.cache.revokeSessionCredentials(guestSessionId);
            if (revokedCount > 0) {
                console.log(`[GuestSession] Revoked ${revokedCount} credentials for session ${guestSessionId}`);
            }
        },
    });
    await service.initialize();
    app.use(initializeGuestSessionRoutes(service));
    return { service };
}
//# sourceMappingURL=integration-example.js.map