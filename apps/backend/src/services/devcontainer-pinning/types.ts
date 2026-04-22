/**
 * @file        apps/backend/src/services/devcontainer-pinning/types.ts
 * @module      collaboration/environment-reproducibility
 * @description Type definitions for devcontainer hash pinning and environment reproducibility
 */

/**
 * Supported container runtimes
 */
export type ContainerRuntime = 'docker' | 'podman' | 'containerd';

/**
 * Hash algorithm for reproducibility
 */
export type HashAlgorithm = 'sha256' | 'sha512';

/**
 * Devcontainer feature definition
 */
export interface DevcontainerFeature {
  id: string; // e.g., "ghcr.io/devcontainers/features/node:1"
  version: string; // e.g., "1.2.3"
  hash: string; // Pinned hash (sha256:abc123...)
  options?: Record<string, string | number | boolean>;
}

/**
 * Devcontainer base image with pinning
 */
export interface DevcontainerImage {
  name: string; // e.g., "node:18-alpine"
  registry: string; // e.g., "docker.io" or "ghcr.io"
  hash: string; // Pinned image hash (sha256:...)
  digest: string; // Manifest digest
  pullUrl: string; // Pull URL with hash
  pinnedAt: number;
  pinMethod: 'manual' | 'auto-scan' | 'policy';
}

/**
 * Devcontainer.json with hash pinning annotations
 */
export interface PinnedDevcontainer {
  // Standard devcontainer.json fields
  image?: string;
  imageHash?: string; // Added for pinning
  imageDigest?: string; // Manifest digest
  
  features?: Record<string, string | Record<string, any>>;
  featureHashes?: Record<string, DevcontainerFeature>; // Hash info for each feature
  
  customizations?: {
    vscode?: {
      extensions?: string[];
      settings?: Record<string, any>;
    };
  };
  
  // Pinning metadata
  _pinningMetadata?: {
    pinnedAt: number;
    pinnedBy: string;
    hashAlgorithm: HashAlgorithm;
    repository: string;
    commitHash?: string; // Git commit that triggered pinning
    policy?: string; // Policy used for pinning
  };
  
  // Original (unpinned) values for comparison
  _originalImage?: string;
  _originalFeatures?: Record<string, string | Record<string, any>>;
}

/**
 * Pinning policy for automation
 */
export interface PinningPolicy {
  id: string;
  workspaceId: string;
  enabled: boolean;
  autoPin: boolean; // Auto-pin on workspace creation/update
  pinningStrategy: 'latest' | 'semver' | 'digest'; // What to pin
  allowUnpinned: boolean; // Allow using unpinned images
  hashAlgorithm: HashAlgorithm;
  registries: string[]; // Allowed registries
  pullSchedule?: string; // Cron for checking updates
  createdAt: number;
  updatedAt: number;
}

/**
 * Pinning scan result
 */
export interface PinningScanResult {
  id: string;
  workspaceId: string;
  devcontainerPath: string;
  scanTime: number;
  
  // Results
  image?: DevcontainerImage;
  features: DevcontainerFeature[];
  
  // Issues found
  unpinnedElements: {
    image?: boolean;
    features?: string[];
  };
  
  // Available updates
  availableUpdates?: {
    image?: { current: string; available: string };
    features?: Record<string, { current: string; available: string }>;
  };
  
  createdAt: number;
}

/**
 * One-click provisioning request
 */
export interface ProvisioningRequest {
  id: string;
  workspaceId: string;
  devcontainerPath: string;
  runtime: ContainerRuntime;
  
  // Pinning
  usePinnedHashes: boolean;
  policyId?: string;
  
  // Build options
  noBuildCache?: boolean;
  buildArgs?: Record<string, string>;
  
  createdAt: number;
}

/**
 * Provisioning result
 */
export interface ProvisioningResult {
  requestId: string;
  success: boolean;
  containerId?: string;
  duration: number;
  
  // Reproducibility info
  reproduced: boolean; // Whether image was pulled/used from hash
  hashesUsed: {
    image?: string;
    features?: Record<string, string>;
  };
  
  logs?: string;
  error?: string;
  createdAt: number;
}

/**
 * Hash pinning statistics
 */
export interface PinningStats {
  totalElements: number;
  pinnedElements: number;
  unpinnedElements: number;
  pinningPercentage: number;
  
  byType: {
    images: { total: number; pinned: number };
    features: { total: number; pinned: number };
  };
  
  lastScanned?: number;
  nextScheduledScan?: number;
}

/**
 * Reproducibility verification result
 */
export interface ReproducibilityVerification {
  verified: boolean;
  imageMatch: boolean;
  featureMatches: Record<string, boolean>;
  mismatches: Array<{
    element: string;
    expected: string;
    actual: string;
  }>;
  verificationTime: number;
}
