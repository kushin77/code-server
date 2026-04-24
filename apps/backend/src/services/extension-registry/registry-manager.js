#!/usr/bin/env node
// @file        apps/backend/src/services/extension-registry/registry-manager.ts
// @module      services/extension-registry
// @description Private extension registry management for #1047
import { EventEmitter } from 'events';
import { getLogger } from '../../lib/logger';
const logger = getLogger('RegistryManager');
/**
 * Private Extension Registry Manager Service
 */
export class RegistryManagerService extends EventEmitter {
    constructor() {
        super();
        this.extensions = new Map();
        this.blocklist = new Map();
        this.versionPinning = new Map();
        this.installationCounts = new Map();
        this.publishers = new Set();
        this.lastSyncTime = 0;
    }
    /**
     * Get singleton instance
     */
    static getInstance() {
        if (!RegistryManagerService.instance) {
            RegistryManagerService.instance = new RegistryManagerService();
        }
        return RegistryManagerService.instance;
    }
    /**
     * Register extension in registry
     */
    registerExtension(id, metadata) {
        const now = Date.now();
        const extension = {
            ...metadata,
            _registeredAt: now,
            _updatedAt: now,
        };
        this.extensions.set(id, extension);
        this.publishers.add(metadata.publisher);
        logger.info(`Extension registered: ${id} v${metadata.version}`, {
            publisher: metadata.publisher,
        });
        this.emit('extension-registered', extension);
        return extension;
    }
    /**
     * Get extension metadata
     */
    getExtension(id) {
        return this.extensions.get(id);
    }
    /**
     * Get all registered extensions
     */
    getAllExtensions() {
        return Array.from(this.extensions.values());
    }
    /**
     * Block an extension
     */
    blockExtension(id, reason, severity = 'medium', alternatives = []) {
        const status = {
            id,
            version: this.extensions.get(id)?.version || '*',
            blocked: true,
            blockReason: reason,
            blockSeverity: severity,
            alternatives,
            installationCount: this.installationCounts.get(id) || 0,
        };
        this.blocklist.set(id, status);
        logger.warn(`Extension blocked: ${id}`, {
            reason,
            severity,
        });
        this.emit('extension-blocked', status);
        return status;
    }
    /**
     * Unblock an extension
     */
    unblockExtension(id) {
        this.blocklist.delete(id);
        logger.info(`Extension unblocked: ${id}`);
        this.emit('extension-unblocked', { id });
    }
    /**
     * Check if extension is blocked
     */
    isBlocked(id) {
        return this.blocklist.has(id);
    }
    /**
     * Get blocklist
     */
    getBlocklist() {
        return Array.from(this.blocklist.values());
    }
    /**
     * Pin extension version for workspace
     */
    setPinning(extensionId, allowedVersions, workspaceId, reason) {
        const key = workspaceId ? `${extensionId}:${workspaceId}` : extensionId;
        const pinning = {
            extensionId,
            workspaceId,
            allowedVersions,
            enforced: true,
            reason,
            _appliedAt: Date.now(),
        };
        if (!this.versionPinning.has(key)) {
            this.versionPinning.set(key, []);
        }
        this.versionPinning.get(key).push(pinning);
        logger.info(`Version pinning applied: ${extensionId}`, {
            workspaceId,
            allowedVersions,
        });
        this.emit('version-pinned', pinning);
        return pinning;
    }
    /**
     * Get version pinning for extension in workspace
     */
    getPinning(extensionId, workspaceId) {
        const key = workspaceId ? `${extensionId}:${workspaceId}` : extensionId;
        const pinnings = this.versionPinning.get(key);
        return pinnings ? pinnings[pinnings.length - 1] : undefined;
    }
    /**
     * Validate version against pinning policy
     */
    validateVersion(extensionId, version, workspaceId) {
        const pinning = this.getPinning(extensionId, workspaceId);
        if (!pinning) {
            return { allowed: true };
        }
        // Simple version matching: exact match or in allowed list
        if (pinning.allowedVersions.includes(version)) {
            return { allowed: true };
        }
        // Check for wildcards (e.g., "1.0.*" or "1.*")
        for (const allowedVersion of pinning.allowedVersions) {
            if (this.versionMatches(version, allowedVersion)) {
                return { allowed: true };
            }
        }
        return {
            allowed: false,
            reason: `Version ${version} not in pinned versions: ${pinning.allowedVersions.join(', ')}`,
        };
    }
    /**
     * Check if version matches pattern (e.g., "1.0.*" or "1.*")
     */
    versionMatches(version, pattern) {
        if (pattern === '*')
            return true;
        const versionParts = version.split('.');
        const patternParts = pattern.split('.');
        for (let i = 0; i < patternParts.length; i++) {
            if (patternParts[i] === '*')
                return true;
            if (versionParts[i] !== patternParts[i])
                return false;
        }
        return versionParts.length === patternParts.length;
    }
    /**
     * Record extension installation
     */
    recordInstallation(extensionId) {
        const current = this.installationCounts.get(extensionId) || 0;
        this.installationCounts.set(extensionId, current + 1);
        const status = this.blocklist.get(extensionId);
        if (status) {
            status.installationCount = current + 1;
            status.lastInstalled = Date.now();
        }
        this.emit('extension-installed', {
            extensionId,
            count: current + 1,
        });
    }
    /**
     * Get installation statistics
     */
    getInstallationStats(extensionId) {
        const status = this.blocklist.get(extensionId);
        return {
            count: this.installationCounts.get(extensionId) || 0,
            lastInstalled: status?.lastInstalled,
        };
    }
    /**
     * Get registry statistics
     */
    getStatistics() {
        const blocked = Array.from(this.blocklist.values());
        const totalInstallations = Array.from(this.installationCounts.values()).reduce((sum, count) => sum + count, 0);
        return {
            totalExtensions: this.extensions.size,
            internalExtensions: Array.from(this.extensions.values()).filter((e) => e.publisher.includes('kushnir')).length,
            blockedExtensions: this.blocklist.size,
            totalInstallations,
            activePublishers: Array.from(this.publishers),
            lastSync: this.lastSyncTime,
            syncStatus: this.getSyncStatus(),
        };
    }
    /**
     * Get sync status
     */
    getSyncStatus() {
        const minutesSinceSync = (Date.now() - this.lastSyncTime) / 60000;
        if (minutesSinceSync < 5)
            return 'healthy';
        if (minutesSinceSync < 30)
            return 'degraded';
        return 'unhealthy';
    }
    /**
     * Sync registry (mark last sync time)
     */
    recordSync() {
        this.lastSyncTime = Date.now();
        logger.info('Registry sync completed');
        this.emit('registry-synced', { timestamp: this.lastSyncTime });
    }
    /**
     * Reset service (for testing)
     */
    reset() {
        this.extensions.clear();
        this.blocklist.clear();
        this.versionPinning.clear();
        this.installationCounts.clear();
        this.publishers.clear();
        this.lastSyncTime = 0;
        this.removeAllListeners();
    }
}
export default RegistryManagerService.getInstance();
//# sourceMappingURL=registry-manager.js.map