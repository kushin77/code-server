/**
 * @file        apps/backend/src/services/devcontainer-pinning/pinning-service.ts
 * @module      collaboration/environment-reproducibility
 * @description Devcontainer hash pinning for reproducible environments
 */

import { EventEmitter } from 'events';
import {
  PinnedDevcontainer,
  PinningPolicy,
  PinningScanResult,
  DevcontainerImage,
  DevcontainerFeature,
  HashAlgorithm,
  PinningStats,
  ReproducibilityVerification,
} from './types.js';

/**
 * DevcontainerPinningService: Manage hash pinning for reproducible environments
 */
export class DevcontainerPinningService extends EventEmitter {
  private isInitialized = false;
  private policies = new Map<string, PinningPolicy>();
  private scanResults = new Map<string, PinningScanResult[]>();
  private hashAlgorithm: HashAlgorithm = 'sha256';

  // Mock registry for testing
  private mockRegistry = new Map<string, { hash: string; digest: string }>();

  /**
   * Initialize service
   */
  async initialize(): Promise<void> {
    if (this.isInitialized) return;

    this.isInitialized = true;
    console.log('[DevcontainerPinningService] Initialized');
    this.emit('initialized');
  }

  /**
   * Scan devcontainer.json and return hash pinning info
   */
  async scanDevcontainer(
    workspaceId: string,
    devcontainerPath: string,
    content: PinnedDevcontainer
  ): Promise<PinningScanResult> {
    if (!this.isInitialized) throw new Error('Service not initialized');

    const startTime = performance.now();

    try {
      const result: PinningScanResult = {
        id: `scan-${workspaceId}-${Date.now()}`,
        workspaceId,
        devcontainerPath,
        scanTime: 0,
        features: [],
        unpinnedElements: { features: [] },
        createdAt: Date.now(),
      };

      // Scan image
      if (content.image) {
        const imageResult = await this.scanImage(content.image);
        result.image = imageResult;

        if (!content.imageHash) {
          result.unpinnedElements.image = true;
        }
      }

      // Scan features
      if (content.features) {
        for (const [featureId, featureVersion] of Object.entries(content.features)) {
          const featureResult = await this.scanFeature(featureId, String(featureVersion));
          result.features.push(featureResult);

          // Check if pinned in metadata
          const isPinned = content.featureHashes?.[featureId];
          if (!isPinned) {
            result.unpinnedElements.features?.push(featureId);
          }
        }
      }

      result.scanTime = performance.now() - startTime;

      // Store result
      const results = this.scanResults.get(workspaceId) || [];
      results.push(result);
      this.scanResults.set(workspaceId, results.slice(-10)); // Keep last 10

      console.log(
        `[DevcontainerPinningService] Scanned ${devcontainerPath} in ${result.scanTime.toFixed(2)}ms`
      );

      this.emit('scan-completed', result);

      return result;
    } catch (error) {
      console.error('[DevcontainerPinningService] Scan failed:', error);
      throw error;
    }
  }

  /**
   * Pin hashes in devcontainer.json
   */
  async pinHashes(
    workspaceId: string,
    content: PinnedDevcontainer,
    policy?: PinningPolicy
  ): Promise<PinnedDevcontainer> {
    if (!this.isInitialized) throw new Error('Service not initialized');

    const pinned: PinnedDevcontainer = JSON.parse(JSON.stringify(content));

    // Store original
    pinned._originalImage = content.image;
    pinned._originalFeatures = content.features ? { ...content.features } : undefined;

    // Pin image
    if (pinned.image) {
      const imageInfo = await this.scanImage(pinned.image);
      pinned.imageHash = imageInfo.hash;
      pinned.imageDigest = imageInfo.digest;
      pinned.image = imageInfo.pullUrl; // Update to use hash
    }

    // Pin features
    if (pinned.features) {
      pinned.featureHashes = {};

      for (const [featureId, featureVersion] of Object.entries(pinned.features)) {
        const featureInfo = await this.scanFeature(featureId, String(featureVersion));
        pinned.featureHashes[featureId] = featureInfo;
      }
    }

    // Add metadata
    pinned._pinningMetadata = {
      pinnedAt: Date.now(),
      pinnedBy: 'auto',
      hashAlgorithm: this.hashAlgorithm,
      repository: workspaceId,
      policy: policy?.id,
    };

    console.log(
      `[DevcontainerPinningService] Pinned hashes for ${workspaceId}`
    );

    this.emit('hashes-pinned', { workspaceId });

    return pinned;
  }

  /**
   * Verify reproducibility against pinned hashes
   */
  async verifyReproducibility(
    pinnedConfig: PinnedDevcontainer,
    currentDigests: Record<string, string>
  ): Promise<ReproducibilityVerification> {
    if (!this.isInitialized) throw new Error('Service not initialized');

    const startTime = performance.now();
    const mismatches: Array<{
      element: string;
      expected: string;
      actual: string;
    }> = [];

    // Verify image
    let imageMatch = true;
    if (pinnedConfig.imageDigest && currentDigests['image']) {
      imageMatch = pinnedConfig.imageDigest === currentDigests['image'];
      if (!imageMatch) {
        mismatches.push({
          element: 'image',
          expected: pinnedConfig.imageDigest,
          actual: currentDigests['image'],
        });
      }
    }

    // Verify features
    const featureMatches: Record<string, boolean> = {};
    if (pinnedConfig.featureHashes) {
      for (const [featureId, featureInfo] of Object.entries(
        pinnedConfig.featureHashes
      )) {
        const expected = featureInfo.hash;
        const actual = currentDigests[`feature-${featureId}`];
        const match = expected === actual;

        featureMatches[featureId] = match;

        if (!match) {
          mismatches.push({
            element: `feature-${featureId}`,
            expected,
            actual: actual || 'unknown',
          });
        }
      }
    }

    const verified = mismatches.length === 0;

    return {
      verified,
      imageMatch,
      featureMatches,
      mismatches,
      verificationTime: performance.now() - startTime,
    };
  }

  /**
   * Create or update pinning policy
   */
  async setPolicy(policy: PinningPolicy): Promise<void> {
    this.policies.set(policy.id, policy);
    console.log(`[DevcontainerPinningService] Policy ${policy.id} updated`);
    this.emit('policy-updated', policy);
  }

  /**
   * Get pinning policy
   */
  getPolicy(policyId: string): PinningPolicy | undefined {
    return this.policies.get(policyId);
  }

  /**
   * Get statistics for workspace
   */
  async getStatistics(workspaceId: string): Promise<PinningStats> {
    const results = this.scanResults.get(workspaceId) || [];
    const latestScan = results[results.length - 1];

    if (!latestScan) {
      return {
        totalElements: 0,
        pinnedElements: 0,
        unpinnedElements: 0,
        pinningPercentage: 0,
        byType: {
          images: { total: 0, pinned: 0 },
          features: { total: 0, pinned: 0 },
        },
      };
    }

    const totalImages = latestScan.image ? 1 : 0;
    const pinnedImages = latestScan.image && !latestScan.unpinnedElements.image ? 1 : 0;

    const totalFeatures = latestScan.features.length;
    const pinnedFeatures = totalFeatures - (latestScan.unpinnedElements.features?.length || 0);

    const totalElements = totalImages + totalFeatures;
    const pinnedElements = pinnedImages + pinnedFeatures;

    return {
      totalElements,
      pinnedElements,
      unpinnedElements: totalElements - pinnedElements,
      pinningPercentage: totalElements > 0 ? (pinnedElements / totalElements) * 100 : 0,
      byType: {
        images: { total: totalImages, pinned: pinnedImages },
        features: { total: totalFeatures, pinned: pinnedFeatures },
      },
      lastScanned: latestScan.createdAt,
    };
  }

  /**
   * Private: Scan image and get hash
   */
  private async scanImage(imageName: string): Promise<DevcontainerImage> {
    // In real implementation, would call container registry API
    // For testing, use mock data
    const mockKey = imageName;
    let imageHash = this.mockRegistry.get(mockKey);

    if (!imageHash) {
      // Generate mock hash
      const hash = `sha256:${Math.random().toString(16).substring(2, 66)}`;
      const digest = `sha256:${Math.random().toString(16).substring(2, 66)}`;
      imageHash = { hash, digest };
      this.mockRegistry.set(mockKey, imageHash);
    }

    return {
      name: imageName,
      registry: this.extractRegistry(imageName),
      hash: imageHash.hash,
      digest: imageHash.digest,
      pullUrl: `${imageName}@${imageHash.hash}`,
      pinnedAt: Date.now(),
      pinMethod: 'auto-scan',
    };
  }

  /**
   * Private: Scan feature and get hash
   */
  private async scanFeature(
    featureId: string,
    version: string
  ): Promise<DevcontainerFeature> {
    const mockKey = `${featureId}:${version}`;
    let featureHash = this.mockRegistry.get(mockKey);

    if (!featureHash) {
      const hash = `sha256:${Math.random().toString(16).substring(2, 66)}`;
      const digest = `sha256:${Math.random().toString(16).substring(2, 66)}`;
      featureHash = { hash, digest };
      this.mockRegistry.set(mockKey, featureHash);
    }

    return {
      id: featureId,
      version,
      hash: featureHash.hash,
    };
  }

  /**
   * Private: Extract registry from image name
   */
  private extractRegistry(imageName: string): string {
    if (imageName.includes('/')) {
      const parts = imageName.split('/');
      if (parts[0].includes('.') || parts[0].includes(':')) {
        return parts[0];
      }
    }
    return 'docker.io';
  }
}

/**
 * Global service instance
 */
let serviceInstance: DevcontainerPinningService | null = null;

/**
 * Get global service instance
 */
export async function getDevcontainerPinningService(): Promise<DevcontainerPinningService> {
  if (!serviceInstance) {
    serviceInstance = new DevcontainerPinningService();
    await serviceInstance.initialize();
  }
  return serviceInstance;
}
