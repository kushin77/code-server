/**
 * Immutable Audit Log Types
 * SOC2-grade append-only audit table with hash chain tamper detection
 */

/**
 * Audit event operations
 */
export type AuditOperation = 'read' | 'write' | 'delete' | 'create' | 'update' | 'execute' | 'access' | 'modify';

/**
 * Audit event resource types
 */
export type AuditResourceType = 
  | 'file' 
  | 'directory' 
  | 'credential' 
  | 'session' 
  | 'user' 
  | 'config' 
  | 'workspace' 
  | 'extension' 
  | 'database';

/**
 * Audit event status
 */
export type AuditStatus = 'success' | 'failure' | 'denied';

/**
 * Core audit event entry
 */
export interface AuditEvent {
  id: string; // Unique event ID (ulid or uuid)
  timestamp: number; // Unix timestamp (ms)
  userId: string; // User performing action
  sessionId: string; // Session ID
  operation: AuditOperation; // read, write, delete, etc.
  resourceType: AuditResourceType; // File, credential, session, etc.
  resourceId: string; // Specific resource identifier
  resourcePath?: string; // File path or resource path
  status: AuditStatus; // success, failure, denied
  details: Record<string, any>; // Context: before/after values, reason for denial, etc.
  ipAddress?: string; // Client IP
  userAgent?: string; // Browser/client identifier
  metadata?: Record<string, any>; // Additional context
  
  // Hash chain for tamper detection
  previousHash: string; // SHA256 hash of previous event
  currentHash: string; // SHA256 hash of this event
}

/**
 * Audit event batch (for batch writes)
 */
export interface AuditEventBatch {
  events: AuditEvent[];
  batchId: string;
  batchTimestamp: number;
  sealed: boolean; // Immutable once sealed
  sealHash?: string; // Hash of entire batch
}

/**
 * Audit event query
 */
export interface AuditQuery {
  userId?: string; // Filter by user
  sessionId?: string; // Filter by session
  operation?: AuditOperation; // Filter by operation type
  resourceType?: AuditResourceType; // Filter by resource type
  resourceId?: string; // Filter by resource
  status?: AuditStatus; // Filter by status
  startTime?: number; // Unix timestamp (ms)
  endTime?: number; // Unix timestamp (ms)
  limit?: number; // Result limit
  offset?: number; // Pagination offset
}

/**
 * Audit event query result
 */
export interface AuditQueryResult {
  events: AuditEvent[];
  total: number;
  hasMore: boolean;
  nextOffset?: number;
}

/**
 * Audit log statistics
 */
export interface AuditStats {
  totalEvents: number;
  eventsByOperation: Record<AuditOperation, number>;
  eventsByResourceType: Record<AuditResourceType, number>;
  eventsByStatus: Record<AuditStatus, number>;
  eventsByUser: Record<string, number>;
  earliestEventTime?: number;
  latestEventTime?: number;
  averageEventsPerSecond: number;
}

/**
 * Hash chain verification result
 */
export interface HashChainVerification {
  valid: boolean;
  tamperDetected: boolean;
  firstTamperedEvent?: string; // Event ID where tampering detected
  details: string;
}

/**
 * Audit log retention policy
 */
export interface RetentionPolicy {
  enabled: boolean;
  maxAgeMs: number; // 2 years = 63072000000 ms
  archiveBeforeDelete: boolean; // Archive events before deletion
}

/**
 * Audit log snapshot for backup/export
 */
export interface AuditSnapshot {
  id: string;
  timestamp: number;
  eventCount: number;
  startHash: string; // Hash of first event in snapshot
  endHash: string; // Hash of last event in snapshot
  snapshotHash: string; // Hash of entire snapshot
  compressed: boolean; // Gzip compressed
  encrypted: boolean; // Encrypted for storage
}

/**
 * Audit log configuration
 */
export interface AuditLogConfig {
  enabled: boolean;
  batchSize: number; // Events to batch before flush
  flushIntervalMs: number; // Max time before flush
  maxMemoryEvents: number; // In-memory buffer size
  retentionPolicy: RetentionPolicy;
  compressionEnabled: boolean; // Compress old events
  encryptionEnabled: boolean; // Encrypt sensitive fields
}
