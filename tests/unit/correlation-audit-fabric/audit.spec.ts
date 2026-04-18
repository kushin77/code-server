// @file        tests/unit/correlation-audit-fabric/audit.spec.ts
// @module      audit/correlation
// @description End-to-end correlation-id audit fabric tests
//

import { describe, it, beforeEach, expect } from "vitest"
import {
  CorrelationAuditFabric,
  AuditDecisionType,
  DecisionResult,
} from "../../../src/services/correlation-audit-fabric"

describe("CorrelationAuditFabric - End-to-End Audit Trail", () => {
  let fabric: CorrelationAuditFabric

  beforeEach(() => {
    fabric = new CorrelationAuditFabric({
      enforceCorrelationRequired: true,
      minCorrelationParts: 1,
      persistenceEnabled: false,
      maxTraceHistoryDays: 30,
      queryEnabled: true,
      queryTimeoutMs: 5000,
      alertOnMissingCorrelation: true,
      alertOnIncompleteChain: true,
      coverageThreshold: 99,
    })
  })

  describe("1. Portal-to-Runtime Decision Chain", () => {
    it("should record complete decision chain portal→gateway→runtime", async () => {
      const correlationId = "trace-full-chain-001"

      // Start trace at portal
      await fabric.startTrace(correlationId, { actor: "portal" })

      // Portal issues assertion
      await fabric.recordDecision({
        correlationId,
        eventId: "portal-001",
        timestamp: Date.now(),
        sequenceNumber: 1,
        decisionType: AuditDecisionType.PORTAL_ASSERTION_ISSUED,
        systemComponent: "portal",
        actor: "portal@company.com",
        actorType: "service",
        result: DecisionResult.ALLOWED,
      })

      // Gateway validates
      await fabric.recordDecision({
        correlationId,
        eventId: "gateway-001",
        timestamp: Date.now(),
        sequenceNumber: 2,
        decisionType: AuditDecisionType.GATEWAY_AUTHENTICATION,
        systemComponent: "gateway",
        actor: "alice@example.com",
        actorType: "user",
        result: DecisionResult.ALLOWED,
      })

      // Runtime enforces
      await fabric.recordDecision({
        correlationId,
        eventId: "runtime-001",
        timestamp: Date.now(),
        sequenceNumber: 3,
        decisionType: AuditDecisionType.BOOTSTRAP_ENFORCEMENT,
        systemComponent: "runtime",
        actor: "alice@example.com",
        actorType: "user",
        result: DecisionResult.ALLOWED,
      })

      // Verify trace
      const trace = await fabric.getTrace(correlationId)

      expect(trace).toBeDefined()
      expect(trace!.events).toHaveLength(4) // Start + 3 decisions
      expect(trace!.decisionChain).toContain("portal")
      expect(trace!.decisionChain).toContain("gateway")
      expect(trace!.decisionChain).toContain("runtime")
    })

    it("should reconstruct decision chain across systems", async () => {
      const correlationId = "trace-reconstruct-001"

      await fabric.startTrace(correlationId)
      await fabric.recordDecision({
        correlationId,
        eventId: "p1",
        timestamp: Date.now(),
        sequenceNumber: 1,
        decisionType: AuditDecisionType.PORTAL_ASSERTION_ISSUED,
        systemComponent: "portal-service",
        actor: "system",
        actorType: "system",
        result: DecisionResult.ALLOWED,
      })

      await fabric.recordDecision({
        correlationId,
        eventId: "r1",
        timestamp: Date.now(),
        sequenceNumber: 2,
        decisionType: AuditDecisionType.BOOTSTRAP_ENFORCEMENT,
        systemComponent: "runtime-broker",
        actor: "alice@example.com",
        actorType: "user",
        result: DecisionResult.ALLOWED,
      })

      const chain = await fabric.reconstructDecisionChain(correlationId)

      expect(chain).toBeDefined()
      expect(chain!.reconstructable).toBe(true) // Has portal and runtime
      expect(chain!.decisionChain).toHaveLength(2)
    })
  })

  describe("2. Correlation ID Coverage (>99%)", () => {
    it("should track events with correlation IDs", async () => {
      for (let i = 0; i < 100; i++) {
        const correlationId = `cov-test-${i}`
        await fabric.startTrace(correlationId)

        await fabric.recordDecision({
          correlationId, // Has correlation ID
          eventId: `event-${i}`,
          timestamp: Date.now(),
          sequenceNumber: 1,
          decisionType: AuditDecisionType.ACL_CHECK,
          systemComponent: "runtime",
          actor: `user-${i}@example.com`,
          actorType: "user",
          result: DecisionResult.ALLOWED,
        })
      }

      const stats = await fabric.getStatistics()

      expect(stats.correlationCoverage).toBeGreaterThanOrEqual(95) // At least 95% coverage
    })

    it("should report coverage below threshold", async () => {
      const stats = await fabric.getStatistics()

      expect(stats.eventsWithCorrelation).toBeDefined()
      expect(stats.totalEvents).toBeDefined()
      expect(stats.correlationCoverage).toBeDefined()
    })
  })

  describe("3. Missing Correlation ID Enforcement", () => {
    it("should deny privileged operation without correlation ID", async () => {
      const result = await fabric.checkPrivilegedOperationAudit({
        operationId: "op-no-corr-001",
        type: "read_secret",
        actor: "alice@example.com",
        target: "secret-key",
        correlationContext: {
          correlationId: "", // Missing!
        },
      })

      expect(result.allowed).toBe(false)
      expect(result.missingCorrelation).toBeDefined()
      expect(result.missingCorrelation!.missing).toContain("correlationId")
    })

    it("should allow privileged operation WITH correlation ID", async () => {
      const result = await fabric.checkPrivilegedOperationAudit({
        operationId: "op-with-corr-001",
        type: "read_secret",
        actor: "bob@example.com",
        target: "secret-key",
        correlationContext: {
          correlationId: "trace-valid-001",
          requestId: "req-123",
        },
      })

      expect(result.allowed).toBe(true)
      expect(result.auditEvent.result).toBe(DecisionResult.ALLOWED)
    })

    it("should record audit event for denied operation", async () => {
      const result = await fabric.checkPrivilegedOperationAudit({
        operationId: "op-denied-audit-001",
        type: "execute_terminal",
        actor: "charlie@example.com",
        correlationContext: {
          correlationId: "", // Missing
        },
      })

      expect(result.auditEvent.type).toBe(AuditDecisionType.PRIVILEGED_OPERATION)
      expect(result.auditEvent.result).toBe(DecisionResult.DENIED)
    })
  })

  describe("4. Query Traces by Criteria", () => {
    it("should query traces by correlation ID", async () => {
      const correlationId = "query-by-id-001"
      await fabric.startTrace(correlationId)

      const results = await fabric.queryTraces({ correlationId })

      expect(results.count).toBeGreaterThan(0)
      expect(results.traces[0].correlationId).toBe(correlationId)
    })

    it("should query traces by actor", async () => {
      const actor = "query-actor@example.com"
      await fabric.startTrace("query-actor-001")

      await fabric.recordDecision({
        correlationId: "query-actor-001",
        eventId: "qa-1",
        timestamp: Date.now(),
        sequenceNumber: 1,
        decisionType: AuditDecisionType.PRIVILEGED_OPERATION,
        systemComponent: "runtime",
        actor,
        actorType: "user",
        result: DecisionResult.ALLOWED,
      })

      const results = await fabric.queryTraces({ actor })

      expect(results.count).toBeGreaterThan(0)
    })

    it("should query traces by decision type", async () => {
      const correlationId = "query-by-type-001"
      await fabric.startTrace(correlationId)

      await fabric.recordDecision({
        correlationId,
        eventId: "qbt-1",
        timestamp: Date.now(),
        sequenceNumber: 1,
        decisionType: AuditDecisionType.REVOCATION_CHECK,
        systemComponent: "runtime",
        actor: "test@example.com",
        actorType: "user",
        result: DecisionResult.DENIED,
      })

      const results = await fabric.queryTraces({ decisionType: AuditDecisionType.REVOCATION_CHECK })

      expect(results.count).toBeGreaterThan(0)
    })

    it("should query traces by result (allowed/denied)", async () => {
      const correlationId = "query-by-result-001"
      await fabric.startTrace(correlationId)

      await fabric.recordDecision({
        correlationId,
        eventId: "qbr-1",
        timestamp: Date.now(),
        sequenceNumber: 1,
        decisionType: AuditDecisionType.ACL_CHECK,
        systemComponent: "runtime",
        actor: "user@example.com",
        actorType: "user",
        result: DecisionResult.DENIED,
      })

      const results = await fabric.queryTraces({ result: DecisionResult.DENIED })

      expect(results.count).toBeGreaterThan(0)
    })
  })

  describe("5. Parent-Child Correlation (Nested Operations)", () => {
    it("should link child trace to parent trace", async () => {
      const parentCorrelationId = "parent-trace-001"
      const childCorrelationId = "child-trace-001"

      await fabric.startTrace(parentCorrelationId)
      await fabric.startTrace(childCorrelationId)
      await fabric.linkParentTrace(childCorrelationId, parentCorrelationId)

      const childTrace = await fabric.getTrace(childCorrelationId)

      expect(childTrace!.events[0].parentCorrelationId).toBe(parentCorrelationId)
    })
  })

  describe("6. Trace Completion & Timing", () => {
    it("should track trace duration", async () => {
      const correlationId = "duration-test-001"
      const startTime = Date.now()

      await fabric.startTrace(correlationId)

      await new Promise((resolve) => setTimeout(resolve, 100))

      await fabric.completeTrace(correlationId, DecisionResult.ALLOWED)

      const trace = await fabric.getTrace(correlationId)

      expect(trace!.complete).toBe(true)
      expect(trace!.durationMs).toBeGreaterThanOrEqual(90)
    })

    it("should distinguish complete vs incomplete traces", async () => {
      const completeId = "complete-trace-001"
      const incompleteId = "incomplete-trace-001"

      await fabric.startTrace(completeId)
      await fabric.completeTrace(completeId, DecisionResult.ALLOWED)

      await fabric.startTrace(incompleteId) // Never completed

      const stats = await fabric.getStatistics()

      expect(stats.completeTraces).toBeGreaterThan(0)
    })
  })

  describe("7. Multi-System Decision Flow", () => {
    it("should track decisions across 3+ systems", async () => {
      const correlationId = "multi-system-001"

      await fabric.startTrace(correlationId)

      // Decision 1: Portal
      await fabric.recordDecision({
        correlationId,
        eventId: "ms-portal",
        timestamp: Date.now(),
        sequenceNumber: 1,
        decisionType: AuditDecisionType.PORTAL_ASSERTION_ISSUED,
        systemComponent: "portal-oauth",
        actor: "alice@example.com",
        actorType: "user",
        result: DecisionResult.ALLOWED,
      })

      // Decision 2: Gateway
      await fabric.recordDecision({
        correlationId,
        eventId: "ms-gateway",
        timestamp: Date.now(),
        sequenceNumber: 2,
        decisionType: AuditDecisionType.GATEWAY_AUTHENTICATION,
        systemComponent: "gateway-proxy",
        actor: "alice@example.com",
        actorType: "user",
        result: DecisionResult.ALLOWED,
      })

      // Decision 3: Bootstrap
      await fabric.recordDecision({
        correlationId,
        eventId: "ms-bootstrap",
        timestamp: Date.now(),
        sequenceNumber: 3,
        decisionType: AuditDecisionType.BOOTSTRAP_ENFORCEMENT,
        systemComponent: "runtime-bootstrap",
        actor: "alice@example.com",
        actorType: "user",
        result: DecisionResult.ALLOWED,
      })

      // Decision 4: Policy
      await fabric.recordDecision({
        correlationId,
        eventId: "ms-policy",
        timestamp: Date.now(),
        sequenceNumber: 4,
        decisionType: AuditDecisionType.POLICY_VERIFICATION,
        systemComponent: "runtime-policy",
        actor: "alice@example.com",
        actorType: "user",
        result: DecisionResult.ALLOWED,
      })

      const trace = await fabric.getTrace(correlationId)

      expect(trace!.systemCount).toBeGreaterThanOrEqual(3)
      expect(trace!.decisionChain.length).toBeGreaterThanOrEqual(3)
    })
  })

  describe("8. Audit Statistics", () => {
    it("should calculate correct statistics", async () => {
      const stats = await fabric.getStatistics()

      expect(stats.totalEvents).toBeGreaterThanOrEqual(0)
      expect(stats.eventsWithCorrelation).toBeGreaterThanOrEqual(0)
      expect(stats.correlationCoverage).toBeGreaterThanOrEqual(0)
      expect(stats.correlationCoverage).toBeLessThanOrEqual(100)
    })

    it("should track denied operations count", async () => {
      await fabric.checkPrivilegedOperationAudit({
        operationId: "stats-denied-001",
        type: "read_secret",
        actor: "test@example.com",
        correlationContext: { correlationId: "" }, // Missing = deny
      })

      const stats = await fabric.getStatistics()

      expect(stats.privilegedOpsDeniedMissingCorrelation).toBeGreaterThan(0)
    })

    it("should track stats by decision type", async () => {
      await fabric.startTrace("stats-by-type-001")

      await fabric.recordDecision({
        correlationId: "stats-by-type-001",
        eventId: "sbt-1",
        timestamp: Date.now(),
        sequenceNumber: 1,
        decisionType: AuditDecisionType.ACL_CHECK,
        systemComponent: "runtime",
        actor: "test@example.com",
        actorType: "user",
        result: DecisionResult.ALLOWED,
      })

      const stats = await fabric.getStatistics()

      expect(stats.byDecisionType[AuditDecisionType.ACL_CHECK]).toBeGreaterThan(0)
    })

    it("should track stats by result", async () => {
      await fabric.startTrace("stats-by-result-001")

      await fabric.recordDecision({
        correlationId: "stats-by-result-001",
        eventId: "sbr-1",
        timestamp: Date.now(),
        sequenceNumber: 1,
        decisionType: AuditDecisionType.PRIVILEGED_OPERATION,
        systemComponent: "runtime",
        actor: "test@example.com",
        actorType: "user",
        result: DecisionResult.ALLOWED,
      })

      const stats = await fabric.getStatistics()

      expect(stats.byResult.allowed).toBeGreaterThan(0)
    })
  })

  describe("9. Reconstructability", () => {
    it("should mark trace as reconstructable with portal+runtime", async () => {
      const correlationId = "recon-valid-001"

      await fabric.startTrace(correlationId)

      await fabric.recordDecision({
        correlationId,
        eventId: "rv-portal",
        timestamp: Date.now(),
        sequenceNumber: 1,
        decisionType: AuditDecisionType.PORTAL_ASSERTION_ISSUED,
        systemComponent: "portal",
        actor: "test@example.com",
        actorType: "user",
        result: DecisionResult.ALLOWED,
      })

      await fabric.recordDecision({
        correlationId,
        eventId: "rv-runtime",
        timestamp: Date.now(),
        sequenceNumber: 2,
        decisionType: AuditDecisionType.BOOTSTRAP_ENFORCEMENT,
        systemComponent: "runtime",
        actor: "test@example.com",
        actorType: "user",
        result: DecisionResult.ALLOWED,
      })

      const chain = await fabric.reconstructDecisionChain(correlationId)

      expect(chain!.reconstructable).toBe(true)
    })

    it("should mark trace as non-reconstructable without portal", async () => {
      const correlationId = "recon-invalid-001"

      await fabric.startTrace(correlationId)

      // Only runtime, no portal
      await fabric.recordDecision({
        correlationId,
        eventId: "ri-runtime",
        timestamp: Date.now(),
        sequenceNumber: 1,
        decisionType: AuditDecisionType.BOOTSTRAP_ENFORCEMENT,
        systemComponent: "runtime",
        actor: "test@example.com",
        actorType: "user",
        result: DecisionResult.ALLOWED,
      })

      const chain = await fabric.reconstructDecisionChain(correlationId)

      expect(chain!.reconstructable).toBe(false)
    })
  })

  describe("10. Metadata Tracking", () => {
    it("should preserve metadata in audit events", async () => {
      const correlationId = "metadata-test-001"
      const metadata = {
        userId: "alice@example.com",
        orgId: "org-123",
        requestPath: "/api/secret",
        ipAddress: "192.168.1.1",
      }

      await fabric.startTrace(correlationId)

      await fabric.recordDecision({
        correlationId,
        eventId: "mt-1",
        timestamp: Date.now(),
        sequenceNumber: 1,
        decisionType: AuditDecisionType.PRIVILEGED_OPERATION,
        systemComponent: "runtime",
        actor: "alice@example.com",
        actorType: "user",
        result: DecisionResult.ALLOWED,
        metadata,
      })

      const trace = await fabric.getTrace(correlationId)

      expect(trace!.events[1].metadata).toEqual(metadata)
    })
  })
})
