#!/usr/bin/env node
// @file        src/services/policy-bundle-verifier/schema.ts
// @module      policy/bundle-verifier
// @description Type definitions and schemas for policy bundle verification
//

/**
 * Identity assertion from admin portal OIDC issuer.
 * Signed with RS256 by the issuer and verified at code-server session start.
 */
export interface IdentityAssertion {
  // Required fields (from JWT)
  email: string
  sub: string // stable user ID
  roles: string[] // ["developer", "admin", "read-only"]
  org: string // kushin77 or scoped organization
  iat: number // issued-at epoch
  exp: number // expiry epoch
  
  // Optional fields
  team?: string
  groups?: string[]
  [key: string]: any // Allow additional JWT claims
}

/**
 * Repository entitlements from admin portal.
 * Specifies which repos a user can access and what they can do.
 */
export interface RepositoryEntitlements {
  repos: string[] // Glob patterns or explicit repo paths
  workspace_policy: string // Policy bundle name for each repo
  credential_scope?: string // GSM secrets accessible in this workspace
  extension_allowlist?: string[] // Extensions allowed in this repo context
  terminal_policy?: Record<string, any> // Allowed commands, env var rules
}

/**
 * Workspace policy bundle.
 * JSON blob fetched from admin portal and applied to code-server session.
 */
export interface WorkspacePolicy {
  policy_version: string // e.g., "1.0", "1.1"
  policy_date: string // ISO 8601 timestamp when policy was issued
  repo_pattern: string // Glob pattern or explicit repo identifier
  extension_allowlist: string[] // Extensions allowed in this workspace
  terminal_env: Record<string, string> // Environment variable whitelist/defaults
  ai_endpoint?: string // Optional AI model endpoint
  db_credentials_scope?: string // Optional database credentials scope
  break_glass_allowed?: boolean // Whether break-glass override is permitted
}

/**
 * Complete policy bundle issued and signed by admin portal.
 */
export interface PolicyBundle {
  // Header metadata
  version: string // Contract version, e.g., "1"
  contract_id: string // e.g., "code-server-thin-client-v1"
  issued_at: number // Unix timestamp
  expires_at: number // Unix timestamp
  
  // Signature information
  signature: string // Base64-encoded signature
  algorithm: string // e.g., "RS256"
  issuer: string // e.g., "https://kushnir.cloud"
  
  // Payload
  identity: IdentityAssertion
  entitlements: RepositoryEntitlements
  workspace_policies: Record<string, WorkspacePolicy>
  
  // Audit correlation
  correlation_id?: string // X-Correlation-ID for audit trail
}

/**
 * Policy bundle signature with detached signature format.
 * Used when signature is transmitted separately from payload.
 */
export interface SignedPolicyBundle extends PolicyBundle {
  payload: string // Base64-encoded JSON payload (for signature verification)
}

/**
 * Verification result with detailed status.
 */
export interface VerificationResult {
  valid: boolean
  errors: VerificationError[]
  warnings: string[]
  
  // Only if valid
  bundle?: PolicyBundle
  identity?: IdentityAssertion
  
  // Timing
  verified_at: number // Unix timestamp when verification completed
  verification_time_ms: number // Time taken to verify (for performance monitoring)
}

/**
 * Detailed verification error.
 */
export interface VerificationError {
  code: string // e.g., "INVALID_SIGNATURE", "EXPIRED_TOKEN", "INVALID_ISSUER"
  message: string // Human-readable error message
  field?: string // Which field failed, if applicable
  details?: Record<string, any> // Additional context
}

/**
 * Signature verification options.
 */
export interface VerificationOptions {
  // Public key or JWKS URL for signature verification
  publicKey?: string // PEM-formatted public key
  jwksUrl?: string // URL to fetch JWKS from
  
  // Issuer to expect (must match JWT issuer claim)
  expectedIssuer: string
  
  // Audience to expect (must match JWT audience claim)
  expectedAudience: string
  
  // Clock skew tolerance (in seconds) for exp/iat claims
  clockSkewSeconds?: number
  
  // Whether to allow unsigned bundles (for testing only)
  allowUnsigned?: boolean
  
  // Whether to check revocation status
  checkRevocation?: boolean
  revocationUrl?: string // URL to check revocation status
  
  // Cache control
  cacheDurationSeconds?: number // How long to cache verification result
}

/**
 * Compatibility check result.
 */
export interface CompatibilityCheckResult {
  compatible: boolean
  localVersion: string
  bundleVersion: string
  downgradeDetected: boolean
  message: string
}

/**
 * Policy bundle cache entry.
 */
export interface CachedPolicyBundle {
  bundle: PolicyBundle
  cached_at: number // Unix timestamp
  expires_at: number // When cache expires
  verification_result: VerificationResult
}

/**
 * Fail-safe mode configuration.
 */
export enum FailSafeMode {
  DENY_ALL = "deny-all", // Full lockout
  DENY_MUTATING = "deny-mutating", // Read-only IDE access
  READ_ONLY_CACHE = "read-only-cache", // Use cached policy
}

/**
 * Policy enforcement context during fail-safe mode.
 */
export interface FailSafeContext {
  mode: FailSafeMode
  triggered_at: number // Unix timestamp
  reason: string // e.g., "portal_unreachable"
  cached_policy?: PolicyBundle
  cache_validity_seconds: number
}
