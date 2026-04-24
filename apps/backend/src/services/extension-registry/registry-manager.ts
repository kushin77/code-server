#!/usr/bin/env node
// @file        apps/backend/src/services/extension-registry/registry-manager.ts
// @module      services/extension-registry
// @description Private extension registry management for #1047

import { EventEmitter } from 'events';
import { getLogger } from '../../lib/logger';

const logger = getLogger('RegistryManager');

/**
 * Extension metadata from registry
 */
export interface ExtensionMetadata {
  id: string;
  name: string;
  displayName?: string;
  publisher: string;
  version: string;
  description?: string;
  icon?: string;
  repository?: string;
  homepage?: string;
  license?: string;
  engines?: {
    vscode?: string;
  };
  categories?: string[];
  keywords?: string[];
  activationEvents?: string[];
  _registeredAt: number;
  _updatedAt: number;
}

/**
 * Extension with blocklist status
 */
export interface ExtensionStatus {
  id: string;
  version: string;
  blocked: boolean;
  blockReason?: string;
  blockSeverity?: 'critical' | 'high' | 'medium' | 'low';
  alternatives?: string[];
  allowedVersions?: string[]; // For version pinning
  installationCount: number;
  lastInstalled?: number;
}

/**
 * Version pinning policy
 */
export interface VersionPinning {
  extensionId: string;
  workspaceId?: string; // If not set, applies globally
  allowedVersions: string[]; // Semantic version ranges or exact versions
  enforced: boolean;
  reason?: string;
  _appliedAt: number;
}

/**
 * Registry statistics
 */
export interface RegistryStats {
  totalExtensions: number;
  internalExtensions: number;
  blockedExtensions: number;
  totalInstallations: number;
  activePublishers: string[];
  lastSync: number;
  syncStatus: 'healthy' | 'degraded' | 'unhealthy';
}

/**
 * Private Extension Registry Manager Service
 */
export class RegistryManagerService extends EventEmitter {
  private static instance: RegistryManagerService;
  private extensions: Map<string, ExtensionMetadata> = new Map();
  private blocklist: Map<string, ExtensionStatus> = new Map();
  private versionPinning: Map<string, VersionPinning[]> = new Map();
  private installationCounts: Map<string, number> = new Map();
  private publishers: Set<string> = new Set();
  private lastSyncTime = 0;

  constructor() {
    super();
  }

  /**
   * Get singleton instance
   */
  static getInstance(): RegistryManagerService {
    if (!RegistryManagerService.instance) {
      RegistryManagerService.instance = new RegistryManagerService();
    }
    return RegistryManagerService.instance;
  }

  /**
   * Register extension in registry
   */
  registerExtension(
    id: string,
    metadata: Omit<ExtensionMetadata, '_registeredAt' | '_updatedAt'>
  ): ExtensionMetadata {
    const now = Date.now();
    const extension: ExtensionMetadata = {
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
  getExtension(id: string): ExtensionMetadata | undefined {
    return this.extensions.get(id);
  }

  /**
   * Get all registered extensions
   */
  getAllExtensions(): ExtensionMetadata[] {
    return Array.from(this.extensions.values());
  }

  /**
   * Block an extension
   */
  blockExtension(
    id: string,
    reason: string,
    severity: 'critical' | 'high' | 'medium' | 'low' = 'medium',
    alternatives: string[] = []
  ): ExtensionStatus {
    const status: ExtensionStatus = {
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
  unblockExtension(id: string): void {
    this.blocklist.delete(id);

    logger.info(`Extension unblocked: ${id}`);

    this.emit('extension-unblocked', { id });
  }

  /**
   * Check if extension is blocked
   */
  isBlocked(id: string): boolean {
    return this.blocklist.has(id);
  }

  /**
   * Get blocklist
   */
  getBlocklist(): ExtensionStatus[] {
    return Array.from(this.blocklist.values());
  }

  /**
   * Pin extension version for workspace
   */
  setPinning(
    extensionId: string,
    allowedVersions: string[],
    workspaceId?: string,
    reason?: string
  ): VersionPinning {
    const key = workspaceId ? `${extensionId}:${workspaceId}` : extensionId;

    const pinning: VersionPinning = {
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

    this.versionPinning.get(key)!.push(pinning);

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
  getPinning(extensionId: string, workspaceId?: string): VersionPinning | undefined {
    const key = workspaceId ? `${extensionId}:${workspaceId}` : extensionId;
    const pinnings = this.versionPinning.get(key);
    return pinnings ? pinnings[pinnings.length - 1] : undefined;
  }

  /**
   * Validate version against pinning policy
   */
  validateVersion(
    extensionId: string,
    version: string,
    workspaceId?: string
  ): { allowed: boolean; reason?: string } {
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
  private versionMatches(version: string, pattern: string): boolean {
    if (pattern === '*') return true;

    const versionParts = version.split('.');
    const patternParts = pattern.split('.');

    for (let i = 0; i < patternParts.length; i++) {
      if (patternParts[i] === '*') return true;
      if (versionParts[i] !== patternParts[i]) return false;
    }

    return versionParts.length === patternParts.length;
  }

  /**
   * Record extension installation
   */
  recordInstallation(extensionId: string): void {
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
  getInstallationStats(extensionId: string): { count: number; lastInstalled?: number } {
    const status = this.blocklist.get(extensionId);
    return {
      count: this.installationCounts.get(extensionId) || 0,
      lastInstalled: status?.lastInstalled,
    };
  }

  /**
   * Get registry statistics
   */
  getStatistics(): RegistryStats {
    const blocked = Array.from(this.blocklist.values());
    const totalInstallations = Array.from(this.installationCounts.values()).reduce(
      (sum, count) => sum + count,
      0
    );

    return {
      totalExtensions: this.extensions.size,
      internalExtensions: Array.from(this.extensions.values()).filter((e) =>
        e.publisher.includes('kushnir')
      ).length,
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
  private getSyncStatus(): 'healthy' | 'degraded' | 'unhealthy' {
    const minutesSinceSync = (Date.now() - this.lastSyncTime) / 60000;

    if (minutesSinceSync < 5) return 'healthy';
    if (minutesSinceSync < 30) return 'degraded';
    return 'unhealthy';
  }

  /**
   * Sync registry (mark last sync time)
   */
  recordSync(): void {
    this.lastSyncTime = Date.now();
    logger.info('Registry sync completed');
    this.emit('registry-synced', { timestamp: this.lastSyncTime });
  }

  /**
   * Reset service (for testing)
   */
  reset(): void {
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
