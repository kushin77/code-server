#!/usr/bin/env node
// @file        apps/backend/src/services/session-broker/consistent-hashing.ts
// @module      session-broker/consistent-hashing
// @description Consistent hashing implementation using Rendezvous (HRW) algorithm
import crypto from 'crypto';
import pino from 'pino';
/**
 * Consistent hashing ring for session routing.
 * Uses Rendezvous hashing (HRW) algorithm for better distribution
 * and resilience to instance changes than traditional Ketama.
 *
 * Rendezvous hashing:
 * - For each item, compute hash(item, node) for all nodes
 * - Pick node with highest hash value
 * - On node addition/removal, only ~1/n keys need to move (optimal)
 * - No need for virtual nodes or complex ring management
 */
export class ConsistentHashRing {
    constructor(instances = [], logger) {
        this.instances = [];
        this.hashCache = new Map();
        this.instances = [...instances].sort((a, b) => a.id.localeCompare(b.id));
        this.logger = logger || pino({ name: 'session-broker' });
    }
    /**
     * Add instance to the ring.
     * Clears cache to ensure consistency.
     */
    addInstance(instance) {
        if (this.instances.some((i) => i.id === instance.id)) {
            this.logger.warn(`Instance ${instance.id} already exists`);
            return;
        }
        this.instances.push(instance);
        this.instances.sort((a, b) => a.id.localeCompare(b.id));
        this.hashCache.clear();
        this.logger.info(`Added instance ${instance.id}`);
    }
    /**
     * Remove instance from the ring.
     * Clears cache to ensure consistency.
     */
    removeInstance(instanceId) {
        const index = this.instances.findIndex((i) => i.id === instanceId);
        if (index === -1) {
            this.logger.warn(`Instance ${instanceId} not found`);
            return;
        }
        this.instances.splice(index, 1);
        this.hashCache.clear();
        this.logger.info(`Removed instance ${instanceId}`);
    }
    /**
     * Update instance status (healthy/unhealthy/draining).
     */
    updateInstanceStatus(instanceId, status) {
        const instance = this.instances.find((i) => i.id === instanceId);
        if (instance) {
            instance.status = status;
            instance.lastHealthCheck = Date.now();
            this.logger.debug(`Updated instance ${instanceId} status to ${status}`);
        }
    }
    /**
     * Get the instance responsible for a routing context using Rendezvous hashing.
     *
     * Algorithm:
     * 1. For each healthy instance, compute hash(key, instance_id)
     * 2. Return instance with highest hash value
     * 3. Fallback to non-draining instances if primary is draining
     *
     * @param context Session routing context (sessionId, userId, workspaceId)
     * @param includeUnhealthy If true, include unhealthy instances (for recovery)
     * @returns HashRingLookup with primary instance and replicas
     */
    getInstances(context, includeUnhealthy = false) {
        const cacheKey = `${context.sessionId}:${context.userId}:${context.workspaceId}`;
        // Check cache for consistency within TTL
        if (this.hashCache.has(cacheKey)) {
            const cachedInstance = this.hashCache.get(cacheKey);
            const replicas = this.getReplicas(context, cachedInstance.id, includeUnhealthy);
            return { instance: cachedInstance, replicas };
        }
        // Filter instances based on status
        let candidateInstances = this.instances;
        if (!includeUnhealthy) {
            candidateInstances = this.instances.filter((i) => i.status !== 'unhealthy' && i.status !== 'draining');
        }
        if (candidateInstances.length === 0) {
            throw new Error('No healthy instances available');
        }
        // Compute score for each instance using Rendezvous hashing
        let bestInstance = candidateInstances[0];
        let bestScore = this.hash(cacheKey, bestInstance.id);
        for (let i = 1; i < candidateInstances.length; i++) {
            const score = this.hash(cacheKey, candidateInstances[i].id);
            if (score > bestScore) {
                bestScore = score;
                bestInstance = candidateInstances[i];
            }
        }
        // Cache the result
        this.hashCache.set(cacheKey, bestInstance);
        // Get replicas (instances with next-highest scores)
        const replicas = this.getReplicas(context, bestInstance.id, includeUnhealthy);
        return { instance: bestInstance, replicas };
    }
    /**
     * Get replica instances in priority order.
     * Replicas are other instances sorted by descending hash score.
     */
    getReplicas(context, primaryId, includeUnhealthy) {
        const cacheKey = `${context.sessionId}:${context.userId}:${context.workspaceId}`;
        let candidateInstances = this.instances.filter((i) => i.id !== primaryId);
        if (!includeUnhealthy) {
            candidateInstances = candidateInstances.filter((i) => i.status !== 'unhealthy' && i.status !== 'draining');
        }
        // Sort by hash score (highest first)
        return candidateInstances.sort((a, b) => {
            const scoreA = this.hash(cacheKey, a.id);
            const scoreB = this.hash(cacheKey, b.id);
            return scoreB - scoreA;
        });
    }
    /**
     * Compute hash for Rendezvous algorithm.
     * Uses HMAC-SHA256 for consistent, cryptographically strong hashing.
     *
     * Returns a number in range [0, 1) for comparison.
     */
    hash(key, nodeId) {
        const hmac = crypto.createHmac('sha256', nodeId);
        hmac.update(key);
        const digest = hmac.digest();
        // Convert first 8 bytes to number in range [0, 1)
        let num = 0;
        for (let i = 0; i < 8; i++) {
            num = num * 256 + digest[i];
        }
        return num / Math.pow(256, 8);
    }
    /**
     * Get all healthy instances.
     */
    getHealthyInstances() {
        return this.instances.filter((i) => i.status === 'healthy');
    }
    /**
     * Get instance by ID.
     */
    getInstance(instanceId) {
        return this.instances.find((i) => i.id === instanceId);
    }
    /**
     * Get all instances.
     */
    getAllInstances() {
        return [...this.instances];
    }
    /**
     * Clear cache (for testing or manual invalidation).
     */
    clearCache() {
        this.hashCache.clear();
    }
    /**
     * Get cache stats (for debugging).
     */
    getCacheStats() {
        return {
            size: this.hashCache.size,
            entries: Array.from(this.hashCache.keys()),
        };
    }
}
//# sourceMappingURL=consistent-hashing.js.map