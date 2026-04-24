/**
 * Extension Registry Service
 * Private VSIX backend with org extensions, version pinning, blocklist, CI publishing
 */

import { EventEmitter } from 'events';
import * as crypto from 'crypto';
import {
  ExtensionRegistryEntry,
  ExtensionVersion,
  VSIXPackage,
  VSIXManifest,
  VersionPin,
  BlocklistEntry,
  ExtensionQuery,
  ExtensionQueryResult,
  PublicationRequest,
  InstallationRequest,
  InstallationResult,
  InstallationStatus,
  RegistryStats,
  RegistryConfig,
  CacheEntry,
  CIMetadata,
} from './types.js';

/**
 * Extension Registry Service
 * Manage private VSIX extensions with version pinning and blocklist
 */
export class ExtensionRegistryService extends EventEmitter {
  private isInitialized = false;
  private extensions: Map<string, ExtensionRegistryEntry> = new Map();
  private versionPins: Map<string, VersionPin[]> = new Map();
  private blocklist: Map<string, BlocklistEntry> = new Map();
  private installations: Map<string, InstallationStatus> = new Map();
  private publicationRequests: Map<string, PublicationRequest> = new Map();
  private cache: Map<string, CacheEntry> = new Map();
  private config: RegistryConfig;
  private stats: RegistryStats = {
    totalExtensions: 0,
    totalVersions: 0,
    extensionsByScope: {},
    extensionsByPublisher: {},
    totalDownloads: 0,
    totalInstalls: 0,
    avgInstallsPerExtension: 0,
    blocklistedCount: 0,
    pinnedVersionsCount: 0,
  };

  constructor(config?: Partial<RegistryConfig>) {
    super();
    this.config = {
      enabled: true,
      maxExtensionSize: 104857600, // 100MB
      maxVersionsPerExtension: 50,
      installTimeoutMs: 30000, // 30 seconds
      enableVersionPinning: true,
      enableBlocklist: true,
      enableCIPublishing: true,
      cacheTTL: 300000, // 5 minutes
      storagePath: '/var/lib/kushnir-cloud/extensions',
      ...config,
    };
  }

  /**
   * Initialize service
   */
  async initialize(): Promise<void> {
    if (this.isInitialized) return;
    this.isInitialized = true;

    // In production, would scan storage path for existing extensions
    // For now, just emit ready
    this.emit('initialized');
  }

  /**
   * Shutdown service
   */
  async shutdown(): Promise<void> {
    this.cache.clear();
    this.emit('shutdown');
  }

  /**
   * Publish/register extension
   */
  async publishExtension(
    manifest: VSIXManifest,
    fileBuffer: Buffer,
    publisher: string,
    scope: 'private' | 'internal' | 'public',
    ciMetadata?: CIMetadata
  ): Promise<VSIXPackage> {
    if (!this.isInitialized) throw new Error('Service not initialized');

    // Validate manifest
    if (!manifest.name || !manifest.publisher || !manifest.version) {
      throw new Error('Invalid manifest: missing required fields');
    }

    // Check file size
    if (fileBuffer.length > this.config.maxExtensionSize) {
      throw new Error(`File exceeds maximum size of ${this.config.maxExtensionSize} bytes`);
    }

    // Check blocklist
    const extensionId = `${manifest.publisher}.${manifest.name}`;
    if (await this.isBlocklisted(extensionId, manifest.version)) {
      throw new Error(`Extension ${extensionId} is blocklisted`);
    }

    // Calculate checksum
    const checksum = crypto.createHash('sha256').update(fileBuffer).digest('hex');

    // Create VSIX package
    const vsixPackage: VSIXPackage = {
      id: `vsix-${extensionId}-${manifest.version}-${Date.now()}`,
      name: manifest.name,
      displayName: manifest.displayName,
      publisher: manifest.publisher,
      version: manifest.version,
      manifest,
      fileSize: fileBuffer.length,
      filePath: `${this.config.storagePath}/${extensionId}/${manifest.version}.vsix`,
      checksum,
      createdAt: Date.now(),
      updatedAt: Date.now(),
    };

    // Get or create registry entry
    let entry = this.extensions.get(extensionId);
    if (!entry) {
      entry = {
        id: extensionId,
        name: manifest.name,
        displayName: manifest.displayName,
        publisher: manifest.publisher,
        description: manifest.description,
        versions: [],
        owner: publisher,
        scope,
        createdAt: Date.now(),
        updatedAt: Date.now(),
        installCount: 0,
        tags: manifest.keywords,
      };
      this.extensions.set(extensionId, entry);
    }

    // Add version to registry
    const version: ExtensionVersion = {
      version: manifest.version,
      vsix: vsixPackage,
      downloadUrl: `/api/extensions/${extensionId}/versions/${manifest.version}/download`,
      publishedAt: Date.now(),
      publishedBy: publisher,
      installCount: 0,
      downloads: 0,
      prerelease: this.isPrerelease(manifest.version),
      ciMetadata,
    };

    // Keep only maxVersionsPerExtension versions
    entry.versions.push(version);
    if (entry.versions.length > this.config.maxVersionsPerExtension) {
      entry.versions = entry.versions.slice(-this.config.maxVersionsPerExtension);
    }

    entry.updatedAt = Date.now();
    this.extensions.set(extensionId, entry);

    this.cache.delete(extensionId); // Invalidate cache
    this.updateStats();
    this.emit('extension-published', { extensionId, version: manifest.version });

    return vsixPackage;
  }

  /**
   * Get extension registry entry
   */
  async getExtension(extensionId: string): Promise<ExtensionRegistryEntry | undefined> {
    // Check cache
    const cached = this.cache.get(extensionId);
    if (cached && cached.expiresAt > Date.now()) {
      return cached.data;
    }

    const entry = this.extensions.get(extensionId);
    if (entry) {
      // Update cache
      this.cache.set(extensionId, {
        data: entry,
        expiresAt: Date.now() + this.config.cacheTTL,
      });
    }

    return entry;
  }

  /**
   * Get specific extension version
   */
  async getExtensionVersion(
    extensionId: string,
    version: string
  ): Promise<ExtensionVersion | undefined> {
    const entry = await this.getExtension(extensionId);
    if (!entry) return undefined;

    return entry.versions.find((v) => v.version === version);
  }

  /**
   * Get latest version of extension
   */
  async getLatestVersion(extensionId: string): Promise<ExtensionVersion | undefined> {
    const entry = await this.getExtension(extensionId);
    if (!entry || entry.versions.length === 0) return undefined;

    // Return latest non-yanked version
    for (let i = entry.versions.length - 1; i >= 0; i--) {
      if (!entry.versions[i].yanked) {
        return entry.versions[i];
      }
    }

    return undefined;
  }

  /**
   * Search/query extensions
   */
  async queryExtensions(query: ExtensionQuery): Promise<ExtensionQueryResult> {
    let results: ExtensionRegistryEntry[] = Array.from(this.extensions.values());

    // Filter by scope
    if (query.scope) {
      results = results.filter((e) => e.scope === query.scope);
    }

    // Filter by publisher
    if (query.publisher) {
      results = results.filter((e) => e.publisher === query.publisher);
    }

    // Filter by search term
    if (query.search) {
      const search = query.search.toLowerCase();
      results = results.filter(
        (e) =>
          e.name.toLowerCase().includes(search) ||
          e.displayName?.toLowerCase().includes(search) ||
          e.description?.toLowerCase().includes(search)
      );
    }

    // Filter by category
    if (query.category) {
      results = results.filter((e) => e.tags?.includes(query.category!));
    }

    // Filter by tag
    if (query.tag) {
      results = results.filter((e) => e.tags?.includes(query.tag!));
    }

    // Sort
    switch (query.sort) {
      case 'popular':
        results.sort((a, b) => b.installCount - a.installCount);
        break;
      case 'rating':
        results.sort((a, b) => (b.rating || 0) - (a.rating || 0));
        break;
      case 'name':
        results.sort((a, b) => a.displayName.localeCompare(b.displayName));
        break;
      case 'recent':
      default:
        results.sort((a, b) => b.updatedAt - a.updatedAt);
    }

    // Paginate
    const limit = query.limit || 20;
    const offset = query.offset || 0;
    const page = results.slice(offset, offset + limit);

    return {
      entries: page,
      totalCount: results.length,
      hasMore: offset + limit < results.length,
    };
  }

  /**
   * Install extension
   */
  async installExtension(
    extensionId: string,
    userId: string,
    workspaceId?: string,
    version?: string
  ): Promise<InstallationResult> {
    if (!this.isInitialized) throw new Error('Service not initialized');

    // Get extension
    const entry = await this.getExtension(extensionId);
    if (!entry) throw new Error(`Extension not found: ${extensionId}`);

    // Get version to install
    let versionToInstall = version;
    if (!versionToInstall) {
      const latest = await this.getLatestVersion(extensionId);
      if (!latest) throw new Error(`No installable version found for ${extensionId}`);
      versionToInstall = latest.version;
    }

    // Check for version pin
    const pin = this.versionPins.get(extensionId)?.find((p) => {
      if (p.scope === 'organization') return true; // Org-wide pin
      if (p.scope === 'workspace' && workspaceId && p.extensionId === extensionId) return true;
      return false;
    });

    if (pin) {
      versionToInstall = pin.pinnedVersion;
    }

    // Get versioned extension
    const versionEntry = await this.getExtensionVersion(extensionId, versionToInstall);
    if (!versionEntry) throw new Error(`Version not found: ${versionToInstall}`);

    // Check blocklist
    if (await this.isBlocklisted(extensionId, versionToInstall)) {
      throw new Error(`Extension ${extensionId}@${versionToInstall} is blocklisted`);
    }

    // Create installation result
    const result: InstallationResult = {
      id: `inst-${extensionId}-${Date.now()}`,
      extensionId,
      version: versionToInstall,
      downloadUrl: versionEntry.downloadUrl,
      fileSize: versionEntry.vsix.fileSize,
      checksum: versionEntry.vsix.checksum,
      installationPath: `${this.config.storagePath}/installed/${userId}/${extensionId}`,
      status: 'downloaded',
      completedAt: Date.now(),
    };

    // Record installation
    const statusKey = workspaceId ? `${extensionId}:${workspaceId}` : `${extensionId}:${userId}`;
    this.installations.set(statusKey, {
      extensionId,
      installedVersion: versionToInstall,
      installationPath: result.installationPath,
      enabled: true,
      lastUpdated: Date.now(),
    });

    // Update stats
    versionEntry.installCount++;
    versionEntry.downloads++;
    if (entry) entry.installCount++;

    this.updateStats();
    this.emit('extension-installed', { extensionId, version: versionToInstall, userId });

    return result;
  }

  /**
   * Add version pin
   */
  async pinVersion(
    extensionId: string,
    pinnedVersion: string,
    scope: 'workspace' | 'organization' | 'global',
    reason: string,
    userId: string,
    expiresAt?: number
  ): Promise<VersionPin> {
    if (!this.config.enableVersionPinning) {
      throw new Error('Version pinning is disabled');
    }

    const pin: VersionPin = {
      extensionId,
      pinnedVersion,
      scope,
      reason,
      createdAt: Date.now(),
      createdBy: userId,
      expiresAt,
    };

    let pins = this.versionPins.get(extensionId);
    if (!pins) {
      pins = [];
      this.versionPins.set(extensionId, pins);
    }

    pins.push(pin);
    this.updateStats();
    this.emit('version-pinned', { extensionId, pinnedVersion });

    return pin;
  }

  /**
   * Remove version pin
   */
  async unpinVersion(extensionId: string): Promise<void> {
    this.versionPins.delete(extensionId);
    this.updateStats();
    this.emit('version-unpinned', { extensionId });
  }

  /**
   * Get version pins
   */
  async getVersionPins(extensionId: string): Promise<VersionPin[]> {
    return this.versionPins.get(extensionId) || [];
  }

  /**
   * Add to blocklist
   */
  async blocklistExtension(
    extensionId: string,
    reason: BlocklistEntry['reason'],
    severity: BlocklistEntry['severity'],
    description: string,
    userId: string,
    affectedVersions?: string[]
  ): Promise<BlocklistEntry> {
    if (!this.config.enableBlocklist) {
      throw new Error('Blocklist is disabled');
    }

    const entry: BlocklistEntry = {
      extensionId,
      reason,
      severity,
      description,
      affectedVersions,
      createdAt: Date.now(),
      createdBy: userId,
      status: 'active',
    };

    this.blocklist.set(`${extensionId}:${reason}`, entry);
    this.cache.delete(extensionId); // Invalidate cache
    this.updateStats();
    this.emit('extension-blocklisted', { extensionId, reason });

    return entry;
  }

  /**
   * Remove from blocklist
   */
  async unblocklistExtension(extensionId: string): Promise<void> {
    // Remove all blocklist entries for this extension
    for (const [key] of this.blocklist) {
      if (key.startsWith(extensionId)) {
        this.blocklist.delete(key);
      }
    }

    this.cache.delete(extensionId); // Invalidate cache
    this.updateStats();
    this.emit('extension-unblocklisted', { extensionId });
  }

  /**
   * Check if extension is blocklisted
   */
  async isBlocklisted(extensionId: string, version?: string): Promise<boolean> {
    for (const [, entry] of this.blocklist) {
      if (entry.extensionId === extensionId) {
        if (!entry.affectedVersions || entry.affectedVersions.length === 0) {
          // All versions blocked
          return true;
        }
        if (version && entry.affectedVersions.includes(version)) {
          return true;
        }
      }
    }
    return false;
  }

  /**
   * Get blocklist entries
   */
  async getBlocklistEntries(): Promise<BlocklistEntry[]> {
    return Array.from(this.blocklist.values());
  }

  /**
   * Get all extensions
   */
  async getAllExtensions(): Promise<ExtensionRegistryEntry[]> {
    return Array.from(this.extensions.values());
  }

  /**
   * Get statistics
   */
  async getStatistics(): Promise<RegistryStats> {
    return { ...this.stats };
  }

  /**
   * Delete extension
   */
  async deleteExtension(extensionId: string): Promise<void> {
    this.extensions.delete(extensionId);
    this.versionPins.delete(extensionId);
    this.cache.delete(extensionId);

    // Remove blocklist entries
    for (const [key] of this.blocklist) {
      if (key.startsWith(extensionId)) {
        this.blocklist.delete(key);
      }
    }

    this.updateStats();
    this.emit('extension-deleted', { extensionId });
  }

  /**
   * Private: Check if version is prerelease
   */
  private isPrerelease(version: string): boolean {
    return /-(alpha|beta|rc)/.test(version);
  }

  /**
   * Private: Update statistics
   */
  private updateStats(): void {
    this.stats.totalExtensions = this.extensions.size;

    let totalVersions = 0;
    this.stats.extensionsByScope = {};
    this.stats.extensionsByPublisher = {};
    let totalInstalls = 0;

    for (const entry of this.extensions.values()) {
      totalVersions += entry.versions.length;
      this.stats.extensionsByScope[entry.scope] =
        (this.stats.extensionsByScope[entry.scope] || 0) + 1;
      this.stats.extensionsByPublisher[entry.publisher] =
        (this.stats.extensionsByPublisher[entry.publisher] || 0) + 1;
      totalInstalls += entry.installCount;
    }

    this.stats.totalVersions = totalVersions;
    this.stats.totalInstalls = totalInstalls;
    this.stats.avgInstallsPerExtension =
      this.stats.totalExtensions > 0 ? totalInstalls / this.stats.totalExtensions : 0;
    this.stats.blocklistedCount = this.blocklist.size;
    this.stats.pinnedVersionsCount = this.versionPins.size;
  }

  /**
   * Get global singleton instance
   */
  private static instance: ExtensionRegistryService;

  static getInstance(config?: Partial<RegistryConfig>): ExtensionRegistryService {
    if (!ExtensionRegistryService.instance) {
      ExtensionRegistryService.instance = new ExtensionRegistryService(config);
    }
    return ExtensionRegistryService.instance;
  }
}
