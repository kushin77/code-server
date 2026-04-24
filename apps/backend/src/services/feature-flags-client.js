// @file        apps/backend/src/services/feature-flags-client.ts
// @module      services/feature-flags-client
// @description Feature flag management with multi-provider support
import axios from 'axios';
/**
 * Feature Flag Management Client
 *
 * Supports multiple providers:
 * - LaunchDarkly (cloud-based)
 * - Unleash (self-hosted)
 * - Local (in-app definitions)
 *
 * Provides:
 * - Flag evaluation
 * - Targeting configuration
 * - Variation management
 * - Caching and performance
 * - Multi-environment support
 */
export class FeatureFlagsClient {
    constructor(environment = 'production', launchDarklyToken, unleashUrl) {
        this.environment = environment;
        this.launchDarklyClient = null;
        this.unleashClient = null;
        this.localFlags = new Map();
        this.cacheMap = new Map();
        this.cacheExpiry = 30 * 1000; // 30 seconds
        if (launchDarklyToken) {
            this.launchDarklyClient = axios.create({
                baseURL: 'https://app.launchdarkly.com/api/v2',
                headers: { 'Authorization': launchDarklyToken },
                timeout: 5000,
            });
        }
        if (unleashUrl) {
            this.unleashClient = axios.create({
                baseURL: unleashUrl,
                headers: { 'Accept': 'application/json' },
                timeout: 5000,
            });
        }
        this.initializeLocalFlags();
    }
    /**
     * Initialize local flags from environment
     */
    initializeLocalFlags() {
        const flagsJson = process.env.FEATURE_FLAGS_JSON || '{}';
        try {
            const flags = JSON.parse(flagsJson);
            for (const [key, value] of Object.entries(flags)) {
                this.localFlags.set(key, {
                    key,
                    name: key,
                    description: '',
                    enabled: Boolean(value),
                    provider: 'local',
                    createdAt: new Date().toISOString(),
                    modifiedAt: new Date().toISOString(),
                });
            }
        }
        catch (_error) {
            // Silently fail if invalid JSON
        }
    }
    /**
     * Evaluate flag for user
     */
    async evaluateFlag(flagKey, userId, context) {
        // Try LaunchDarkly
        if (this.launchDarklyClient) {
            try {
                const flag = await this.getLaunchDarklyFlag(flagKey);
                if (flag) {
                    // Simplified evaluation (real implementation would use rules)
                    return flag.on && !flag.archived;
                }
            }
            catch (_error) {
                // Continue to next provider
            }
        }
        // Try Unleash
        if (this.unleashClient) {
            try {
                const flag = await this.getUnleashFlag(flagKey);
                if (flag) {
                    return flag.enabled;
                }
            }
            catch (_error) {
                // Continue to next provider
            }
        }
        // Try local flags
        const localFlag = this.localFlags.get(flagKey);
        if (localFlag) {
            return localFlag.enabled;
        }
        return false;
    }
    /**
     * Get flag from LaunchDarkly
     */
    async getLaunchDarklyFlag(flagKey) {
        if (!this.launchDarklyClient)
            return null;
        return this.cachedRequest(`ld_${flagKey}`, async () => {
            const response = await this.launchDarklyClient.get(`/flags/${this.environment}/${flagKey}`);
            return response.data;
        });
    }
    /**
     * Get flag from Unleash
     */
    async getUnleashFlag(flagKey) {
        if (!this.unleashClient)
            return null;
        return this.cachedRequest(`unleash_${flagKey}`, async () => {
            const response = await this.unleashClient.get(`/client/features/${flagKey}`);
            return response.data.features[0] || null;
        });
    }
    /**
     * List all flags
     */
    async listFlags() {
        const flags = [];
        // Add LaunchDarkly flags
        if (this.launchDarklyClient) {
            try {
                const response = await this.launchDarklyClient.get(`/flags/${this.environment}`);
                flags.push(...response.data.items.map((flag) => ({
                    key: flag.key,
                    name: flag.name,
                    description: flag.description,
                    enabled: flag.on,
                    provider: 'launchdarkly',
                    createdAt: new Date(flag.createdDate).toISOString(),
                    modifiedAt: new Date(flag.lastModified).toISOString(),
                })));
            }
            catch (_error) {
                // Silently continue
            }
        }
        // Add Unleash flags
        if (this.unleashClient) {
            try {
                const response = await this.unleashClient.get('/client/features');
                flags.push(...response.data.features.map((flag) => ({
                    key: flag.name,
                    name: flag.name,
                    description: flag.description,
                    enabled: flag.enabled,
                    provider: 'unleash',
                    createdAt: flag.createdAt,
                    modifiedAt: flag.lastSeenAt,
                })));
            }
            catch (_error) {
                // Silently continue
            }
        }
        // Add local flags
        flags.push(...Array.from(this.localFlags.values()));
        return flags;
    }
    /**
     * Toggle flag (local only)
     */
    async toggleFlag(flagKey, enabled) {
        let flag = this.localFlags.get(flagKey);
        if (!flag) {
            flag = {
                key: flagKey,
                name: flagKey,
                description: '',
                enabled: false,
                provider: 'local',
                createdAt: new Date().toISOString(),
                modifiedAt: new Date().toISOString(),
            };
        }
        flag.enabled = enabled;
        flag.modifiedAt = new Date().toISOString();
        this.localFlags.set(flagKey, flag);
        this.invalidateCache(`local_${flagKey}`);
        return flag;
    }
    /**
     * Create flag
     */
    async createFlag(flagKey, name, description) {
        const flag = {
            key: flagKey,
            name,
            description,
            enabled: false,
            provider: 'local',
            createdAt: new Date().toISOString(),
            modifiedAt: new Date().toISOString(),
        };
        this.localFlags.set(flagKey, flag);
        return flag;
    }
    /**
     * Delete flag
     */
    async deleteFlag(flagKey) {
        this.localFlags.delete(flagKey);
        this.invalidateCache(`local_${flagKey}`);
    }
    /**
     * Get flag targeting rules
     */
    async getFlagTargeting(flagKey) {
        const flag = await this.getLaunchDarklyFlag(flagKey);
        if (flag) {
            return {
                users: [],
                segments: [],
                percentage: 100,
            };
        }
        return undefined;
    }
    /**
     * Update flag targeting
     */
    async updateFlagTargeting(flagKey, targeting) {
        const flag = this.localFlags.get(flagKey) || {
            key: flagKey,
            name: flagKey,
            description: '',
            enabled: false,
            provider: 'local',
            createdAt: new Date().toISOString(),
            modifiedAt: new Date().toISOString(),
        };
        flag.targeting = targeting;
        flag.modifiedAt = new Date().toISOString();
        this.localFlags.set(flagKey, flag);
        this.invalidateCache(`local_${flagKey}`);
        return flag;
    }
    /**
     * Get analytics on flag usage
     */
    async getFlagAnalytics(flagKey) {
        return {
            flag: flagKey,
            evaluations: 0,
            successRate: 100,
            lastEvaluated: new Date().toISOString(),
        };
    }
    /**
     * Export all flags
     */
    async exportFlags() {
        const flags = {};
        for (const [key, flag] of this.localFlags) {
            flags[key] = flag.enabled;
        }
        return flags;
    }
    /**
     * Import flags
     */
    async importFlags(flags) {
        for (const [key, enabled] of Object.entries(flags)) {
            await this.toggleFlag(key, enabled);
        }
    }
    /**
     * Cached request
     */
    async cachedRequest(cacheKey, fetchFn) {
        const cached = this.cacheMap.get(cacheKey);
        if (cached && Date.now() - cached.timestamp < this.cacheExpiry) {
            return cached.data;
        }
        const data = await fetchFn();
        this.cacheMap.set(cacheKey, { data, timestamp: Date.now() });
        return data;
    }
    /**
     * Invalidate cache
     */
    invalidateCache(cacheKey) {
        this.cacheMap.delete(cacheKey);
    }
    /**
     * Clear all cache
     */
    clearCache() {
        this.cacheMap.clear();
    }
}
export default FeatureFlagsClient;
//# sourceMappingURL=feature-flags-client.js.map