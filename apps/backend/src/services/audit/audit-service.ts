// @file        apps/backend/src/services/audit/audit-service.ts
// @module      audit/logging
// @description Immutable append-only audit logging for RBAC authorization decisions.
//              Writes are fire-and-forget (never block the request path).

import { getLogger } from '../../lib/logger';

const logger = getLogger('AuditService');

// ── Types ─────────────────────────────────────────────────────────────────────

export type AuditAction = 'allow' | 'deny';
export type IdentityType = 'human' | 'workload' | 'automation';

export interface AuditEvent {
  userId: string;
  userEmail?: string;
  /** The role that matched (allow) or required roles (deny). */
  role: string;
  identityType?: IdentityType;
  method: string;
  path: string;
  action: AuditAction;
  reason?: string;
  statusCode?: number;
  ipAddress?: string;
  jwtClaims?: Record<string, unknown>;
  sessionId?: string;
  traceId?: string;
}

/** Minimal DB interface required by AuditService — satisfied by any pg Pool/Client. */
export interface AuditDb {
  query(sql: string, params?: unknown[]): Promise<unknown>;
}

// ── Service ───────────────────────────────────────────────────────────────────

const INSERT_SQL = `
  INSERT INTO audit_logs (
    user_id, user_email, role, identity_type,
    method, path, action, reason, status_code,
    ip_address, jwt_claims, session_id, trace_id
  ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
`;

export class AuditService {
  private db: AuditDb;
  /** In-flight write count — used in tests to assert flush happened. */
  private _writeCount = 0;

  constructor(db: AuditDb) {
    this.db = db;
  }

  /**
   * Emit an audit event. Fire-and-forget: never throws, never blocks the
   * caller. Any DB error is caught and logged internally.
   */
  emit(event: AuditEvent): void {
    // Schedule write outside the current call stack so the request handler
    // returns immediately. setImmediate gives DB writes the lowest priority.
    setImmediate(() => {
      this._write(event).catch((err) => {
        logger.error('Audit write failed (non-critical)', {
          error: err instanceof Error ? err.message : String(err),
          userId: event.userId,
          action: event.action,
          path: event.path,
        });
      });
    });
  }

  private async _write(event: AuditEvent): Promise<void> {
    await this.db.query(INSERT_SQL, [
      event.userId,
      event.userEmail ?? null,
      event.role,
      event.identityType ?? 'human',
      event.method,
      event.path,
      event.action,
      event.reason ?? null,
      event.statusCode ?? null,
      event.ipAddress ?? null,
      event.jwtClaims ? JSON.stringify(event.jwtClaims) : null,
      event.sessionId ?? null,
      event.traceId ?? null,
    ]);
    this._writeCount++;
  }

  /** Exposed for testing — number of successful DB writes so far. */
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
