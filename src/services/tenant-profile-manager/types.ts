// @file        src/services/tenant-profile-manager/types.ts
// @module      session/tenant-profiles
// @description Tenant-aware profile hierarchy and immutable policy overlay types
//

/**
 * Profile hierarchy levels with precedence ordering.
 * Lower numeric value = higher precedence (overrides lower levels).
 */
export enum ProfileLevel {
  // Immutable defaults - lowest precedence
  GLOBAL_POLICY = 5,
  
  // Role-based settings
  ROLE_POLICY = 4,
  
  // Team/organization settings
  TEAM_POLICY = 3,
  
  // Workspace-specific settings
  WORKSPACE_SETTINGS = 2,
  
  // User preferences - highest precedence (where allowed)
  USER_PREFERENCES = 1,
}

/**
 * Profile source indicates where a setting came from in the hierarchy.
 */
export interface ProfileSource {
  level: ProfileLevel
  origin: string // e.g., "role:developer", "team:platform", "org:kushin77"
  appliedAt: number // Unix timestamp when applied
  correlationId: string // For audit trail
}

/**
 * Profile setting with immutability marker.
 */
export interface ProfileSetting {
  key: string
  value: any
  immutable: boolean // If true, user cannot override
  source: ProfileSource
  description?: string
}

/**
 * Merged profile result showing all settings and their precedence.
 */
export interface MergedProfile {
  settings: Map<string, ProfileSetting>
  appliedHierarchy: ProfileLevel[]
  driftDetected: boolean
  driftDetails?: string[]
  computedAt: number
  correlationId: string
}

/**
 * Profile directory structure for tenant isolation.
 */
export interface TenantProfilePath {
  // Base path for all tenant profiles
  basePath: string
  
  // Organization-scoped
  orgPath: string // ~/.code-server/profiles/{org}/
  
  // User-scoped within org
  userPath: string // ~/.code-server/profiles/{org}/{user@domain}/
  
  // Workspace-scoped within user
  workspacePath: string // ~/.code-server/profiles/{org}/{user@domain}/{workspace_id}/
}

/**
 * Profile namespace separates profiles by identity.
 */
export interface ProfileNamespace {
  org: string // Organization ID from assertion
  user: string // User email from assertion
  workspace?: string // Optional workspace identifier
  
  // Computed properties
  asPath(): string // Converts to filesystem path
  asPrefix(): string // Converts to key prefix for settings
}

/**
 * Immutable key registry - keys that cannot be overridden by user.
 */
export interface ImmutableKeyPolicy {
  keys: string[] // List of immutable key patterns (supports * wildcards)
  source: "global" | "role" | "team"
  reason?: string
  appliedAt: number
}

/**
 * Profile merge operation options.
 */
export interface ProfileMergeOptions {
  // Include user preferences level
  includeUserPreferences: boolean
  
  // Fail if immutable keys would be overridden
  enforceImmutability: boolean
  
  // Detect drift (modifications outside hierarchy)
  detectDrift: boolean
  
  // Log all merge operations for audit
  auditLog: boolean
}

/**
 * Profile migration result for backward compatibility.
 */
export interface ProfileMigrationResult {
  success: boolean
  migratedSettings: number
  skippedSettings: number
  errors: MigrationError[]
  correlationId: string
}

/**
 * Migration error details.
 */
export interface MigrationError {
  key: string
  reason: string
  severity: "info" | "warn" | "error"
  suggestion?: string
}

/**
 * Immutable key override attempt (blocked operation).
 */
export interface ImmutableKeyViolation {
  key: string
  attemptedValue: any
  allowedValue: any
  source: ProfileSource
  attemptedAt: number
  correlationId: string
}

/**
 * Profile drift detection result.
 */
export interface ProfileDriftResult {
  drifted: boolean
  driftedKeys: string[]
  driftDetails: Map<string, DriftDetail>
  detectedAt: number
}

/**
 * Drift detail for a single key.
 */
export interface DriftDetail {
  expectedValue: any
  actualValue: any
  source: ProfileSource
  lastModified: number // When the drift occurred
}

/**
 * Profile metadata for tracking.
 */
export interface ProfileMetadata {
  namespace: ProfileNamespace
  level: ProfileLevel
  version: string // Profile format version
  createdAt: number
  modifiedAt: number
  checksumBefore?: string // For integrity checking
  checksumAfter?: string
  correlationId: string
}

/**
 * Recommendation/marketplace policy keys that are locked.
 */
export enum LockedPolicyKey {
  // Extensions whitelist cannot be modified by user
  EXTENSIONS_ALLOWLIST = "extensions.allowlist",
  EXTENSIONS_DENYLIST = "extensions.denylist",
  
  // Git/SSH cannot be overridden
  GIT_AUTOCRLF = "git.autocrlf",
  GIT_AUTOSTAGE = "git.autostage",
  
  // Terminal/shell settings locked
  TERMINAL_ENV = "terminal.environment",
  TERMINAL_SHELL = "terminal.shell",
  TERMINAL_ARGS = "terminal.args",
  
  // Keybindings locked for security
  KEYBINDINGS = "keybindings",
  
  // Marketplace/extension settings
  MARKETPLACE_ENABLED = "marketplace.enabled",
  MARKETPLACE_ALLOWLIST = "marketplace.allowlist",

  // Extension recommendations — must not be re-enabled by user settings
  EXTENSIONS_RECOMMENDATIONS = "extensions.recommendations",
  EXTENSIONS_IGNORE_RECOMMENDATIONS = "extensions.ignoreRecommendations",
  
  // Proxy and network settings
  HTTP_PROXY = "http.proxy",
  HTTPS_PROXY = "https.proxy",
  
  // File watching and performance
  FILES_WATCHMAN_EXCLUDE = "files.watchedPathPattern",
}

/**
 * Profile hierarchy resolver options.
 */
export interface ResolverOptions {
  // Org and user from session assertion
  namespace: ProfileNamespace
  
  // Workspace context
  workspaceId?: string
  
  // User roles from assertion
  roles: string[]
  
  // Team/org from assertion
  org: string
  
  // Session correlation ID
  correlationId: string
}

/**
 * Recommendation/marketplace policy keys configuration.
 */
export interface RecommendationPolicy {
  // VS Code Marketplace extension IDs
  recommendedExtensions: string[]
  
  // Forbidden extensions
  forbiddenExtensions: string[]
  
  // Theme recommendations
  recommendedTheme?: string
  
  // Settings recommendations (read-only)
  recommendedSettings: Map<string, any>
  
  // When policy was last updated
  policyVersion: string
  appliedAt: number
}
