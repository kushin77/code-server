// @file        src/services/correlation-audit-fabric/types.ts
// @module      audit/correlation
// @description End-to-end correlation-id audit fabric for decision traceability
//

/**
 * Audit decision type (decision point in the system)
 */
export enum AuditDecisionType {
  PORTAL_ASSERTION_ISSUED = "portal_assertion_issued", // Portal issues assertion
  GATEWAY_AUTHENTICATION = "gateway_authentication", // Gateway validates auth
  BOOTSTRAP_ENFORCEMENT = "bootstrap_enforcement", // Runtime enforces bootstrap
  POLICY_VERIFICATION = "policy_verification", // Policy bundle verification
  PROFILE_MERGE = "profile_merge", // Tenant profile hierarchy merge
  ACL_CHECK = "acl_check", // Shared workspace ACL check
  REVOCATION_CHECK = "revocation_check", // Revocation status check
  PRIVILEGED_OPERATION = "privileged_operation", // Privileged operation execution
  WORKSPACE_LIFECYCLE = "workspace_lifecycle", // Workspace state change
  SESSION_TERMINATION = "session_termination", // Session cleanup
}

/**
 * Decision result
 */
export enum DecisionResult {
  ALLOWED = "allowed",
  DENIED = "denied",
  ERROR = "error",
  DEFERRED = "deferred",
}

/**
 * Single audit event in the correlation chain
 */
export interface CorrelationAuditEvent {
  // Correlation tracking
  correlationId: string; // Unique trace ID (UUID or distributed trace ID)
  parentCorrelationId?: string; // Parent trace ID (for nested operations)
  
  // Event identity
  eventId: string; // Unique event ID within trace
  timestamp: number; // UNIX timestamp (ms)
  sequenceNumber: number; // Order in trace
  
  // Decision point
  decisionType: AuditDecisionType;
  type?: AuditDecisionType; // Alias used by some tests and consumers
  systemComponent: string; // Portal, Gateway, Runtime, etc.
  
  // Actor and target
  actor: string; // User/service performing action
  actorType: "user" | "service" | "system"; // Type of actor
  target?: string; // Resource being accessed
  targetType?: string; // Type of resource
  
  // Decision outcome
  result: DecisionResult;
  reason?: string; // Why allowed/denied
  
  // Request context
  requestId?: string; // HTTP request ID (for portal/gateway)
  sessionId?: string; // Session ID (for runtime)
  organizationId?: string; // Org ID for multi-tenancy
  
  // Metadata
  metadata?: Record<string, unknown>; // Additional context
  
  // Error tracking (if result=ERROR)
  error?: {
    code: string;
    message: string;
    stack?: string;
  };
}

/**
 * Complete correlation trace (all events in a decision chain)
 */
export interface CorrelationTrace {
  correlationId: string;
  
  // Trace metadata
  startedAt: number;
  completedAt?: number;
  duration?: number; // Total duration in ms
  
  // Trace status
  complete: boolean;
  finalResult: DecisionResult;
  
  // Events in order
  events: CorrelationAuditEvent[];
  
  // Statistics
  eventCount: number;
  systemCount: number; // Number of systems involved
  durationMs: number;
  
  // Reconstruction
  decisionChain: string[]; // System→component→result chain
}

/**
 * Correlation ID context (required for privileged operations)
 */
export interface CorrelationContext {
  correlationId: string;
  parentCorrelationId?: string;
  requestId?: string;
  sessionId?: string;
  organizationId?: string;
}

/**
 * Privilege operation that requires correlation ID
 */
export interface PrivilegedOperationWithAudit {
  operationId: string;
  type: "read_secret" | "execute_terminal" | "install_extension" | "modify_workspace" | "git_credential" | "break_glass";
  
  actor: string;
  target?: string;
  
  // MUST include correlation context for audit
  correlationContext: CorrelationContext;
  
  timestamp?: number;
  metadata?: Record<string, unknown>;
}

/**
 * Result of privileged operation with audit enforcement
 */
export interface PrivilegedOperationAuditResult {
  allowed: boolean;
  reason: string;
  
  // Audit event created
  auditEvent: CorrelationAuditEvent;
  
  // Missing correlation details (if denied due to missing correlation)
  missingCorrelation?: {
    missing: string[]; // Which fields are missing
    required: string[];
  };
}

/**
 * Correlation audit query (search traces)
 */
export interface CorrelationQueryOptions {
  correlationId?: string; // Find specific trace
  actor?: string; // By actor
  target?: string; // By target resource
  decisionType?: AuditDecisionType; // By decision type
  result?: DecisionResult; // By result (allowed/denied/error)
  organizationId?: string; // By org
  timeRange?: {
    startTime: number;
    endTime: number;
  };
  limit?: number; // Max results
}

/**
 * Correlation query result
 */
export interface CorrelationQueryResult {
  traces: CorrelationTrace[];
  count: number;
  totalCount: number; // Total matching (if paginated)
}

/**
 * Correlation decision audit entry (for storage)
 */
export interface CorrelationDecisionEntry {
  correlationId: string;
  
  // Decision sequence
  decisions: {
    portal?: DecisionResult;
    gateway?: DecisionResult;
    runtime?: DecisionResult;
  };
  
  // Timeline
  decisionChain: Array<{
    component: string;
    type: AuditDecisionType;
    result: DecisionResult;
    timestamp: number;
  }>;
  
  // Final status
  finalResult: DecisionResult;
  reconstructable: boolean; // Can decision chain be reconstructed
}

/**
 * Correlation audit fabric statistics
 */
export interface CorrelationAuditStats {
  // Coverage
  totalEvents: number;
  eventsWithCorrelation: number;
  correlationCoverage: number; // Percentage with correlation ID
  
  // By decision type
  byDecisionType: {
    [key in AuditDecisionType]?: number;
  };
  
  // By result
  byResult: {
    allowed: number;
    denied: number;
    error: number;
    deferred: number;
  };
  
  // Trace completeness
  completeTraces: number;
  incompleteTraces: number;
  reconstructableTraces: number;
  
  // Performance
  avgTraceLength: number; // Average decisions per trace
  avgTraceCompletionMs: number; // Average duration
  
  // Audit violations
  privilegedOpsDeniedMissingCorrelation: number;
  incompleteCorrelationIds: number; // Missing parent/request IDs
}

/**
 * Configuration for correlation audit fabric
 */
export interface CorrelationAuditConfig {
  // Enforcement
  enforceCorrelationRequired: boolean; // Deny ops without correlation ID
  minCorrelationParts: number; // Min required fields (default 1: correlationId)
  
  // Storage
  persistenceEnabled: boolean;
  maxTraceHistoryDays: number; // Auto-expire old traces
  
  // Query
  queryEnabled: boolean;
  queryTimeoutMs: number;
  
  // Monitoring
  alertOnMissingCorrelation: boolean;
  alertOnIncompleteChain: boolean;
  coverageThreshold: number; // Alert if coverage < this % (default 99%)
}

/**
 * Correlation audit fabric interface
 */
export interface ICorrelationAuditFabric {
  // Record decision events
  recordDecision(event: CorrelationAuditEvent): Promise<void>;
  
  // Start new trace
  startTrace(correlationId: string, metadata?: Record<string, unknown>): Promise<void>;
  
  // Link parent trace
  linkParentTrace(correlationId: string, parentCorrelationId: string): Promise<void>;
  
  // Complete trace
  completeTrace(correlationId: string, finalResult: DecisionResult): Promise<void>;
  
  // Enforce correlation on privileged operation
  checkPrivilegedOperationAudit(op: PrivilegedOperationWithAudit): Promise<PrivilegedOperationAuditResult>;
  
  // Query traces
  queryTraces(options: CorrelationQueryOptions): Promise<CorrelationQueryResult>;
  
  // Get complete trace
  getTrace(correlationId: string): Promise<CorrelationTrace | undefined>;
  
  // Reconstruct decision chain
  reconstructDecisionChain(correlationId: string): Promise<CorrelationDecisionEntry | undefined>;
  
  // Statistics
  getStatistics(): Promise<CorrelationAuditStats>;
  
  // Shutdown
  shutdown(): Promise<void>;
}
