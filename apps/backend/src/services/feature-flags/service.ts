/**
 * Redis-backed Feature Flag Service.
 * Implements gradual rollout and user-specific overrides.
 */

import { IFeatureFlagService, FeatureFlag, FeatureFlagValue } from "./types";
import crypto from "crypto";

// Mocking Redis for this example as we don't have the client yet.
// In a real scenario, this would import a shared redis client.
// For now, we'll design it to take a redis client or use a simulated one.

export class FeatureFlagService implements IFeatureFlagService {
  private readonly redisPrefix = "ff:";
  private redis: any;

  constructor(redisClient: any) {
    this.redis = redisClient;
  }

  /**
   * Check if a feature flag is enabled for a specific user.
   * Logic:
   * 1. Check if flag exists and is globally enabled.
   * 2. Check if user is in the explicit override list.
   * 3. Check gradual rollout percentage.
   */
  async isEnabled(flag: string, userId?: string | null): Promise<boolean> {
    try {
      const config = await this.getFlagConfig(flag);
      if (!config) return false;
      if (!config.enabled) return false;

      // If no rollout config, it's globally enabled
      if (!config.rollout) return true;

      // If user ID is provided, check overrides and rollout
      if (userId) {
        // 1. Check explicit user whitelist
        if (config.rollout.users?.includes(userId)) {
          return true;
        }

        // 2. Check gradual rollout percentage
        // Use consistent hashing to ensure a user always gets the same experience
        const hash = crypto.createHash("md5").update(`${flag}:${userId}`).digest("hex");
        const hashInt = parseInt(hash.substring(0, 8), 16);
        const userScore = hashInt % 100;

        return userScore < config.rollout.percentage;
      }

      // If no user ID but there's a rollout, we can't determine person-specific state.
      // We return true if percentage is 100, else default to false for safety.
      return config.rollout.percentage === 100;
    } catch (error) {
      console.error(`[FeatureFlag] Error checking flag ${flag}:`, error);
      return false; // Fail-closed
    }
  }

  /**
   * Get the value of a feature flag with type safety.
   */
  async getFlagValue<T extends FeatureFlagValue>(flag: string, defaultValue: T): Promise<T> {
    try {
      const config = await this.getFlagConfig(flag);
      if (!config || config.value === undefined) {
        return defaultValue;
      }
      return config.value as T;
    } catch (error) {
      return defaultValue;
    }
  }

  /**
   * Set a feature flag configuration in Redis.
   */
  async setFlag(flag: string, config: FeatureFlag): Promise<void> {
    const key = `${this.redisPrefix}${flag}`;
    await this.redis.set(key, JSON.stringify(config));
  }

  /**
   * Delete a feature flag configuration.
   */
  async deleteFlag(flag: string): Promise<void> {
    const key = `${this.redisPrefix}${flag}`;
    await this.redis.del(key);
  }

  /**
   * Internal helper to fetch and parse config from Redis.
   */
  private async getFlagConfig(flag: string): Promise<FeatureFlag | null> {
    const key = `${this.redisPrefix}${flag}`;
    const data = await this.redis.get(key);
    if (!data) return null;
    return JSON.parse(data) as FeatureFlag;
  }
}
