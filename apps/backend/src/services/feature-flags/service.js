/**
 * Redis-backed Feature Flag Service.
 * Implements gradual rollout and user-specific overrides.
 */
import crypto from "crypto";
// Mocking Redis for this example as we don't have the client yet.
// In a real scenario, this would import a shared redis client.
// For now, we'll design it to take a redis client or use a simulated one.
export class FeatureFlagService {
    constructor(redisClient, auditService) {
        this.redisPrefix = "ff:";
        this.redis = redisClient;
        this.auditService = auditService;
    }
    /**
     * Check if a feature flag is enabled for a specific user.
     * Logic:
     * 1. Check if flag exists and is globally enabled.
     * 2. Check if user is in the explicit override list.
     * 3. Check gradual rollout percentage.
     */
    async isEnabled(flag, userId) {
        try {
            const config = await this.getFlagConfig(flag);
            if (!config)
                return false;
            if (!config.enabled)
                return false;
            // If no rollout config, it's globally enabled
            if (!config.rollout)
                return true;
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
                const isEnabled = userScore < config.rollout.percentage;
                if (this.auditService) {
                    this.auditService.emit({
                        userId: userId,
                        action: 'read',
                        resourceType: 'feature-flag',
                        resource: `feature:${flag}`,
                        metadata: {
                            flag,
                            enabled: isEnabled,
                            rolloutPercentage: config.rollout.percentage,
                            userScore,
                            inWhitelist: config.rollout.users?.includes(userId) || false,
                        },
                        reason: 'SOC2: Feature flag evaluation with gradual rollout',
                    });
                }
                return isEnabled;
            }
            // If no user ID but there's a rollout, we can't determine person-specific state.
            // We return true if percentage is 100, else default to false for safety.
            return config.rollout.percentage === 100;
        }
        catch (error) {
            console.error(`[FeatureFlag] Error checking flag ${flag}:`, error);
            return false; // Fail-closed
        }
    }
    /**
     * Get the value of a feature flag with type safety.
     */
    async getFlagValue(flag, defaultValue) {
        try {
            const config = await this.getFlagConfig(flag);
            if (!config || config.value === undefined) {
                return defaultValue;
            }
            return config.value;
        }
        catch (error) {
            return defaultValue;
        }
    }
    /**
     * Set a feature flag configuration in Redis.
     */
    async setFlag(flag, config) {
        const key = `${this.redisPrefix}${flag}`;
        await this.redis.set(key, JSON.stringify(config));
        if (this.auditService) {
            this.auditService.emit({
                userId: 'system',
                action: 'create',
                resourceType: 'feature-flag-config',
                resource: `feature:${flag}`,
                metadata: {
                    flag,
                    enabled: config.enabled,
                    rolloutPercentage: config.rollout?.percentage || 100,
                    userWhitelist: config.rollout?.users?.length || 0,
                },
                reason: 'SOC2: Feature flag configuration creation',
            });
        }
    }
    /**
     * Delete a feature flag configuration.
     */
    async deleteFlag(flag) {
        const key = `${this.redisPrefix}${flag}`;
        await this.redis.del(key);
        if (this.auditService) {
            this.auditService.emit({
                userId: 'system',
                action: 'delete',
                resourceType: 'feature-flag-config',
                resource: `feature:${flag}`,
                metadata: {
                    flag,
                    deletedAt: Date.now(),
                },
                reason: 'SOC2: Feature flag configuration deletion',
            });
        }
    }
    /**
     * Internal helper to fetch and parse config from Redis.
     */
    async getFlagConfig(flag) {
        const key = `${this.redisPrefix}${flag}`;
        const data = await this.redis.get(key);
        if (!data)
            return null;
        return JSON.parse(data);
    }
}
//# sourceMappingURL=service.js.map