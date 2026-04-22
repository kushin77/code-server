// @file        apps/backend/src/services/guest-sessions/integration-example.ts
// @module      collaboration/guest-sessions
// @description Runtime bootstrap helper for guest sessions with credential teardown wiring
// @owner       collab-5.5
// @status      active
import { JwtRedisCache } from '../auth/jwt-redis-cache.js';
import { initializeGuestSessionRoutes } from '../../routes/guest-sessions.js';
import { GuestSessionService } from './index.js';
export async function initializeGuestSessionRuntime(app, config) {
    const service = new GuestSessionService(config.pool, {
        ...config.guestSessionConfig,
        onSessionEnded: async (guestSessionId) => {
            if (!config.cache) {
                return;
            }
            await config.cache.revokeSessionCredentials(guestSessionId);
        },
    });
    await service.initialize();
    app.use(initializeGuestSessionRoutes(service));
    return { service };
}