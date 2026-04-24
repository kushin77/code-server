#!/usr/bin/env node
// @file        tests/unit/policy-bundle-verifier/conformance.spec.ts
// @module      policy/bundle-verifier
// @description CI conformance tests for policy bundle verification
//

import { describe, it, beforeEach, expect, vi } from "vitest"
import { PolicyBundleVerifier, createPolicyBundleVerifier } from "../../../src/services/policy-bundle-verifier"
import {
  PolicyBundle,
  VerificationResult,
  IdentityAssertion,
  RepositoryEntitlements,
  WorkspacePolicy,
} from "../../../src/services/policy-bundle-verifier/schema"

/**
 * Helper: Create a valid policy bundle for testing.
 */
function createValidBundle(overrides: Partial<PolicyBundle> = {}): PolicyBundle {
  const now = Math.floor(Date.now() / 1000)
  const identity: IdentityAssertion = {
    email: "test@example.com",
    sub: "user-123",
    roles: ["developer"],
    org: "kushin77",
    iat: now,
    exp: now + 3600, // 1 hour validity
  }

  const entitlements: RepositoryEntitlements = {
    repos: ["https://github.com/kushin77/*"],
    workspace_policy: "default",
    extension_allowlist: ["ms-python.python", "eamodio.gitlens"],
    terminal_policy: { allowed_commands: ["ls", "pwd", "git"] },
  }

  const workspacePolicy: WorkspacePolicy = {
    policy_version: "1.0",
    policy_date: new Date().toISOString(),
    repo_pattern: "github.com/kushin77/*",
    extension_allowlist: ["ms-python.python"],
    terminal_env: { PATH: "/usr/bin:/bin", SHELL: "/bin/bash" },
  }

  const bundle: PolicyBundle = {
    version: "1",
    contract_id: "code-server-thin-client-v1",
    issued_at: now,
    expires_at: now + 3600,
    signature: "test-signature-base64", // In real tests, use actual RS256 signature
    algorithm: "RS256",
    issuer: "https://kushnir.cloud",
    identity,
    entitlements,
    workspace_policies: { default: workspacePolicy },
    correlation_id: "test-corr-123",
    ...overrides,
  }

  return bundle
}

describe("PolicyBundleVerifier - Conformance Test Suite", () => {
  let verifier: PolicyBundleVerifier
  let validBundle: PolicyBundle

  beforeEach(() => {
    // Create verifier with test configuration (allowUnsigned for testing)
    verifier = new PolicyBundleVerifier({
      expectedIssuer: "https://kushnir.cloud",
      expectedAudience: "code-server",
      allowUnsigned: true, // Allow for testing without real signatures
      clockSkewSeconds: 30,
    })

    validBundle = createValidBundle()
  })

  describe("1. Basic Structure Validation", () => {
    it("should accept valid bundle with all required fields", async () => {
      const result = await verifier.verify(validBundle)
      expect(result.valid).toBe(true)
      expect(result.errors).toHaveLength(0)
      expect(result.bundle).toEqual(validBundle)
    })

    it("should reject bundle missing required field: version", async () => {
      const bundle = createValidBundle()
      delete (bundle as any).version
      const result = await verifier.verify(bundle)
      expect(result.valid).toBe(false)
      expect(result.errors).toContainEqual(expect.objectContaining({ code: "MISSING_FIELD", field: "version" }))
    })

    it("should reject bundle missing required field: signature", async () => {
      const bundle = createValidBundle()
      delete (bundle as any).signature
      const result = await verifier.verify(bundle)
      expect(result.valid).toBe(false)
      expect(result.errors).toContainEqual(expect.objectContaining({ code: "MISSING_FIELD" }))
    })

    it("should reject bundle with invalid identity type", async () => {
      const bundle = createValidBundle({ identity: "not-an-object" as any })
      const result = await verifier.verify(bundle)
      expect(result.valid).toBe(false)
      expect(result.errors).toContainEqual(expect.objectContaining({ code: "INVALID_TYPE", field: "identity" }))
    })

    it("should reject bundle with invalid timestamp types", async () => {
      const bundle = createValidBundle({ issued_at: "not-a-number" as any })
      const result = await verifier.verify(bundle)
      expect(result.valid).toBe(false)
      expect(result.errors).toContainEqual(expect.objectContaining({ code: "INVALID_TYPE", field: "timestamps" }))
    })
  })

  describe("2. Expiry Validation", () => {
    it("should reject expired bundle", async () => {
      const now = Math.floor(Date.now() / 1000)
      const bundle = createValidBundle({
        expires_at: now - 100, // Expired 100 seconds ago
      })
      const result = await verifier.verify(bundle)
      expect(result.valid).toBe(false)
      expect(result.errors).toContainEqual(expect.objectContaining({ code: "EXPIRED_BUNDLE" }))
    })

    it("should accept bundle near expiry within clock skew", async () => {
      const now = Math.floor(Date.now() / 1000)
      const bundle = createValidBundle({
        expires_at: now + 20, // Expires in 20 seconds
      })
      const result = await verifier.verify(bundle)
      expect(result.valid).toBe(true) // Within default 30s clock skew
    })

    it("should reject bundle not yet valid (future iat)", async () => {
      const now = Math.floor(Date.now() / 1000)
      const bundle = createValidBundle({
        issued_at: now + 1000, // Issued in future
      })
      const result = await verifier.verify(bundle)
      expect(result.valid).toBe(false)
      expect(result.errors).toContainEqual(expect.objectContaining({ code: "NOT_YET_VALID" }))
    })

    it("should reject bundle with iat >= exp", async () => {
      const now = Math.floor(Date.now() / 1000)
      const bundle = createValidBundle({
        issued_at: now + 100,
        expires_at: now + 100, // Same as issued_at
      })
      const result = await verifier.verify(bundle)
      expect(result.valid).toBe(false)
      expect(result.errors).toContainEqual(expect.objectContaining({ code: "INVALID_TIME_RANGE" }))
    })
  })

  describe("3. Identity Assertion Validation", () => {
    it("should reject identity missing required field: email", async () => {
      const bundle = createValidBundle()
      delete (bundle.identity as any).email
      const result = await verifier.verify(bundle)
      expect(result.valid).toBe(false)
      expect(result.errors).toContainEqual(expect.objectContaining({ code: "MISSING_IDENTITY_FIELD", field: "identity.email" }))
    })

    it("should reject identity missing required field: sub", async () => {
      const bundle = createValidBundle()
      delete (bundle.identity as any).sub
      const result = await verifier.verify(bundle)
      expect(result.valid).toBe(false)
      expect(result.errors).toContainEqual(expect.objectContaining({ code: "MISSING_IDENTITY_FIELD", field: "identity.sub" }))
    })

    it("should reject identity missing required field: roles", async () => {
      const bundle = createValidBundle()
      delete (bundle.identity as any).roles
      const result = await verifier.verify(bundle)
      expect(result.valid).toBe(false)
      expect(result.errors).toContainEqual(expect.objectContaining({ code: "MISSING_IDENTITY_FIELD", field: "identity.roles" }))
    })

    it("should reject invalid email format", async () => {
      const bundle = createValidBundle()
      bundle.identity.email = "not-an-email"
      const result = await verifier.verify(bundle)
      expect(result.valid).toBe(false)
      expect(result.errors).toContainEqual(expect.objectContaining({ code: "INVALID_EMAIL" }))
    })

    it("should reject empty roles array", async () => {
      const bundle = createValidBundle()
      bundle.identity.roles = []
      const result = await verifier.verify(bundle)
      expect(result.valid).toBe(false)
      expect(result.errors).toContainEqual(expect.objectContaining({ code: "INVALID_ROLES" }))
    })

    it("should reject roles field if not an array", async () => {
      const bundle = createValidBundle()
      bundle.identity.roles = "developer" as any
      const result = await verifier.verify(bundle)
      expect(result.valid).toBe(false)
      expect(result.errors).toContainEqual(expect.objectContaining({ code: "INVALID_ROLES" }))
    })
  })

  describe("4. Issuer and Audience Validation", () => {
    it("should reject bundle with mismatched issuer", async () => {
      const bundle = createValidBundle({
        issuer: "https://attacker.com",
      })
      const result = await verifier.verify(bundle)
      expect(result.valid).toBe(false)
      expect(result.errors).toContainEqual(expect.objectContaining({ code: "INVALID_ISSUER" }))
    })

    it("should reject bundle with non-code-server contract_id", async () => {
      const bundle = createValidBundle({
        contract_id: "other-app-v1",
      })
      const result = await verifier.verify(bundle)
      expect(result.valid).toBe(false)
      expect(result.errors).toContainEqual(expect.objectContaining({ code: "INVALID_AUDIENCE" }))
    })

    it("should accept bundle with correct issuer", async () => {
      const bundle = createValidBundle({
        issuer: "https://kushnir.cloud",
      })
      const result = await verifier.verify(bundle)
      expect(result.errors).not.toContainEqual(expect.objectContaining({ code: "INVALID_ISSUER" }))
    })
  })

  describe("5. Version Compatibility", () => {
    it("should accept bundle with same version as local", async () => {
      const bundle = createValidBundle({ version: "1" })
      const result = await verifier.verify(bundle)
      expect(result.errors).not.toContainEqual(expect.objectContaining({ code: "INCOMPATIBLE_VERSION" }))
    })

    it("should accept bundle with lower minor version (backward compatible)", async () => {
      const bundle = createValidBundle({ version: "0.9" })
      const result = await verifier.verify(bundle)
      // Should still be valid (compatible), just warn about downgrade
      expect(result.valid).toBe(true)
    })

    it("should warn on version downgrade", async () => {
      const bundle = createValidBundle({ version: "0.9" })
      const result = await verifier.verify(bundle)
      expect(result.warnings).toContainEqual(expect.stringContaining("Policy downgrade detected"))
    })

    it("should reject bundle with higher major version (incompatible)", async () => {
      const bundle = createValidBundle({ version: "2.0" })
      const result = await verifier.verify(bundle)
      expect(result.valid).toBe(false)
      expect(result.errors).toContainEqual(expect.objectContaining({ code: "INCOMPATIBLE_VERSION" }))
    })
  })

  describe("6. Caching", () => {
    it("should cache verified bundle", async () => {
      const result = await verifier.verify(validBundle)
      verifier.cacheBundle(validBundle, result, 300)

      const cached = verifier.getCachedBundle("test-corr-123")
      expect(cached).not.toBeNull()
      expect(cached?.bundle).toEqual(validBundle)
    })

    it("should return null for expired cache", async () => {
      const result = await verifier.verify(validBundle)
      verifier.cacheBundle(validBundle, result, 1) // 1 second TTL

      // Wait for cache to expire
      await new Promise((resolve) => setTimeout(resolve, 1100))

      const cached = verifier.getCachedBundle("test-corr-123")
      expect(cached).toBeNull()
    })

    it("should clear cache on demand", async () => {
      const result = await verifier.verify(validBundle)
      verifier.cacheBundle(validBundle, result, 300)

      verifier.clearCache()

      const cached = verifier.getCachedBundle("test-corr-123")
      expect(cached).toBeNull()
    })
  })

  describe("7. Fail-safe Mode", () => {
    it("should return deny-mutating mode without cached bundle", () => {
      const failSafe = verifier.getFailSafeContext()
      expect(failSafe.mode).toBe("deny-mutating")
      expect(failSafe.cached_policy).toBeUndefined()
    })

    it("should return read-only-cache mode with cached bundle", () => {
      const failSafe = verifier.getFailSafeContext(validBundle)
      expect(failSafe.mode).toBe("read-only-cache")
      expect(failSafe.cached_policy).toEqual(validBundle)
    })
  })

  describe("8. Performance Metrics", () => {
    it("should record verification time", async () => {
      const result = await verifier.verify(validBundle)
      expect(result.verification_time_ms).toBeGreaterThanOrEqual(0)
      expect(result.verified_at).toBeGreaterThan(0)
    })

    it("should complete verification in reasonable time", async () => {
      const result = await verifier.verify(validBundle)
      expect(result.verification_time_ms).toBeLessThan(1000) // Should be <1 second
    })
  })

  describe("9. Factory Function", () => {
    it("should create verifier with environment variables", () => {
      process.env.POLICY_ISSUER_URL = "https://custom.issuer.com"
      process.env.POLICY_ALLOW_UNSIGNED = "true"

      const customVerifier = createPolicyBundleVerifier({
        expectedAudience: "code-server",
      })

      expect(customVerifier).toBeInstanceOf(PolicyBundleVerifier)

      // Cleanup
      delete process.env.POLICY_ISSUER_URL
      delete process.env.POLICY_ALLOW_UNSIGNED
    })
  })

  describe("10. Multiple Error Scenarios", () => {
    it("should collect multiple errors in single verification", async () => {
      const bundle = createValidBundle({
        version: "2.0", // Incompatible
        expires_at: Math.floor(Date.now() / 1000) - 100, // Expired
        issuer: "https://attacker.com", // Wrong issuer
      })
      bundle.identity.email = "invalid-email" // Invalid email
      delete (bundle.identity as any).sub // Missing required field

      const result = await verifier.verify(bundle)
      expect(result.valid).toBe(false)
      expect(result.errors.length).toBeGreaterThan(3)
    })
  })
})

describe("Contract Compatibility Matrix", () => {
  let verifier: PolicyBundleVerifier

  beforeEach(() => {
    verifier = new PolicyBundleVerifier({
      expectedIssuer: "https://kushnir.cloud",
      expectedAudience: "code-server",
      allowUnsigned: true,
    })
  })

  // Test matrix for backward compatibility
  const compatibilityMatrix = [
    { local: "1.0", bundle: "1.0", shouldPass: true, description: "Same version" },
    { local: "1.0", bundle: "0.9", shouldPass: true, description: "Downgrade warning" },
    { local: "1.0", bundle: "2.0", shouldPass: false, description: "Major version mismatch" },
    { local: "1.5", bundle: "1.0", shouldPass: true, description: "Minor downgrade" },
    { local: "1.5", bundle: "1.5", shouldPass: true, description: "Exact match" },
  ]

  compatibilityMatrix.forEach(({ local, bundle, shouldPass, description }) => {
    it(`[Compatibility] ${description}: local ${local} vs bundle ${bundle}`, async () => {
      const testBundle = createValidBundle({ version: bundle })
      const result = await verifier.verify(testBundle)

      if (shouldPass) {
        // Should not have INCOMPATIBLE_VERSION error
        const incompatError = result.errors.find((e) => e.code === "INCOMPATIBLE_VERSION")
        expect(incompatError).toBeUndefined()
      } else {
        // Should have INCOMPATIBLE_VERSION error
        expect(result.errors).toContainEqual(expect.objectContaining({ code: "INCOMPATIBLE_VERSION" }))
      }
    })
  })
})
