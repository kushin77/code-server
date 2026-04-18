// @file        src/services/tenant-profile-manager/index.ts
// @module      session/tenant-profiles
// @description Tenant-aware profile manager with hierarchical merging and immutable policy overlay
//

import * as fs from "fs"
import * as path from "path"
import * as crypto from "crypto"
import {
  ProfileLevel,
  ProfileSetting,
  ProfileSource,
  MergedProfile,
  TenantProfilePath,
  ProfileNamespace,
  ImmutableKeyPolicy,
  ProfileMergeOptions,
  ProfileMigrationResult,
  MigrationError,
  ImmutableKeyViolation,
  ProfileDriftResult,
  DriftDetail,
  ProfileMetadata,
  LockedPolicyKey,
  ResolverOptions,
  RecommendationPolicy,
} from "./types"

/**
 * TenantProfileManager enforces tenant-aware profile hierarchy with immutable policy overlays.
 *
 * Profile hierarchy (precedence order):
 * 1. User Preferences (highest) - Can be overridden by user settings
 * 2. Workspace Settings - Workspace-specific defaults
 * 3. Team/Org Policy - Organization policy enforced
 * 4. Role Policy - Role-based defaults (developer, admin, etc.)
 * 5. Global Policy (lowest) - System defaults
 *
 * Immutable keys from any level block overrides at user level.
 */
export class TenantProfileManager {
  private profileBasePath: string
  private immutableKeys: Map<string, ImmutableKeyPolicy> = new Map()
  private profileCache: Map<string, MergedProfile> = new Map()
  private cacheRefreshTtlMs: number = 30000 // 30 second TTL

  constructor(basePath: string = "~/.code-server/profiles") {
    this.profileBasePath = this.expandPath(basePath)
    this.initializeImmutableKeyRegistry()
  }

  /**
   * Get profile namespace from session assertion.
   */
  getNamespace(org: string, user: string, workspace?: string): ProfileNamespace {
    return {
      org,
      user,
      workspace,
      asPath: () => {
        const segments = [this.profileBasePath, org, this.sanitizeFileName(user)]
        if (workspace) {
          segments.push(this.sanitizeFileName(workspace))
        }
        return segments.join(path.sep)
      },
      asPrefix: () => {
        const segments = [org, this.sanitizeFileName(user)]
        if (workspace) {
          segments.push(this.sanitizeFileName(workspace))
        }
        return segments.join(":")
      },
    }
  }

  /**
   * Main entry point: Merge all profile levels for a given namespace.
   */
  async mergeProfiles(options: ResolverOptions & ProfileMergeOptions): Promise<MergedProfile> {
    const cacheKey = this.getCacheKey(options.namespace)
    const cached = this.profileCache.get(cacheKey)

    // Return cached if available and fresh
    if (cached && Date.now() - cached.computedAt < this.cacheRefreshTtlMs) {
      return cached
    }

    const merged = new Map<string, ProfileSetting>()
    const appliedHierarchy: ProfileLevel[] = []

    // Load profiles in hierarchy order (lowest to highest precedence)
    const levels = [
      ProfileLevel.GLOBAL_POLICY,
      ProfileLevel.ROLE_POLICY,
      ProfileLevel.TEAM_POLICY,
      ProfileLevel.WORKSPACE_SETTINGS,
      ProfileLevel.USER_PREFERENCES,
    ]

    const violatedKeys: ImmutableKeyViolation[] = []

    for (const level of levels) {
      // Skip user preferences if not included
      if (level === ProfileLevel.USER_PREFERENCES && !options.includeUserPreferences) {
        continue
      }

      const levelSettings = await this.loadProfileLevel(level, options.namespace, options.roles)

      for (const [key, setting] of Object.entries(levelSettings)) {
        const existingSetting = merged.get(key)

        // Check for immutable key violation
        if (existingSetting && existingSetting.immutable && level === ProfileLevel.USER_PREFERENCES) {
          violatedKeys.push({
            key,
            attemptedValue: (setting as any).value,
            allowedValue: existingSetting.value,
            source: existingSetting.source,
            attemptedAt: Date.now(),
            correlationId: options.correlationId,
          })

          if (options.enforceImmutability) {
            // Skip this user preference - keep immutable value
            continue
          }
        }

        // Apply the setting (overrides lower-precedence levels)
        merged.set(key, {
          key,
          value: (setting as any).value,
          immutable: (setting as any).immutable || this.isImmutableKey(key),
          source: {
            level,
            origin: this.getLevelOrigin(level, options),
            appliedAt: Date.now(),
            correlationId: options.correlationId,
          },
          description: (setting as any).description,
        })
      }

      if (levelSettings && Object.keys(levelSettings).length > 0) {
        appliedHierarchy.push(level)
      }
    }

    // Check for drift if requested
    let driftDetected = false
    let driftDetails: string[] = []

    if (options.detectDrift) {
      const driftResult = await this.detectDrift(options.namespace, merged)
      driftDetected = driftResult.drifted
      driftDetails = Array.from(driftResult.driftDetails.entries()).map(
        ([key, detail]) => `${key}: expected ${JSON.stringify(detail.expectedValue)} but got ${JSON.stringify(detail.actualValue)}`,
      )
    }

    const result: MergedProfile = {
      settings: merged,
      appliedHierarchy,
      driftDetected,
      driftDetails: driftDetails.length > 0 ? driftDetails : undefined,
      computedAt: Date.now(),
      correlationId: options.correlationId,
    }

    // Log violations if any occurred
    if (violatedKeys.length > 0 && options.auditLog) {
      console.warn(`Immutable key violations detected (${violatedKeys.length}):`, violatedKeys)
    }

    // Cache the result
    this.profileCache.set(cacheKey, result)

    return result
  }

  /**
   * Load a specific profile level for a namespace.
   */
  private async loadProfileLevel(
    level: ProfileLevel,
    namespace: ProfileNamespace,
    roles: string[],
  ): Promise<Record<string, any>> {
    const baseDir = namespace.asPath()
    let profileFile = ""

    switch (level) {
      case ProfileLevel.GLOBAL_POLICY:
        profileFile = path.join(this.profileBasePath, "global-policy.json")
        break

      case ProfileLevel.ROLE_POLICY:
        // Load for each role the user has
        const allRoleSettings: Record<string, any> = {}
        for (const role of roles) {
          const roleFile = path.join(this.profileBasePath, `role-${role}.json`)
          try {
            const roleSettings = JSON.parse(await fs.promises.readFile(roleFile, "utf-8"))
            Object.assign(allRoleSettings, roleSettings)
          } catch (e) {
            // Role policy may not exist
          }
        }
        return allRoleSettings

      case ProfileLevel.TEAM_POLICY:
        profileFile = path.join(this.profileBasePath, namespace.org, "team-policy.json")
        break

      case ProfileLevel.WORKSPACE_SETTINGS:
        profileFile = path.join(baseDir, "workspace-settings.json")
        break

      case ProfileLevel.USER_PREFERENCES:
        profileFile = path.join(baseDir, "preferences.json")
        break
    }

    if (!profileFile) {
      return {}
    }

    try {
      const content = await fs.promises.readFile(profileFile, "utf-8")
      return JSON.parse(content)
    } catch (e) {
      // Profile file may not exist - return empty
      return {}
    }
  }

  /**
   * Detect settings that have drifted from expected policy.
   */
  private async detectDrift(namespace: ProfileNamespace, expectedProfile: Map<string, ProfileSetting>): Promise<ProfileDriftResult> {
    const driftDetails = new Map<string, DriftDetail>()
    let drifted = false

    // Check for unexpected keys in user preference directory
    const userPrefPath = path.join(namespace.asPath(), "preferences.json")

    try {
      const actualContent = await fs.promises.readFile(userPrefPath, "utf-8")
      const actualSettings = JSON.parse(actualContent)

      // Check for extra keys not in hierarchy
      for (const [key, actualValue] of Object.entries(actualSettings)) {
        const expectedSetting = expectedProfile.get(key)

        if (!expectedSetting) {
          // Unauthorized key in user preferences
          drifted = true
          driftDetails.set(key, {
            expectedValue: undefined,
            actualValue,
            source: {
              level: ProfileLevel.USER_PREFERENCES,
              origin: "user",
              appliedAt: Date.now(),
              correlationId: crypto.randomUUID(),
            },
            lastModified: (await fs.promises.stat(userPrefPath)).mtimeMs,
          })
        } else if (JSON.stringify(expectedSetting.value) !== JSON.stringify(actualValue)) {
          // Value mismatch (user may have modified)
          drifted = true
          driftDetails.set(key, {
            expectedValue: expectedSetting.value,
            actualValue,
            source: expectedSetting.source,
            lastModified: (await fs.promises.stat(userPrefPath)).mtimeMs,
          })
        }
      }
    } catch (e) {
      // User preferences file may not exist - no drift
    }

    return {
      drifted,
      driftedKeys: Array.from(driftDetails.keys()),
      driftDetails,
      detectedAt: Date.now(),
    }
  }

  /**
   * Apply a new profile setting at a specific level with validation.
   */
  async applySetting(
    namespace: ProfileNamespace,
    level: ProfileLevel,
    key: string,
    value: any,
    correlationId: string,
  ): Promise<{ success: boolean; error?: string }> {
    // Validate immutability
    if (this.isImmutableKey(key) && level === ProfileLevel.USER_PREFERENCES) {
      return {
        success: false,
        error: `Cannot override immutable key: ${key}`,
      }
    }

    // Ensure directory exists
    const dir = namespace.asPath()
    await fs.promises.mkdir(dir, { recursive: true })

    // Load existing settings at this level
    const levelFile = this.getLevelFileName(level, namespace)
    let settings: Record<string, any> = {}

    try {
      const content = await fs.promises.readFile(levelFile, "utf-8")
      settings = JSON.parse(content)
    } catch (e) {
      // File doesn't exist yet
    }

    // Update setting
    settings[key] = {
      value,
      immutable: this.isImmutableKey(key),
      appliedAt: Date.now(),
      correlationId,
    }

    // Write back to file
    try {
      await fs.promises.writeFile(levelFile, JSON.stringify(settings, null, 2), "utf-8")
      this.invalidateCache(namespace)
      return { success: true }
    } catch (e) {
      return {
        success: false,
        error: `Failed to write profile: ${(e as Error).message}`,
      }
    }
  }

  /**
   * Migrate legacy profiles to tenant-aware structure.
   */
  async migrateProfiles(
    namespace: ProfileNamespace,
    legacyProfilePath: string,
    correlationId: string,
  ): Promise<ProfileMigrationResult> {
    const errors: MigrationError[] = []
    let migratedSettings = 0
    let skippedSettings = 0

    try {
      const content = await fs.promises.readFile(legacyProfilePath, "utf-8")
      const legacySettings = JSON.parse(content)

      for (const [key, value] of Object.entries(legacySettings)) {
        // Check if this is a locked/immutable key
        if (this.isImmutableKey(key)) {
          errors.push({
            key,
            reason: "Immutable key cannot be migrated from legacy profile",
            severity: "warn",
            suggestion: `Key ${key} must be set via policy, not user preferences`,
          })
          skippedSettings++
          continue
        }

        // Migrate the setting
        const result = await this.applySetting(namespace, ProfileLevel.USER_PREFERENCES, key, value, correlationId)

        if (result.success) {
          migratedSettings++
        } else {
          errors.push({
            key,
            reason: result.error || "Unknown error",
            severity: "error",
          })
          skippedSettings++
        }
      }
    } catch (e) {
      errors.push({
        key: "_migration",
        reason: `Failed to read legacy profile: ${(e as Error).message}`,
        severity: "error",
      })
    }

    return {
      success: errors.filter((e) => e.severity === "error").length === 0,
      migratedSettings,
      skippedSettings,
      errors,
      correlationId,
    }
  }

  /**
   * Get recommendation/marketplace policy for the profile.
   */
  async getRecommendationPolicy(namespace: ProfileNamespace): Promise<RecommendationPolicy> {
    const policyFile = path.join(namespace.asPath(), "recommendations.json")

    try {
      const content = await fs.promises.readFile(policyFile, "utf-8")
      const policy = JSON.parse(content)
      return {
        recommendedExtensions: policy.recommendedExtensions || [],
        forbiddenExtensions: policy.forbiddenExtensions || [],
        recommendedTheme: policy.recommendedTheme,
        recommendedSettings: new Map(Object.entries(policy.recommendedSettings || {})),
        policyVersion: policy.policyVersion || "1.0",
        appliedAt: policy.appliedAt || Date.now(),
      }
    } catch (e) {
      // Return default empty policy
      return {
        recommendedExtensions: [],
        forbiddenExtensions: [],
        recommendedSettings: new Map(),
        policyVersion: "1.0",
        appliedAt: Date.now(),
      }
    }
  }

  /**
   * Test if a key is immutable (cannot be overridden by user).
   */
  private isImmutableKey(key: string): boolean {
    // Check if key matches any locked policy key
    const lockedKeys = Object.values(LockedPolicyKey)
    if (lockedKeys.includes(key)) {
      return true
    }

    // Check if key matches a registered immutable pattern
    for (const [pattern, policy] of this.immutableKeys) {
      if (this.matchesPattern(key, pattern)) {
        return true
      }
    }

    return false
  }

  /**
   * Pattern matching for immutable keys (supports wildcards).
   */
  private matchesPattern(key: string, pattern: string): boolean {
    const regex = new RegExp(`^${pattern.replace(/\*/g, ".*")}$`)
    return regex.test(key)
  }

  /**
   * Get the origin description for a profile level.
   */
  private getLevelOrigin(level: ProfileLevel, options: ResolverOptions): string {
    switch (level) {
      case ProfileLevel.GLOBAL_POLICY:
        return "global"
      case ProfileLevel.ROLE_POLICY:
        return `role:${options.roles.join(",")}`
      case ProfileLevel.TEAM_POLICY:
        return `org:${options.org}`
      case ProfileLevel.WORKSPACE_SETTINGS:
        return `workspace:${options.workspaceId || "default"}`
      case ProfileLevel.USER_PREFERENCES:
        return `user:${options.namespace.user}`
      default:
        return "unknown"
    }
  }

  /**
   * Get the filename for a profile level.
   */
  private getLevelFileName(level: ProfileLevel, namespace: ProfileNamespace): string {
    const baseDir = namespace.asPath()

    switch (level) {
      case ProfileLevel.GLOBAL_POLICY:
        return path.join(this.profileBasePath, "global-policy.json")
      case ProfileLevel.ROLE_POLICY:
        return path.join(this.profileBasePath, "role-policy.json")
      case ProfileLevel.TEAM_POLICY:
        return path.join(this.profileBasePath, namespace.org, "team-policy.json")
      case ProfileLevel.WORKSPACE_SETTINGS:
        return path.join(baseDir, "workspace-settings.json")
      case ProfileLevel.USER_PREFERENCES:
        return path.join(baseDir, "preferences.json")
      default:
        throw new Error(`Unknown profile level: ${level}`)
    }
  }

  /**
   * Generate cache key for merged profile.
   */
  private getCacheKey(namespace: ProfileNamespace): string {
    return namespace.asPrefix()
  }

  /**
   * Invalidate cache for a namespace.
   */
  private invalidateCache(namespace: ProfileNamespace): void {
    const key = this.getCacheKey(namespace)
    this.profileCache.delete(key)
  }

  /**
   * Expand home directory paths.
   */
  private expandPath(filePath: string): string {
    if (filePath.startsWith("~/")) {
      return path.join(require("os").homedir(), filePath.slice(2))
    }
    return filePath
  }

  /**
   * Sanitize filename to prevent directory traversal.
   */
  private sanitizeFileName(name: string): string {
    return name
      .replace(/\//g, "_")
      .replace(/\\/g, "_")
      .replace(/\.\./g, "")
      .replace(/^\./, "")
      .toLowerCase()
  }

  /**
   * Initialize the immutable key registry with default locked keys.
   */
  private initializeImmutableKeyRegistry(): void {
    // Register all locked policy keys as immutable
    const lockedKeys = Object.values(LockedPolicyKey)
    for (const key of lockedKeys) {
      this.immutableKeys.set(key, {
        keys: [key],
        source: "global",
        reason: `Policy-enforced immutable key`,
        appliedAt: Date.now(),
      })
    }

    // Register extension-related patterns as immutable
    this.immutableKeys.set("extensions.*", {
      keys: ["extensions.*"],
      source: "global",
      reason: "Extension management is policy-controlled",
      appliedAt: Date.now(),
    })
  }
}

/**
 * Factory function to create a TenantProfileManager instance.
 */
export function createTenantProfileManager(basePath?: string): TenantProfileManager {
  return new TenantProfileManager(basePath)
}

/**
 * Export all types for convenience.
 */
export * from "./types"
