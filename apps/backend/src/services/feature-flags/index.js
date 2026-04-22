import { FeatureFlagService } from "./service";
/**
 * Mock Redis client for testing and local dev.
 */
class MockRedis {
    constructor() {
        this.data = new Map();
    }
    async get(key) {
        return this.data.get(key) || null;
    }
    async set(key, value) {
        this.data.set(key, value);
    }
    async del(key) {
        this.data.delete(key);
    }
}
// Singleton instance
let instance = null;
/**
 * Initialize and get the feature flag service.
 * In production, pass the real Redis client.
 */
export function getFeatureFlagService(redisClient) {
    if (!instance) {
        // Fallback to mock if no client provided (useful for tests)
        const client = redisClient || new MockRedis();
        instance = new FeatureFlagService(client);
    }
    return instance;
}
export * from "./types";
export { FeatureFlagService };
//# sourceMappingURL=index.js.map