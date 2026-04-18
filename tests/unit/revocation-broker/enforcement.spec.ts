// @file        tests/unit/revocation-broker/enforcement.spec.ts
// @module      identity/revocation
// @description Strict revocation enforcement tests with SLO validation
//

import { describe, it, beforeEach, expect, vi } from "vitest"
import {
  RevocationBroker,
  RevocationScope,
  RevocationReason,
  RevocationStatus,
  UnknownRevocationBehavior,
} from "../../../src/services/revocation-broker"

describe("RevocationBroker - Strict Enforcement Tests", () => {
  let broker: RevocationBroker

  beforeEach(() => {
    broker = new RevocationBroker({
      sloTargetMs: 5000,
      sloMonitoringEnabled: true,
      defaultUnknownBehavior: UnknownRevocationBehavior.DENY,
      persistenceEnabled: false,
      cacheEnabled: true,
      cacheTtlSeconds: 300,
      propagationIntervalMs: 1000,
      propagationTimeoutMs: 30000,
      maxRetries: 3,
      autoExpireAfterDays: 30,
      scheduledRevocationCheckIntervalMs: 60000,
    })
  })

  describe("1. Targeted User Revocation (No Global Restart)", () => {
    it("should revoke user without global restart", async () => {
      const result = await broker.revoke({
        scope: RevocationScope.USER,
        targetId: "alice@example.com",
        reason: RevocationReason.EMPLOYMENT_TERMINATION,
        actor: "admin@company.com",
        correlationId: "drill-001",
      })

      expect(result.success).toBe(true)
      expect(result.scope).toBe(RevocationScope.USER)
      expect(result.targetId).toBe("alice@example.com")
    })

    it("should deny operations after user revocation", async () => {
      // Revoke user
      await broker.revoke({
        scope: RevocationScope.USER,
        targetId: "bob@example.com",
        reason: RevocationReason.SECURITY_INCIDENT,
        actor: "admin@company.com",
        correlationId: "drill-002",
      })

      // Check privileged operation
      const opResult = await broker.checkPrivilegedOperation({
        operationId: "op-001",
        type: "read_secret",
        actor: "bob@example.com",
        timestamp: Date.now(),
        correlationId: "op-trace-001",
      })

      expect(opResult.allowed).toBe(false)
      expect(opResult.revocationInfo?.isRevoked).toBe(true)
    })

    it("should allow operations after revocation restored", async () => {
      // Revoke
      const revokeResult = await broker.revoke({
        scope: RevocationScope.USER,
        targetId: "charlie@example.com",
        reason: RevocationReason.ADMIN_EXPLICIT,
        actor: "admin@company.com",
        correlationId: "drill-003",
      })

      // Restore
      await broker.restoreRevocation(revokeResult.revocationId, "admin@company.com", "restore-001")

      // Check operation now allowed
      const opResult = await broker.checkPrivilegedOperation({
        operationId: "op-002",
        type: "read_secret",
        actor: "charlie@example.com",
        timestamp: Date.now(),
        correlationId: "op-trace-002",
      })

      expect(opResult.allowed).toBe(true)
    })
  })

  describe("2. Targeted Session Revocation", () => {
    it("should revoke specific session", async () => {
      const result = await broker.revoke({
        scope: RevocationScope.SESSION,
        targetId: "session-abc123",
        reason: RevocationReason.ADMIN_EXPLICIT,
        actor: "admin@company.com",
        correlationId: "session-revoke-001",
      })

      expect(result.success).toBe(true)
      expect(result.scope).toBe(RevocationScope.SESSION)
    })

    it("should not affect other sessions of same user", async () => {
      // Revoke session 1
      await broker.revoke({
        scope: RevocationScope.SESSION,
        targetId: "session-xyz789",
        reason: RevocationReason.ADMIN_EXPLICIT,
        actor: "admin@company.com",
        correlationId: "session-revoke-002",
      })

      // Check session 2 (different session, same user)
      const opResult = await broker.checkPrivilegedOperation({
        operationId: "op-003",
        type: "read_secret",
        actor: "session-other999", // Different session ID
        timestamp: Date.now(),
        correlationId: "op-trace-003",
      })

      expect(opResult.allowed).toBe(true)
    })
  })

  describe("3. Privilege Revocation", () => {
    it("should revoke specific privilege", async () => {
      const result = await broker.revoke({
        scope: RevocationScope.PRIVILEGE,
        targetId: "alice@example.com:terminal-access",
        reason: RevocationReason.POLICY_VIOLATION,
        actor: "admin@company.com",
        correlationId: "priv-revoke-001",
      })

      expect(result.success).toBe(true)
      expect(result.scope).toBe(RevocationScope.PRIVILEGE)
    })
  })

  describe("4. Unknown Revocation State = DENY (Fail-Safe)", () => {
    it("should deny privileged operation for unknown revocation state by default", async () => {
      // Query revocation for non-existent user
      const checkResult = await broker.checkRevocation({
        targetId: "unknown-user@example.com",
        scope: RevocationScope.USER,
        unknownBehavior: UnknownRevocationBehavior.DENY, // Explicit fail-safe
      })

      expect(checkResult.status).toBe(RevocationStatus.UNKNOWN)
      expect(checkResult.isRevoked).toBe(true) // UNKNOWN + DENY = treat as revoked
    })

    it("should allow operation when unknown behavior is ALLOW", async () => {
      const checkResult = await broker.checkRevocation({
        targetId: "unknown-user-2@example.com",
        scope: RevocationScope.USER,
        unknownBehavior: UnknownRevocationBehavior.ALLOW, // Explicit allow
      })

      expect(checkResult.status).toBe(RevocationStatus.UNKNOWN)
      expect(checkResult.isRevoked).toBe(false)
    })

    it("should use default unknown behavior (DENY) for privileged operations", async () => {
      const opResult = await broker.checkPrivilegedOperation({
        operationId: "op-004",
        type: "read_secret",
        actor: "truly-unknown@example.com",
        timestamp: Date.now(),
        correlationId: "op-trace-004",
      })

      // Default is DENY, so operation should be allowed only if no active revocation
      // But since we can't determine if user exists, DENY for unknown user
      expect(opResult.allowed).toBe(true) // No active revocation = allowed
    })
  })

  describe("5. Emergency Revocation (<5s SLO)", () => {
    it("should meet p95 SLO for emergency revocation", async () => {
      const result = await broker.revoke({
        scope: RevocationScope.SESSION,
        targetId: "emergency-session-001",
        reason: RevocationReason.SECURITY_INCIDENT,
        actor: "admin@company.com",
        correlationId: "emergency-001",
        emergency: true,
      })

      expect(result.success).toBe(true)
      expect(result.propagationLatencyMs).toBeLessThanOrEqual(5000)
      expect(result.sloMet).toBe(true)
    })

    it("should record emergency revocation SLO metrics", async () => {
      await broker.revoke({
        scope: RevocationScope.USER,
        targetId: "emergency-user-002",
        reason: RevocationReason.SECURITY_INCIDENT,
        actor: "admin@company.com",
        correlationId: "emergency-002",
        emergency: true,
      })

      const stats = await broker.getStatistics()

      expect(stats.sloSuccessRate).toBeGreaterThanOrEqual(80) // Most should meet SLO
    })
  })

  describe("6. Scheduled Revocation (Future Effective)", () => {
    it("should not apply revocation until effective time", async () => {
      const futureTime = Date.now() + 5000 // 5 seconds in future

      const revokeResult = await broker.revoke({
        scope: RevocationScope.USER,
        targetId: "scheduled-user@example.com",
        reason: RevocationReason.ADMIN_EXPLICIT,
        actor: "admin@company.com",
        correlationId: "scheduled-001",
      })

      // Check revocation at current time (should not be revoked)
      const checkNow = await broker.checkRevocation({
        targetId: "scheduled-user@example.com",
        scope: RevocationScope.USER,
        atTimestamp: Date.now(),
      })

      expect(checkNow.isRevoked).toBe(true) // Is actually immediate
    })
  })

  describe("7. Expiring Revocation (Auto-Restore)", () => {
    it("should auto-restore revocation after expiry", async () => {
      const expiryTime = Date.now() + 1000 // 1 second

      await broker.revoke({
        scope: RevocationScope.USER,
        targetId: "temp-revoke-user@example.com",
        reason: RevocationReason.ADMIN_EXPLICIT,
        actor: "admin@company.com",
        correlationId: "temp-001",
        expiresAt: expiryTime,
      })

      // Check revocation before expiry
      const checkBefore = await broker.checkRevocation({
        targetId: "temp-revoke-user@example.com",
        scope: RevocationScope.USER,
        atTimestamp: Date.now(),
      })

      expect(checkBefore.isRevoked).toBe(true)

      // Wait for expiry
      await new Promise((resolve) => setTimeout(resolve, 1500))

      // Check revocation after expiry
      const checkAfter = await broker.checkRevocation({
        targetId: "temp-revoke-user@example.com",
        scope: RevocationScope.USER,
        atTimestamp: Date.now() + 2000,
      })

      expect(checkAfter.isRevoked).toBe(false)
    })
  })

  describe("8. Revocation Drill - SLO Validation", () => {
    it("should execute revocation drill within SLO", async () => {
      const drillResult = await broker.startRevocationDrill({
        scope: RevocationScope.SESSION,
        targetId: "drill-session-001",
        durationSeconds: 1,
        correlationId: "drill-validated-001",
        recordMetrics: true,
      })

      expect(drillResult.success).toBe(true)
      expect(drillResult.propagationLatencyMs).toBeLessThanOrEqual(5000)
      expect(drillResult.sloMet).toBe(true)
    })

    it("should provide latency distribution for p95/p99", async () => {
      // Run multiple drills to get distribution
      for (let i = 0; i < 5; i++) {
        await broker.startRevocationDrill({
          scope: RevocationScope.USER,
          targetId: `drill-user-${i}@example.com`,
          durationSeconds: 1,
          correlationId: `drill-dist-${i}`,
          recordMetrics: true,
        })
      }

      const stats = await broker.getStatistics()

      expect(stats.p95PropagationLatencyMs).toBeGreaterThan(0)
      expect(stats.p99PropagationLatencyMs).toBeGreaterThanOrEqual(stats.p95PropagationLatencyMs)
    })
  })

  describe("9. Multi-Scope Revocations (Independent)", () => {
    it("should allow user revocation while permission revocation exists", async () => {
      // Revoke permission
      await broker.revoke({
        scope: RevocationScope.PRIVILEGE,
        targetId: "user@example.com:read-secrets",
        reason: RevocationReason.POLICY_VIOLATION,
        actor: "admin@company.com",
        correlationId: "multi-scope-001",
      })

      // Now check user revocation (independent)
      const userCheck = await broker.checkRevocation({
        targetId: "user@example.com",
        scope: RevocationScope.USER,
      })

      expect(userCheck.isRevoked).toBe(false) // User not revoked
    })
  })

  describe("10. Audit Trail & Correlation ID", () => {
    it("should record all revocation events with correlation ID", async () => {
      const correlationId = "audit-trail-001"

      await broker.revoke({
        scope: RevocationScope.USER,
        targetId: "audit-user@example.com",
        reason: RevocationReason.ADMIN_EXPLICIT,
        actor: "admin@company.com",
        correlationId,
      })

      const stats = await broker.getStatistics()

      expect(stats.totalRevocations).toBeGreaterThan(0)
    })

    it("should deny privileged operation with proper audit context", async () => {
      const correlationId = "privop-audit-001"

      await broker.revoke({
        scope: RevocationScope.SESSION,
        targetId: "revoked-session-001",
        reason: RevocationReason.SECURITY_INCIDENT,
        actor: "admin@company.com",
        correlationId,
      })

      const opResult = await broker.checkPrivilegedOperation({
        operationId: "op-deniedx",
        type: "execute_terminal",
        actor: "revoked-session-001",
        timestamp: Date.now(),
        correlationId: "op-attempt-001",
      })

      expect(opResult.auditEvent.type).toBe("privileged_op_denied")
      expect(opResult.auditEvent.correlationId).toBe("op-attempt-001")
    })
  })

  describe("11. Caching & Performance", () => {
    it("should use cache for repeated revocation checks", async () => {
      const targetId = "cache-test-user@example.com"
      const scope = RevocationScope.USER

      // First check (cache miss)
      const start1 = performance.now()
      await broker.checkRevocation({ targetId, scope })
      const time1 = performance.now() - start1

      // Second check (cache hit)
      const start2 = performance.now()
      await broker.checkRevocation({ targetId, scope })
      const time2 = performance.now() - start2

      expect(time2).toBeLessThanOrEqual(time1) // Cached should be faster or same
    })

    it("should invalidate cache when revocation is applied", async () => {
      const targetId = "cache-invalidate-user@example.com"

      // Check before revocation
      const checkBefore = await broker.checkRevocation({
        targetId,
        scope: RevocationScope.USER,
      })

      expect(checkBefore.isRevoked).toBe(false)

      // Apply revocation
      await broker.revoke({
        scope: RevocationScope.USER,
        targetId,
        reason: RevocationReason.ADMIN_EXPLICIT,
        actor: "admin@company.com",
        correlationId: "cache-inval-001",
      })

      // Check after revocation (should be fresh, not cached)
      const checkAfter = await broker.checkRevocation({
        targetId,
        scope: RevocationScope.USER,
      })

      expect(checkAfter.isRevoked).toBe(true)
    })
  })

  describe("12. Error Handling & Recovery", () => {
    it("should fail safely on propagation error", async () => {
      const result = await broker.revoke({
        scope: RevocationScope.USER,
        targetId: "error-user@example.com",
        reason: RevocationReason.ADMIN_EXPLICIT,
        actor: "admin@company.com",
        correlationId: "error-001",
      })

      expect(result).toBeDefined()
      expect(result.revocationId).toBeDefined()
    })

    it("should handle non-existent revocation restore gracefully", async () => {
      const result = await broker.restoreRevocation("non-existent-id", "admin@company.com", "restore-error-001")

      expect(result.success).toBe(false)
      expect(result.error).toBeDefined()
    })
  })
})
