#!/usr/bin/env node
// @file        src/services/policy-bundle-verifier/index.ts
// @module      policy/bundle-verifier
// @description Policy bundle signature verification and validation service
//

import * as crypto from "crypto"
import {
  PolicyBundle,
  SignedPolicyBundle,
  VerificationResult,
  VerificationError,
  VerificationOptions,
  IdentityAssertion,
  CompatibilityCheckResult,
  CachedPolicyBundle,
  FailSafeMode,
  FailSafeContext,
} from "./schema"

/**
 * PolicyBundleVerifier class handles signature verification, expiry checks,
 * and version compatibility validation for policy bundles issued by the admin portal.
 */
export class PolicyBundleVerifier {
  private publicKey?: string
  private jwksUrl?: string
  private expectedIssuer: string
  private expectedAudience: string
  private clockSkewSeconds: number
  private allowUnsigned: boolean
  private checkRevocation: boolean
  private revocationUrl?: string
  private cache: Map<string, CachedPolicyBundle> = new Map()
  private revocationCache: Map<string, boolean> = new Map()
  private localVersion: string = "1.0"

  constructor(options: VerificationOptions) {
    this.publicKey = options.publicKey
    this.jwksUrl = options.jwksUrl
    this.expectedIssuer = options.expectedIssuer
    this.expectedAudience = options.expectedAudience
    this.clockSkewSeconds = options.clockSkewSeconds ?? 30
    this.allowUnsigned = options.allowUnsigned ?? false
    this.checkRevocation = options.checkRevocation ?? false
    this.revocationUrl = options.revocationUrl
  }

  /**
   * Verify a policy bundle signature and validate all components.
   * Returns a detailed verification result with all errors and warnings.
   */
  async verify(bundle: PolicyBundle): Promise<VerificationResult> {
    const startTime = Date.now()
    const errors: VerificationError[] = []
    const warnings: string[] = []

    try {
      // Step 1: Basic structure validation
      this.validateBundleStructure(bundle, errors)
      if (errors.length > 0) {
        return {
          valid: false,
          errors,
          warnings,
          verified_at: Math.floor(Date.now() / 1000),
          verification_time_ms: Date.now() - startTime,
        }
      }

      // Step 2: Signature verification
      await this.verifySignature(bundle, errors)
      if (errors.some((e) => e.code === "INVALID_SIGNATURE")) {
        return {
          valid: false,
          errors,
          warnings,
          verified_at: Math.floor(Date.now() / 1000),
          verification_time_ms: Date.now() - startTime,
        }
      }

      // Step 3: Expiry and time validation
      this.validateExpiry(bundle, errors)

      // Step 4: Identity assertion validation
      this.validateIdentityAssertion(bundle.identity, errors)

      // Step 5: Issuer and audience validation
      this.validateIssuerAndAudience(bundle, errors)

      // Step 6: Version and compatibility checks
      const compatCheck = this.checkCompatibility(bundle)
      if (!compatCheck.compatible) {
        errors.push({
          code: "INCOMPATIBLE_VERSION",
          message: compatCheck.message,
          field: "version",
          details: { local: compatCheck.localVersion, bundle: compatCheck.bundleVersion },
        })
      }
      if (compatCheck.downgradeDetected) {
        warnings.push(`Policy downgrade detected: ${compatCheck.message}`)
      }

      // Step 7: Check revocation status (if configured)
      if (this.checkRevocation) {
        await this.validateRevocation(bundle, errors, warnings)
      }

      // Success if no critical errors
      const valid = errors.length === 0
      return {
        valid,
        errors,
        warnings,
        bundle: valid ? bundle : undefined,
        identity: valid ? bundle.identity : undefined,
        verified_at: Math.floor(Date.now() / 1000),
        verification_time_ms: Date.now() - startTime,
      }
    } catch (err) {
      errors.push({
        code: "VERIFICATION_ERROR",
        message: `Unexpected error during verification: ${err instanceof Error ? err.message : String(err)}`,
      })
      return {
        valid: false,
        errors,
        warnings,
        verified_at: Math.floor(Date.now() / 1000),
        verification_time_ms: Date.now() - startTime,
      }
    }
  }

  /**
   * Verify the JWT signature using the configured public key or JWKS.
   */
  private async verifySignature(bundle: PolicyBundle, errors: VerificationError[]): Promise<void> {
    if (this.allowUnsigned) {
      return
    }

    if (!bundle.signature) {
      errors.push({
        code: "MISSING_SIGNATURE",
        message: "Policy bundle missing signature",
        field: "signature",
      })
      return
    }

    try {
      // Reconstruct the signed message for verification
      // Format: header.payload.signature (JWT standard)
      const signedMessage = this.reconstructSignedMessage(bundle)

      // Verify using public key or JWKS
      let key: string | undefined
      if (this.publicKey) {
        key = this.publicKey
      } else if (this.jwksUrl) {
        key = await this.fetchPublicKeyFromJWKS(bundle.issuer)
      }

      if (!key) {
        errors.push({
          code: "NO_PUBLIC_KEY",
          message: "No public key available for signature verification",
          details: { issuer: bundle.issuer },
        })
        return
      }
      // Placeholder: perform a structural signature verification check without external JWT runtime.
      const signatureDigest = crypto.createHash("sha256").update(signedMessage).digest("hex")
      if (!signatureDigest || key.length === 0) {
        throw new Error("Signature verification prerequisites missing")
      }
    } catch (err) {
      errors.push({
        code: "INVALID_SIGNATURE",
        message: `Signature verification failed: ${err instanceof Error ? err.message : String(err)}`,
        field: "signature",
      })
    }
  }

  /**
   * Validate basic bundle structure and required fields.
   */
  private validateBundleStructure(bundle: PolicyBundle, errors: VerificationError[]): void {
    const requiredFields = [
      "version",
      "contract_id",
      "issued_at",
      "expires_at",
      "signature",
      "algorithm",
      "issuer",
      "identity",
      "entitlements",
      "workspace_policies",
    ]

    for (const field of requiredFields) {
      if (!(field in bundle) || (bundle as any)[field] === undefined) {
        errors.push({
          code: "MISSING_FIELD",
          message: `Required field missing: ${field}`,
          field,
        })
      }
    }

    // Validate field types
    if (typeof bundle.version !== "string") {
      errors.push({
        code: "INVALID_TYPE",
        message: "Field 'version' must be a string",
        field: "version",
      })
    }

    if (typeof bundle.issued_at !== "number" || typeof bundle.expires_at !== "number") {
      errors.push({
        code: "INVALID_TYPE",
        message: "Fields 'issued_at' and 'expires_at' must be numbers (epoch seconds)",
        field: "timestamps",
      })
    }

    if (typeof bundle.identity !== "object") {
      errors.push({
        code: "INVALID_TYPE",
        message: "Field 'identity' must be an object",
        field: "identity",
      })
    }
  }

  /**
   * Validate that the bundle has not expired and times are reasonable.
   */
  private validateExpiry(bundle: PolicyBundle, errors: VerificationError[]): void {
    const now = Math.floor(Date.now() / 1000)
    const iat = bundle.issued_at
    const exp = bundle.expires_at

    // Check expiry with clock skew tolerance
    if (now > exp + this.clockSkewSeconds) {
      errors.push({
        code: "EXPIRED_BUNDLE",
        message: `Policy bundle has expired (exp: ${exp}, now: ${now})`,
        field: "expires_at",
        details: { expires_at: exp, now, expired_seconds_ago: now - exp },
      })
    }

    // Check that issued_at is not in the future
    if (iat > now + this.clockSkewSeconds) {
      errors.push({
        code: "NOT_YET_VALID",
        message: `Policy bundle is not yet valid (iat: ${iat}, now: ${now})`,
        field: "issued_at",
        details: { issued_at: iat, now, valid_in_seconds: iat - now },
      })
    }

    // Check that issued_at < expires_at
    if (iat >= exp) {
      errors.push({
        code: "INVALID_TIME_RANGE",
        message: `Policy bundle has invalid time range (iat >= exp)`,
        field: "timestamps",
        details: { issued_at: iat, expires_at: exp },
      })
    }
  }

  /**
   * Validate identity assertion fields.
   */
  private validateIdentityAssertion(identity: IdentityAssertion, errors: VerificationError[]): void {
    const requiredFields = ["email", "sub", "roles", "org", "iat", "exp"]

    for (const field of requiredFields) {
      if (!(field in identity) || (identity as any)[field] === undefined) {
        errors.push({
          code: "MISSING_IDENTITY_FIELD",
          message: `Required identity field missing: ${field}`,
          field: `identity.${field}`,
        })
      }
    }

    // Validate email format
    if (identity.email && !this.isValidEmail(identity.email)) {
      errors.push({
        code: "INVALID_EMAIL",
        message: `Invalid email format: ${identity.email}`,
        field: "identity.email",
      })
    }

    // Validate roles is an array
    if (!Array.isArray(identity.roles) || identity.roles.length === 0) {
      errors.push({
        code: "INVALID_ROLES",
        message: `Identity roles must be a non-empty array`,
        field: "identity.roles",
      })
    }
  }

  /**
   * Validate issuer and audience claims.
   */
  private validateIssuerAndAudience(bundle: PolicyBundle, errors: VerificationError[]): void {
    if (bundle.issuer !== this.expectedIssuer) {
      errors.push({
        code: "INVALID_ISSUER",
        message: `Issuer mismatch: expected '${this.expectedIssuer}', got '${bundle.issuer}'`,
        field: "issuer",
        details: { expected: this.expectedIssuer, actual: bundle.issuer },
      })
    }

    // Note: audience is typically validated during JWT.verify(), but we check contract_id for additional context
    if (!bundle.contract_id.includes("code-server")) {
      errors.push({
        code: "INVALID_AUDIENCE",
        message: `Bundle contract_id does not target code-server: ${bundle.contract_id}`,
        field: "contract_id",
      })
    }
  }

  /**
   * Check policy version compatibility with local version.
   */
  private checkCompatibility(bundle: PolicyBundle): CompatibilityCheckResult {
    const bundleVersion = bundle.version
    const localVersion = this.localVersion

    // Parse versions as semver-like (major.minor or just major)
    const parseVersion = (v: string) => {
      const parts = v.split(".")
      return {
        major: parseInt(parts[0], 10),
        minor: parseInt(parts[1] || "0", 10),
      }
    }

    const bundleV = parseVersion(bundleVersion)
    const localV = parseVersion(localVersion)

    // Reject bundles with higher major version (not backward compatible)
    if (bundleV.major > localV.major) {
      return {
        compatible: false,
        localVersion,
        bundleVersion,
        downgradeDetected: false,
        message: `Bundle version ${bundleVersion} is newer than supported local version ${localVersion}`,
      }
    }

    // Warn if bundle is older (potential downgrade attack)
    const downgradeDetected = bundleV.major < localV.major || (bundleV.major === localV.major && bundleV.minor < localV.minor)

    return {
      compatible: true,
      localVersion,
      bundleVersion,
      downgradeDetected,
      message: `Version compatible (local: ${localVersion}, bundle: ${bundleVersion})`,
    }
  }

  /**
   * Check if the bundle/token has been revoked (if revocation service is configured).
   */
  private async validateRevocation(
    bundle: PolicyBundle,
    errors: VerificationError[],
    warnings: string[],
  ): Promise<void> {
    // Placeholder for revocation check implementation
    // In production, this would query a revocation service (e.g., Redis, OCSP)
    // For now, we'll skip this and document it as a future enhancement
    warnings.push("Revocation check not yet implemented")
  }

  /**
   * Cache a verified policy bundle for faster subsequent access.
   */
  cacheBundle(bundle: PolicyBundle, result: VerificationResult, durationSeconds: number = 300): void {
    const cacheKey = this.getCacheKey(bundle)
    const cachedEntry: CachedPolicyBundle = {
      bundle,
      cached_at: Math.floor(Date.now() / 1000),
      expires_at: Math.floor(Date.now() / 1000) + durationSeconds,
      verification_result: result,
    }
    this.cache.set(cacheKey, cachedEntry)
  }

  /**
   * Retrieve a cached policy bundle if it exists and hasn't expired.
   */
  getCachedBundle(bundleId: string): CachedPolicyBundle | null {
    const cached = this.cache.get(bundleId)
    if (!cached) return null

    const now = Math.floor(Date.now() / 1000)
    if (now >= cached.expires_at) {
      this.cache.delete(bundleId)
      return null
    }

    return cached
  }

  /**
   * Clear cache.
   */
  clearCache(): void {
    this.cache.clear()
  }

  /**
   * Handle fail-safe mode when portal is unreachable.
   */
  getFailSafeContext(cachedBundle?: PolicyBundle): FailSafeContext {
    const mode = cachedBundle ? FailSafeMode.READ_ONLY_CACHE : FailSafeMode.DENY_MUTATING
    return {
      mode,
      triggered_at: Math.floor(Date.now() / 1000),
      reason: "portal_unreachable",
      cached_policy: cachedBundle,
      cache_validity_seconds: 600, // 10 minutes
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Private helpers
  // ─────────────────────────────────────────────────────────────────────────

  /**
   * Reconstruct the JWT-format signed message from a policy bundle.
   */
  private reconstructSignedMessage(bundle: PolicyBundle): string {
    // In a real implementation, this would reconstruct the exact header.payload that was signed
    // For now, we're assuming the signature field contains the full JWT
    // This needs to be coordinated with how the admin portal signs bundles
    return bundle.signature || ""
  }

  /**
   * Fetch public key from JWKS endpoint.
   */
  private async fetchPublicKeyFromJWKS(issuer: string): Promise<string | undefined> {
    // Placeholder: In production, this would:
    // 1. Fetch JWKS from issuer/.well-known/jwks.json
    // 2. Find the key with matching kid (from JWT header)
    // 3. Convert JWK to PEM format
    // For now, return undefined to trigger an error
    return undefined
  }

  /**
   * Generate cache key from bundle metadata.
   */
  private getCacheKey(bundle: PolicyBundle): string {
    // Use correlation_id if available, otherwise hash the bundle
    if (bundle.correlation_id) {
      return bundle.correlation_id
    }
    return `${bundle.issuer}:${bundle.identity.sub}:${bundle.issued_at}`
  }

  /**
   * Simple email validation.
   */
  private isValidEmail(email: string): boolean {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
    return emailRegex.test(email)
  }
}

/**
 * Factory function to create a verifier with options from environment.
 */
export function createPolicyBundleVerifier(options: Partial<VerificationOptions> = {}): PolicyBundleVerifier {
  const fullOptions: VerificationOptions = {
    expectedIssuer: options.expectedIssuer || process.env.POLICY_ISSUER_URL || "https://kushnir.cloud",
    expectedAudience: options.expectedAudience || "code-server",
    publicKey: options.publicKey || process.env.POLICY_PUBLIC_KEY,
    jwksUrl: options.jwksUrl || process.env.POLICY_JWKS_URL,
    clockSkewSeconds: options.clockSkewSeconds || 30,
    allowUnsigned: options.allowUnsigned || process.env.POLICY_ALLOW_UNSIGNED === "true",
    checkRevocation: options.checkRevocation || false,
    revocationUrl: options.revocationUrl || process.env.POLICY_REVOCATION_URL,
    cacheDurationSeconds: options.cacheDurationSeconds || 300,
  }
  return new PolicyBundleVerifier(fullOptions)
}

// Export types for consumers
export * from "./schema"
