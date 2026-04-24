/**
 * Private Extension Registry Types
 * VSIX backend for org extensions, version pinning, blocklist, CI publishing
 */

/**
 * VSIX extension manifest
 */
export interface VSIXManifest {
  name: string;
  displayName: string;
  version: string;
  description?: string;
  author?: string;
  publisher: string;
  license?: string;
  homepage?: string;
  repository?: string;
  categories?: string[];
  keywords?: string[];
  engines: Record<string, string>; // e.g., { "vscode": "^1.75.0" }
  activationEvents?: string[];
  main?: string;
  contributes?: Record<string, any>;
}

/**
 * VSIX package metadata
 */
export interface VSIXPackage {
  id: string;
  name: string;
  displayName: string;
  publisher: string;
  version: string;
  manifest: VSIXManifest;
  fileSize: number;
  filePath: string;
  checksum: string; // SHA256
  createdAt: number;
  updatedAt: number;
  deprecated?: boolean;
  deprecationMessage?: string;
}

/**
 * Extension registry entry
 */
export interface ExtensionRegistryEntry {
  id: string;
  name: string;
  displayName: string;
  publisher: string;
  description?: string;
  versions: ExtensionVersion[];
  owner: string; // org/user who published
  scope: 'private' | 'internal' | 'public';
  blocklisted?: boolean;
  blocklistReason?: string;
  createdAt: number;
  updatedAt: number;
  installCount: number;
  rating?: number;
  tags?: string[];
}

/**
 * Extension version metadata
 */
export interface ExtensionVersion {
  version: string;
  vsix: VSIXPackage;
  downloadUrl: string;
  publishedAt: number;
  publishedBy: string;
  installCount: number;
  downloads: number;
  prerelease?: boolean;
  yanked?: boolean;
  yankReason?: string;
}

/**
 * Version pinning rule
 */
export interface VersionPin {
  extensionId: string;
  pinnedVersion: string; // e.g., "1.2.3" or "^1.2.0"
  scope: 'workspace' | 'organization' | 'global';
  reason: string;
  createdAt: number;
  createdBy: string;
  expiresAt?: number;
}

/**
 * Extension blocklist entry
 */
export interface BlocklistEntry {
  extensionId: string;
  reason: 'security' | 'malware' | 'license' | 'compliance' | 'deprecated' | 'other';
  severity: 'low' | 'medium' | 'high' | 'critical';
  description: string;
  affectedVersions?: string[]; // If empty, all versions blocked
  createdAt: number;
  createdBy: string;
  status: 'active' | 'suspended' | 'resolved';
}

/**
 * Extension query/search
 */
export interface ExtensionQuery {
  search?: string;
  publisher?: string;
  scope?: 'private' | 'internal' | 'public';
  category?: string;
  tag?: string;
  limit?: number;
  offset?: number;
  sort?: 'recent' | 'popular' | 'rating' | 'name';
}

/**
 * Extension query result
 */
export interface ExtensionQueryResult {
  entries: ExtensionRegistryEntry[];
  totalCount: number;
  hasMore: boolean;
}

/**
 * Extension publication request
 */
export interface PublicationRequest {
  id: string;
  extensionPath: string;
  manifestPath: string;
  publisher: string;
  scope: 'private' | 'internal' | 'public';
  version?: string;
  prerelease?: boolean;
  ciMetadata?: CIMetadata;
  submittedAt: number;
  submittedBy: string;
  status: 'pending' | 'published' | 'failed' | 'rejected';
  errorMessage?: string;
}

/**
 * CI/CD metadata from automated publishing
 */
export interface CIMetadata {
  ciProvider: 'github-actions' | 'gitlab-ci' | 'jenkins' | 'other';
  workflowId: string;
  buildNumber: string;
  gitCommitSha: string;
  gitBranch: string;
  artifactUrl: string;
  timestamp: number;
}

/**
 * Installation request
 */
export interface InstallationRequest {
  extensionId: string;
  version?: string; // Latest if not specified
  workspaceId?: string;
  userId: string;
  requestedAt: number;
}

/**
 * Installation result
 */
export interface InstallationResult {
  id: string;
  extensionId: string;
  version: string;
  downloadUrl: string;
  fileSize: number;
  checksum: string;
  installationPath: string;
  completedAt?: number;
  status: 'pending' | 'downloaded' | 'installed' | 'failed';
  errorMessage?: string;
}

/**
 * Registry statistics
 */
export interface RegistryStats {
  totalExtensions: number;
  totalVersions: number;
  extensionsByScope: Record<string, number>;
  extensionsByPublisher: Record<string, number>;
  totalDownloads: number;
  totalInstalls: number;
  avgInstallsPerExtension: number;
  blocklistedCount: number;
  pinnedVersionsCount: number;
}

/**
 * Registry configuration
 */
export interface RegistryConfig {
  enabled: boolean;
  maxExtensionSize: number; // In bytes, default 100MB
  maxVersionsPerExtension: number; // Keep last N versions
  installTimeoutMs: number; // Installation must complete within this time
  enableVersionPinning: boolean;
  enableBlocklist: boolean;
  enableCIPublishing: boolean;
  cacheTTL: number; // Cache metadata for N ms
  storagePath: string; // Base path for VSIX files
}

/**
 * Extension installation status
 */
export interface InstallationStatus {
  extensionId: string;
  installedVersion: string;
  installationPath: string;
  enabled: boolean;
  lastUpdated: number;
  pendingUpdate?: {
    version: string;
    updateAvailableAt: number;
  };
}

/**
 * Extension cache entry
 */
export interface CacheEntry {
  data: ExtensionRegistryEntry;
  expiresAt: number;
}
