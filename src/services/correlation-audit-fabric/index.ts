// @file        src/services/correlation-audit-fabric/index.ts
// @module      audit/correlation
// @description End-to-end correlation-id audit fabric for decision traceability
//

import * as crypto from "crypto"
import {
  AuditDecisionType,
  DecisionResult,
  CorrelationAuditEvent,
  CorrelationTrace,
  CorrelationContext,
  PrivilegedOperationWithAudit,
  PrivilegedOperationAuditResult,
  CorrelationQueryOptions,
  CorrelationQueryResult,
  CorrelationDecisionEntry,
  CorrelationAuditStats,
  CorrelationAuditConfig,
  ICorrelationAuditFabric,
} from "./types"

/**
 * CorrelationAuditFabric - End-to-end audit trail with correlation IDs
 *
 * Ensures every decision in the system (portal → gateway → runtime) is
 * traceable via correlation IDs, enabling reconstruction of decision chains.
 */
export class CorrelationAuditFabric implements ICorrelationAuditFabric {
  private config: CorrelationAuditConfig
  private traces: Map<string, CorrelationTrace> = new Map() // correlationId → trace
  private events: CorrelationAuditEvent[] = [] // All events for querying
  private parentLinks: Map<string, string> = new Map() // childId → parentId
  private stats: CorrelationAuditStats = {
    totalEvents: 0,
    eventsWithCorrelation: 0,
    correlationCoverage: 100,
    byDecisionType: {},
    byResult: {
      allowed: 0,
      denied: 0,
      error: 0,
      deferred: 0,
    },
    completeTraces: 0,
    incompleteTraces: 0,
    reconstructableTraces: 0,
    avgTraceLength: 0,
    avgTraceCompletionMs: 0,
    privilegedOpsDeniedMissingCorrelation: 0,
    incompleteCorrelationIds: 0,
  }

  constructor(config: CorrelationAuditConfig) {
    this.config = config
  }

  /**
   * Record a decision event in the correlation trace
   */
  async recordDecision(event: CorrelationAuditEvent): Promise<void> {
    // Ensure event has event ID
    if (!event.eventId) {
      event.eventId = crypto.randomUUID()
    }

    if (!event.type) {
      event.type = event.decisionType
    }

    // Record event
    this.events.push(event)
    this.stats.totalEvents++

    // Track correlation coverage
    if (event.correlationId) {
      this.stats.eventsWithCorrelation++
    }

    // Update by decision type
    const typeKey = event.decisionType as AuditDecisionType
    this.stats.byDecisionType[typeKey] = (this.stats.byDecisionType[typeKey] || 0) + 1

    // Update by result
    this.stats.byResult[event.result]++

    // Find or create trace
    let trace = this.traces.get(event.correlationId)
    if (!trace) {
      trace = {
        correlationId: event.correlationId,
        startedAt: event.timestamp,
        complete: false,
        finalResult: DecisionResult.DEFERRED,
        events: [],
        eventCount: 0,
        systemCount: 0,
        durationMs: 0,
        decisionChain: [],
      }
      this.traces.set(event.correlationId, trace)
    }

    // Add event to trace
    event.sequenceNumber = trace.events.length + 1
    trace.events.push(event)
    trace.eventCount = trace.events.length

    // Track unique systems in trace
    const systems = new Set(trace.events.map((e) => e.systemComponent))
    trace.systemCount = systems.size
    trace.decisionChain = Array.from(systems)

    // Update coverage statistics
    this.updateCoverageStats()

    // Keep only last 1 million events
    if (this.events.length > 1000000) {
      this.events.splice(0, this.events.length - 1000000)
    }
  }

  /**
   * Start a new correlation trace
   */
  async startTrace(correlationId: string, metadata?: Record<string, unknown>): Promise<void> {
    const trace: CorrelationTrace = {
      correlationId,
      startedAt: Date.now(),
      complete: false,
      finalResult: DecisionResult.DEFERRED,
      events: [],
      eventCount: 0,
      systemCount: 0,
      durationMs: 0,
      decisionChain: [],
    }

    this.traces.set(correlationId, trace)

    // Record a synthetic start event so empty traces still carry context and can be linked.
    await this.recordDecision({
      correlationId,
      eventId: crypto.randomUUID(),
      timestamp: Date.now(),
      sequenceNumber: 0,
      decisionType: AuditDecisionType.PORTAL_ASSERTION_ISSUED,
      type: AuditDecisionType.PORTAL_ASSERTION_ISSUED,
      systemComponent: "trace",
      actor: typeof metadata?.actor === "string" ? metadata.actor : "system",
      actorType: "system",
      result: DecisionResult.DEFERRED,
      metadata,
    })
  }

  /**
   * Link this trace to a parent trace (for nested operations)
   */
  async linkParentTrace(correlationId: string, parentCorrelationId: string): Promise<void> {
    this.parentLinks.set(correlationId, parentCorrelationId)

    // Add link event
    const trace = this.traces.get(correlationId)
    if (trace && trace.events.length > 0) {
      const firstEvent = trace.events[0]
      firstEvent.parentCorrelationId = parentCorrelationId
    }
  }

  /**
   * Complete a trace with final result
   */
  async completeTrace(correlationId: string, finalResult: DecisionResult): Promise<void> {
    const trace = this.traces.get(correlationId)
    if (!trace) return

    trace.complete = true
    trace.finalResult = finalResult
    trace.completedAt = Date.now()
    trace.durationMs = trace.completedAt - trace.startedAt

    if (trace.complete) {
      this.stats.completeTraces++
    } else {
      this.stats.incompleteTraces++
    }
  }

  /**
   * Check if privileged operation has required correlation ID
   * Denies operation if correlation ID is missing and enforceRequired=true
   */
  async checkPrivilegedOperationAudit(op: PrivilegedOperationWithAudit): Promise<PrivilegedOperationAuditResult> {
    const timestamp = op.timestamp || Date.now()

    // Check for required correlation fields
    const missing: string[] = []
    if (!op.correlationContext.correlationId) {
      missing.push("correlationId")
    }

    // Determine if correlation is sufficient
    const hasRequiredCorrelation = missing.length === 0

    // Check enforcement
    if (!hasRequiredCorrelation && this.config.enforceCorrelationRequired) {
      // Deny operation - missing required correlation ID
      const event: CorrelationAuditEvent = {
        correlationId: op.correlationContext.correlationId || "unknown",
        eventId: crypto.randomUUID(),
        timestamp,
        sequenceNumber: 0,
        decisionType: AuditDecisionType.PRIVILEGED_OPERATION,
        systemComponent: "runtime",
        actor: op.actor,
        actorType: "user",
        target: op.target,
        targetType: op.type,
        result: DecisionResult.DENIED,
        reason: `Missing required correlation fields: ${missing.join(", ")}`,
        requestId: op.correlationContext.requestId,
        sessionId: op.correlationContext.sessionId,
        organizationId: op.correlationContext.organizationId,
        metadata: op.metadata,
      }

      await this.recordDecision(event)
      this.stats.privilegedOpsDeniedMissingCorrelation++

      return {
        allowed: false,
        reason: `Privileged operation denied: missing correlation ID`,
        auditEvent: event,
        missingCorrelation: {
          missing,
          required: ["correlationId"],
        },
      }
    }

    // Operation allowed - record audit event
    const event: CorrelationAuditEvent = {
      correlationId: op.correlationContext.correlationId,
      parentCorrelationId: op.correlationContext.parentCorrelationId,
      eventId: crypto.randomUUID(),
      timestamp,
      sequenceNumber: 0,
      decisionType: AuditDecisionType.PRIVILEGED_OPERATION,
      systemComponent: "runtime",
      actor: op.actor,
      actorType: "user",
      target: op.target,
      targetType: op.type,
      result: DecisionResult.ALLOWED,
      reason: `Privileged operation allowed: ${op.type}`,
      requestId: op.correlationContext.requestId,
      sessionId: op.correlationContext.sessionId,
      organizationId: op.correlationContext.organizationId,
      metadata: op.metadata,
    }

    await this.recordDecision(event)

    return {
      allowed: true,
      reason: `Privileged operation allowed with correlation ID`,
      auditEvent: event,
    }
  }

  /**
   * Query traces by various criteria
   */
  async queryTraces(options: CorrelationQueryOptions): Promise<CorrelationQueryResult> {
    let results: CorrelationTrace[] = []

    if (options.correlationId) {
      // Direct lookup
      const trace = this.traces.get(options.correlationId)
      if (trace) {
        results.push(trace)
      }
    } else {
      // Filter by criteria
      for (const trace of this.traces.values()) {
        if (!this.matchesQuery(trace, options)) {
          continue
        }
        results.push(trace)
      }
    }

    // Apply limit
    if (options.limit) {
      results = results.slice(0, options.limit)
    }

    return {
      traces: results,
      count: results.length,
      totalCount: this.traces.size,
    }
  }

  /**
   * Get complete trace by ID
   */
  async getTrace(correlationId: string): Promise<CorrelationTrace | undefined> {
    return this.traces.get(correlationId)
  }

  /**
   * Reconstruct decision chain from trace
   */
  async reconstructDecisionChain(correlationId: string): Promise<CorrelationDecisionEntry | undefined> {
    const trace = this.traces.get(correlationId)
    if (!trace) return undefined

    const decisions: {
      portal?: DecisionResult
      gateway?: DecisionResult
      runtime?: DecisionResult
    } = {}

    // Extract decisions by component
    for (const event of trace.events) {
      const component = event.systemComponent.toLowerCase()
      if (component.includes("portal") || component.includes("gateway")) {
        decisions.portal = event.result
      }
      if (component.includes("gateway") || component.includes("proxy")) {
        decisions.gateway = event.result
      }
      if (component.includes("runtime") || component.includes("bootstrap")) {
        decisions.runtime = event.result
      }
    }

    // Build decision chain
    const decisionChain = trace.events.map((e) => ({
      component: e.systemComponent,
      type: e.decisionType,
      result: e.result,
      timestamp: e.timestamp,
    })).filter((entry) => entry.component !== "trace")

    // Determine if reconstructable
    const hasPortalComponent = trace.events.some((e) => e.systemComponent.toLowerCase().includes("portal"))
    const hasGatewayComponent = trace.events.some((e) => e.systemComponent.toLowerCase().includes("gateway"))
    const hasRuntimeComponent = trace.events.some((e) => e.systemComponent.toLowerCase().includes("runtime"))

    const reconstructable = hasPortalComponent && hasRuntimeComponent // At minimum need portal and runtime

    if (reconstructable) {
      this.stats.reconstructableTraces++
    }

    return {
      correlationId,
      decisions,
      decisionChain,
      finalResult: trace.finalResult,
      reconstructable,
    }
  }

  /**
   * Get audit statistics
   */
  async getStatistics(): Promise<CorrelationAuditStats> {
    // Update coverage percentage
    if (this.stats.totalEvents > 0) {
      this.stats.correlationCoverage = (this.stats.eventsWithCorrelation / this.stats.totalEvents) * 100
    }

    // Calculate average trace length
    if (this.traces.size > 0) {
      const totalEvents = Array.from(this.traces.values()).reduce((sum, t) => sum + t.events.length, 0)
      this.stats.avgTraceLength = totalEvents / this.traces.size
    }

    // Calculate average trace duration
    const completedTraces = Array.from(this.traces.values()).filter((t) => t.complete)
    if (completedTraces.length > 0) {
      const totalDuration = completedTraces.reduce((sum, t) => sum + (t.durationMs || 0), 0)
      this.stats.avgTraceCompletionMs = totalDuration / completedTraces.length
    }

    return { ...this.stats }
  }

  /**
   * Shutdown fabric
   */
  async shutdown(): Promise<void> {
    // Cleanup
    this.traces.clear()
    this.events = []
    this.parentLinks.clear()
  }

  // ============ Private helpers ============

  private matchesQuery(trace: CorrelationTrace, options: CorrelationQueryOptions): boolean {
    // Check by actor
    if (options.actor) {
      const hasActor = trace.events.some((e) => e.actor === options.actor)
      if (!hasActor) return false
    }

    // Check by target
    if (options.target) {
      const hasTarget = trace.events.some((e) => e.target === options.target)
      if (!hasTarget) return false
    }

    // Check by decision type
    if (options.decisionType) {
      const hasType = trace.events.some((e) => e.decisionType === options.decisionType)
      if (!hasType) return false
    }

    // Check by result
    if (options.result) {
      const hasResult = trace.events.some((e) => e.result === options.result)
      if (!hasResult) return false
    }

    // Check by org
    if (options.organizationId) {
      const hasOrg = trace.events.some((e) => e.organizationId === options.organizationId)
      if (!hasOrg) return false
    }

    // Check time range
    if (options.timeRange) {
      if (trace.startedAt < options.timeRange.startTime || trace.startedAt > options.timeRange.endTime) {
        return false
      }
    }

    return true
  }

  private updateCoverageStats(): void {
    if (this.stats.totalEvents > 0) {
      this.stats.correlationCoverage = (this.stats.eventsWithCorrelation / this.stats.totalEvents) * 100
    }
  }
}

/**
 * Factory function to create a CorrelationAuditFabric instance.
 */
export function createCorrelationAuditFabric(config: CorrelationAuditConfig): CorrelationAuditFabric {
  return new CorrelationAuditFabric(config)
}

/**
 * Export all types for convenience.
 */
export * from "./types"
