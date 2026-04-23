// @file        apps/backend/src/services/audit/audit-service.ts
// @module      audit/logging
// @description Immutable append-only audit logging for RBAC authorization decisions.
//              Writes are fire-and-forget (never block the request path).

import { getLogger } from '../../lib/logger';
import { createHash } from 'crypto';

const logger = getLogger('AuditService');

// ── Types ─────────────────────────────────────────────────────────────────────

export type AuditAction = 'allow' | 'deny' | 'create' | 'read' | 'update' | 'delete';
export type IdentityType = 'human' | 'workload' | 'automation';
export type ResourceType = 'help-request' | 'help-response' | 'expert' | 'mention' | 'file' | 'session' | 'credential' | string;

export interface AuditEvent {
  userId: string;
  userEmail?: string;
  /** The role that matched (allow) or required roles (deny). For application-domain events, use action field instead. */
  role?: string;
  identityType?: IdentityType;
  userAgent?: string;
  /** HTTP method - optional, mainly for HTTP request auditing */
  method?: string;
  /** HTTP path - optional, mainly for HTTP request auditing */
  path?: string;
  action: AuditAction;
  reason?: string;
  statusCode?: number;
  ipAddress?: string;
  jwtClaims?: Record<string, unknown>;
  sessionId?: string;
  traceId?: string;
  /** SHA-256 hash of (previous_hash + current_event_data) */
  eventHash?: string;
  /** Reference to previous event hash in chain */
  previousHash?: string;
  
  /** Application-domain fields for non-HTTP auditing (e.g., Help Queue, Mention System) */
  resource?: string;  // e.g., 'help-request:uuid' or 'mention:uuid'
  resourceType?: ResourceType;
  metadata?: Record<string, unknown>;  // Additional context (urgency, tags, SLA info, etc.)
}

/** Minimal DB interface required by AuditService — satisfied by any pg Pool/Client. */
export interface AuditDb {
  query(sql: string, params?: unknown[]): Promise<unknown>;
}

// ── Service ───────────────────────────────────────────────────────────────────

const INSERT_SQL = `
  INSERT INTO audit_logs (
    user_id, user_email, role, identity_type, user_agent,
    method, path, action, reason, status_code,
    ip_address, jwt_claims, session_id, trace_id, 
    resource, resource_type, metadata, event_hash, previous_hash
  ) VALUES (,,,,,,,,,,,,,,,,,,)
`;

export class AuditService {
  private db: AuditDb;
  /** In-flight write count — used in tests to assert flush happened. */
  private _writeCount = 0;
  /** Last processed event hash — used for hash chain chaining. */
  private _lastHash: string | null = null;

  constructor(db: AuditDb) {
    this.db = db;
  }

  /**
   * Emit an audit event. Fire-and-forget: never throws, never blocks the
   * caller. Any DB error is caught and logged internally.
   */
  emit(event: AuditEvent): void {
    // Return early to ensure fire-and-forget behavior
    setImmediate(() => {
      // Calculate hash before writing to maintain chain
      event.previousHash = this._lastHash ?? '0000000000000000000000000000000000000000000000000000000000000000';
      event.eventHash = this._calculateHash(event, event.previousHash);
      this._lastHash = event.eventHash;

      this._write(event).catch((err) => {
        logger.error('Audit write failed (non-critical)', {
          error: err instanceof Error ? err.message : String(err),
          userId: event.userId,
          action: event.action,
          path: event.path,
          resource: event.resource,
        });
      });
    });
  }

  private async _write(event: AuditEvent): Promise<void> {
    await this.db.query(INSERT_SQL, [
      event.userId,                                               // [0]  user_id
      event.userEmail ?? null,                                    // [1]  user_email
      event.role ?? null,                                         // [2]  role
      event.identityType ?? 'human',                             // [3]  identity_type
      event.userAgent ?? null,                                    // [4]  user_agent
      event.method ?? null,                                       // [5]  method
      event.path ?? null,                                         // [6]  path
      event.action,                                               // [7]  action
      event.reason ?? null,                                       // [8]  reason
      event.statusCode ?? null,                                   // [9]  status_code
      event.ipAddress ?? null,                                    // [10] ip_address
      event.jwtClaims ? JSON.stringify(event.jwtClaims) : null,  // [11] jwt_claims
      event.sessionId ?? null,                                    // [12] session_id
      event.traceId ?? null,                                      // [13] trace_id
      event.resource ?? null,                                     // [14] resource
      event.resourceType ?? null,                                 // [15] resource_type
      event.metadata ? JSON.stringify(event.metadata) : null,     // [16] metadata
      event.eventHash ?? null,                                    // [17] event_hash
      event.previousHash ?? null,                                 // [18] previous_hash
    ]);
    this._writeCount++;
  }

  /** Exposed for testing — number of successful DB writes so far. */
  private async _initLastHash(): Promise<void> {
    try {
      const result = await this.db.query('SELECT event_hash FROM audit_logs ORDER BY created_at DESC LIMIT 1') as any;
      if (result && result.rows && result.rows.length > 0) {
        this._lastHash = result.rows[0].event_hash;
      }
    } catch (err) {
      logger.error('Failed to initialize last hash', { err });
    }
  }

  private _calculateHash(event: AuditEvent, prevHash: string | null): string {
    const hash = createHash('sha256');
    const payload = JSON.stringify({
      u: event.userId,
      a: event.action,
      p: event.path,
      r: event.resource,
      ts: Date.now(),
      prev: prevHash
    });
    return hash.update(payload).digest('hex');
  }

  get writeCount(): number {
    return this._writeCount;
  }
}

// ── Singleton ─────────────────────────────────────────────────────────────────

let _instance: AuditService | null = null;

/**
 * Initialise the singleton. Call once at app startup with a live DB pool.
 */
export function initAuditService(db: AuditDb): AuditService {
  _instance = new AuditService(db);
  return _instance;
}

/**
 * Return the singleton, or null if not yet initialised.
 * Returns null instead of throwing so that routes/middleware can call this
 * without crashing when audit is not configured (e.g. in unit tests that
 * don't boot the full app).
 */
export function getAuditService(): AuditService | null {
  return _instance;
}

/** Reset singleton — used in tests. */
export function resetAuditService(): void {
  _instance = null;
}
