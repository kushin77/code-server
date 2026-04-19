import { FeatureFlagService } from "./service";
import { FeatureFlag, IFeatureFlagService } from "./types";

/**
 * Mock Redis client for testing and local dev.
 */
class MockRedis {
  private data = new Map<string, string>();

  async get(key: string): Promise<string | null> {
    return this.data.get(key) || null;
  }

  async set(key: string, value: string): Promise<void> {
    this.data.set(key, value);
  }

  async del(key: string): Promise<void> {
    this.data.delete(key);
  }
}

// Singleton instance
let instance: IFeatureFlagService | null = null;

/**
 * Initialize and get the feature flag service.
 * In production, pass the real Redis client.
 */
export function getFeatureFlagService(redisClient?: any): IFeatureFlagService {
  if (!instance) {
    // Fallback to mock if no client provided (useful for tests)
    const client = redisClient || new MockRedis();
    instance = new FeatureFlagService(client);
  }
  return instance;
}

export * from "./types";
export { FeatureFlagService };
